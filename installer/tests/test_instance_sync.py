import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import sys

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'lib'))
from instance_layout import synchronize, migrate

INSTALLER=Path(__file__).resolve().parents[1]

class InstanceSync(unittest.TestCase):
    def test_repeated_sync_preserves_private_bytes_and_logs(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); game=root/'game'; sm=game/'addons/sourcemod'; app=root/'app'; app.mkdir(); config=root/'config'; config.mkdir()
            (config/'instances_exclude.json').write_text(json.dumps({'data':['dumps','bansystem_chatlog'],'plugins':['private.smx']}))
            for rel,value in [('plugins/community.smx','community'),('plugins/private.smx','default'),('data/static.cfg','static'),('data/dumps/primary','DO NOT COPY'),('data/bansystem_chatlog/private','DO NOT COPY')]:
                path=sm/rel; path.parent.mkdir(parents=True,exist_ok=True); path.write_text(value)
            dest=Path(str(sm)+'1')
            for rel,value in [('data/dumps/local','own'),('data/bansystem_chatlog/local','own-chat'),('logs/errors_1.log','evidence'),('plugins/private.smx','private-instance')]:
                path=dest/rel; path.parent.mkdir(parents=True,exist_ok=True); path.write_text(value)
            executable=app/'l4d2server'; executable.write_text('#!/bin/bash\nexit 0\n'); executable.chmod(0o755)
            mock=root/'mock'; mock.mkdir(); tmux=mock/'tmux'; tmux.write_text('#!/bin/bash\nexit 1\n'); tmux.chmod(0o755)
            env=dict(os.environ,DIR_INSTALLER_BIN=str(INSTALLER/'bin'),DIR_INSTALLER_LIB=str(INSTALLER/'lib'),DIR_INSTALLER_CONFIG=str(config),DIR_APP=str(app),DIR_SOURCEMOD=str(sm),DIR_LEFT4DEAD2=str(game),DIR_CFG=str(game/'cfg'),DIR_INSTALLER_STATE=str(root/'state'),GAMESERVER='l4d2server',STACK_LOCK_ROOT=str(root/'locks'),PATH=str(mock)+':'+os.environ['PATH'])
            for _ in range(3):
                result=subprocess.run(['bash',str(INSTALLER/'bin/sync_instances.sh'),'0'],env=env,capture_output=True,text=True)
                self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                self.assertEqual((dest/'data/dumps/local').read_text(),'own')
                self.assertEqual((dest/'logs/errors_1.log').read_text(),'evidence')
                self.assertEqual((dest/'plugins/private.smx').read_text(),'private-instance')
                self.assertFalse((dest/'data/dumps/primary').exists())
                self.assertTrue((dest/'plugins/community.smx').exists())
                self.assertFalse((game/'addons/.instance-data').exists())
                self.assertFalse(Path(str(dest)+'.previous').exists())
                self.assertFalse((dest/'data').is_symlink())
                self.assertFalse((dest/'logs').is_symlink())

    def test_existing_link_storage_migrates_back_without_copying_live_data(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); sm=root/'addons/sourcemod'; sm.mkdir(parents=True)
            plugin=sm/'plugins/shared.smx'; plugin.parent.mkdir(); plugin.write_text('shared')
            static=sm/'data/static.cfg'; static.parent.mkdir(); static.write_text('shared static')
            dest=root/'addons/sourcemod1'; dest.mkdir()
            stable=root/'addons/.instance-data/sourcemod1'
            for rel in ['data/dumps/local','logs/errors_1.log','overrides/plugins/private.smx']:
                p=stable/rel; p.parent.mkdir(parents=True,exist_ok=True); p.write_text(rel)
            (stable/'data/static.cfg').symlink_to(static)
            (dest/'data').symlink_to(stable/'data'); (dest/'logs').symlink_to(stable/'logs')
            (dest/'plugins').mkdir(); (dest/'plugins/shared.smx').symlink_to(plugin)
            (dest/'plugins/private.smx').symlink_to(stable/'overrides/plugins/private.smx')
            previous=Path(str(dest)+'.previous'); previous.mkdir()
            (previous/'plugins').symlink_to(sm/'plugins')
            inode=(stable/'data/dumps/local').stat().st_ino
            policy=root/'policy.json'; policy.write_text(json.dumps({'data':['dumps'],'plugins':['private.smx']}))
            for _ in range(3):
                synchronize(sm,dest,policy)
                self.assertEqual((dest/'data/dumps/local').stat().st_ino,inode)
                self.assertEqual((dest/'logs/errors_1.log').read_text(),'logs/errors_1.log')
                self.assertEqual((dest/'plugins/private.smx').read_text(),'overrides/plugins/private.smx')
                self.assertTrue((dest/'plugins/shared.smx').is_symlink())
                self.assertTrue((dest/'data/static.cfg').is_symlink())
                self.assertFalse(stable.parent.exists()); self.assertFalse(previous.exists())

    def test_migration_refuses_conflicts_and_keeps_unrecognized_private_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); dest=root/'addons/sourcemod1'; (dest/'logs').mkdir(parents=True)
            stable=root/'addons/.instance-data/sourcemod1'; (stable/'logs').mkdir(parents=True)
            local=dest/'logs/local'; local.write_text('active')
            old=stable/'logs/old'; old.write_text('old')
            with self.assertRaisesRegex(ValueError,'Conflicting physical'): migrate(dest,{})
            self.assertEqual(local.read_text(),'active'); self.assertEqual(old.read_text(),'old')

    def test_old_layout_with_physical_file_is_never_swept_away(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); sm=root/'addons/sourcemod'; sm.mkdir(parents=True)
            dest=root/'addons/sourcemod1'; dest.mkdir()
            previous=Path(str(dest)+'.previous'); previous.mkdir()
            unknown=previous/'unknown'; unknown.write_text('keep')
            policy=root/'policy.json'; policy.write_text('{}')
            with self.assertRaisesRegex(ValueError,'Physical file'): synchronize(sm,dest,policy)
            self.assertEqual(unknown.read_text(),'keep')

    def test_nested_exclusions_and_missing_primary_private_directories(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); sm=root/'sourcemod'; (sm/'data').mkdir(parents=True)
            (sm/'configs/project').mkdir(parents=True)
            (sm/'configs/project/default.cfg').write_text('default')
            (sm/'configs/project/private.cfg').write_text('private default')
            (sm/'data/sqlite').mkdir()
            (sm/'data/sqlite/shared.cfg').write_text('shared')
            (sm/'data/private.sq3').write_text('primary live database')
            dest=root/'sourcemod1'; policy=root/'policy.json'
            policy.write_text(json.dumps({'data':['dumps','bansystem_chatlog','sqlite/private','private.sq3'],'configs':['project/private.cfg']}))
            synchronize(sm,dest,policy)
            self.assertTrue((dest/'data/dumps').is_dir())
            self.assertTrue((dest/'data/bansystem_chatlog').is_dir())
            self.assertTrue((dest/'data/sqlite/private').is_dir())
            self.assertFalse((dest/'data/private.sq3').exists())
            (sm/'data/sqlite/later.cfg').write_text('later')
            private=dest/'configs/project/private.cfg'; private.write_text('own config')
            synchronize(sm,dest,policy)
            self.assertEqual(private.read_text(),'own config')
            self.assertTrue((dest/'configs/project/default.cfg').is_symlink())
            self.assertTrue((dest/'data/sqlite/later.cfg').is_symlink())

    def test_retired_instances_keep_private_files_and_can_be_reintroduced(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); game=root/'game'; sm=game/'addons/sourcemod'; app=root/'app'; app.mkdir()
            config=root/'config'; config.mkdir(); (config/'instances_exclude.json').write_text('{"data":["dumps"]}')
            (sm/'data/dumps').mkdir(parents=True); (sm/'data/dumps/primary').write_text('primary')
            (sm/'plugins').mkdir(); (sm/'plugins/community.smx').write_text('shared')
            cfg=game/'cfg'; cfg.mkdir(); (cfg/'l4d2server-2.cfg').write_text('local cfg')
            for name in ['l4d2server','l4d2server-2']:
                p=app/name; p.write_text('#!/bin/bash\nexit 0\n'); p.chmod(0o755)
            retired=Path(str(sm)+'2'); private=retired/'data/dumps/local'; private.parent.mkdir(parents=True); private.write_text('private bytes')
            mock=root/'mock'; mock.mkdir(); (mock/'tmux').write_text('#!/bin/bash\nexit 1\n'); (mock/'tmux').chmod(0o755)
            env=dict(os.environ,DIR_INSTALLER_BIN=str(INSTALLER/'bin'),DIR_INSTALLER_LIB=str(INSTALLER/'lib'),DIR_INSTALLER_CONFIG=str(config),DIR_APP=str(app),DIR_SOURCEMOD=str(sm),DIR_LEFT4DEAD2=str(game),DIR_CFG=str(cfg),DIR_INSTALLER_STATE=str(root/'state'),GAMESERVER='l4d2server',STACK_LOCK_ROOT=str(root/'locks'),PATH=str(mock)+':'+os.environ['PATH'])
            result=subprocess.run(['bash',str(INSTALLER/'bin/sync_instances.sh'),'0'],env=env,capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertFalse((app/'l4d2server-2').exists())
            self.assertEqual(private.read_text(),'private bytes'); self.assertEqual((cfg/'l4d2server-2.cfg').read_text(),'local cfg')
            synchronize(sm,retired,config/'instances_exclude.json')
            self.assertEqual(private.read_text(),'private bytes')
            self.assertTrue((retired/'plugins').is_symlink())

    def test_non_private_static_copies_refresh_to_shared_links_without_stale_plugins(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); sm=root/'sourcemod'; dest=root/'sourcemod1'
            (sm/'plugins').mkdir(parents=True); (dest/'plugins').mkdir(parents=True)
            (sm/'plugins/shared.smx').write_text('new canonical version')
            (dest/'plugins/shared.smx').write_text('old copied version')
            (dest/'plugins/stale.smx').write_text('retired plugin')
            (sm/'configs').mkdir(); (sm/'configs/default.cfg').write_text('default')
            (dest/'configs').mkdir(); local=dest/'configs/local.cfg'; local.write_text('local')
            policy=root/'policy.json'; policy.write_text('{}')
            for _ in range(2):
                synchronize(sm,dest,policy)
                self.assertTrue((dest/'plugins').is_symlink())
                self.assertEqual((dest/'plugins/shared.smx').read_text(),'new canonical version')
                self.assertFalse((dest/'plugins/stale.smx').exists())
                self.assertEqual(local.read_text(),'local')

    def test_missing_nested_private_path_rejects_external_symlink_parent_repeatedly(self):
        for folder in ('data','configs','plugins'):
            for target_exists in (False,True):
                with self.subTest(folder=folder,target_exists=target_exists), tempfile.TemporaryDirectory() as tmp:
                    root=Path(tmp); sm=root/'sourcemod'; (sm/folder).mkdir(parents=True)
                    dest=root/'sourcemod1'; (dest/folder).mkdir(parents=True)
                    external=root/'outside'; external.mkdir(); sentinel=external/'keep.txt'; sentinel.write_text('external data')
                    if target_exists: (external/'missing').mkdir()
                    (dest/folder/'custom').symlink_to(external, target_is_directory=True)
                    policy=root/'policy.json'; policy.write_text(json.dumps({folder:['custom/missing']}))

                    for _ in range(2):
                        with self.assertRaisesRegex(ValueError,'Private path has a symlink parent'):
                            synchronize(sm,dest,policy)
                        self.assertTrue((dest/folder/'custom').is_symlink())
                        self.assertEqual((dest/folder/'custom').resolve(),external.resolve())
                        self.assertEqual(sentinel.read_text(),'external data')
                        self.assertEqual((external/'missing').is_dir(),target_exists)
                        self.assertFalse((sm/folder/'custom').exists())

    def test_refresh_rejects_external_symlink_parent_without_detaching_its_data(self):
        for folder in ('data','configs','plugins'):
            with self.subTest(folder=folder), tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp); sm=root/'sourcemod'; canonical=sm/folder/'custom'
                canonical.mkdir(parents=True); (canonical/'shared.cfg').write_text('canonical')
                dest=root/'sourcemod1'; (dest/folder).mkdir(parents=True)
                external=root/'outside'; external.mkdir(); sentinel=external/'keep.txt'; sentinel.write_text('external data')
                (dest/folder/'custom').symlink_to(external, target_is_directory=True)
                policy=root/'policy.json'; policy.write_text(json.dumps({folder:['custom/missing']}))

                with self.assertRaisesRegex(ValueError,'Unverified symlink blocks private instance layout'):
                    synchronize(sm,dest,policy)
                self.assertTrue((dest/folder/'custom').is_symlink())
                self.assertEqual((dest/folder/'custom').resolve(),external.resolve())
                self.assertEqual(sentinel.read_text(),'external data')
                self.assertFalse((external/'missing').exists())
                self.assertEqual((canonical/'shared.cfg').read_text(),'canonical')

    def test_nested_private_path_replaces_only_a_verified_canonical_parent_link(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); sm=root/'sourcemod'; canonical=sm/'data/custom'
            canonical.mkdir(parents=True); (canonical/'shared.cfg').write_text('canonical')
            dest=root/'sourcemod1'; (dest/'data').mkdir(parents=True)
            (dest/'data/custom').symlink_to(canonical, target_is_directory=True)
            policy=root/'policy.json'; policy.write_text(json.dumps({'data':['custom/missing']}))

            for _ in range(2):
                synchronize(sm,dest,policy)
                local=dest/'data/custom'
                self.assertFalse(local.is_symlink())
                self.assertEqual((local/'shared.cfg').read_text(),'canonical')
                self.assertTrue((local/'shared.cfg').is_symlink())
                self.assertTrue((local/'missing').is_dir())
                self.assertFalse((canonical/'missing').exists())

    def test_legacy_private_override_rejects_external_symlink_parent_without_moving_data(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); sm=root/'sourcemod'; (sm/'data').mkdir(parents=True)
            dest=root/'sourcemod1'; (dest/'data').mkdir(parents=True)
            external=root/'outside'; external.mkdir(); sentinel=external/'keep.txt'; sentinel.write_text('external data')
            (dest/'data/custom').symlink_to(external, target_is_directory=True)
            stable=root/'.instance-data/sourcemod1'
            legacy=stable/'overrides/data/custom/missing/private.db'
            legacy.parent.mkdir(parents=True); legacy.write_text('legacy private data')
            policy=root/'policy.json'; policy.write_text(json.dumps({'data':['custom/missing']}))

            for _ in range(2):
                with self.assertRaisesRegex(ValueError,'Shared parent hides private override'):
                    synchronize(sm,dest,policy)
                self.assertEqual(legacy.read_text(),'legacy private data')
                self.assertEqual(sentinel.read_text(),'external data')
                self.assertFalse((external/'missing').exists())
                self.assertTrue((dest/'data/custom').is_symlink())

    def test_legacy_override_source_rejects_external_symlink_parent_before_rename(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); sm=root/'sourcemod'; sm.mkdir()
            dest=root/'sourcemod1'; dest.mkdir()
            stable=root/'.instance-data/sourcemod1'; overrides=stable/'overrides'
            overrides.mkdir(parents=True)
            external=root/'outside'; external.mkdir(); legacy=external/'private.smx'; legacy.write_text('external private bytes')
            (overrides/'plugins').symlink_to(external, target_is_directory=True)
            policy=root/'policy.json'; policy.write_text(json.dumps({'plugins':['private.smx']}))

            for _ in range(2):
                with self.assertRaisesRegex(ValueError,'Private path has a symlink parent'):
                    synchronize(sm,dest,policy)
                self.assertEqual(legacy.read_text(),'external private bytes')
                self.assertTrue((overrides/'plugins').is_symlink())
                self.assertEqual((overrides/'plugins').resolve(),external.resolve())
                self.assertFalse((dest/'plugins/private.smx').exists())

    def test_legacy_migration_rejects_symlink_instance_root_before_moving_private_data(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); outside=root/'outside'; outside.mkdir()
            dest=root/'addons/sourcemod1'; dest.parent.mkdir()
            dest.symlink_to(outside, target_is_directory=True)
            stable=dest.parent/'.instance-data/sourcemod1'
            private=stable/'data/dumps/local.db'; private.parent.mkdir(parents=True); private.write_text('legacy private bytes')
            inode=private.stat().st_ino

            for _ in range(2):
                with self.assertRaisesRegex(ValueError,'Instance root cannot be a symlink'):
                    migrate(dest,{})
                self.assertTrue(dest.is_symlink())
                self.assertEqual(dest.resolve(),outside.resolve())
                self.assertEqual(private.read_text(),'legacy private bytes')
                self.assertEqual(private.stat().st_ino,inode)
                self.assertFalse((outside/'data').exists())

    def test_migrate_all_rejects_symlink_sourcemod_root_before_any_legacy_rename(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); addons=root/'addons'; addons.mkdir()
            outside=root/'outside'; outside.mkdir()
            source=addons/'sourcemod'; source.symlink_to(outside, target_is_directory=True)
            legacy=addons/'.instance-data/sourcemod2/data/private.db'
            legacy.parent.mkdir(parents=True); legacy.write_text('legacy private bytes')
            inode=legacy.stat().st_ino
            policy=root/'policy.json'; policy.write_text(json.dumps({'data':['private.db']}))

            for _ in range(2):
                result=subprocess.run(
                    ['python3',str(INSTALLER/'lib/instance_layout.py'),'--migrate-all',str(source),str(policy)],
                    capture_output=True,text=True)
                self.assertNotEqual(result.returncode,0,result.stdout+result.stderr)
                self.assertIn('SourceMod root must be a physical directory',result.stderr)
                self.assertTrue(source.is_symlink())
                self.assertEqual(source.resolve(),outside.resolve())
                self.assertEqual(legacy.read_text(),'legacy private bytes')
                self.assertEqual(legacy.stat().st_ino,inode)
                self.assertFalse((addons/'sourcemod2').exists())
                self.assertFalse((outside/'data').exists())
