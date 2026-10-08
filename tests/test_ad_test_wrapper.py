import os
from pathlib import Path
import socket
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/ad_test_trace.sh'


class WrapperTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='ad-wrap-', dir='/tmp')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.vm = self.root / 'test vm'
        self.vm.mkdir()
        (self.vm / 'udid-prediction.txt').write_text('UDID=test-vm\nECID=ignored\n')
        sock = socket.socket(socket.AF_UNIX)
        sock.bind(str(self.vm / 'vphone.sock'))
        self.addCleanup(sock.close)
        tool = self.root / 'idevice_id'
        tool.write_text('#!/bin/sh\nprintf "real-iphone\\ntest-vm\\n"\n')
        tool.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.root) + os.pathsep + os.environ['PATH'])

    def run_wrapper(self, *args):
        return subprocess.run(['zsh', str(SCRIPT), *args, '--vm', str(self.vm)],
                              text=True, capture_output=True, env=self.env)

    def test_preview_selects_vm_among_multiple_devices(self):
        result = self.run_wrapper('rewarded', '--dry-run')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('--udid test-vm', result.stdout)
        self.assertIn('--placement-id 983634549', result.stdout)
        self.assertNotIn('--udid real-iphone', result.stdout)

    def test_interstitial_and_capture_only(self):
        result = self.run_wrapper('interstitial', '--capture-only', '--dry-run')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('--placement-id 983639115', result.stdout)
        self.assertNotIn('--request', result.stdout)

    def test_mismatched_udid_rejected(self):
        result = self.run_wrapper('--udid', 'real-iphone', '--dry-run')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('不一致', result.stderr)

    def test_disconnected_vm_rejected(self):
        (self.vm / 'udid-prediction.txt').write_text('UDID=offline-vm\n')
        self.assertNotEqual(self.run_wrapper('--dry-run').returncode, 0)

    def test_output_is_unique_and_invalid_duration_rejected(self):
        first = self.run_wrapper('--dry-run').stdout
        second = self.run_wrapper('--dry-run').stdout
        self.assertNotEqual(first, second)
        self.assertNotEqual(self.run_wrapper('--seconds', '0', '--dry-run').returncode, 0)


if __name__ == '__main__':
    unittest.main()
