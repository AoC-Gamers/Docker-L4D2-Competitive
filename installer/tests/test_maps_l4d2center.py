"""Run the actual map synchronizer with tiny archives and an offline HTTP fixture."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]


class MapsSync(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.addons = self.root / 'addons'
        self.addons.mkdir()
        self.tmp = self.root / 'tmp'
        self.tmp.mkdir()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        curl = self.bin / 'curl'
        curl.write_text('''#!/usr/bin/env python3
import json, os, pathlib, shutil, sys
root = pathlib.Path(os.environ['MAP_FIXTURE'])
args = sys.argv[1:]
url = args[-1]
with (root/'requests').open('a') as log:
    log.write(url+'\\n')
dest = args[args.index('--output')+1]
if url.endswith('/index.json'):
    if os.environ.get('FAIL_INDEX'):
        pathlib.Path(dest).write_text('partial')
        sys.exit(22)
    shutil.copyfile(root/'index.json', dest)
else:
    routes = json.loads((root/'routes.json').read_text())
    if url not in routes:
        sys.exit(22)
    shutil.copyfile(routes[url], dest)
''')
        curl.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.bin) + ':' + os.environ['PATH'],
                        MAP_FIXTURE=str(self.root), DIR_ADDONS=str(self.addons),
                        DIR_INSTALLER_LIB=str(ROOT / 'installer/lib'), DIR_TMP=str(self.tmp),
                        L4D2_MAP='', L4D2_MAPS_NO_MD5='false', L4D2_MAPS_FORCE_DOWNLOAD='false')
        self.entries = []
        self.routes = {}

    def add_map(self, name='test map.vpk', content=b'valid-map', kind='zip'):
        archive = self.root / (str(len(self.entries)) + '.' + kind)
        if kind == 'zip':
            with zipfile.ZipFile(archive, 'w') as output:
                output.writestr(name, content)
                output.writestr('../escape', 'must not be extracted')
                output.writestr('extra.vpk', 'must not be installed')
        else:
            source = self.root / 'source'
            source.mkdir(exist_ok=True)
            (source / name).write_bytes(content)
            subprocess.run(['7z', 'a', str(archive), name], cwd=source,
                           check=True, capture_output=True)
        url = 'https://fixture.invalid/' + name[:-4] + '.' + kind
        self.routes[url.replace(' ', '%20')] = str(archive)
        self.entries.append(dict(name=name, size=len(content),
                                 md5=hashlib.md5(content).hexdigest(), download_link=url))
        return self.addons / name

    def run_sync(self, **environment):
        (self.root / 'index.json').write_text(json.dumps(self.entries))
        (self.root / 'routes.json').write_text(json.dumps(self.routes))
        result = subprocess.run(['bash', str(ROOT / 'installer/bin/maps_l4d2center.sh')],
                                env=dict(self.env, **environment), text=True,
                                capture_output=True, timeout=20)
        self.assertEqual(list((self.tmp / 'maps').glob('sync.*')), [])
        self.assertEqual([p for p in self.addons.glob('.maps_l4d2center.*') if p.is_dir()], [])
        return result

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def requests(self):
        return (self.root / 'requests').read_text().splitlines()

    def test_zip_spaces_and_7z_install_only_expected_member(self):
        for kind in ('zip', '7z'):
            self.add_map(name=kind + ' map.vpk', kind=kind)
        self.assert_success(self.run_sync())
        self.assertEqual({p.name for p in self.addons.glob('*.vpk')}, {'zip map.vpk', '7z map.vpk'})
        self.assertFalse((self.root / 'escape').exists())
        self.assertEqual((self.addons / 'zip map.vpk').read_bytes(), b'valid-map')
        self.assertEqual((self.addons / 'zip map.vpk').stat().st_mode & 0o777, 0o644)

    def test_unchanged_index_still_repairs_missing_and_corrupt_files(self):
        target = self.add_map()
        self.assert_success(self.run_sync())
        self.assert_success(self.run_sync())
        self.assertEqual(len(self.requests()), 3)  # Two indices, one archive.
        for content in (None, b'bad-size!', b'bad'):
            if content is None:
                target.unlink()
            else:
                target.write_bytes(content)
            self.assert_success(self.run_sync())
            self.assertEqual(target.read_bytes(), b'valid-map')

    def test_force_filter_and_custom_files_preserved(self):
        one = self.add_map('one.vpk')
        two = self.add_map('two.vpk')
        custom = self.addons / 'my-custom.vpk'
        custom.write_bytes(b'private-map')
        self.assert_success(self.run_sync(L4D2_MAP='one'))
        self.assertTrue(one.exists())
        self.assertFalse(two.exists())
        cache = json.loads((self.tmp / 'cache_maps_l4d2center.json').read_text())
        self.assertEqual(list(cache), ['one.vpk'])
        self.assert_success(self.run_sync(L4D2_MAP='one', L4D2_MAPS_FORCE_DOWNLOAD='true'))
        self.assertEqual(len(self.requests()), 4)
        self.assertEqual(custom.read_bytes(), b'private-map')

    def test_http_failure_retries_preserves_old_map_and_cache(self):
        target = self.add_map()
        target.write_bytes(b'old-map')
        cache = self.tmp / 'cache_maps_l4d2center.json'
        cache.write_text('{"old": "receipt"}')
        self.routes.clear()
        result = self.run_sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.requests()), 4)
        self.assertEqual(target.read_bytes(), b'old-map')
        self.assertEqual(cache.read_text(), '{"old": "receipt"}')

    def test_bad_md5_size_archive_or_missing_member_never_replaces_old_map(self):
        target = self.add_map()
        archive = Path(next(iter(self.routes.values())))
        for fault in ('md5', 'size', 'archive', 'member'):
            with self.subTest(fault=fault):
                target.write_bytes(b'old-map')
                self.entries[0]['md5'] = hashlib.md5(b'valid-map').hexdigest()
                self.entries[0]['size'] = 9
                if fault == 'md5':
                    self.entries[0]['md5'] = '0' * 32
                elif fault == 'size':
                    self.entries[0]['size'] = 10
                elif fault == 'archive':
                    archive.write_bytes(b'not an archive')
                else:
                    with zipfile.ZipFile(archive, 'w') as output:
                        output.writestr('other.vpk', b'valid-map')
                self.assertNotEqual(self.run_sync().returncode, 0)
                self.assertEqual(target.read_bytes(), b'old-map')
                self.assertFalse((self.tmp / 'cache_maps_l4d2center.json').exists())

    def test_malformed_indices_rejected_before_any_map_download(self):
        target = self.add_map()
        good = dict(self.entries[0])
        for bad in ([], [good, good], [dict(good, name='../escape.vpk')],
                    [dict(good, name='*.vpk')], [dict(good, md5='bad')],
                    [dict(good, size=-1)], [dict(good, download_link='file:///etc/passwd')],
                    [dict(good, download_link='http://fixture.invalid/map.zip')], {'error': 'offline'}):
            with self.subTest(index=bad):
                self.entries = bad
                self.assertNotEqual(self.run_sync().returncode, 0)
                self.assertFalse(target.exists())
        self.assertTrue(all(url.endswith('index.json') for url in self.requests()))

    def test_symlink_destinations_and_unknown_selection_are_rejected(self):
        target = self.add_map()
        outside = self.root / 'outside'
        outside.write_bytes(b'private')
        target.symlink_to(outside)
        self.assertNotEqual(self.run_sync().returncode, 0)
        self.assertTrue(target.is_symlink())
        self.assertEqual(outside.read_bytes(), b'private')
        self.assertNotEqual(self.run_sync(L4D2_MAP='unknown').returncode, 0)
        self.assertNotEqual(self.run_sync(L4D2_MAPS_FORCE_DOWNLOAD='yes').returncode, 0)

    def test_no_md5_flag_still_checks_size(self):
        target = self.add_map()
        self.entries[0]['md5'] = '0' * 32
        self.assert_success(self.run_sync(L4D2_MAPS_NO_MD5='true'))
        self.assertEqual(target.read_bytes(), b'valid-map')
        self.entries[0]['size'] = 100
        self.assertNotEqual(self.run_sync(L4D2_MAPS_NO_MD5='true').returncode, 0)
        self.assertEqual(target.read_bytes(), b'valid-map')

    def test_index_http_failure_preserves_maps_and_receipt(self):
        target = self.add_map()
        target.write_bytes(b'old-map')
        cache = self.tmp / 'cache_maps_l4d2center.json'
        cache.write_text('old-receipt')
        self.assertNotEqual(self.run_sync(FAIL_INDEX='1').returncode, 0)
        self.assertEqual(target.read_bytes(), b'old-map')
        self.assertEqual(cache.read_text(), 'old-receipt')
        self.assertEqual(len(self.requests()), 1)

    def test_shared_addons_symlink_waits_for_same_destination_lock(self):
        target = self.add_map()
        alias = self.root / 'shared-addons'
        alias.symlink_to(self.addons, target_is_directory=True)
        (self.root / 'index.json').write_text(json.dumps(self.entries))
        (self.root / 'routes.json').write_text(json.dumps(self.routes))
        with (self.addons / '.maps_l4d2center.lock').open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            with subprocess.Popen(['bash', str(ROOT / 'installer/bin/maps_l4d2center.sh')],
                                  env=dict(self.env, DIR_ADDONS=str(alias)),
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as proc:
                try:
                    with self.assertRaises(subprocess.TimeoutExpired):
                        proc.communicate(timeout=0.3)
                    self.assertFalse((self.root / 'requests').exists())
                finally:
                    fcntl.flock(lock, fcntl.LOCK_UN)
                    stdout, stderr = proc.communicate(timeout=20)
                self.assertEqual(proc.returncode, 0, stdout + stderr)
        self.assertEqual(target.read_bytes(), b'valid-map')
