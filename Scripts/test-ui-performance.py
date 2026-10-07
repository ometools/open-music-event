import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('metrics', Path(__file__).with_name('ui-performance.py'))
metrics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metrics)


class PerformanceReportingTests(unittest.TestCase):
    def test_repeated_entries_keep_app_time_separate_from_runner_time(self):
        report = metrics.summarize('''OME_PERF 1.0 enter.begin event
OME_PERF 1.1 install.begin event
OME_PERF 1.2 cache.hit event
OME_PERF 1.4 install.end event
OME_PERF 1.5 schedule.appear event
OME_PERF 2.0 enter.begin event
OME_PERF 2.1 http.begin /xrpc/example
OME_PERF 2.2 bundle-request.begin event
OME_PERF 2.3 bundle-request.end event
OME_PERF 2.5 schedule.appear event
''', [('commands.json', [{'command': {'tapOnElement': {}},
                          'metadata': {'duration': 6000, 'status': 'COMPLETED'}}])])
        self.assertEqual([e['action_to_schedule_appear_ms'] for e in report['entries']], [500, 500])
        self.assertEqual(report['entries'][0]['spans'], [{'phase': 'install', 'milliseconds': 300}])
        self.assertEqual(report['entries'][0]['http_requests'], [])
        self.assertEqual(report['entries'][1]['bundle_requests'], 1)
        self.assertEqual(report['automation_commands'][0]['duration_ms'], 6000)
        self.assertIsNone(report['thresholds'])

    def test_runner_entry_interval_includes_automation_overhead(self):
        rows = [
            {'command': {'tapOnElement': {'selector': {'idRegex': 'button.enter-event.test'}}},
             'metadata': {'timestamp': 1000, 'duration': 6000, 'status': 'COMPLETED'}},
            {'command': {'assertConditionCommand': {'condition': {'visible': {'idRegex': 'view.schedule.event'}}}},
             'metadata': {'timestamp': 7000, 'duration': 300, 'status': 'COMPLETED'}},
        ]
        report = metrics.summarize('', [('commands.json', rows)])
        self.assertEqual(report['automation_entries'][0]['tap_to_schedule_assert_ms'], 6300)
        rows[1]['metadata']['status'] = 'FAILED'
        self.assertIsNone(metrics.summarize('', [('commands.json', rows)])['automation_entries'][0]['tap_to_schedule_assert_ms'])

    def test_missing_or_failed_measurement_is_not_zero(self):
        self.assertEqual(metrics.summarize('', [])['entries'], [])
        entry = metrics.summarize('OME_PERF 1.0 enter.begin event', [])['entries'][0]
        self.assertFalse(entry['complete'])
        self.assertIsNone(entry['action_to_schedule_appear_ms'])


if __name__ == '__main__':
    unittest.main()
