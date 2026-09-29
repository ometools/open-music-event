import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
import json
import subprocess
import tempfile


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


runner = module('runner', 'run.py')
hosts = module('hosts', 'host-routing.py')
provision = module('provision', 'prepare-run.py')


class HarnessTests(unittest.TestCase):
    def test_resume_retries_failure_and_preserves_successful_signup(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            run = root / '.build/auth-e2e/runs/incomplete'
            (run / 'signup/ios').mkdir(parents=True)
            original_credentials = '{"password": "disposable-fixture-password"}'
            (run / 'credentials.json').write_text(original_credentials)
            (run / 'report.json').write_text(json.dumps(dict(
                run='incomplete', passed=False, failures=['old failure'],
                identities={'ios': 'ios-existing', 'android': 'android-existing'}, phases=[
                    dict(name='signup', platform='ios', passed=False),
                    dict(name='signup', platform='android', passed=True),
                ])))
            calls = []

            def execute(command, **kwargs):
                calls.append(command)
                return subprocess.CompletedProcess(command, 1 if command[0] == 'maestro' else 0)

            arguments = ['run.py', '--ios-device', 'ios', '--android-device', 'android',
                         '--ios-app-id', 'ios.app', '--android-app-id', 'android.app',
                         '--resume', str(run)]
            with patch.object(runner, 'ROOT', root), \
                 patch.object(runner.socket, 'getaddrinfo', return_value=[(None, None, None, None, ('127.0.0.1', 443))]), patch.object(runner, 'dedicated_ios'), \
                 patch.object(runner, 'dedicated_android'), \
                 patch.object(runner, 'output', return_value=''), \
                 patch.object(runner.subprocess, 'run', side_effect=execute), \
                 patch('sys.argv', arguments):
                with self.assertRaisesRegex(RuntimeError, 'signup: ios'):
                    runner.main()

            # Only the failed platform is retried, with the original UI account password.
            maestro = [command for command in calls if command[0] == 'maestro']
            self.assertEqual(len(maestro), 1)
            self.assertEqual(maestro[0][2], 'ios')
            self.assertIn('PASSWORD=disposable-fixture-password', maestro[0])
            self.assertIn('USERNAME=ios-existing', maestro[0])
            self.assertEqual((run / 'credentials.json').read_text(), original_credentials)
            report = json.loads((run / 'report.json').read_text())
            self.assertTrue(next(p for p in report['phases'] if p['platform'] == 'android')['passed'])
            self.assertEqual(report['failures'], ['signup: ios UI or network evidence failed'])

    def test_fresh_runs_keep_unique_persisted_account_identities(self):
        identities = []
        for _ in range(2):
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                commands = []
                def execute(command, **kwargs):
                    commands.append(command)
                    return subprocess.CompletedProcess(command, 1 if command[0] == 'maestro' else 0)
                arguments = ['run.py', '--ios-device', 'ios', '--android-device', 'android',
                             '--ios-app-id', 'ios.app', '--android-app-id', 'android.app']
                with patch.object(runner, 'ROOT', root), patch.object(runner.socket, 'getaddrinfo', return_value=[(None, None, None, None, ('127.0.0.1', 443))]), patch.object(runner, 'dedicated_ios'), \
                     patch.object(runner, 'dedicated_android'), patch.object(runner, 'output', return_value=''), \
                     patch.object(runner.subprocess, 'run', side_effect=execute), patch('sys.argv', arguments):
                    with self.assertRaises(RuntimeError):
                        runner.main()
                report = json.loads(next(root.rglob('report.json')).read_text())
                for platform, username in report['identities'].items():
                    self.assertRegex(username, '^' + platform + '-[a-f0-9]{10}$')
                    command = next(c for c in commands if c[0] == 'maestro' and c[2] == platform)
                    self.assertLessEqual(len(username), 18)
                    self.assertIn('USERNAME=' + username, command)
                    self.assertIn('HANDLE=' + username + '.pds1.ome-auth.test', command)
                    identities.append(username)
        self.assertEqual(len(set(identities)), 4)

    def test_prepare_and_missing_dns_never_start_ui(self):
        for prepare in (True, False):
            with self.subTest(prepare=prepare), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                arguments = ['run.py', '--ios-device', 'ios', '--android-device', 'android',
                             '--ios-app-id', 'ios.app', '--android-app-id', 'android.app']
                if prepare:
                    arguments.append('--prepare')
                with patch.object(runner, 'ROOT', root), patch.object(runner, 'dedicated_ios'), \
                     patch.object(runner, 'dedicated_android'), \
                     patch.object(runner.socket, 'getaddrinfo', side_effect=runner.socket.gaierror), \
                     patch.object(runner.subprocess, 'run') as execute, patch('sys.argv', arguments):
                    if prepare:
                        runner.main()
                    else:
                        with self.assertRaisesRegex(RuntimeError, 'No UI tests were started'):
                            runner.main()
                self.assertEqual(len(list(root.rglob('report.json'))), 1)
                self.assertFalse(any(call.args[0][0] == 'maestro' for call in execute.call_args_list))

    def test_log_rotation_does_not_hide_repeated_status_codes(self):
        before = ['09-28 20:00:00.000 123 I OME_AUTH_E2E getSession status=200']
        after = ['09-28 20:05:00.000 456 I OME_AUTH_E2E getSession status=401',
                 '09-28 20:05:00.010 456 I OME_AUTH_E2E refresh status=200',
                 '09-28 20:05:00.020 456 I OME_AUTH_E2E getSession status=200']
        self.assertTrue(runner.refresh_proven(runner.new_events(before, after)))
        self.assertEqual(runner.new_events(after, after), [])

    def test_successful_session_alone_does_not_prove_refresh(self):
        self.assertFalse(runner.refresh_proven([('getSession', '200')]))
        self.assertFalse(runner.refresh_proven([('refresh', '200'), ('getSession', '401')]))
        self.assertFalse(runner.refresh_proven([('getSession', '401'), ('refresh', '400'), ('getSession', '200')]))

    def test_expired_session_refresh_and_retry_are_required_in_order(self):
        self.assertTrue(runner.refresh_proven([('getSession', '401'), ('refresh', '400'),
                                               ('refresh', '200'), ('getSession', '200')]))

    def test_host_install_is_idempotent_and_preserves_other_entries(self):
        original = '127.0.0.1 localhost\n192.0.2.1 other.test\n'
        installed = hosts.updated(original, True)
        self.assertEqual(hosts.updated(installed, True), installed)
        self.assertEqual(hosts.updated(installed, False), original)

    def test_run_routes_are_idempotent_and_keep_existing_accounts(self):
        caddy = 'pds1.ome-auth.test, ios-tester.pds1.ome-auth.test {\n tls internal\n}\n'
        core = 'hosts {\n    172.30.248.2 pds1.ome-auth.test ios-tester.pds1.ome-auth.test\n}\n'
        handles = ['ios-new.pds1.ome-auth.test', 'android-new.pds1.ome-auth.test']
        routed = provision.routes(caddy, core, handles)
        self.assertEqual(provision.routes(*routed, handles), routed)
        for contents in routed:
            for name in handles + ['ios-tester.pds1.ome-auth.test']:
                self.assertEqual(contents.count(name), 1)
        installed = hosts.updated('127.0.0.1 localhost\n', True, handles)
        self.assertEqual(hosts.updated(installed, True, handles), installed)
        for name in handles:
            self.assertIn('127.0.0.1 ' + name, installed)

    def test_unrecognized_gateway_is_not_rewritten(self):
        with self.assertRaises(ValueError):
            provision.routes('unexpected config', 'unexpected config', ['ios-new.pds1.ome-auth.test'])

    def test_partial_block_is_not_overwritten(self):
        with self.assertRaises(ValueError):
            hosts.updated(hosts.BEGIN + '\n127.0.0.1 example.test\n', True)


if __name__ == '__main__':
    unittest.main()
