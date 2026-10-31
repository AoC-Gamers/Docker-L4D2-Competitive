"""Exercise the manual analysis contract with a real scanner stand-in and files."""
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import make_sonar as sonar
import sonar_support as support


class AnalysisExecution(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.reports = self.root/'reports'
        self.enterContext(patch.object(sonar, 'ROOT', self.root))
        self.enterContext(patch.object(sonar, 'REPORTS', self.reports))
        subprocess.run(['git', 'init', '-q', '-b', 'develop', str(self.root)], check=True)
        (self.root/'.gitignore').write_text('reports/\n')
        (self.root/'source.py').write_text('value = 1\n')
        self.scanner = self.root/'scanner'
        self.scanner.write_text('''#!/usr/bin/env python3
import pathlib,sys
p=pathlib.Path(sys.argv[1].split('=',1)[1])
p.write_text('projectKey=fixture\\nserverUrl=https://sonar.invalid\\nceTaskId=t1\\n')
print('credential: opaque-token')
''')
        self.scanner.chmod(0o755)
        self.enterContext(patch.object(sonar.shutil, 'which', return_value=str(self.scanner)))
        self.enterContext(patch.object(sonar.time, 'sleep'))
        self.statuses = ['SUCCESS']
        self.gate = 'OK'
        self.api = self.enterContext(patch.object(sonar, 'request', side_effect=self.response))
        self.enterContext(patch.object(sonar, 'collect_coverage', side_effect=self.measured_fixture))

    def measured_fixture(self):
        # Validator fixture only; never used as measured coverage of this repository.
        self.reports.mkdir(exist_ok=True)
        xml = self.reports/'coverage.xml'
        xml.write_text('<coverage><packages><package><classes><class filename="source.py"><lines><line number="1" hits="1"/></lines></class></classes></package></packages></coverage>')
        return {'sourceSha256': support.source_identity(self.root)['sha256'],
                'coveragePath': 'reports/coverage.xml', 'coverageSha256': support.file_hash(xml)}

    def response(self, base, token, path, params):
        self.assertEqual((base, token), ('https://sonar.invalid', 'opaque-token'))
        if path == '/api/ce/task':
            status = self.statuses.pop(0) if len(self.statuses) > 1 else self.statuses[0]
            return {'task': {'id': 't1', 'componentKey': 'fixture', 'status': status, 'analysisId': 'a1'}}
        if path == '/api/qualitygates/project_status':
            self.assertEqual(params, {'analysisId': 'a1'})
            return {'projectStatus': {'status': self.gate}}
        if path == '/api/project_analyses/search':
            return {'analyses': [{'key': 'a1'}]}
        if path in ('/api/issues/search', '/api/hotspots/search'):
            collection = 'issues' if 'issues' in path else 'hotspots'
            return {'paging': {'total': 1}, collection: [{'key': 'i1', 'project': 'fixture', 'component': 'fixture:source.py'}]}
        if path == '/api/measures/component':
            return {'component': {'key': 'fixture', 'measures': [{'metric': 'coverage', 'value': '81.0'}]}}
        if path == '/api/measures/component_tree':
            return {'paging': {'total': 1}, 'components': [{'key': 'fixture:source.py', 'path': 'source.py'}]}
        self.fail(path)

    def analyze(self):
        with patch('sys.stdout', new_callable=io.StringIO):
            sonar.analyze('https://sonar.invalid', 'opaque-token', 'fixture')

    def test_pending_task_completes_and_reports_bind_to_real_source(self):
        self.statuses = ['PENDING', 'IN_PROGRESS', 'SUCCESS']
        self.analyze()
        receipt = json.loads((self.reports/'sonar-run.json').read_text())
        self.assertEqual(receipt['sourceSha256'], support.source_identity(self.root)['sha256'])
        self.assertEqual(receipt['analysisId'], 'a1')
        log = next(self.reports.glob('sonar-runs/*/scanner.log'))
        self.assertNotIn('opaque-token', log.read_text())
        self.assertIn('[REDACTED]', log.read_text())
        self.assertEqual(log.stat().st_mode & 0o777, 0o600)
        for command in ('issues', 'hotspots', 'coverage', 'duplications'):
            with self.subTest(command=command), patch('sys.stdout', new_callable=io.StringIO):
                sonar.report(command, 'https://sonar.invalid', 'opaque-token', 'fixture')
            report = json.loads((self.reports/f'sonar-{command}.json').read_text())
            self.assertTrue(report['complete'])
            self.assertEqual(report['analysisId'], receipt['analysisId'])

    def test_red_gate_keeps_receipt_for_diagnosis_but_returns_failure(self):
        self.gate = 'ERROR'
        with self.assertRaisesRegex(support.SonarToolError, 'Quality Gate'):
            self.analyze()
        self.assertEqual(json.loads((self.reports/'sonar-quality-gate.json').read_text())['projectStatus']['status'], 'ERROR')
        self.assertEqual(sonar.binding('https://sonar.invalid', 'opaque-token', 'fixture')['analysisId'], 'a1')

    def test_missing_scanner_does_not_publish_receipt(self):
        with patch.object(sonar.shutil, 'which', return_value=None), self.assertRaises(support.SonarToolError):
            self.analyze()
        self.assertFalse(self.reports.exists())

    def test_scanner_failure_keeps_redacted_log_without_receipt(self):
        self.scanner.write_text('#!/bin/sh\necho opaque-token >&2\nexit 7\n')
        with self.assertRaisesRegex(support.SonarToolError, 'Scanner fallo'):
            self.analyze()
        self.assertNotIn('opaque-token', next(self.reports.glob('sonar-runs/*/scanner.log')).read_text())
        self.assertFalse((self.reports/'sonar-run.json').exists())

    def test_failed_and_expired_compute_tasks_never_confirm_receipt(self):
        for status in ('FAILED', 'CANCELED', 'PENDING'):
            with self.subTest(status=status):
                self.statuses = [status]
                with patch.object(sonar.time, 'monotonic', side_effect=[0, 301]), self.assertRaisesRegex(support.SonarToolError, 'Compute Engine'):
                    self.analyze()
                self.assertFalse((self.reports/'sonar-run.json').exists())

    def test_changed_source_during_scan_is_rejected(self):
        original = self.response
        def changed(base, token, path, params):
            if path == '/api/qualitygates/project_status':
                (self.root/'source.py').write_text('value = 2\n')
            return original(base, token, path, params)
        self.api.side_effect = changed
        with self.assertRaisesRegex(support.SonarToolError, 'Fuentes cambiaron'):
            self.analyze()
        self.assertFalse((self.reports/'sonar-run.json').exists())

    def test_report_rejects_tampered_receipt_and_source(self):
        self.analyze()
        path = self.reports/'sonar-run.json'
        original = json.loads(path.read_text())
        for change in ({'projectKey': 'other'}, {'schema': 2}, {'hostUrl': 'https://other.invalid'}, {'sourceSha256': 'bad'}, {'analysisId': 'other'}):
            with self.subTest(change=change):
                path.write_text(json.dumps({**original, **change}))
                with self.assertRaises(support.SonarToolError):
                    sonar.binding('https://sonar.invalid', 'opaque-token', 'fixture')
        path.write_text(json.dumps(original))
        self.statuses = ['FAILED']
        with self.assertRaises(support.SonarToolError):
            sonar.binding('https://sonar.invalid', 'opaque-token', 'fixture')

    def test_report_rejects_foreign_measures_and_mid_export_changes(self):
        self.analyze()
        original = self.response
        def changed(base, token, path, params):
            result = original(base, token, path, params)
            if path == '/api/measures/component':
                result['component']['key'] = 'other'
            return result
        self.api.side_effect = changed
        with self.assertRaisesRegex(support.SonarToolError, 'otro proyecto'):
            sonar.report('coverage', 'https://sonar.invalid', 'opaque-token', 'fixture')
        receipt = json.loads((self.reports/'sonar-run.json').read_text())
        self.api.side_effect = original
        with patch.object(sonar, 'binding', side_effect=[receipt, {**receipt, 'analysisId': 'new'}]), self.assertRaisesRegex(support.SonarToolError, 'cambio'):
            sonar.report('issues', 'https://sonar.invalid', 'opaque-token', 'fixture')
        self.assertFalse((self.reports/'sonar-issues.json').exists())

    def test_cli_routes_commands_and_preserves_error_status(self):
        with patch.object(sonar, 'context', return_value=('base', 'token', 'project')):
            with patch.object(sys, 'argv', ['sonar', 'analyze']), patch.object(sonar, 'analyze') as analyze:
                self.assertEqual(sonar.main(), 0)
                analyze.assert_called_once_with('base', 'token', 'project')
            with patch.object(sys, 'argv', ['sonar', 'issues']), patch.object(sonar, 'report') as report:
                self.assertEqual(sonar.main(), 0)
                report.assert_called_once_with('issues', 'base', 'token', 'project')
            for error in (support.SonarToolError('safe error'), OSError('private error')):
                with patch.object(sys, 'argv', ['sonar', 'issues']), patch.object(sonar, 'report', side_effect=error), patch('sys.stderr', new_callable=io.StringIO) as stderr:
                    self.assertEqual(sonar.main(), 1)
                    self.assertNotIn('private error', stderr.getvalue())


class Transport(unittest.TestCase):
    def test_request_decodes_json_and_sends_token_only_in_header(self):
        opener = unittest.mock.MagicMock()
        opener.open.return_value.__enter__.return_value = io.StringIO('{"valid":true}')
        with patch.object(sonar, 'build_opener', return_value=opener):
            self.assertEqual(sonar.request('https://sonar.invalid', 'private', '/api/test', {'q': 'a b'}), {'valid': True})
        req = opener.open.call_args.args[0]
        self.assertEqual(req.full_url, 'https://sonar.invalid/api/test?q=a+b')
        self.assertEqual(req.get_header('Authorization'), 'Bearer private')
        self.assertIsNone(sonar.NoRedirect().redirect_request(None, None, None, None, None, None))

    def test_transport_errors_never_echo_credentials_or_response_body(self):
        for error in (URLError('private'), HTTPError('https://sonar.invalid', 403, 'private', {}, None), ValueError('private')):
            opener = unittest.mock.MagicMock()
            opener.open.side_effect = error
            with patch.object(sonar, 'build_opener', return_value=opener), self.assertRaises(support.SonarToolError) as caught:
                sonar.request('https://sonar.invalid', 'private', '/api/test', {})
            self.assertNotIn('private', str(caught.exception))
