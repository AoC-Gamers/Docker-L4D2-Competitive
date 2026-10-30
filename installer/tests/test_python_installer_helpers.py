"""Filesystem and downloader contracts; all data temporary and all network mocked."""
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'installer/lib'))
import git_original
import merge_local_configs
import safe_extract

spec = importlib.util.spec_from_file_location('workshop_contract', ROOT/'installer/bin/workshop.py')
workshop = importlib.util.module_from_spec(spec)
spec.loader.exec_module(workshop)


class InstallerFilesystem(unittest.TestCase):
    def test_archive_validation_precedes_extraction(self):
        for name in ('../escape', '/absolute', 'dir\\file'):
            with self.assertRaises(ValueError):
                safe_extract.check(name)
        safe_extract.check('./')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root/'safe.zip'
            with zipfile.ZipFile(archive, 'w') as z:
                z.writestr('dir/file', 'content')
            dest = root/'output'
            safe_extract.extract(archive, dest, True)
            self.assertFalse(dest.exists())
            safe_extract.extract(archive, dest)
            self.assertEqual((dest/'dir/file').read_text(), 'content')
            with zipfile.ZipFile(archive, 'w') as z:
                link = zipfile.ZipInfo('link')
                link.external_attr = (stat.S_IFLNK | 0o777) << 16
                z.writestr(link, 'outside')
            with self.assertRaises(ValueError):
                safe_extract.extract(archive, dest)
            archive = root/'safe.tar'
            with tarfile.open(archive, 'w') as tar:
                item = tarfile.TarInfo('file')
                item.size = 3
                tar.addfile(item, io.BytesIO(b'abc'))
            safe_extract.extract(archive, dest, True)
            subprocess.run([sys.executable, str(ROOT/'installer/lib/safe_extract.py'), str(archive), str(dest)], check=True)
            self.assertEqual((dest/'file').read_bytes(), b'abc')
            with tarfile.open(archive, 'w') as tar:
                item = tarfile.TarInfo('link')
                item.type = tarfile.SYMTYPE
                item.linkname = '../outside'
                tar.addfile(item)
            with self.assertRaises(ValueError):
                safe_extract.extract(archive, dest)

    def test_merge_keeps_local_edits_and_new_managed_loader(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            candidate, active, state = [root/n for n in ('candidate', 'active', 'state')]
            for base in (candidate, active):
                (base/'cfg').mkdir(parents=True)
                (base/'cfg/sharedplugins.cfg').write_text('new loader' if base == candidate else 'old loader')
                (base/'cfg/local.cfg').write_text('default' if base == candidate else 'local edit')
            state.mkdir()
            baseline = root/'baseline.json'
            subprocess.run([sys.executable, str(ROOT/'installer/lib/merge_local_configs.py'), str(candidate), str(active), str(state), str(baseline)], check=True)
            self.assertEqual((candidate/'cfg/local.cfg').read_text(), 'local edit')
            self.assertEqual((candidate/'cfg/sharedplugins.cfg').read_text(), 'new loader')
            self.assertIn('cfg/local.cfg', json.loads(baseline.read_text()))
            import hashlib
            (state/'managed-files.json').write_text(json.dumps({'hashes': {'cfg/local.cfg': hashlib.sha256(b'local edit').hexdigest()}}))
            (candidate/'cfg/local.cfg').write_text('updated default')
            merge_local_configs.merge(candidate, active, state, baseline)
            self.assertEqual((candidate/'cfg/local.cfg').read_text(), 'updated default')

    def test_git_mode_repair_rejects_content_changes_and_untracked_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(['git', 'init', '-q', str(root)], check=True)
            script = root/'script'
            script.write_text('echo fixture\n')
            script.chmod(0o755)
            (root/'text').write_text('text')
            subprocess.run(['git', 'add', '.'], cwd=root, check=True)
            subprocess.run(['git', '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture'], cwd=root, check=True)
            script.chmod(0o644)
            (root/'text').chmod(0o755)
            subprocess.run([sys.executable, str(ROOT/'installer/lib/git_original.py'), str(root)], check=True)
            self.assertTrue(script.stat().st_mode & 0o100)
            self.assertFalse((root/'text').stat().st_mode & 0o100)
            script.write_text('modified\n')
            self.assertFalse(git_original.restore_modes(root))
            subprocess.run(['git', 'checkout', '--', 'script'], cwd=root, check=True)
            (root/'untracked').write_text('private')
            self.assertFalse(git_original.restore_modes(root))


class WorkshopOffline(unittest.TestCase):
    def test_download_reuses_current_files_and_reports_failed_downloads(self):
        plugins = [{'publishedfileid': str(i), 'file_url': 'https://fixture.invalid/file', 'title': 'Map', 'time_updated': 1} for i in range(1, 4)]
        plugins.append({'publishedfileid': '4'})
        with tempfile.TemporaryDirectory() as directory, patch.object(workshop.urllib.request, 'urlretrieve', side_effect=[None, HTTPError('url', 503, 'busy', {}, None)]) as download:
            errors, failed, succeeded = workshop.download_plugins(directory, plugins, {'1': {'time_updated': 1}})
            self.assertEqual(errors, 1)
            self.assertEqual(failed[0]['publishedfileid'], '3')
            self.assertEqual(set(succeeded), {'1', '2'})
            self.assertEqual(download.call_count, 2)

    def test_steam_metadata_and_nested_collections(self):
        details = {'response': {'publishedfiledetails': [{'publishedfileid': '1'}]}}
        with patch.object(workshop.urllib.request, 'urlopen', return_value=io.BytesIO(json.dumps(details).encode())):
            error, plugins = workshop.get_plugins_info(['1'])
            self.assertIsNone(error)
            self.assertEqual(plugins[0]['publishedfileid'], '1')
        parent = {'response': {'collectiondetails': [{'publishedfileid': '10', 'children': [{'publishedfileid': '1', 'filetype': 0}, {'publishedfileid': '20', 'filetype': 2}, {'publishedfileid': 'other', 'filetype': 9}]}, {'publishedfileid': 'invalid'}]}}
        child = {'response': {'collectiondetails': [{'publishedfileid': '20', 'children': [{'publishedfileid': '2', 'filetype': 0}]}]}}
        with patch.object(workshop.urllib.request, 'urlopen', side_effect=[io.BytesIO(json.dumps(parent).encode()), io.BytesIO(json.dumps(child).encode())]):
            error, plugins, valid = workshop.get_plugins_id_from_collections_list(['10'])
            self.assertIsNone(error)
            self.assertEqual(plugins, ['1', '2'])
            self.assertEqual(valid, ['10'])
        for function in (workshop.get_plugins_info, workshop.get_plugins_id_from_collections_list):
            for error in (HTTPError('url', 503, 'busy', {}, None), URLError('offline')):
                with patch.object(workshop.urllib.request, 'urlopen', side_effect=error):
                    self.assertIs(function(['1'])[0], error)

    def test_saved_state_arguments_and_retry_do_not_require_steam_or_game(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            save = root/'addons.lst'
            self.assertEqual(workshop.load_saved_data(save), {})
            save.write_text(json.dumps({'collections': ['10'], 'plugins': {'1': {'time_updated': 1}}}))
            with patch.object(workshop.os, 'getcwd', return_value=directory):
                self.assertEqual(workshop.init(['workshop', '-o', directory, '10'])[1], directory)
                self.assertEqual(workshop.init(['workshop', '-o', str(root/'missing')])[0], 1)
                for args in (['workshop', '-z'],):
                    with self.assertRaises(SystemExit):
                        workshop.init(args)
            with patch.object(workshop, 'init', return_value=(0, directory, [], str(save))), patch.object(workshop, 'get_plugins_id_from_collections_list', return_value=(None, ['1'], ['10'])), patch.object(workshop, 'get_plugins_info', return_value=(None, [{'publishedfileid': '1'}])), patch.object(workshop, 'download_plugins', side_effect=[(1, [{'publishedfileid': '1'}], {}), (0, [], {'1': {'title': 'done'}})]), patch.object(workshop.time, 'sleep') as sleep:
                workshop.main(['workshop'])
                sleep.assert_called_once_with(15)
                self.assertEqual(workshop.load_saved_data(save)['plugins'], {'1': {'title': 'done'}})
            with patch.object(workshop, 'init', return_value=(0, directory, [], str(root/'missing-save'))):
                workshop.main(['workshop'])
