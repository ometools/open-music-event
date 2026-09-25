import importlib.util
from pathlib import Path
import unittest


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


runner = module('runner', 'run.py')
hosts = module('hosts', 'host-routing.py')


class HarnessTests(unittest.TestCase):
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

    def test_partial_block_is_not_overwritten(self):
        with self.assertRaises(ValueError):
            hosts.updated(hosts.BEGIN + '\n127.0.0.1 example.test\n', True)


if __name__ == '__main__':
    unittest.main()
