"""Real Bash entry point, local Git component, no Valve/Docker/private credentials."""
import json
import os
import pwd
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

INSTALLER=Path(__file__).resolve().parents[1]

class InstallerFlow(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.base=Path(self.temp.name); self.game=self.base/'serverfiles/left4dead2'; self.game.mkdir(parents=True)
        self.installer=self.base/'installer'; shutil.copytree(INSTALLER,self.installer)
        self.stack=self.base/'stack'; (self.stack/'hooks').mkdir(parents=True); (self.stack/'profiles').mkdir(); (self.stack/'manifests').mkdir()
        (self.stack/'preserve-paths.json').write_text('{"configs":["hostname.cfg"],"data":["sqlite"]}')
        (self.installer/'config/instances_exclude.json').write_text('{"data":["dumps"]}')
        self.app=self.base/'app'; self.app.mkdir(); self.mock=self.base/'mock'; self.mock.mkdir()
        (self.mock/'tmux').write_text('#!/bin/bash\nexit 1\n'); (self.mock/'tmux').chmod(0o755)
        (self.installer/'bin/geoip_update.sh').write_text('#!/bin/bash\nexit 0\n')
        self.source=self.base/'source'; self.source.mkdir()
        subprocess.run(['git','init','-q',str(self.source)],check=True)
        (self.source/'plugin').write_text('version1')
        subprocess.run(['git','-C',str(self.source),'add','.'],check=True)
        subprocess.run(['git','-C',str(self.source),'-c','user.name=Test','-c','user.email=test@example.invalid','commit','-qm','fixture'],check=True)
        self.hook=self.stack/'hooks/demo.default.sh'
        self.hook.write_text('''#!/bin/bash
set -euo pipefail
mkdir -p "$DIR_SOURCEMOD/plugins" "$DIR_SOURCEMOD/data/sqlite"
cp "$1/plugin" "$DIR_SOURCEMOD/plugins/demo.smx"
printf default > "$DIR_SOURCEMOD/data/sqlite/local.sq3"
''')
        (self.installer/'bin/sync_instances.sh').write_text('#!/bin/bash\nexit 0\n')
        (self.stack/'manifests/components.json').write_text(json.dumps({'demo':{'folder':'demo','source_type':'git','repo_url':str(self.source),'branch':'default','prepare_cache':True}}))
        (self.stack/'profiles/test.json').write_text('{"components":["demo"]}')
        # Docker can run as root while USER still names the image's LinuxGSM
        # account. The fixture belongs to the effective user, not that variable.
        fixture_user=pwd.getpwuid(os.geteuid()).pw_name
        self.env=dict(os.environ,PATH=str(self.mock)+':'+os.environ['PATH'],USER=fixture_user,DIR_INSTALLER=str(self.installer),DIR_INSTALLER_BIN=str(self.installer/'bin'),DIR_INSTALLER_LIB=str(self.installer/'lib'),DIR_INSTALLER_CONFIG=str(self.installer/'config'),DIR_INSTALLER_STATE=str(self.base/'state'),DIR_STACK=str(self.stack),DIR_STACK_HOOKS=str(self.stack/'hooks'),DIR_LEFT4DEAD2=str(self.game),DIR_SOURCEMOD=str(self.game/'addons/sourcemod'),DIR_ADDONS=str(self.game/'addons'),DIR_CFG=str(self.game/'cfg'),DIR_APP=str(self.app),DIR_TMP=str(self.base/'tmp'),STACK_PROFILE='test',GAMESERVER='l4d2server',L4D2_AUTOSTART='false',STACK_LOCK_ROOT=str(self.base/'locks'),GEOIPUPDATE_ENABLED='false')

    def run_install(self,mode='update',extra=None):
        result=subprocess.run(['bash',str(self.installer/'bin/install_stack.sh'),mode],env=dict(self.env,**(extra or {})),capture_output=True,text=True,timeout=20)
        return result

    def assertSuccess(self,result):
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_inherited_user_does_not_switch_away_from_fixture_owner(self):
        from unittest.mock import patch
        with patch.dict(os.environ, {'USER':'not-the-fixture-owner'}):
            fixture=InstallerFlow()
            fixture.setUp()
            self.addCleanup(fixture.doCleanups)
        fixture.assertSuccess(fixture.run_install())

    def test_profile_workspace_names_have_no_generated_trailing_underscore(self):
        for profile in ('develop', 'latest', 'feature_test', 'develop_'):
            with self.subTest(profile=profile):
                (self.stack/'profiles'/f'{profile}.json').write_text('{"components":["demo"]}')
                result=self.run_install('install',extra={'STACK_PROFILE':profile})
                self.assertSuccess(result)
                self.assertTrue((self.installer/'cache/work/install_stack'/profile).is_dir())
                self.assertTrue((self.base/'state/sources'/profile/'demo').is_dir())
                self.assertTrue((self.base/'state/cache'/f'{profile}.log').is_file())
                self.assertFalse((self.base/'state/sources'/(profile+'_')).exists())

    def test_legacy_profile_cache_keeps_pinned_sources_reusable_without_remote(self):
        entry=self.installer/'bin/install_stack.sh'
        current=entry.read_text()
        # Reproduce the previous formatter, including its accidental newline.
        legacy=current.replace("stack_profile_slug=\"$(printf '%s'",
                               "stack_profile_slug=\"$(printf '%s\\n'",1)
        self.assertNotEqual(current,legacy)
        entry.write_text(legacy)
        (self.stack/'profiles/develop.json').write_text('{"components":["demo"]}')
        self.assertSuccess(self.run_install('install',extra={'STACK_PROFILE':'develop'}))
        old_cache=self.base/'state/cache/develop_.log'
        old_source=self.base/'state/sources/develop_/demo/plugin'
        cached_state=old_cache.read_bytes()
        cached_source=old_source.read_bytes()
        pinned=json.loads((self.base/'state/source-lock.json').read_text())
        entry.write_text(current)
        shutil.rmtree(self.source)
        for _ in range(2):
            self.assertSuccess(self.run_install(extra={'STACK_PROFILE':'develop','STACK_REUSE_SOURCES':'true'}))
            self.assertTrue((self.installer/'cache/work/install_stack/develop').is_dir())
            self.assertTrue((self.base/'state/sources/develop').is_dir())
            self.assertTrue((self.base/'state/cache/develop.log').is_file())
            self.assertEqual(old_cache.read_bytes(),cached_state)
            self.assertEqual(old_source.read_bytes(),cached_source)
            self.assertEqual(json.loads((self.base/'state/source-lock.json').read_text()),pinned)
            self.assertEqual((self.game/'addons/sourcemod/plugins/demo.smx').read_text(),'version1')

    def test_install_repeat_local_reapply_and_hook_fail(self):
        self.assertSuccess(self.run_install('install'))
        plugin=self.game/'addons/sourcemod/plugins/demo.smx'; self.assertEqual(plugin.read_text(),'version1')
        db=self.game/'addons/sourcemod/data/sqlite/local.sq3'; db.parent.mkdir(parents=True,exist_ok=True); db.write_text('live')
        self.assertSuccess(self.run_install(extra={'STACK_REUSE_SOURCES':'true'}))
        self.assertEqual(db.read_text(),'live')
        self.hook.write_text(self.hook.read_text()+'exit 23\n')
        result=self.run_install(); self.assertNotEqual(result.returncode,0)
        self.assertEqual(plugin.read_text(),'version1'); self.assertEqual(db.read_text(),'live')
        state=json.loads((self.base/'state/current/deploy-state.json').read_text()); self.assertEqual(state['status'],'failed')
        sources=json.loads((self.base/'state/source-lock.json').read_text()); self.assertEqual(len(sources[0]['identity']['commit']),40)

    def test_download_failure_and_required_hook_leave_tree(self):
        self.assertSuccess(self.run_install('install'))
        plugin=self.game/'addons/sourcemod/plugins/demo.smx'
        shutil.rmtree(self.base/'state/sources')
        shutil.rmtree(self.source)
        result=self.run_install(); self.assertNotEqual(result.returncode,0); self.assertEqual(plugin.read_text(),'version1')
        self.hook.unlink()
        result=self.run_install(); self.assertNotEqual(result.returncode,0); self.assertIn('Required hook',result.stdout+result.stderr)
        self.assertEqual(plugin.read_text(),'version1')

    def test_publication_failure_restores_and_not_ready(self):
        self.assertSuccess(self.run_install('install'))
        self.hook.write_text(self.hook.read_text()+'printf version2 > "$DIR_SOURCEMOD/plugins/demo.smx"\n')
        result=self.run_install(extra={'STACK_TEST_FAIL_PUBLISH_AFTER':'0'}); self.assertNotEqual(result.returncode,0)
        self.assertEqual((self.game/'addons/sourcemod/plugins/demo.smx').read_text(),'version1')
        self.assertEqual(json.loads((self.base/'state/current/deploy-state.json').read_text())['status'],'failed')

    def test_extraction_failure_leaves_operational_tree(self):
        self.assertSuccess(self.run_install('install'))
        catalog={'demo':{'folder':'demo','source_type':'github_release','github_repo':'example/demo','release_tag':'fixed','asset_name':'bad.zip','branch':'default'}}
        (self.stack/'manifests/components.json').write_text(json.dumps(catalog))
        tools=self.installer/'lib/tools_stack.sh'
        tools.write_text(tools.read_text()+'''
github_api_request() { printf '%s\\n' '{"assets":[{"id":1,"name":"bad.zip","url":"https://api.github.com/repos/example/demo/releases/assets/1","browser_download_url":"https://github.com/example/demo.zip","updated_at":"fixed"}]}'; }
download_file() { printf corrupt > "$2"; }
''')
        result=self.run_install(); self.assertNotEqual(result.returncode,0)
        self.assertEqual((self.game/'addons/sourcemod/plugins/demo.smx').read_text(),'version1')
        self.assertEqual(json.loads((self.base/'state/current/deploy-state.json').read_text())['status'],'failed')

    def test_killed_installer_recovers_on_next_invocation(self):
        self.assertSuccess(self.run_install('install'))
        self.hook.write_text(self.hook.read_text()+'printf version2 > "$DIR_SOURCEMOD/plugins/demo.smx"\n')
        result=self.run_install(extra={'STACK_TEST_KILL_PUBLISH_AFTER':'0'})
        self.assertNotEqual(result.returncode,0)
        self.assertNotEqual(json.loads((self.base/'state/current/deploy-state.json').read_text())['status'],'ready')
        self.hook.write_text(self.hook.read_text().replace('printf version2','printf version3'))
        self.assertSuccess(self.run_install(extra={'STACK_REUSE_SOURCES':'true'}))
        self.assertEqual((self.game/'addons/sourcemod/plugins/demo.smx').read_text(),'version3')

    def test_logic_reapply_uses_last_committed_sources_after_failed_remote_update(self):
        self.assertSuccess(self.run_install('install'))
        (self.source/'plugin').write_text('version2')
        subprocess.run(['git','-C',str(self.source),'add','.'],check=True)
        subprocess.run(['git','-C',str(self.source),'-c','user.name=Test','-c','user.email=test@example.invalid','commit','-qm','new remote fixture'],check=True)
        original=self.hook.read_text(); self.hook.write_text(original+'exit 19\n')
        self.assertNotEqual(self.run_install().returncode,0)
        self.hook.write_text(original+'# new local materialization logic\n')
        shutil.rmtree(self.source) # Prove no remote resolution is necessary.
        self.assertSuccess(self.run_install(extra={'STACK_REUSE_SOURCES':'true'}))
        self.assertEqual((self.game/'addons/sourcemod/plugins/demo.smx').read_text(),'version1')

    def test_local_configs_survive_defaults_and_repeated_updates(self):
        self.hook.write_text(self.hook.read_text()+'''mkdir -p "$DIR_SOURCEMOD/configs" "$DIR_CFG"
printf default > "$DIR_SOURCEMOD/configs/databases.cfg"
printf default > "$DIR_CFG/local.cfg"
''')
        self.assertSuccess(self.run_install('install'))
        dbcfg=self.game/'addons/sourcemod/configs/databases.cfg'; dbcfg.write_text('local credentials fixture')
        local=self.game/'cfg/local.cfg'; local.write_text('custom local config')
        for _ in range(2):
            self.assertSuccess(self.run_install(extra={'STACK_REUSE_SOURCES':'true'}))
            self.assertEqual(dbcfg.read_text(),'local credentials fixture')
            self.assertEqual(local.read_text(),'custom local config')

    def test_prepared_cache_survives_ephemeral_directory_and_skips_hook(self):
        calls=self.base/'hook-calls'
        self.hook.write_text(self.hook.read_text()+f'printf call >> "{calls}"\n')
        self.assertSuccess(self.run_install())
        self.assertEqual(calls.read_text(),'call')
        shutil.rmtree(self.base/'tmp',ignore_errors=True)
        self.assertSuccess(self.run_install(extra={'STACK_REUSE_SOURCES':'true'}))
        self.assertEqual(calls.read_text(),'call')
        tx=self.base/'serverfiles/.stack-transaction'
        self.assertEqual(json.loads((tx/'journal.json').read_text())['phase'],'committed')
        for name in ('candidate','sources','backup'):
            self.assertFalse((tx/name).exists())
        plugin=self.game/'addons/sourcemod/plugins/demo.smx'
        plugin.unlink()
        result=self.run_install(extra={'STACK_REUSE_SOURCES':'true'})
        self.assertSuccess(result)
        self.assertIn('Prepared cache reused: demo',result.stdout)
        self.assertEqual(plugin.read_text(),'version1')
        self.assertEqual(calls.read_text(),'call')
        self.hook.write_text(self.hook.read_text()+'# changed hook\n')
        self.assertSuccess(self.run_install(extra={'STACK_REUSE_SOURCES':'true'}))
        self.assertEqual(calls.read_text(),'callcall')

    def test_corrupt_prepared_cache_is_rebuilt_without_publishing_bad_bytes(self):
        self.assertSuccess(self.run_install())
        payloads=list((self.installer/'cache/prepared').rglob('demo.smx'))
        self.assertEqual(len(payloads),1)
        payloads[0].write_text('corrupt')
        self.assertSuccess(self.run_install(extra={'STACK_REUSE_SOURCES':'true'}))
        self.assertEqual((self.game/'addons/sourcemod/plugins/demo.smx').read_text(),'version1')
        self.assertEqual(payloads[0].read_text(),'version1')

    def test_direct_zip_is_persistent_pristine_and_extracts_only_once(self):
        import zipfile, hashlib
        archive=self.base/'artifact.zip'
        with zipfile.ZipFile(archive,'w') as z: z.writestr('plugin','archive version')
        sha=hashlib.sha256(archive.read_bytes()).hexdigest()
        (self.stack/'manifests/components.json').write_text(json.dumps({'demo':{
            'folder':'demo','source_type':'archive','url':archive.as_uri(),
            'sha256':sha,'prepare_cache':True}}))
        self.assertSuccess(self.run_install())
        original=self.installer/'cache/artifacts'/sha/'artifact.zip'
        self.assertEqual(original.read_bytes(),archive.read_bytes())
        archive.unlink()
        self.assertSuccess(self.run_install(extra={'STACK_REUSE_SOURCES':'true'}))
        self.assertEqual((self.game/'addons/sourcemod/plugins/demo.smx').read_text(),'archive version')
        # Force hook invalidation, while the pristine extraction remains reusable.
        self.hook.write_text(self.hook.read_text()+'# new policy\n')
        extractor=self.installer/'lib/tools_stack.sh'
        extractor.write_text(extractor.read_text()+'\nextract_archive() { echo unexpected extraction >&2; return 31; }\n')
        self.assertSuccess(self.run_install(extra={'STACK_REUSE_SOURCES':'true'}))
        self.assertEqual(hashlib.sha256(original.read_bytes()).hexdigest(),sha)

    def test_declared_environment_and_upstream_layer_invalidate_prepared_cache(self):
        catalog=json.loads((self.stack/'manifests/components.json').read_text())
        catalog['demo']['prepare_env']=['PLUGIN_FLAVOR']
        (self.stack/'manifests/components.json').write_text(json.dumps(catalog))
        self.hook.write_text(self.hook.read_text()+'printf "%s" "$PLUGIN_FLAVOR" > "$DIR_SOURCEMOD/plugins/demo.smx"\n')
        for flavor in ('one','two','two'):
            self.assertSuccess(self.run_install(extra={'PLUGIN_FLAVOR':flavor,'STACK_REUSE_SOURCES':'true'}))
            self.assertEqual((self.game/'addons/sourcemod/plugins/demo.smx').read_text(),flavor)

    def test_hook_downloads_are_acquired_once_before_candidate_hooks(self):
        import zipfile
        archive=self.base/'framework.zip'
        with zipfile.ZipFile(archive,'w') as z: z.writestr('plugin','framework')
        catalog={'framework':{'folder':'framework','source_type':'hook_only','prepare_cache':True,
            'prepare_downloads':[{'name':'framework','url':'https://example.invalid/latest'}]}}
        (self.stack/'manifests/components.json').write_text(json.dumps(catalog))
        (self.stack/'profiles/test.json').write_text('{"components":["framework"]}')
        tools=self.installer/'lib/tools_stack.sh'
        tools.write_text(tools.read_text()+f'''
stack_resolve_archive_url() {{ printf '%s\\n' framework.zip https://example.invalid/exact; }}
download_file() {{ printf download >> "{self.base}/downloads"; cp "{archive}" "$2"; }}
''')
        # Resolver belongs to stack_component_lib; mock curl instead to cover its
        # redirect-resolution contract without contacting a public endpoint.
        curl=self.mock/'curl'
        curl.write_text('#!/bin/bash\nprintf resolve >> "'+str(self.base/'resolutions')+'"\nprintf https://example.invalid/framework.zip\n')
        curl.chmod(0o755)
        (self.stack/'hooks/framework.default.sh').write_text('''#!/bin/bash
set -euo pipefail
source "$DIR_INSTALLER_LIB/tools_stack.sh"
source "$DIR_INSTALLER_LIB/stack_component_lib.sh"
file=$(stack_download_release_tarball_if_changed framework https://example.invalid/latest "")
mkdir -p "$DIR_SOURCEMOD/plugins"
printf framework > "$DIR_SOURCEMOD/plugins/framework.smx"
''')
        self.assertSuccess(self.run_install())
        self.assertEqual((self.base/'downloads').read_text(),'download')
        self.assertEqual((self.base/'resolutions').read_text(),'resolve')
        lock=json.loads((self.base/'state/source-lock.json').read_text())
        self.assertEqual(len(lock[0]['identity']['framework']['sha256']),64)
        archive.unlink()
        self.assertSuccess(self.run_install(extra={'STACK_REUSE_SOURCES':'true'}))
        self.assertEqual((self.base/'downloads').read_text(),'download')
        self.assertEqual((self.base/'resolutions').read_text(),'resolve')
        self.assertEqual((self.game/'addons/sourcemod/plugins/framework.smx').read_text(),'framework')

    def test_failed_raw_expansion_never_caches_partial_output_or_publishes(self):
        import zipfile,hashlib
        self.assertSuccess(self.run_install())
        archive=self.base/'later.zip'
        with zipfile.ZipFile(archive,'w') as z: z.writestr('plugin','version2')
        sha=hashlib.sha256(archive.read_bytes()).hexdigest()
        (self.stack/'manifests/components.json').write_text(json.dumps({'demo':{
            'folder':'demo','source_type':'archive','url':archive.as_uri(),
            'sha256':sha,'prepare_cache':True}}))
        tools=self.installer/'lib/tools_stack.sh'
        tools.write_text(tools.read_text()+'\nextract_archive() { touch "$2/partial"; return 31; }\n')
        result=self.run_install()
        self.assertNotEqual(result.returncode,0)
        self.assertEqual((self.game/'addons/sourcemod/plugins/demo.smx').read_text(),'version1')
        self.assertEqual(json.loads((self.base/'state/current/deploy-state.json').read_text())['status'],'failed')
        self.assertEqual(list((self.installer/'cache/artifacts/expanded').glob('*.sha256')),[])
