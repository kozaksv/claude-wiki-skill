"""Incomplete or unbounded navigation must never certify an unchanged wiki."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("session_health_scan", ROOT / "hooks/lib/session_health.py")
health = importlib.util.module_from_spec(spec)
spec.loader.exec_module(health)


class ScanTests(unittest.TestCase):
    def test_directory_read_error_is_unknown(self):
        def failed_walk(root, *, followlinks, onerror):
            onerror(PermissionError("unreadable child"))
            return iter(())
        with patch.object(health.os, "walk", side_effect=failed_walk):
            self.assertIsNone(health.fingerprint(Path("/unused")))

    def test_empty_directory_tree_has_count_budget(self):
        visits = [("/unused", [], [])] * 4
        with patch.object(health, "MAX_FILES", 3), patch.object(health.os, "walk", return_value=iter(visits)):
            self.assertIsNone(health.fingerprint(Path("/unused")))

    def test_empty_directory_tree_has_time_budget(self):
        with patch.object(health.os, "walk", return_value=iter([("/unused", [], [])])), patch.object(health.time, "monotonic", side_effect=[0, 2]):
            self.assertIsNone(health.fingerprint(Path("/unused")))

    def test_real_empty_directory_is_a_complete_scan(self):
        with tempfile.TemporaryDirectory() as root:
            value = health.fingerprint(Path(root))
            self.assertIsInstance(value, str)
            self.assertEqual(len(value), 64)
