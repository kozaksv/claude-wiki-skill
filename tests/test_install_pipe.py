"""`curl … | bash` safety: a truncated installer must execute nothing."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PipeSafety(unittest.TestCase):
    def run_piped(self, script: bytes, *args):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp) / "home"
            proc = subprocess.run(["bash", "-s", "--", *args], input=script, capture_output=True,
                                  env=dict(os.environ, HOME=str(home)), timeout=30)
            return proc, home.exists() and any(home.iterdir())

    def test_truncated_download_executes_nothing(self):
        data = (ROOT / "install.sh").read_bytes()
        for cut in (len(data) // 4, len(data) // 2, len(data) - 3):
            proc, touched = self.run_piped(data[:cut])
            self.assertNotEqual(proc.returncode, 0, cut)
            self.assertFalse(touched, cut)

    def test_full_pipe_runs(self):
        proc, _ = self.run_piped((ROOT / "install.sh").read_bytes(), "--help")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn(b"usage: install.sh", proc.stdout)


if __name__ == "__main__":
    unittest.main()
