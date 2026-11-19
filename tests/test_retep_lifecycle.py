"""RETEP regression tests; no live systemd or harmful resource allocation.

Run: python3 -m unittest discover -s tests -v
The real guest-reboot test remains a manual deployment gate.
"""
import os
import base64
import io
import tarfile
from pathlib import Path
import pwd
import subprocess
import sys
import tempfile
import types
import unittest
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / 'templates' / 'retep' / 'init.sh'
SOURCE = SCRIPT.read_text(encoding='utf-8')


def embedded(label):
    prefix = "<<'" + label + "'\n"
    assert SOURCE.count(prefix) == 1, label
    return SOURCE.split(prefix, 1)[1].split('\n' + label + '\n', 1)[0]


def loaded(name, source):
    module = types.ModuleType(name)
    exec(compile(source, name, 'exec'), module.__dict__)
    return module


class TestRetepSystemdTemplate(unittest.TestCase):
    def test_dependency_cycle_removed_but_persistence_retained(self):
        unit = SOURCE.split('cat > /etc/systemd/system/mem-boost.service <<UNIT\n', 1)[1].split('\nUNIT\n', 1)[0]
        self.assertIn('WantedBy=multi-user.target', unit)
        self.assertNotIn('After=multi-user.target', unit)
        self.assertIn('Restart=always', unit)
        self.assertIn('RestartSec=3', unit)

    def test_initial_infection_is_opt_in(self):
        # Activation must be inside the simulated installer, not at setup time.
        installer = embedded('FRONTEND')
        self.assertIn('/usr/local/lib/retep/activate', installer)
        self.assertIn('systemctl enable --now mem-boost.service', embedded('ACTIVATE'))
        self.assertNotIn('systemctl enable --now mem-boost.service', SOURCE.split("<<'ACTIVATE'", 1)[0])

    def test_no_risky_runtime_download(self):
        self.assertNotIn('curl ', SOURCE)
        self.assertNotIn('wget ', SOURCE)
        self.assertLess(len(SOURCE.encode('utf-8')), 65536)

    def test_media_archive_contains_twenty_files(self):
        raw = SOURCE.split("base64 --decode <<'RETEP_MEDIA_ARCHIVE' | tar -xz -C \"$team_home\"\n", 1)[1].split('\nRETEP_MEDIA_ARCHIVE\n', 1)[0]
        with tarfile.open(fileobj=io.BytesIO(base64.b64decode(raw)), mode='r:gz') as archive:
            files = [entry.name for entry in archive if entry.isfile()]
        self.assertEqual(sum('/Pictures/' in '/' + f for f in files), 15)
        self.assertEqual(sum('/Videos/' in '/' + f for f in files), 5)


class TestPeterCoreValidation(unittest.TestCase):
    """Run the *real embedded* Peter Core validation logic on temp fixtures."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='retep-test-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.root.chmod(0o755)
        self.config = self.root / 'core.conf'
        self.data = self.root / 'registry.dat'
        self.executable = self.root / 'peter-core'
        source = embedded('PETER_APP')
        source = source.replace("CONFIG = '/etc/peter-core/core.conf'", f'CONFIG = {str(self.config)!r}')
        source = source.replace("'/var/lib/peter-core/registry.dat'", repr(str(self.data)))
        self.executable.write_text(source)
        self.executable.chmod(0o755)
        self.config.write_text(self.good_config())
        self.config.chmod(0o644)
        self.data.write_text('PETER_DATABASE=READY\n')
        self.data.chmod(0o644)
        if os.geteuid() == 0:
            account = pwd.getpwnam('nobody')
            self.user = account.pw_uid
            self.group = account.pw_gid
        else:
            self.user = os.geteuid()
            self.group = os.getegid()

    def good_config(self):
        return '[server]\nschema = 2\nnode = peter\nmode = active\ndata_file = '+str(self.data)+'\n'

    def validate(self):
        # CI can run unprivileged; only use setuid/setgroups in root-capable test runs.
        credentials = (dict(user=self.user, group=self.group, extra_groups=[])
                       if os.geteuid() == 0 else {})
        return subprocess.run([str(self.executable), '--validate'], **credentials,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              text=True, timeout=5, check=False).returncode == 0

    def test_clean_configuration_and_valid_alternative_permissions(self):
        self.assertTrue(self.validate(), 'clean config must be readable')
        self.data.chmod(0o644)
        self.assertTrue(self.validate(), '0644 is valid despite being less private')
        if os.geteuid() == 0:
            os.chown(self.data, 0, self.group)
            self.data.chmod(0o640)
            self.assertTrue(self.validate(), 'root:servicegroup 0640 is valid')

    def test_broken_config_rejected_after_previous_good_validation(self):
        self.assertTrue(self.validate())
        for name, replacement in (('schema', 'schema = 1'),
                                  ('mode', 'mode = retep'),
                                  ('node', 'node = hostile'),
                                  ('path', 'data_file = /var/invalid/records.dat')):
            with self.subTest(name=name):
                config = self.good_config()
                config = config.replace(next(line for line in config.splitlines() if line.startswith(name if name != 'path' else 'data_file')), replacement)
                self.config.write_text(config)
                self.assertFalse(self.validate())
        self.config.write_text(self.good_config())
        self.assertTrue(self.validate())

    def test_registry_contents_rejected(self):
        self.data.write_text('PETER_DATABASE=BROKEN\n')
        self.assertFalse(self.validate())

    def test_actual_readability_rejected_as_unprivileged_service_user(self):
        self.assertTrue(self.validate())
        self.data.chmod(0o000)
        self.assertFalse(self.validate(), 'must not rely on root os.access')
        if os.geteuid() == 0:
            self.data.chmod(0o600)
            os.chown(self.data, 0, 0)
            self.assertFalse(self.validate(), 'root:root 0600 is unreadable to the service')

    def test_config_file_unreadability_rejected(self):
        self.config.chmod(0o000)
        self.assertFalse(self.validate())


class TestChecker(unittest.TestCase):
    def setUp(self):
        self.check = loaded('retep_check_test', embedded('CHECK'))
        self.tmp = tempfile.TemporaryDirectory(prefix='retep-check-test-')
        self.addCleanup(self.tmp.cleanup)
        self.unit = Path(self.tmp.name) / 'mem-boost.service'
        self.link = Path(self.tmp.name) / 'startup-link'
        self.check.UNIT = str(self.unit)
        self.check.STARTUP_LINK = str(self.link)
        self.unit.write_text('[Service]\n')
        self.controller = dict(core=True, resource=False, enabled=False,
                               restarting=False, heartbeat=True, config=True, worker=False)
        def ctl(*args):
            if args[0] == 'is-active':
                return self.controller['core'] if args[-1] == 'peter-core.service' else self.controller['resource']
            if args[0] == 'is-enabled':
                return self.controller['enabled']
            raise AssertionError(args)
        self.patches = [mock.patch.object(self.check, 'systemctl', side_effect=ctl),
                        mock.patch.object(self.check, 'retep_restart_pending', side_effect=lambda: self.controller['restarting']),
                        mock.patch.object(self.check, 'heartbeat_fresh', side_effect=lambda: self.controller['heartbeat']),
                        mock.patch.object(self.check, 'peter_configuration_valid_now', side_effect=lambda: self.controller['config']),
                        mock.patch.object(self.check, 'worker_running', side_effect=lambda: self.controller['worker'])]
        for p in self.patches: p.start(); self.addCleanup(p.stop)

    def test_stopped_and_disabled_unit_passes(self):
        self.assertTrue(self.check.recovery_ok())

    def test_deleted_unit_with_dangling_symlink_passes(self):
        self.link.symlink_to(self.unit)
        self.unit.unlink()
        self.assertTrue(self.link.is_symlink())
        self.assertFalse(self.link.exists())
        self.assertTrue(self.check.recovery_ok())

    def test_working_enabled_link_rejected(self):
        self.link.symlink_to(self.unit)
        self.controller['enabled'] = True
        self.assertFalse(self.check.recovery_ok())

    def test_enabled_unit_without_link_rejected(self):
        self.controller['enabled'] = True
        self.assertFalse(self.check.recovery_ok())

    def test_restarting_service_rejected_even_if_is_active_false(self):
        self.controller['restarting'] = True
        self.assertFalse(self.check.recovery_ok())

    def test_active_process_or_unhealthy_core_rejected(self):
        for issue, value in [('resource', True), ('worker', True), ('core', False),
                             ('heartbeat', False), ('config', False)]:
            with self.subTest(issue=issue):
                self.controller[issue] = value
                self.assertFalse(self.check.recovery_ok())
                self.controller[issue] = not value

    def test_checker_verifies_with_service_user_credentials(self):
        fake = types.SimpleNamespace(pw_uid=1234, pw_gid=5678, pw_name='petercore')
        fresh = loaded('fresh_checker_test', embedded('CHECK'))
        with (mock.patch.object(fresh.pwd, 'getpwnam', return_value=fake) as get,
              mock.patch.object(fresh.os, 'getgrouplist', return_value=[5678, 9000]) as groups,
              mock.patch.object(fresh.subprocess, 'run', return_value=types.SimpleNamespace(returncode=0)) as run):
            self.assertTrue(fresh.peter_configuration_valid_now())
            get.assert_called_once_with('petercore')
            self.assertEqual(run.call_args.kwargs['user'], 1234)
            self.assertEqual(run.call_args.kwargs['group'], 5678)
            self.assertEqual(run.call_args.kwargs['extra_groups'], [5678, 9000])
            groups.assert_called_once_with('petercore', 5678)
            self.assertIn('--validate', run.call_args.args[0])

    def test_actual_restart_delay_detection(self):
        fresh = loaded('fresh_restart_checker_test', embedded('CHECK'))
        with mock.patch.object(fresh, 'command', return_value=types.SimpleNamespace(stdout='auto-restart\n')):
            self.assertTrue(fresh.retep_restart_pending())
        with mock.patch.object(self.check, 'command', return_value=types.SimpleNamespace(stdout='dead\n')):
            self.assertFalse(fresh.retep_restart_pending())


class TestDialogue(unittest.TestCase):
    def setUp(self):
        self.dialogue = loaded('retep_dialogue_test', embedded('DIALOGUE_PY'))
        self.tmp = tempfile.TemporaryDirectory(prefix='retep-dialogue-test-')
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.dialogue.DIR = root
        self.dialogue.STATE = root / 'dialogue-state.json'
        self.dialogue.LOCK = root / 'dialogue-state.lock'
        self.dialogue.START = root / 'activated'
        self.dialogue.START.touch()
        self.dialogue.snapshot = lambda: dict(resource_active=False, resource_enabled=False,
                                              config_ok=True, data_ok=True, core_ok=True,
                                              restart_count=0, main_pid=0)
        self.messages = []
        self.dialogue.say = self.messages.append

    def invoke(self, *args):
        with (mock.patch.object(sys, 'argv', ['dialogue', *args]),
              mock.patch.object(self.dialogue.os, 'geteuid', return_value=0)):
            return self.dialogue.main()

    def test_48_lines_present(self):
        lines=self.dialogue.DIALOGUE
        self.assertEqual(len(lines), 14)
        self.assertEqual(sum(len(v) for v in lines.values()), 48)
        self.assertEqual([len(lines[key]) for key in ('ambient_full_control', 'ambient_peter_restored', 'ambient_retep_stopped')],[5,5,5])

    def test_complete_message_once_and_then_permanent_silence(self):
        self.assertEqual(self.invoke('event', 'team-1', 'complete'), 0)
        self.assertEqual(self.invoke('prompt', 'team-1', ''), 0)
        self.assertEqual(len(self.messages), 1)
        self.assertIn(self.messages[0], self.dialogue.DIALOGUE['final_defeat'])
        for _ in range(3):
            self.assertEqual(self.invoke('event', 'team-1', 'checker_incomplete'), 0)
            self.assertEqual(self.invoke('prompt', 'team-1', 'systemctl status mem-boost'), 0)
            self.assertEqual(self.invoke('event', 'team-1', 'complete'), 0)
        self.assertEqual(len(self.messages), 1)

    def test_event_only_queued_once(self):
        state = self.dialogue.load(123, self.dialogue.snapshot())
        self.dialogue.event(state, 'config_repaired')
        self.dialogue.event(state, 'config_repaired')
        self.assertEqual(len(state['pending']), 1)


if __name__ == '__main__':
    unittest.main()
