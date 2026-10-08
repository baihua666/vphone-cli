"""Exercise the wrapper in an isolated repo; never build or touch a real VM."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class ExpWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="exp workflow ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.script = self.root / "scripts/exp.sh"
        self.script.parent.mkdir()
        shutil.copyfile(Path(__file__).resolve().parents[1] / "scripts/exp.sh", self.script)
        self.log = self.root / "calls.jsonl"
        self.library = self.root / "VM library"
        self.library.mkdir()
        self.env = dict(os.environ, VPHONE_LIBRARY_ROOT=str(self.library),
                        EXP_TEST_LOG=str(self.log), EXP_TEST_FAIL="")
        stub = '''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:] if Path(sys.argv[0]).name != 'build.sh' else ['build']
with open(os.environ['EXP_TEST_LOG'], 'a') as out:
    out.write(json.dumps(args) + '\\n')
if ' '.join(args[:2]) == os.environ.get('EXP_TEST_FAIL'):
    sys.exit(7)
'''
        for path in (self.script.parent / "build.sh",
                     self.root / ".build/vphone-cli.app/Contents/MacOS/vphone-cli"):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(stub)
            path.chmod(0o755)

    def run_script(self, *args):
        return subprocess.run(["zsh", str(self.script), *args], env=self.env,
                              text=True, capture_output=True)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_prepare_routes_flag_only_to_patch_and_preserves_paths(self):
        source = str(self.root / "firmware with spaces.ipsw")
        result = self.run_script("prepare", "new-phone", "--force-exc-guard",
                                 "--iphone-source", source)
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        self.assertEqual([c[:2] for c in calls], [["build"], ["vm", "new"],
                                                ["fw", "prepare"], ["fw", "patch"]])
        self.assertIn(source, calls[2])
        self.assertNotIn("--force-exc-guard", calls[2])
        self.assertEqual(calls[3][-3:], ["--variant", "exp", "--force-exc-guard"])
        for call in calls[1:]:
            self.assertEqual(call[call.index("--library-root") + 1], str(self.library))

    def test_default_does_not_enable_guard_patch(self):
        self.assertEqual(self.run_script("prepare", "new-phone").returncode, 0)
        self.assertNotIn("--force-exc-guard", self.calls()[-1])

    def test_dry_run_has_no_side_effects(self):
        result = self.run_script("prepare", "new-phone", "--dry-run", "--force-exc-guard")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--force-exc-guard", result.stdout)
        self.assertEqual(self.calls(), [])
        self.assertEqual(list(self.library.iterdir()), [])

    def test_existing_vm_is_never_modified(self):
        (self.library / "existing").mkdir()
        self.assertNotEqual(self.run_script("prepare", "existing").returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_failure_stops_before_patch(self):
        self.env["EXP_TEST_FAIL"] = "fw prepare"
        self.assertEqual(self.run_script("prepare", "new-phone").returncode, 7)
        self.assertEqual(self.calls()[-1][:2], ["fw", "prepare"])

    def test_invalid_options_fail_before_build(self):
        for args in (("prepare", "new-phone", "--iphone-source"),
                     ("prepare", "new-phone", "--variant", "regular"),
                     ("prepare", "../existing"),
                     ("create", "new-phone", str(self.root / "out.tzst"), "--force-exc-guard")):
            with self.subTest(args=args):
                self.assertNotEqual(self.run_script(*args).returncode, 0)
                self.assertEqual(self.calls(), [])


if __name__ == "__main__":
    unittest.main()
