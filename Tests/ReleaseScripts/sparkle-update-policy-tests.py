#!/usr/bin/env python3
"""Exercise the real packaging stamp functions against isolated Info.plists."""
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
EXPECTED = {
    "SUEnableAutomaticChecks": True,
    "SUAllowsAutomaticUpdates": True,
    "SUAutomaticallyUpdate": False,
}


def shell_function(path, name):
    source = path.read_text()
    match = re.search(r"^" + re.escape(name) + r"\(\) \{\n.*?^\}", source, re.M | re.S)
    if match is None:
        raise AssertionError(f"Missing function {name} in {path}")
    return match.group(0)


class UpdatePolicyTests(unittest.TestCase):
    def test_xcode_defaults_allow_opt_in_without_enrolling_users(self):
        source = (ROOT / "project.yml").read_text()
        for key, value in EXPECTED.items():
            match = re.search(r"INFOPLIST_KEY_" + key + r":\s*(YES|NO)", source)
            self.assertIsNotNone(match, key)
            self.assertEqual(match.group(1), "YES" if value else "NO", key)

    def test_both_packaging_paths_stamp_opt_in_policy(self):
        for script, names in [
            ("build-app.sh", ["stamp_sparkle_info"]),
            ("release-app.sh", ["set_plist_string", "set_plist_bool", "stamp_exported_info"]),
        ]:
            with self.subTest(script=script), tempfile.TemporaryDirectory() as directory:
                app = Path(directory) / "Fixture.app"
                widget = app / "Contents/PlugIns/Fixture.appex"
                paths = [app / "Contents/Info.plist", widget / "Contents/Info.plist"]
                for path in paths:
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(plistlib.dumps({}))
                env = dict(os.environ, APP=str(app), WIDGET_APPEX=str(widget),
                           HEADROOM_APP_GROUP_IDENTIFIER="group.fixture",
                           HEADROOM_SPARKLE_FEED_URL="https://example.invalid/appcast.xml",
                           HEADROOM_SPARKLE_PUBLIC_ED_KEY="fixture-public-key")
                functions = "\n".join(shell_function(ROOT / "Scripts" / script, name) for name in names)
                command = "set -eu\n" + functions + "\n" + names[-1] + "\n"
                for initial in [{}, {key: not value for key, value in EXPECTED.items()}]:
                    paths[0].write_bytes(plistlib.dumps(initial))
                    subprocess.run(["bash", "-c", command], env=env, check=True, capture_output=True)
                    result = plistlib.loads(paths[0].read_bytes())
                    for key, value in EXPECTED.items():
                        self.assertIs(result.get(key), value, f"{script}: {key}")


if __name__ == "__main__":
    unittest.main()
