#!/usr/bin/env python3
"""Exercise the DMG layout gate against saved install-window .DS_Store files."""
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
CHECK = ROOT / "Scripts/dmg-layout-check.py"
FIXTURES = ROOT / "Tests/ReleaseScripts/Fixtures"
EXPECTED = ["Headroom.app=196,176", "Applications=484,176"]


def run(store, *args):
    return subprocess.run(
        [sys.executable, str(CHECK), str(FIXTURES / store), *args],
        capture_output=True, text=True,
    )


class DMGLayoutCheckTests(unittest.TestCase):
    def test_rejects_the_shipped_1_5_41_layout(self):
        # 1.5 (41) shipped Finder's default positions, reversed and above the arrow.
        result = run("dmg-1.5-41.DS_Store", *EXPECTED)
        self.assertEqual(result.returncode, 1)
        self.assertIn("Headroom.app: expected (196, 176), saved (265, 37)", result.stderr)
        self.assertIn("Applications: expected (484, 176), saved (95, 37)", result.stderr)

    def test_accepts_the_fixed_layout_with_hidden_items_parked(self):
        result = run("dmg-fixed-layout.DS_Store", *EXPECTED,
                     "--offscreen", ".background", ".VolumeIcon.icns")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_a_hidden_item_with_no_saved_position(self):
        result = run("dmg-1.5-41.DS_Store", "--offscreen", ".background")
        self.assertEqual(result.returncode, 1)
        self.assertIn(".background: expected off-window", result.stderr)


if __name__ == "__main__":
    unittest.main()
