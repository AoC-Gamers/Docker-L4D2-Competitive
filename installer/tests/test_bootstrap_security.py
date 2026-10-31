import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('bootstrap', ROOT/'container/root/bootstrap.py')
bootstrap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bootstrap)


class BootstrapSecurity(unittest.TestCase):
    def test_runtime_has_no_caps_and_preserves_supplementary_groups(self):
        args = bootstrap.runtime_command(1000, 1000, ['runtime'])
        for option in ['--init-groups','--no-new-privs','--bounding-set=-all','--ambient-caps=-all','--inh-caps=-all']:
            self.assertIn(option, args)
        for value in ['0','-1','root','1;id','1000\n0']:
            with self.assertRaises(ValueError): bootstrap.numeric(value, 'UID')

    def test_ownership_migration_does_not_cross_mounts_or_symlinks_or_change_shared_gid(self):
        with tempfile.TemporaryDirectory() as tmp:
            data=Path(tmp)/'data'; data.mkdir(); resources=data/'resources'; resources.mkdir()
            (resources/'sdk').write_text('read only'); outside=Path(tmp)/'outside'; outside.write_text('private')
            (data/'link').symlink_to(outside)
            shared=data/'shared'; shared.mkdir(); shared.chmod(0o2770)
            (data/'normal').write_text('data')
            with patch.object(bootstrap,'mount_roots',return_value={str(resources)}), patch.object(bootstrap.os,'chown') as chown:
                bootstrap.repair_data(data,1234,5678,os.getuid(),os.getgid(),[])
            changes={str(call.args[0]):call.args[1:] for call in chown.call_args_list}
            self.assertNotIn(str(resources),changes); self.assertNotIn(str(resources/'sdk'),changes)
            self.assertNotIn(str(data/'link'),changes); self.assertNotIn(str(outside),changes)
            self.assertEqual(changes[str(shared)][1],-1)
            self.assertIn(str(data/'normal'),changes)

    def test_migration_preserves_ssh_identity_and_refuses_symlinks(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); old=root/'old'; old.mkdir(); new=root/'new'; new.mkdir()
            key=old/'ssh_host_ed25519_key'
            subprocess.run(['ssh-keygen','-q','-t','ed25519','-N','','-f',str(key)],check=True)
            original=key.read_bytes(); bootstrap.migrate_keys(old,new)
            self.assertEqual((new/key.name).read_bytes(),original)
            # An existing protected destination is not replaced on later boots.
            key.unlink(); key.symlink_to(root/'not-a-key')
            bootstrap.migrate_keys(old,new)
            (new/key.name).unlink()
            with self.assertRaises(OSError):bootstrap.migrate_keys(old,new)
            self.assertFalse((new/key.name).exists())

    def test_unsafe_legacy_key_permissions_fail_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); old=root/'old'; old.mkdir(); new=root/'new'; new.mkdir()
            (old/'ssh_host_rsa_key').write_text('not private')
            (old/'ssh_host_rsa_key').chmod(0o644)
            with self.assertRaises(ValueError): bootstrap.migrate_keys(old,new)
            self.assertFalse(list(new.iterdir()))

    def test_legacy_protection_does_not_follow_symlink(self):
        with tempfile.TemporaryDirectory() as tmp:
            source=Path(tmp)/'ssh';source.mkdir();outside=Path(tmp)/'outside';outside.write_text('data')
            (source/'ssh_host_rsa_key').symlink_to(outside)
            with patch.object(bootstrap.os,'fchown') as chown:
                with self.assertRaises(OSError):bootstrap.protect_legacy_keys(source)
            chown.assert_not_called()
            self.assertEqual(outside.read_text(),'data')

    def test_broken_legacy_directory_link_is_not_treated_as_no_identity(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);source=root/'legacy';source.symlink_to(root/'missing',target_is_directory=True)
            destination=root/'protected';destination.mkdir()
            with self.assertRaises(OSError):bootstrap.migrate_keys(source,destination)
            self.assertFalse(list(destination.iterdir()))

    def test_default_environment_keeps_secrets_out_of_public_pam_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);real_path=Path
            def paths(value):
                return root/'public-env' if value=='/etc/environment' else real_path(value)
            with patch.object(bootstrap,'STATE',root),patch.object(bootstrap,'Path',side_effect=paths),patch.object(bootstrap.os,'chown'):
                values=bootstrap.environment({'GITHUB_TOKEN':'secret-$(id)', 'LGSM_PASSWORD':'private'},1000,1000)
            self.assertEqual(values['SSH_PORT'],'422')
            self.assertEqual(values['REPO_RESOURCES_DIR'],'/data/resources')
            self.assertNotIn('L4D2_ADDITIONAL_INSTANCES',values)
            self.assertNotIn('secret-',(root/'public-env').read_text())
            self.assertNotIn('private',(root/'public-env').read_text())
            self.assertEqual((root/'environment.json').stat().st_mode & 0o777,0o640)
