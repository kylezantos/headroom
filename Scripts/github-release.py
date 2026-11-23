#!/usr/bin/env python3
"""Render canonical Sparkle notes for both GitHub repositories; publish only on request."""

import argparse
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import subprocess


class Notes(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.body = False
        self.parts = []
        self.link = None
        self.content_depth = 0
        self.has_content = False

    def handle_starttag(self, tag, attrs):
        if tag == "body":
            self.body = True
        elif self.body:
            if tag in {"p", "li"}:
                self.content_depth += 1
            if tag in {"h1", "h2", "h3"}:
                self.parts.append("\n\n## ")
            elif tag in {"p", "ul", "ol"}:
                self.parts.append("\n\n")
            elif tag == "li":
                self.parts.append("\n- ")
            elif tag in {"strong", "b"}:
                self.parts.append("**")
            elif tag in {"em", "i"}:
                self.parts.append("*")
            elif tag == "code":
                self.parts.append("`")
            elif tag == "br":
                self.parts.append("\n")
            elif tag == "a":
                href = dict(attrs).get("href") or ""
                if self.link is not None or not re.fullmatch(r"https://[^\s()<>]+", href):
                    raise ValueError("Release-note links require a safe absolute HTTPS URL")
                self.link = href
                self.parts.append("[")
            else:
                raise ValueError(f"Unsupported release-note element: {tag}; extend the renderer first")

    def handle_endtag(self, tag):
        if tag == "body":
            self.body = False
        elif self.body:
            if tag in {"p", "li"}:
                self.content_depth -= 1
            if tag in {"h1", "h2", "h3", "p", "ul", "ol"}:
                self.parts.append("\n\n")
            elif tag in {"strong", "b"}:
                self.parts.append("**")
            elif tag in {"em", "i"}:
                self.parts.append("*")
            elif tag == "code":
                self.parts.append("`")
            elif tag == "a":
                if self.link is None:
                    raise ValueError("Release-note link has no opening tag")
                self.parts.append(f"]({self.link})")
                self.link = None

    def handle_data(self, data):
        if self.body:
            # Ignore indentation between block elements, retaining inline spaces.
            if data.strip():
                if self.content_depth > 0:
                    self.has_content = True
                self.parts.append(re.sub(r"\s+", " ", data))


def render(html, version, build):
    parser = Notes()
    parser.feed(html)
    if parser.link is not None:
        raise ValueError("Release-note link is not closed")
    notes = re.sub(r"\n{3,}", "\n\n", "".join(parser.parts)).strip()
    if not notes.startswith("## ") or not parser.has_content:
        raise ValueError("Release notes must contain a headline and non-empty paragraph or list content")
    base = "https://headroom.zantos.co"
    return (
        f"# Headroom {version} ({build})\n\n{notes}\n\n"
        f"## Downloads\n\n"
        f"- [macOS installer]({base}/Headroom-{version}-{build}.dmg)\n"
        f"- [Changelog]({base}/release-notes#v{version})\n"
        f"- [Sparkle notes]({base}/Headroom-{version}-{build}.html)\n"
        f"- [Update feed]({base}/appcast.xml)\n\n"
        "The iPhone companion is distributed separately through TestFlight and the App Store. "
        "A macOS release does not imply App Store availability.\n"
    )


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    parser.add_argument("build")
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--publish", action="store_true", help="Create/update both GitHub release descriptions")
    args = parser.parse_args()
    if not re.fullmatch(r"\d+(?:\.\d+)+", args.version) or not args.build.isdigit():
        parser.error("Expected a numeric marketing version and build")
    root = Path(__file__).resolve().parents[1]
    relative = f"docs/release/sparkle/Headroom-{args.version}-{args.build}.html"
    commit = run("git", "-C", str(root), "rev-parse", f"{args.source_commit}^{{commit}}")
    subprocess.run(["git", "-C", str(root), "merge-base", "--is-ancestor", commit, "origin/main"], check=True)
    html = run("git", "-C", str(root), "show", f"{commit}:{relative}")
    if html != (root / relative).read_text().strip():
        raise ValueError("Canonical notes differ from the released source commit")
    body = render(html, args.version, args.build)
    if not args.publish:
        print(body, end="")
        return
    source_repo = "kylezantos/headroom"
    archive_repo = "kylezantos/headroom-downloads"
    source_tag = f"v{args.version}"
    archive_tag = f"headroom-{args.version}-{args.build}"
    # Verify the artifact release exists before creating a source release. Never upload or replace assets.
    run("gh", "release", "view", archive_tag, "--repo", archive_repo, "--json", "url")
    releases = json.loads(run("gh", "api", "--paginate", "--slurp", f"repos/{source_repo}/releases"))
    exists = any(release["tag_name"] == source_tag for page in releases for release in page)
    # A pre-existing tag must identify exactly the commit used to build the app.
    refs = run("git", "ls-remote", f"https://github.com/{source_repo}.git", f"refs/tags/{source_tag}", f"refs/tags/{source_tag}^{{}}")
    if refs and refs.splitlines()[-1].split()[0] != commit:
        raise ValueError(f"{source_tag} already points at a different commit; refusing to move it")
    title = f"Headroom {args.version} ({args.build})"
    command = ["gh", "release", "edit" if exists else "create", source_tag, "--repo", source_repo, "--title", title, "--notes-file", "-"]
    if not exists:
        command.extend(["--target", commit])
    subprocess.run(command, input=body, text=True, check=True)
    published_refs = run("git", "ls-remote", f"https://github.com/{source_repo}.git", f"refs/tags/{source_tag}", f"refs/tags/{source_tag}^{{}}")
    if not published_refs or published_refs.splitlines()[-1].split()[0] != commit:
        raise ValueError("Published source tag does not match the artifact source commit")
    subprocess.run(["gh", "release", "edit", archive_tag, "--repo", archive_repo, "--title", title, "--notes-file", "-"], input=body, text=True, check=True)
    for repo, tag in [(source_repo, source_tag), (archive_repo, archive_tag)]:
        actual = json.loads(run("gh", "release", "view", tag, "--repo", repo, "--json", "body,url"))
        if actual["body"].replace("\r\n", "\n").strip() != body.strip():
            raise ValueError(f"GitHub notes read-back mismatch: {repo}")
        print(actual["url"])


if __name__ == "__main__":
    main()
