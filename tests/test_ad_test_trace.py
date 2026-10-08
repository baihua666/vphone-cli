import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('ad_trace', Path(__file__).resolve().parents[1] / 'scripts/ad_test_trace.py')
trace = importlib.util.module_from_spec(spec)
spec.loader.exec_module(trace)


class AdTraceTests(unittest.TestCase):
    def test_only_confirmed_test_panel_request_counts(self):
        line = '[NativeAdTest] tap format=rewarded tokenOnly=false mode=测试设备验证 canRun=true attached=true'
        self.assertEqual(trace.classify(line), 'app_request_started')
        for old, new in [('测试设备验证', '正式用户验证'), ('canRun=true', 'canRun=false'),
                         ('attached=true', 'attached=false'), ('tokenOnly=false', 'tokenOnly=true')]:
            self.assertEqual(trace.classify(line.replace(old, new)), 'unverified_or_blocked_tap')

    def test_wrong_button_is_not_a_request(self):
        self.assertEqual(trace.classify('[NativeAdTest] tap serverBidding canTest=true'), 'unexpected_test_action')
        self.assertEqual(trace.classify('[NativeAdTest] tap viewAd=Banner'), 'unexpected_test_action')

    def test_loading_is_not_impression(self):
        self.assertEqual(trace.classify('[NativeAdTest] status=加载成功，正在展示…'), 'load_success_show_attempt')
        self.assertEqual(trace.classify('[NativeAdTest] status=加载失败：no_fill'), 'ad_failure')
        self.assertEqual(trace.classify('[NativeAdTest] status=已收到奖励回调：1'), 'reward_callback')

    def test_hour_boundary_and_check_window(self):
        with tempfile.TemporaryDirectory() as path:
            folder = Path(path)
            rows = []
            for hour, kind in [('2026-09-18T23:00:00+08:00', 'app_request_started'),
                               ('2026-09-19T00:00:00+08:00', 'app_request_started'),
                               ('2026-09-19T00:00:00+08:00', 'ui_request_sent')]:
                rows.append(dict(utc='', report_time='', report_hour=hour, elapsed_ms=0, kind=kind, message=''))
            result = trace.export_summary(folder, rows, 'Asia/Shanghai')
            self.assertEqual(result['app_request_starts'], 2)
            self.assertIsNone(result['impressions'])
            self.assertIn('2026-09-19T05:00:00+08:00', (folder / 'hours.csv').read_text())
            self.assertEqual(json.loads((folder / 'summary.json').read_text())['failures'], 0)

    def test_unrelated_sdk_logs_do_not_count(self):
        self.assertEqual(trace.classify('SDK advertisement loaded'), 'raw')

    def test_latency_uses_monotonic_elapsed_not_wall_clock(self):
        with tempfile.TemporaryDirectory() as path:
            rows = [dict(utc='2026-09-18T07:00:00Z', report_time='',
                         report_hour='2026-09-18T07:00:00+00:00', elapsed_ms=ms,
                         kind=kind, message='') for ms, kind in (
                             (4000, 'ui_request_sent'), (4111, 'app_request_started'),
                             (5096, 'ad_failure'))]
            result = trace.export_summary(Path(path), rows, 'UTC')
            self.assertEqual(result['app_start_after_ui_ms'], 111)
            self.assertEqual(result['load_result_after_ui_ms'], 1096)


if __name__ == '__main__':
    unittest.main()
