#!/usr/bin/env python3
"""Splice an editor draft into lib/levels.lua.

The editor cannot write to the source tree -- LÖVE's filesystem is sandboxed to
the save directory, and a game that can rewrite its own level data is a game that
can corrupt it. So `L` in the editor writes drafts/<id>.lua, and this puts it in
place: brace-matched, id-checked, and verified by running the test suite.

    python3 tools/apply-level.py angled-bay            # splice the draft
    python3 tools/apply-level.py angled-bay --dry-run  # show what would change
    python3 tools/apply-level.py angled-bay --no-test  # skip the suite
    python3 tools/apply-level.py my-level --draft /tmp/my-level.lua
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEVELS = os.path.join(ROOT, "lib", "levels.lua")


def save_dir():
    """LÖVE's save directory for this game, per platform."""
    if sys.platform.startswith("win"):
        base = os.environ.get("APPDATA") or os.path.expanduser("~")
        return os.path.join(base, "LOVE", "tow-yard")
    if sys.platform == "darwin":
        return os.path.expanduser("~/Library/Application Support/LOVE/tow-yard")
    return os.path.expanduser("~/.local/share/love/tow-yard")


def read(path):
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def entry_span(text, level_id):
    """The [start, end) of the table literal whose body declares `level_id`.

    Brace counting rather than regex: an entry contains nested tables, and the
    hint strings contain prose that may contain braces.
    """
    marker = 'id = "%s",' % level_id
    at = text.find(marker)
    if at < 0:
        raise SystemExit("no entry with id %r in %s" % (level_id, LEVELS))
    if text.find(marker, at + 1) >= 0:
        raise SystemExit("id %r appears twice -- fix the catalogue first" % level_id)

    # walk back to the '{' that opens this entry
    start = text.rfind("{", 0, at)
    if start < 0:
        raise SystemExit("could not find the opening brace for %r" % level_id)
    line_start = text.rfind("\n", 0, start) + 1
    if text[line_start:start].strip():
        # the '{' is not alone on its line: this is not the shape we expect
        raise SystemExit("entry for %r does not start on its own line" % level_id)

    depth, i, n = 0, start, len(text)
    in_string = in_longstring = in_line_comment = None
    while i < n:
        ch = text[i]
        if in_line_comment:
            if ch == "\n":
                in_line_comment = None
        elif in_string:
            if ch == "\\":
                i += 1
            elif ch == in_string:
                in_string = None
        elif in_longstring:
            if text.startswith(in_longstring, i):
                i += len(in_longstring) - 1
                in_longstring = None
        else:
            if ch == "-" and text.startswith("--", i):
                if text.startswith("--[[", i):
                    in_longstring = "]]"
                    i += 3
                else:
                    in_line_comment = True
                    i += 1
            elif ch in "\"'":
                in_string = ch
            elif ch == "[" and text.startswith("[[", i):
                in_longstring = "]]"
                i += 1
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    # from the START OF THE LINE, not from the brace: the caller
                    # re-adds the indent, and prefixing it twice doubled it
                    return line_start, i + 1
        i += 1
    raise SystemExit("unbalanced braces in the entry for %r" % level_id)


def reindent(draft, indent):
    """Re-indent a generated table literal to sit where the entry goes."""
    lines = [ln.rstrip() for ln in draft.strip("\n").split("\n")]
    while lines and not lines[0].strip():
        lines.pop(0)
    pad = lines[0][: len(lines[0]) - len(lines[0].lstrip())]
    out = []
    for ln in lines:
        if ln.startswith(pad):
            ln = ln[len(pad):]
        out.append((indent + ln) if ln.strip() else "")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("level_id")
    ap.add_argument("--draft", help="path to the exported Lua entry")
    ap.add_argument("--levels", default=LEVELS, help="catalogue to edit")
    ap.add_argument("--dry-run", action="store_true", help="print, do not write")
    ap.add_argument("--no-test", action="store_true", help="do not run the suite")
    args = ap.parse_args()

    draft_path = args.draft or os.path.join(save_dir(), "drafts", args.level_id + ".lua")
    if not os.path.exists(draft_path):
        raise SystemExit("no draft at %s -- press L in the editor for this level" % draft_path)

    draft = read(draft_path)
    if 'id = "%s"' % args.level_id not in draft:
        raise SystemExit("%s does not declare id %r -- is it the right level?"
                         % (draft_path, args.level_id))

    text = read(args.levels)
    start, end = entry_span(text, args.level_id)
    indent = text[text.rfind("\n", 0, start) + 1:start]
    body = reindent(draft, indent)
    new_text = text[:start] + body + text[end:]

    if body == text[start:end]:
        print("already identical: %s is up to date" % args.level_id)
        return 0

    comments = sum(1 for ln in text[start:end].split("\n") if "--" in ln)
    if comments:
        print("note: %d comment line(s) inside this entry are replaced by the draft "
              "(the generated literal carries no comments)" % comments)

    if args.dry_run:
        before = text[start:end].count("\n")
        after = body.count("\n")
        print("would replace %d lines with %d in %s"
              % (before + 1, after + 1, os.path.relpath(args.levels, ROOT)))
        return 0

    with open(args.levels, "w", encoding="utf-8") as fh:
        fh.write(new_text)
    print("spliced %s into %s" % (os.path.relpath(draft_path), os.path.relpath(args.levels, ROOT)))

    if args.no_test:
        print("suite not run: love tests before you commit")
        return 0

    # the suite runs in the repo that owns the catalogue, which is not necessarily
    # where this script lives (it is not, when the catalogue is a worktree)
    repo = os.path.dirname(os.path.dirname(os.path.abspath(args.levels)))
    print("running the suite in %s..." % repo)
    result = subprocess.run(["love", "tests"], cwd=repo, capture_output=True, text=True)
    tail = [ln for ln in result.stdout.strip().split("\n") if ln.strip()][-3:]
    for ln in tail:
        print("  " + ln)
    if result.returncode != 0:
        print("\nSUITE FAILED -- the level is now in the catalogue and the tests reject it.")
        print("Fix the draft and run this again, or `git checkout lib/levels.lua`.")
        return result.returncode
    print("\nnext: love . --audit N (a floor, not a par) and playtest it")
    return 0


if __name__ == "__main__":
    sys.exit(main())
