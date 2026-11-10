#!/usr/bin/env python3
"""Turns an addon's CHANGELOG.md into release notes, for the release workflows.

usage: release_changelog.py <CHANGELOG.md> <version> <notes-file> [date]

Finds the notes for <version> and writes them to <notes-file>:
  - the body of the "## [Unreleased]" section, which is then moved under a new
    "## [<version>] - <date>" heading in the changelog (the changelog file is rewritten), or
  - when Unreleased is empty, the body of an existing "## [<version>]" section (a release
    heading added by hand ahead of time); the changelog is left as it is.
Exits with status 1 and writes nothing when neither has any entries, so the workflow can
fall back to GitHub's generated notes.
"""
import datetime
import re
import sys


def sections(lines):
    """-> list of (heading_index, name) for every '## [name]' line."""
    return [(i, m.group(1)) for i, line in enumerate(lines) if (m := re.match(r"## \[(.+?)\]", line))]


def body(lines, start, end):
    text = "\n".join(lines[start + 1:end]).strip("\n")
    return text if re.search(r"^- ", text, re.M) else ""


def main(path, version, notes_path, date=None):
    date = date or datetime.date.today().isoformat()
    lines = open(path, encoding="utf-8").read().split("\n")
    found = sections(lines)
    ends = [i for i, _ in found[1:]] + [len(lines)]
    spans = {name: (i, end) for (i, name), end in zip(found, ends)}

    notes = ""
    if "Unreleased" in spans:
        start, end = spans["Unreleased"]
        notes = body(lines, start, end)
        if notes:
            lines[start + 1:start + 1] = ["", f"## [{version}] - {date}"]
            open(path, "w", encoding="utf-8").write("\n".join(lines))
    if not notes and version in spans:
        notes = body(lines, *spans[version])
    if not notes:
        return 1
    # Release notes use H3 headings (Added / Changed / Fixed) as they are.
    open(notes_path, "w", encoding="utf-8").write(notes + "\n")
    return 0


if __name__ == "__main__":
    if len(sys.argv) not in (4, 5):
        sys.exit(__doc__)
    sys.exit(main(*sys.argv[1:]))
