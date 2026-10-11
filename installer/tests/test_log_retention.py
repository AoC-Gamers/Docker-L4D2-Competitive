import datetime
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('retention', Path(__file__).parents[1]/'lib/retain_error_logs.py')
retention = importlib.util.module_from_spec(spec)
spec.loader.exec_module(retention)


class LogRetention(unittest.TestCase):
    def test_dry_run_recent_writes_links_compression_and_expiry(self):
        now = datetime.datetime(2026, 10, 11, tzinfo=datetime.timezone.utc).timestamp()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ('errors_20261001.log', 'errors_20260101.log', 'errors_20260102.log', 'errors_20261011.log', 'local.log'):
                (root/name).write_text('evidence')
                os.utime(root/name, (now-100*86400, now-100*86400))
            os.utime(root/'errors_20260102.log', (now, now))
            (root/'errors_20260103.log').symlink_to(root/'local.log')
            expected = [('remove', 'errors_20260101.log'), ('compress', 'errors_20261001.log')]
            self.assertEqual(retention.retain(root, now=now), expected)
            self.assertTrue((root/'errors_20260101.log').exists())
            self.assertEqual(retention.retain(root, apply=True, now=now), expected)
            self.assertTrue((root/'errors_20261001.log.gz').is_file())
            self.assertFalse((root/'errors_20260101.log').exists())
            self.assertTrue((root/'errors_20260102.log').exists())
            self.assertTrue((root/'errors_20260103.log').is_symlink())
            self.assertEqual(retention.retain(root, apply=True, now=now), [])
