"""The retired EXP wrapper must never call an old build or modify a VM."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/exp.sh"


class RetiredExpWorkflowTests(unittest.TestCase):
    def test_old_actions_refuse_without_creating_files(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            env = dict(os.environ, VPHONE_LIBRARY_ROOT=str(root / "machines"))
            for args in (("prepare", "phone", "--dry-run"),
                         ("prepare", "phone", "--force-exc-guard"),
                         ("create", "phone", str(root / "out.tzst")),
                         ("export", "phone", str(root / "out.tzst"))):
                with self.subTest(args=args):
                    result = subprocess.run(["zsh", str(SCRIPT), *args], env=env,
                                            cwd=root, text=True, capture_output=True)
                    self.assertEqual(result.returncode, 2)
                    self.assertIn("未构建", result.stderr)
                    self.assertEqual(list(root.iterdir()), [])

    def test_help_explains_recovery_branch(self):
        result = subprocess.run(["zsh", str(SCRIPT), "--help"],
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0)
        self.assertIn("codex/pre-upstream-sync-20261008", result.stdout)


if __name__ == "__main__":
    unittest.main()
