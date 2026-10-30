"""Adversarial evidence and pagination contracts, using temporary Git fixtures."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import sonar_support as support


class Evidence(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_source_identity_includes_dirty_untracked_and_deleted_files(self):
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        source = self.root/'source.py'
        source.write_text('one')
        subprocess.run(['git', 'add', 'source.py'], cwd=self.root, check=True)
        first = support.source_identity(self.root)
        source.write_text('two')
        self.assertNotEqual(first['sha256'], support.source_identity(self.root)['sha256'])
        (self.root/'new.py').write_text('new')
        self.assertIn('new.py', support.source_identity(self.root)['files'])
        source.unlink()
        self.assertEqual(support.source_identity(self.root)['files']['source.py'], 'deleted')
        (self.root/'link.py').symlink_to(self.root/'new.py')
        with self.assertRaises(support.SonarToolError):
            support.source_identity(self.root)
        with self.assertRaises(support.SonarToolError):
            support.file_hash(source)
        with self.assertRaises(support.SonarToolError):
            support.file_hash(self.root/'link.py')

    def test_json_replace_is_atomic_and_cleans_failed_temporary(self):
        target = self.root/'nested/report.json'
        support.atomic_json(target, {'value': 'á'})
        self.assertEqual(json.loads(target.read_text()), {'value': 'á'})
        with patch.object(support.os, 'replace', side_effect=OSError('disk full')), self.assertRaises(OSError):
            support.atomic_json(target, {'value': 'new'})
        self.assertEqual(json.loads(target.read_text()), {'value': 'á'})
        self.assertFalse(list(target.parent.glob('.sonar-*')))

    def test_task_receipts_require_matching_server_project_and_unique_fields(self):
        target = self.root/'task'
        with self.assertRaises(support.SonarToolError):
            support.read_task(target, 'https://sonar.invalid', 'fixture')
        valid = 'projectKey=fixture\nserverUrl=https://sonar.invalid/\nceTaskId=t1\n'
        target.write_text('# scanner receipt\n' + valid)
        self.assertEqual(support.read_task(target, 'https://sonar.invalid', 'fixture')['ceTaskId'], 't1')
        for text in (valid + 'ceTaskId=t2\n', valid.replace('fixture', 'other'), valid.replace('sonar.invalid', 'other.invalid'), valid.replace('ceTaskId=t1\n', '')):
            target.write_text(text)
            with self.assertRaises(support.SonarToolError):
                support.read_task(target, 'https://sonar.invalid', 'fixture')
        link = self.root/'link'
        link.symlink_to(target)
        with self.assertRaises(support.SonarToolError):
            support.read_task(link, 'https://sonar.invalid', 'fixture')

    def test_task_and_latest_analysis_are_bound_to_the_exact_identity(self):
        valid = {'id': 't1', 'componentKey': 'fixture', 'status': 'SUCCESS', 'analysisId': 'a1'}
        support.verify_task(valid, 't1', 'fixture')
        for task in (None, {}, {**valid, 'id': 'other'}, {**valid, 'componentKey': 'other'}, {**valid, 'analysisId': ''}):
            with self.assertRaises(support.SonarToolError):
                support.verify_task(task, 't1', 'fixture')
        for data in ({}, {'analyses': []}, {'analyses': ['bad']}, {'analyses': [{'key': 'old'}]}):
            with self.assertRaises(support.SonarToolError):
                support.verify_latest(lambda *a: data, 'base', 'token', 'fixture', 'a1')
        support.verify_latest(lambda *a: {'analyses': [{'key': 'a1'}]}, 'base', 'token', 'fixture', 'a1')

    def test_origin_validates_port_path_and_credentials(self):
        self.assertEqual(support.validate_origin('https://sonar.invalid:9443/'), 'https://sonar.invalid:9443')
        for value in ('https://sonar.invalid:', 'https://sonar.invalid:bad', 'https://sonar.invalid#x', 'https://user@sonar.invalid'):
            with self.assertRaises(support.SonarToolError):
                support.validate_origin(value)


class Pagination(unittest.TestCase):
    def fetch(self, payload, collection='issues'):
        return support.paginate(lambda *a: payload, 'base', 'token', '/api/items', {}, collection, 'fixture')

    def test_all_pages_preserve_unique_identity_and_exact_total(self):
        pages = [
            {'paging': {'total': 501, 'pageIndex': 1, 'pageSize': 500}, 'issues': [{'key': str(i), 'project': 'fixture'} for i in range(500)]},
            {'paging': {'total': 501, 'pageIndex': 2, 'pageSize': 500}, 'issues': [{'key': '500', 'project': 'fixture'}]},
        ]
        seen = []
        def request(*args):
            seen.append(args[-1])
            return pages.pop(0)
        items = support.paginate(request, 'base', 'token', '/api/items', {}, 'issues', 'fixture')
        self.assertEqual(len(items), 501)
        self.assertEqual([p['p'] for p in seen], [1, 2])
        self.assertEqual(self.fetch({'total': 0, 'issues': []}), [])
        self.assertEqual(self.fetch({'total': 1, 'components': [{'key': 'fixture:source.py'}]}, 'components')[0]['key'], 'fixture:source.py')

    def test_malformed_or_foreign_pages_are_rejected_without_partial_export(self):
        good = {'key': 'i1', 'project': 'fixture'}
        invalid = [
            {'issues': []}, {'total': -1, 'issues': []}, {'total': True, 'issues': []},
            {'total': 1, 'paging': {'total': 2}, 'issues': [good]},
            {'paging': 'bad', 'issues': []},
            {'total': 1, 'paging': {'pageIndex': 9}, 'issues': [good]},
            {'total': 1, 'paging': {'pageSize': 1}, 'issues': [good]},
            {'total': 1, 'issues': []}, {'total': 1, 'issues': 'bad'},
            {'total': 1, 'issues': [None]}, {'total': 1, 'issues': [{'project': 'fixture'}]},
            {'total': 1, 'issues': [{**good, 'project': 'other'}]},
            {'total': 1, 'issues': [{**good, 'component': 'other:source.py'}]},
            {'total': 1, 'issues': [{**good, 'component': None}]},
            {'total': 1, 'issues': [good, {**good, 'key': 'i2'}]},
            {'total': 501, 'issues': [good] * 501},
        ]
        for payload in invalid:
            with self.subTest(payload=str(payload)[:100]), self.assertRaises(support.SonarToolError):
                self.fetch(payload)
        with self.assertRaises(support.SonarToolError):
            self.fetch({'total': 1, 'components': [{'key': 'other:source.py'}]}, 'components')
        payloads = iter([{'total': 2, 'issues': [good]}, {'total': 3, 'issues': [{**good, 'key': 'i2'}]}])
        with self.assertRaises(support.SonarToolError):
            support.paginate(lambda *a: next(payloads), 'base', 'token', '/api/items', {}, 'issues', 'fixture')
