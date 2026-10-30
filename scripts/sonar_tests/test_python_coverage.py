"""Coverage collection failures and source/XML binding, without remote Sonar."""
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import make_sonar as sonar
import sonar_support as support


class CoverageEvidence(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.enterContext(patch.object(sonar, 'ROOT', self.root))
        self.enterContext(patch.object(sonar, 'REPORTS', self.root/'reports'))
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        (self.root/'.gitignore').write_text('reports/\n')
        (self.root/'source.py').write_text('value = 1\n')
        self.xml = '<coverage><packages><package><classes><class filename="source.py"><lines><line number="1" hits="1"/></lines></class></classes></package></packages></coverage>'
        self.commands = []
        self.real_run = subprocess.run
        self.enterContext(patch.dict(sys.modules, {'coverage': SimpleNamespace(__file__=str(self.root/'venv/site-packages/coverage/__init__.py'))}))

    def process(self, args, **kwargs):
        if args[0] == 'git':
            return self.real_run(args, **kwargs)
        self.commands.append((args, kwargs))
        if 'xml' in args:
            Path(args[args.index('-o')+1]).write_text(self.xml)
        return subprocess.CompletedProcess(args, 0, stdout='tests passed\n', stderr='')

    def collect(self):
        with patch.object(sonar.subprocess, 'run', side_effect=self.process), patch('sys.stdout', new_callable=io.StringIO):
            return sonar.collect_coverage()

    def test_collection_binds_xml_and_does_not_pass_sonar_secrets_to_tests(self):
        with patch.dict(sonar.os.environ, {'SONAR_TOKEN': 'private', 'SONAR_HOST_URL': 'https://sonar.invalid'}):
            receipt = self.collect()
        self.assertEqual(support.coverage_binding(self.root, self.root/'reports', receipt).read_text(), self.xml)
        self.assertEqual(json.loads((self.root/'reports/python-coverage.json').read_text()), receipt)
        test_env = self.commands[0][1]['env']
        self.assertNotIn('SONAR_TOKEN', test_env)
        self.assertNotIn('SONAR_HOST_URL', test_env)
        bootstrap = Path(test_env['PYTHONPATH'].split(':')[0])
        self.assertIn('coverage.process_startup()', (bootstrap/'sitecustomize.py').read_text())
        self.assertEqual(test_env['COVERAGE_SOURCE_ROOT'], str(self.root))
        self.assertTrue(all('COVERAGE_PROCESS_START' not in kw['env'] for _, kw in self.commands[1:]))

    def test_failed_tests_never_confirm_a_coverage_receipt(self):
        def failed(args, **kwargs):
            if args[0] == 'git':
                return self.real_run(args, **kwargs)
            return subprocess.CompletedProcess(args, 1, stdout='', stderr='failure')
        with patch.object(sonar.subprocess, 'run', side_effect=failed), self.assertRaisesRegex(support.SonarToolError, 'Pruebas fallaron'):
            sonar.collect_coverage()
        self.assertFalse((self.root/'reports/python-coverage.json').exists())

    def test_source_changes_during_collection_are_rejected(self):
        original = self.process
        def changed(args, **kwargs):
            result = original(args, **kwargs)
            if 'json' in args:
                (self.root/'source.py').write_text('value = 2\n')
            return result
        with patch.object(sonar.subprocess, 'run', side_effect=changed), self.assertRaisesRegex(support.SonarToolError, 'Fuentes cambiaron'):
            sonar.collect_coverage()
        self.assertFalse((self.root/'reports/python-coverage.json').exists())

    def test_missing_dependency_has_actionable_diagnostic(self):
        with patch.dict(sys.modules, {'coverage': None}), self.assertRaisesRegex(support.SonarToolError, 'quality-setup'):
            sonar.collect_coverage()

    def test_tampered_missing_or_external_coverage_cannot_be_reused(self):
        receipt = self.collect()
        xml = self.root/receipt['coveragePath']
        xml.write_text(self.xml.replace('hits="1"', 'hits="99"'))
        with self.assertRaises(support.SonarToolError):
            support.coverage_binding(self.root, self.root/'reports', receipt)
        for value in ({}, {**receipt, 'coveragePath': '../outside.xml'}):
            with self.assertRaises(support.SonarToolError):
                support.coverage_binding(self.root, self.root/'reports', value)
        xml.unlink()
        with self.assertRaises(support.SonarToolError):
            support.coverage_binding(self.root, self.root/'reports', receipt)

    def test_xml_requires_every_product_file_even_if_not_executed(self):
        xml = self.root/'coverage.xml'
        for text in ('not xml', '<coverage/>', self.xml.replace('source.py', '../foreign.py'), self.xml.replace('number="1"', 'number="0"'), self.xml.replace('hits="1"', 'hits="-1"')):
            xml.write_text(text)
            with self.assertRaises(support.SonarToolError):
                support.validate_python_xml(self.root, xml)
        xml.unlink()
        outside = self.root/'outside.xml'
        outside.write_text(self.xml)
        xml.symlink_to(outside)
        with self.assertRaises(support.SonarToolError):
            support.validate_python_xml(self.root, xml)
        xml.unlink()
        xml.write_text(self.xml)
        (self.root/'never_executed.py').write_text('value = 2\n')
        with self.assertRaises(support.SonarToolError):
            support.validate_python_xml(self.root, xml)
        (self.root/'never_executed.py').unlink()
        support.validate_python_xml(self.root, xml)

    def test_coverage_command_works_without_sonar_credentials(self):
        with patch.object(sys, 'argv', ['sonar', 'coverage-run']), patch.object(sonar, 'context') as context, patch.object(sonar, 'collect_coverage') as collect:
            self.assertEqual(sonar.main(), 0)
            context.assert_not_called()
            collect.assert_called_once()
