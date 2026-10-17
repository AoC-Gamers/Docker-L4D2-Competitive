"""Real Bash entry point, local Git component, no Valve/Docker/private credentials."""
import json
import os
import pwd
from pathlib import Path
import shutil
import shlex
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

    def test_explicit_update_refreshes_sources_when_automatic_update_is_disabled(self):
        extra = {'L4D2_STACK_AUTOUPDATE': 'false'}
        self.assertSuccess(self.run_install('install', extra))
        lock = self.base/'state/source-lock.json'
        previous = json.loads(lock.read_text())
        (self.source/'plugin').write_text('version2')
        subprocess.run(['git', '-C', str(self.source), 'add', '.'], check=True)
        subprocess.run(['git', '-C', str(self.source), '-c', 'user.name=Test',
                        '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'updated fixture'], check=True)
        self.assertSuccess(self.run_install('update', extra))
        self.assertEqual((self.game/'addons/sourcemod/plugins/demo.smx').read_text(), 'version2')
        self.assertNotEqual(json.loads(lock.read_text()), previous)
        state = json.loads((self.base/'state/current/deploy-state.json').read_text())
        self.assertEqual(state['status'], 'ready')

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

    def test_missing_shared_load_is_advisory_before_publication_and_repeated_cache_replay(self):
        cfg = 'sm plugins load demo.smx\nsm plugins load external/missing.smx\n'
        self.hook.write_text(self.hook.read_text() +
            'mkdir -p "$DIR_CFG"\n' +
            'printf %s ' + shlex.quote(cfg) + ' > "$DIR_CFG/sharedplugins.cfg"\n')
        runs = [('install', {}), ('update', {'STACK_REUSE_SOURCES': 'true'}),
                ('update', {'STACK_REUSE_SOURCES': 'true'})]
        for iteration, (mode, extra) in enumerate(runs):
            result = self.run_install(mode, extra)
            self.assertSuccess(result)
            self.assertEqual((self.game/'cfg/sharedplugins.cfg').read_text(), cfg)
            self.assertEqual(result.stdout.count('Plugin load has no binary'), 1)
            self.assertIn('cfg/sharedplugins.cfg:2: addons/sourcemod/plugins/external/missing.smx', result.stdout)
            blocks = ['Acquire stack sources', 'Compose prepared stack artifacts',
                      'Apply final exclusions to composed artifacts',
                      'Preserve local configuration in candidate',
                      'Apply final exclusions after preserving local configuration',
                      'Inspect shared plugin loads in composed candidate',
                      'Plan managed-file publication', 'Stop affected running instances',
                      'Publish managed files', 'Synchronize instance links and private paths',
                      'Run after-sync extensions', 'Confirm publication']
            positions = [result.stdout.index(block) for block in blocks]
            self.assertEqual(positions, sorted(positions))
            self.assertEqual(json.loads((self.base/'state/current/deploy-state.json').read_text())['status'], 'ready')
            if iteration < 2:
                self.assertEqual(result.stdout.count('Process artifact with component hook: demo'), 1)
                if iteration == 0:
                    self.assertIn('Download Git source: demo', result.stdout + result.stderr)
            else:
                self.assertIn('Prepared cache reused: demo', result.stdout)
                self.assertNotIn('Process artifact with component hook: demo', result.stdout)

    def test_download_failure_and_required_hook_leave_tree(self):
        self.assertSuccess(self.run_install('install'))
        plugin=self.game/'addons/sourcemod/plugins/demo.smx'
        shutil.rmtree(self.base/'state/sources')
        shutil.rmtree(self.source)
        result=self.run_install(); self.assertNotEqual(result.returncode,0); self.assertEqual(plugin.read_text(),'version1')
        self.hook.unlink()
        result=self.run_install(); self.assertNotEqual(result.returncode,0); self.assertIn('Required hook',result.stdout+result.stderr)
        self.assertEqual(plugin.read_text(),'version1')

    def publication(self):
        paths=list((self.base/'state/publication').glob('*/journal.json'))
        self.assertEqual(len(paths),1)
        return paths[0].parent

    def retry(self,mode='retry'):
        return subprocess.run(['bash',str(self.installer/'bin/recover_stack.sh'),mode],env=self.env,capture_output=True,text=True,timeout=20)

    def test_publication_failure_manual_retry_without_redownload_or_hook(self):
        self.assertSuccess(self.run_install('install'))
        calls=self.base/'calls'
        self.hook.write_text(self.hook.read_text()+f'printf version2 > "$DIR_SOURCEMOD/plugins/demo.smx"\nprintf call >> "{calls}"\n')
        result=self.run_install(extra={'STACK_TEST_FAIL_PUBLISH_AFTER':'0'}); self.assertNotEqual(result.returncode,0)
        self.assertEqual((self.game/'addons/sourcemod/plugins/demo.smx').read_text(),'version2')
        self.assertEqual(json.loads((self.base/'state/current/deploy-state.json').read_text())['status'],'failed')
        tx=self.publication(); candidate=tx/'candidate/serverfiles/left4dead2/addons/sourcemod/plugins/demo.smx'
        self.assertEqual(candidate.read_text(),'version2'); self.assertFalse((tx/'backup').exists())
        self.assertFalse((self.base/'serverfiles/.stack-transaction').exists())
        blocked=self.run_install(); self.assertNotEqual(blocked.returncode,0)
        self.assertIn('Publication incomplete',blocked.stdout+blocked.stderr)
        shutil.rmtree(self.source)
        self.assertSuccess(self.retry())
        self.assertEqual(calls.read_text(),'call')
        self.assertFalse((tx/'candidate').exists())
        self.assertEqual(json.loads((self.base/'state/current/deploy-state.json').read_text())['status'],'ready')

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

    def test_killed_installer_blocks_automatic_deploy_until_manual_retry(self):
        self.assertSuccess(self.run_install('install'))
        self.hook.write_text(self.hook.read_text()+'printf version2 > "$DIR_SOURCEMOD/plugins/demo.smx"\n')
        result=self.run_install(extra={'STACK_TEST_KILL_PUBLISH_AFTER':'0'})
        self.assertNotEqual(result.returncode,0)
        self.assertNotEqual(json.loads((self.base/'state/current/deploy-state.json').read_text())['status'],'ready')
        result=self.run_install(extra={'STACK_REUSE_SOURCES':'true'})
        self.assertNotEqual(result.returncode,0)
        self.assertIn('Publication incomplete',result.stdout+result.stderr)
        self.assertSuccess(self.retry())
        self.assertEqual((self.game/'addons/sourcemod/plugins/demo.smx').read_text(),'version2')

    def test_manual_rebuild_after_logic_change_does_not_silently_publish_old_candidate(self):
        self.assertSuccess(self.run_install())
        self.hook.write_text(self.hook.read_text()+'printf version2 > "$DIR_SOURCEMOD/plugins/demo.smx"\n')
        self.assertNotEqual(self.run_install(extra={'STACK_TEST_FAIL_PUBLISH_AFTER':'0'}).returncode,0)
        self.hook.write_text(self.hook.read_text().replace('printf version2','printf version3'))
        refused=self.retry(); self.assertNotEqual(refused.returncode,0)
        self.assertIn('logic changed',refused.stdout+refused.stderr)
        self.assertSuccess(self.retry('rebuild'))
        self.assertSuccess(self.run_install(extra={'STACK_REUSE_SOURCES':'true'}))
        self.assertEqual((self.game/'addons/sourcemod/plugins/demo.smx').read_text(),'version3')

    def test_failed_publish_keeps_instances_stopped_and_manual_retry_restores_only_selection(self):
        self.assertSuccess(self.run_install())
        running=self.base/'running'; running.write_text('yes')
        events=self.base/'events'
        self.env.update(RUNNING=str(running),EVENTS=str(events),L4D2_AUTOSTART='true')
        for name in ('l4d2server','l4d2server-2'):
            p=self.app/name
            p.write_text('''#!/bin/bash
printf '%s %s\\n' "$(basename "$0")" "$1" >> "$EVENTS"
if [[ "$1" == stop ]]; then rm -f "$RUNNING"; else touch "$RUNNING"; fi
'''); p.chmod(0o755)
        (self.mock/'tmux').write_text('''#!/bin/bash
[[ "$*" == *'=l4d2server' && -f "$RUNNING" ]]
''')
        self.hook.write_text(self.hook.read_text()+'printf version2 > "$DIR_SOURCEMOD/plugins/demo.smx"\n')
        self.assertNotEqual(self.run_install(extra={'STACK_TEST_FAIL_PUBLISH_AFTER':'0'}).returncode,0)
        self.assertFalse(running.exists())
        self.assertEqual(events.read_text().splitlines(),['l4d2server stop'])
        self.assertSuccess(self.retry())
        self.assertEqual(events.read_text().splitlines(),['l4d2server stop','l4d2server start'])
        # An acknowledged resume must not restart a deliberately stopped server.
        running.unlink(); self.assertSuccess(self.retry())
        self.assertFalse(running.exists())

    def test_committed_recovery_marks_matching_deployment_ready_after_resume(self):
        self.assertSuccess(self.run_install())
        tx=self.publication()
        journal=json.loads((tx/'journal.json').read_text())
        journal['resume_pending']=True
        (tx/'journal.json').write_text(json.dumps(journal))
        (tx/'running-instances').write_text('l4d2server\n')
        state_path=self.base/'state/current/deploy-state.json'
        state=json.loads(state_path.read_text()); state['status']='failed'; state['last_error']='install_stack exited with code 137'
        state_path.write_text(json.dumps(state))
        events=self.base/'resume-events'
        executable=self.app/'l4d2server'
        executable.write_text(f'#!/bin/bash\nprintf "%s\\n" "$1" >> "{events}"\n'); executable.chmod(0o755)
        self.env['L4D2_AUTOSTART']='FALSE'

        self.assertSuccess(self.retry())

        state=json.loads(state_path.read_text())
        self.assertEqual(state['status'],'ready')
        self.assertEqual(events.read_text() if events.exists() else '', '')
        self.assertFalse(json.loads((tx/'journal.json').read_text())['resume_pending'])
        self.assertEqual((tx/'running-instances').read_text(),'')

    def test_committed_recovery_resume_failure_stays_failed(self):
        self.assertSuccess(self.run_install())
        tx=self.publication()
        journal=json.loads((tx/'journal.json').read_text()); journal['resume_pending']=True
        (tx/'journal.json').write_text(json.dumps(journal))
        (tx/'running-instances').write_text('l4d2server\n')
        state_path=self.base/'state/current/deploy-state.json'
        state=json.loads(state_path.read_text()); state['status']='failed'; state['last_error']='install_stack exited with code 137'
        state_path.write_text(json.dumps(state))
        events=self.base/'resume-events'
        executable=self.app/'l4d2server'
        executable.write_text(f'#!/bin/bash\nprintf "%s\\n" "$1" >> "{events}"\nexit 23\n'); executable.chmod(0o755)
        self.env['L4D2_AUTOSTART']='TRUE'

        result=self.retry()

        self.assertNotEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertEqual(json.loads(state_path.read_text())['status'],'failed')
        self.assertEqual(events.read_text().splitlines(),['start'])
        self.assertTrue(json.loads((tx/'journal.json').read_text())['resume_pending'])

    def test_committed_recovery_finalizes_matching_deployment_after_resume_ack(self):
        self.assertSuccess(self.run_install())
        tx=self.publication()
        journal=json.loads((tx/'journal.json').read_text()); journal['resume_pending']=False
        (tx/'journal.json').write_text(json.dumps(journal))
        (tx/'running-instances').write_text('')
        state_path=self.base/'state/current/deploy-state.json'
        state=json.loads(state_path.read_text()); state['status']='failed'; state['last_error']='manual publication retry failed'
        state_path.write_text(json.dumps(state))

        self.assertSuccess(self.retry())

        state=json.loads(state_path.read_text())
        self.assertEqual(state['status'],'ready')
        self.assertEqual(state['deployment_id'],journal['deployment_id'])

    def test_committed_recovery_preserves_deployment_metadata_from_ambient_profile(self):
        self.assertSuccess(self.run_install())
        tx=self.publication()
        journal=json.loads((tx/'journal.json').read_text()); journal['resume_pending']=False
        (tx/'journal.json').write_text(json.dumps(journal))
        state_path=self.base/'state/current/deploy-state.json'
        original=json.loads(state_path.read_text())
        original['status']='failed'; original['last_error']='interrupted after publication commit'
        state_path.write_text(json.dumps(original))

        self.assertSuccess(subprocess.run(
            ['bash',str(self.installer/'bin/recover_stack.sh'),'retry'],
            env=dict(self.env,STACK_PROFILE='other-profile',GAMESERVER='other-server'),
            capture_output=True,text=True,timeout=20))

        recovered=json.loads(state_path.read_text())
        self.assertEqual(recovered['status'],'ready')
        self.assertEqual(recovered['deployment_id'],original['deployment_id'])
        self.assertEqual(recovered['stack'],original['stack'])
        self.assertEqual(recovered['runtime'],original['runtime'])

    def test_recovery_error_preserves_deployment_metadata_from_ambient_profile(self):
        self.assertSuccess(self.run_install())
        tx=self.publication()
        journal=json.loads((tx/'journal.json').read_text()); journal['resume_pending']=True
        (tx/'journal.json').write_text(json.dumps(journal))
        (tx/'running-instances').write_text('l4d2server\n')
        state_path=self.base/'state/current/deploy-state.json'
        original=json.loads(state_path.read_text())
        original['status']='failed'; original['last_error']='interrupted after publication commit'
        state_path.write_text(json.dumps(original))
        executable=self.app/'l4d2server'
        executable.write_text('#!/bin/bash\nexit 23\n'); executable.chmod(0o755)

        result=subprocess.run(
            ['bash',str(self.installer/'bin/recover_stack.sh'),'retry'],
            env=dict(self.env,STACK_PROFILE='other-profile',GAMESERVER='other-server',L4D2_AUTOSTART='true'),
            capture_output=True,text=True,timeout=20)

        self.assertNotEqual(result.returncode,0,result.stdout+result.stderr)
        recovered=json.loads(state_path.read_text())
        self.assertEqual(recovered['status'],'failed')
        self.assertEqual(recovered['deployment_id'],original['deployment_id'])
        self.assertEqual(recovered['stack'],original['stack'])
        self.assertEqual(recovered['runtime'],original['runtime'])

    def test_rejected_recovery_operations_leave_matching_ready_state_unchanged(self):
        self.assertSuccess(self.run_install())
        tx=self.publication()
        state_path=self.base/'state/current/deploy-state.json'
        before=json.loads(state_path.read_text())
        for mode in ('invalid','rebuild'):
            with self.subTest(mode=mode):
                command=['bash',str(self.installer/'bin/recover_stack.sh')]
                if mode == 'invalid':
                    command.append('not-a-mode')
                else:
                    command.append('rebuild')
                result=subprocess.run(command,env=self.env,capture_output=True,text=True,timeout=20)
                self.assertNotEqual(result.returncode,0,result.stdout+result.stderr)
                self.assertEqual(json.loads(state_path.read_text()),before)

    def test_recovery_failure_for_foreign_deployment_does_not_mark_it_failed(self):
        self.assertSuccess(self.run_install())
        self.hook.write_text(self.hook.read_text()+'printf version2 > "$DIR_SOURCEMOD/plugins/demo.smx"\n')
        interrupted=self.run_install(extra={'STACK_TEST_FAIL_PUBLISH_AFTER':'0'})
        self.assertNotEqual(interrupted.returncode,0)
        tx=self.publication()
        state_path=self.base/'state/current/deploy-state.json'
        foreign=json.loads(state_path.read_text())
        foreign.update(deployment_id='newer-ready-deployment',status='ready',last_error=None)
        state_path.write_text(json.dumps(foreign))
        plugin=self.game/'addons/sourcemod/plugins/demo.smx'
        plugin.write_text('version3')
        candidate=tx/'candidate/serverfiles/left4dead2/addons/sourcemod/plugins/demo.smx'
        before_state=json.loads(state_path.read_text())
        before_journal=(tx/'journal.json').read_bytes()
        before_candidate=candidate.read_bytes()

        def tree_snapshot(root):
            snapshot={}
            for path in sorted(root.rglob('*')):
                relative=str(path.relative_to(root))
                if path.is_symlink():
                    snapshot[relative]=('symlink',path.readlink().as_posix())
                elif path.is_file():
                    snapshot[relative]=('file',path.read_bytes())
                elif path.is_dir():
                    snapshot[relative]=('dir',)
            return snapshot

        before_tree=tree_snapshot(self.game)
        for mode in ('retry','rebuild'):
            with self.subTest(mode=mode):
                result=subprocess.run(
                    ['bash',str(self.installer/'bin/recover_stack.sh'),mode],
                    env=self.env,capture_output=True,text=True,timeout=20)
                self.assertNotEqual(result.returncode,0,result.stdout+result.stderr)
                self.assertIn('different deployment',result.stdout+result.stderr)
                self.assertEqual(json.loads(state_path.read_text()),before_state)
                self.assertEqual(tree_snapshot(self.game),before_tree)
                self.assertEqual((tx/'journal.json').read_bytes(),before_journal)
                self.assertEqual(candidate.read_bytes(),before_candidate)

    def test_old_committed_receipt_does_not_mark_new_failed_deployment_ready(self):
        self.assertSuccess(self.run_install())
        tx=self.publication()
        journal=json.loads((tx/'journal.json').read_text()); journal['resume_pending']=True
        (tx/'journal.json').write_text(json.dumps(journal))
        (tx/'running-instances').write_text('')
        state_path=self.base/'state/current/deploy-state.json'
        state=json.loads(state_path.read_text())
        state.update(deployment_id='newer-failed-deployment',status='failed',last_error='install_stack exited with code 1')
        state_path.write_text(json.dumps(state))

        self.assertSuccess(self.retry())

        current=json.loads(state_path.read_text())
        self.assertEqual(current['status'],'failed')
        self.assertEqual(current['deployment_id'],'newer-failed-deployment')

    def test_legacy_committed_receipt_without_finalization_owner_stays_unfinalized(self):
        self.assertSuccess(self.run_install())
        tx=self.publication()
        journal=json.loads((tx/'journal.json').read_text())
        journal.pop('deployment_id',None); journal.pop('finalizes_deploy_state',None)
        journal['resume_pending']=True
        (tx/'journal.json').write_text(json.dumps(journal))
        (tx/'running-instances').write_text('l4d2server\n')
        state_path=self.base/'state/current/deploy-state.json'
        state=json.loads(state_path.read_text()); state['status']='failed'; state['last_error']='manual publication retry failed'
        state_path.write_text(json.dumps(state))
        events=self.base/'legacy-resume-events'
        executable=self.app/'l4d2server'
        executable.write_text(f'#!/bin/bash\nprintf "%s\\n" "$1" >> "{events}"\n'); executable.chmod(0o755)
        self.env['L4D2_AUTOSTART']='true'

        self.assertSuccess(self.retry())

        self.assertEqual(json.loads(state_path.read_text())['status'],'failed')
        self.assertTrue(json.loads((tx/'journal.json').read_text())['resume_pending'])
        self.assertEqual((tx/'running-instances').read_text(),'l4d2server\n')
        self.assertFalse(events.exists())

    def test_nested_publication_retry_leaves_parent_deploy_to_finalize_and_resume(self):
        self.assertSuccess(self.run_install())
        self.hook.write_text(self.hook.read_text().replace('cp "$1/plugin"', 'printf version2 > "$DIR_SOURCEMOD/plugins/demo.smx"\n# cp "$1/plugin"'))
        state_path=self.base/'state/current/deploy-state.json'
        state=json.loads(state_path.read_text()); state['status']='installing'
        state_path.write_text(json.dumps(state))
        owner_env={'STACK_DEPLOY_OWNER_PID':str(os.getpid()),'STACK_DEFER_RESUME':'true'}
        failed=self.run_install(extra={**owner_env,'STACK_TEST_FAIL_PUBLISH_AFTER':'0'})
        self.assertNotEqual(failed.returncode,0)
        tx=self.publication()
        journal=json.loads((tx/'journal.json').read_text())
        self.assertFalse(journal['finalizes_deploy_state'])
        state=json.loads(state_path.read_text()); state['status']='failed'; state['last_error']='deploy_stack exited with code 1'
        state_path.write_text(json.dumps(state))
        (tx/'running-instances').write_text('l4d2server\n')
        events=self.base/'nested-resume-events'
        executable=self.app/'l4d2server'
        executable.write_text(f'#!/bin/bash\nprintf "%s\\n" "$1" >> "{events}"\n'); executable.chmod(0o755)

        result=self.retry()

        self.assertSuccess(result)
        journal=json.loads((tx/'journal.json').read_text())
        self.assertEqual(journal['phase'],'committed')
        self.assertTrue(journal['resume_pending'])
        self.assertEqual(json.loads(state_path.read_text())['status'],'failed')
        self.assertEqual((tx/'running-instances').read_text(),'l4d2server\n')
        self.assertFalse(events.exists())
        self.assertIn('Complete deploy_stack.sh',result.stdout)

    def test_abandon_partial_metadata_keeps_last_committed_sources_for_rebuild(self):
        self.assertSuccess(self.run_install())
        confirmed=json.loads((self.base/'state/source-lock.json').read_text())
        (self.source/'plugin').write_text('unconfirmed version2')
        subprocess.run(['git','-C',str(self.source),'add','.'],check=True)
        subprocess.run(['git','-C',str(self.source),'-c','user.name=Test','-c','user.email=test@example.invalid','commit','-qm','next source'],check=True)
        result=self.run_install(extra={'STACK_TEST_FAIL_PUBLISH_AFTER':'2'})
        self.assertNotEqual(result.returncode,0)
        self.assertNotEqual(json.loads((self.base/'state/source-lock.json').read_text()),confirmed)
        self.assertSuccess(self.retry('rebuild'))
        self.assertEqual(json.loads((self.base/'state/source-lock.json').read_text()),confirmed)
        shutil.rmtree(self.source)
        self.assertSuccess(self.run_install(extra={'STACK_REUSE_SOURCES':'true'}))
        self.assertEqual((self.game/'addons/sourcemod/plugins/demo.smx').read_text(),'version1')

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
        tx=self.publication()
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

    def test_snapshot_hash_describes_copied_bytes_when_git_metadata_changes(self):
        identity=self.installer/'lib/source_identity.py'
        original=self.base/'state/sources/test/demo'
        marker=self.base/'metadata-changed'
        # Simulate Git maintenance completing between hashing and snapshot copy.
        identity.write_text(identity.read_text()+f'''
if __name__ == '__main__' and Path(sys.argv[1]) == Path({str(original)!r}) and not Path({str(marker)!r}).exists():
    Path({str(marker)!r}).write_text('changed')
    (Path(sys.argv[1])/'.git/FETCH_HEAD').write_text('metadata changed after hashing\\n')
''')
        self.assertSuccess(self.run_install())
        self.assertTrue(marker.exists())
        self.assertSuccess(self.run_install(extra={'STACK_REUSE_SOURCES':'true'}))
        self.assertEqual((self.game/'addons/sourcemod/plugins/demo.smx').read_text(),'version1')

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
        result=self.run_install()
        self.assertSuccess(result)
        for block in ('Download original archive: artifact.zip',
                      'Validate original archive: artifact.zip',
                      'Extract original archive: artifact.zip',
                      'Copy original archive to editable workspace'):
            self.assertIn(block,result.stdout+result.stderr)
        original=self.installer/'cache/artifacts'/sha/'artifact.zip'
        self.assertEqual(original.read_bytes(),archive.read_bytes())
        archive.unlink()
        result=self.run_install(extra={'STACK_REUSE_SOURCES':'true'})
        self.assertSuccess(result)
        self.assertIn('Prepared cache reused: demo',result.stdout)
        self.assertNotIn('Extract original archive:',result.stdout+result.stderr)
        self.assertEqual((self.game/'addons/sourcemod/plugins/demo.smx').read_text(),'archive version')
        # Force hook invalidation, while the pristine extraction remains reusable.
        self.hook.write_text(self.hook.read_text()+'# new policy\n')
        extractor=self.installer/'lib/tools_stack.sh'
        extractor.write_text(extractor.read_text()+'\nextract_archive() { echo unexpected extraction >&2; return 31; }\n')
        result=self.run_install(extra={'STACK_REUSE_SOURCES':'true'})
        self.assertSuccess(result)
        self.assertIn('Reuse extracted archive: artifact.zip',result.stdout+result.stderr)
        self.assertNotIn('Download original archive:',result.stdout+result.stderr)
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
