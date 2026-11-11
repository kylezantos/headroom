"""Contract tests for GitHub notes and cross-repository drift detection."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
import sys

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "Scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ReleaseNotesTests(unittest.TestCase):
    def test_current_notes_preserve_every_bullet_and_link(self):
        body = load("github-release").render((ROOT / "docs/release/sparkle/Headroom-1.6-44.html").read_text(), "1.6", "44")
        self.assertEqual(body.count("\n- **"), 5)
        self.assertIn("support@zantos.co", body)
        self.assertIn("**Track GitHub Copilot.** Turn it on", body)
        self.assertIn("/Headroom-1.6-44.dmg", body)
        self.assertNotIn("<li>", body)

    def test_empty_or_unsupported_notes_fail_closed(self):
        render = load("github-release").render
        for html in ["<body></body>", '<body><a href="https://example.com">Link</a></body>']:
            with self.assertRaises(ValueError):
                render(html, "1.6", "44")

    def test_provider_drift_blocks_site_gate(self):
        import json
        import shutil
        with tempfile.TemporaryDirectory() as directory:
            site = Path(directory)
            (site / "public").mkdir()
            (site / "lib/headroom-demo").mkdir(parents=True)
            (site / "public/latest.json").write_text(json.dumps({"version": "1.6", "build": "44"}))
            shutil.copy(ROOT / "docs/release/sparkle/Headroom-1.6-44.html", site / "public")
            (site / "public/appcast.xml").write_text('''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>44</sparkle:version><sparkle:shortVersionString>1.6</sparkle:shortVersionString><sparkle:releaseNotesLink>https://headroom.zantos.co/Headroom-1.6-44.html</sparkle:releaseNotesLink></item></channel></rss>''')
            (site / "lib/headroom-demo/usage-model.ts").write_text('export const PROVIDER_ORDER = ["claude", "codex", "grok", "cursor"]')
            source = site / "source"
            (source / "docs/release/sparkle").mkdir(parents=True)
            (source / "Sources/HeadroomCore/Models").mkdir(parents=True)
            shutil.copy(site / "public/Headroom-1.6-44.html", source / "docs/release/sparkle")
            (source / "project.yml").write_text('MARKETING_VERSION: "1.6"\nCURRENT_PROJECT_VERSION: "44"\n')
            (source / "Sources/HeadroomCore/Models/ProviderID.swift").write_text('\n'.join(f'public static let {key} = ProviderID("{key}")' for key in ["claude", "codex", "grok", "cursor", "copilot"]))
            gate = load("check-release-sync")
            with self.assertRaisesRegex(ValueError, "provider drift"):
                gate.check(source, site)
            (site / "lib/headroom-demo/usage-model.ts").write_text('export const PROVIDER_ORDER = ["claude", "codex", "grok", "cursor", "copilot"]')
            (site / "lib/site-metadata.ts").write_text('export const SITE_DESCRIPTION = "Claude Codex Grok Cursor Copilot"')
            gate.check(source, site)
            # The site may leave a supported provider out on purpose, but only by naming it.
            (site / "lib/headroom-demo/usage-model.ts").write_text('export const PROVIDER_ORDER = ["claude", "codex", "grok", "cursor"]\nexport const UNFEATURED_PROVIDERS: string[] = ["copilot"]')
            (site / "lib/site-metadata.ts").write_text('export const SITE_DESCRIPTION = "Claude Codex Grok Cursor and more"')
            gate.check(source, site)
            (site / "lib/headroom-demo/usage-model.ts").write_text('export const PROVIDER_ORDER = ["claude", "codex", "grok", "cursor", "copilot"]\nexport const UNFEATURED_PROVIDERS: string[] = ["copilot"]')
            with self.assertRaisesRegex(ValueError, "shows unfeatured"):
                gate.check(source, site)
            (site / "lib/headroom-demo/usage-model.ts").write_text('export const PROVIDER_ORDER = ["claude", "codex", "grok", "cursor"]\nexport const UNFEATURED_PROVIDERS: string[] = ["copilot", "opencode"]')
            with self.assertRaisesRegex(ValueError, "not app providers"):
                gate.check(source, site)
            (site / "lib/headroom-demo/usage-model.ts").write_text('export const PROVIDER_ORDER = ["claude", "codex", "grok", "cursor", "copilot"]')
            (site / "lib/site-metadata.ts").write_text('export const SITE_DESCRIPTION = "Claude Codex Grok Cursor Copilot"')
            (source / "project.yml").write_text(
                'targets:\n  Headroom:\n    platform: macOS\n    MARKETING_VERSION: 1.6\n    CURRENT_PROJECT_VERSION: 44\n'
                '  HeadroomIOS:\n    platform: iOS\n    MARKETING_VERSION: 1.5.1\n    CURRENT_PROJECT_VERSION: 44\n')
            gate.check(source, site)
            (source / "project.yml").write_text(
                'targets:\n  Headroom:\n    platform: macOS\n    MARKETING_VERSION: 1.5.2\n    CURRENT_PROJECT_VERSION: 44\n'
                '  HeadroomIOS:\n    platform: iOS\n    MARKETING_VERSION: 1.6\n    CURRENT_PROJECT_VERSION: 44\n')
            with self.assertRaisesRegex(ValueError, "App versions"):
                gate.check(source, site)
            (source / "project.yml").write_text('MARKETING_VERSION: "1.6"\nCURRENT_PROJECT_VERSION: "44"\n')
            (site / "public/Headroom-1.6-44.html").write_text("different notes")
            with self.assertRaisesRegex(ValueError, "canonical"):
                gate.check(source, site)


if __name__ == "__main__":
    unittest.main()
