#!/usr/bin/env python3
"""Move indexed PDFs through DEVONthink, so records keep their UUID.

    devonthink-move.py move [--apply] [--limit N] [--plain-rename] --moves FILE
    devonthink-move.py move [--apply] [--limit N] [--plain-rename] --library DIR --flatten SUBDIR ...
    devonthink-move.py check [--json] NOTES_DIR ...

`move` is a dry run unless --apply is given.  A move is a pair FROM, TO of
absolute paths: one tab separated pair per line of the --moves file, or every
file below DIR/SUBDIR moved to the top of DIR with --flatten.  Each file is
moved with DEVONthink's own `move`, so the record, its UUID, its tags and its
annotations stay, and the `x-devonthink-item://` links and `#+devonthink:`
keywords that name the UUID keep working.  After every move the record is
asked for its UUID and path; the run stops at the first one that does not
match.  `check` lists the UUIDs in notes that DEVONthink no longer knows.

Tangled from docs/tangles/academic/devonthink-move.org; edit that file.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

APP = "DEVONthink"   # the scripting name of DEVONthink 4; "DEVONthink 3" for version 3
STATE_DIR = Path.home() / ".local" / "state" / "devonthink-move"
UUID = r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
UUID_RE = re.compile(r"(?:x-devonthink-item://|devonthink:|#\+devonthink:[ \t]*)(" + UUID + ")")

def read_moves(path):
    """Return the (FROM, TO) pairs of the tab separated file PATH."""
    moves = []
    for number, line in enumerate(Path(path).expanduser().read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) != 2 or not all(p.startswith("/") for p in parts):
            raise SystemExit("devonthink-move: line %d of %s is not FROM<TAB>TO, both absolute"
                             % (number, path))
        moves.append(tuple(parts))
    return moves


def flatten_moves(library, subdirs):
    """Return the moves of every file below LIBRARY/SUBDIR to the top of LIBRARY.

    A file whose name is taken at the top, or taken by another file of the
    run, is left out and returned in the second list."""
    library = Path(library).expanduser()
    moves, left, taken = [], [], set()
    for sub in subdirs:
        for root, dirs, files in os.walk(library / sub):
            dirs[:] = sorted(d for d in dirs if not d.startswith("."))
            for name in sorted(files):
                if name.startswith("."):
                    continue
                src, dst = Path(root) / name, library / name
                if dst.exists() or name in taken:
                    left.append(str(src))
                else:
                    taken.add(name)
                    moves.append((str(src), str(dst)))
    return moves, left


def plan_moves(moves, found, exists=os.path.exists):
    """Sort MOVES into what to do.  Pure, so it is tested without DEVONthink.

    FOUND maps a source path to its record, {"uuid", "database", "count"}, or
    None.  Returns a dict of lists: `move` (FROM, TO, record), `plain` (FROM, TO:
    no record), `done` (already at TO), `missing` (no file at FROM) and
    `blocked` (FROM, TO, why)."""
    plan = {"move": [], "plain": [], "done": [], "missing": [], "blocked": []}
    for src, dst in moves:
        record = found.get(src)
        if not exists(src):
            plan["done" if exists(dst) else "missing"].append((src, dst))
        elif exists(dst):
            plan["blocked"].append((src, dst, "the destination exists"))
        elif record is None:
            plan["plain"].append((src, dst))
        elif record["count"] > 1:
            plan["blocked"].append((src, dst, "%d records have this path" % record["count"]))
        else:
            plan["move"].append((src, dst, record))
    return plan


def same_path(a, b):
    """True when the paths A and B are the same file's, links and case aside."""
    try:
        return os.path.realpath(a) == os.path.realpath(b)
    except (OSError, TypeError):
        return False


def moved_ok(src, dst, record, after, exists=os.path.exists):
    """True when DEVONthink's AFTER, {"uuid", "path"}, shows the record moved."""
    return bool(after and after.get("uuid") == record["uuid"]
                and same_path(after.get("path"), dst)
                and exists(dst) and not exists(src))


def uuids_in(text):
    """Return the DEVONthink UUIDs in the TEXT of a note, upper case, in order."""
    out = []
    for m in UUID_RE.finditer(text):
        u = m.group(1).upper()
        if u not in out:
            out.append(u)
    return out


def note_uuids(dirs):
    """Return {uuid: [note paths]} for the .org files below DIRS."""
    out = {}
    for d in dirs:
        for path in sorted(Path(d).expanduser().rglob("*.org")):
            try:
                text = path.read_text(encoding="utf-8", errors="replace")
            except OSError as e:
                print("devonthink-move: skipped %s: %s" % (path, e), file=sys.stderr)
                continue
            for u in uuids_in(text):
                out.setdefault(u, []).append(str(path))
    return out

def jxa(script):
    """Run the JavaScript for Automation SCRIPT and return its JSON result."""
    result = subprocess.run(["osascript", "-l", "JavaScript", "-e", script],
                            capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit("devonthink-move: osascript failed: %s" % result.stderr.strip())
    out = result.stdout.strip()
    return json.loads(out) if out else None


JS_HEAD = "const app = Application(%s);\n" % json.dumps(APP)


def dt_lookup(paths):
    """Return {path: record or None}: the record of each file path in DEVONthink."""
    script = JS_HEAD + """
const out = {};
for (const p of %s) {
  const recs = app.lookupRecordsWithPath(p);
  out[p] = recs.length ? {uuid: recs[0].uuid(), database: recs[0].database().name(),
                          count: recs.length} : null;
}
JSON.stringify(out);
""" % json.dumps(list(paths))
    return jxa(script) or {}


def dt_move(uuid, folder):
    """Move the record UUID into the group of the folder FOLDER; return its new state.

    The result is {"uuid", "path"} read back from DEVONthink, {"error"} when the
    folder has no group in the record's database, or None."""
    script = JS_HEAD + """
const rec = app.getRecordWithUuid(%s);
const found = app.lookupRecordsWithPath(%s, {in: rec.database()});
let group = null;
for (const r of found) if (String(r.recordType()).toLowerCase().indexOf("group") >= 0) group = r;
let result;
if (!group) {
  result = {error: "no group for " + %s};
} else {
  app.move({record: rec, to: group});
  const after = app.getRecordWithUuid(%s);
  result = after ? {uuid: after.uuid(), path: after.path()} : null;
}
JSON.stringify(result);
""" % (json.dumps(uuid), json.dumps(folder), json.dumps(folder), json.dumps(uuid))
    return jxa(script)


def dt_resolve(uuids):
    """Return {uuid: name or None}: what DEVONthink knows of each UUID."""
    script = JS_HEAD + """
const out = {};
for (const u of %s) {
  try { const r = app.getRecordWithUuid(u); out[u] = r ? r.name() : null; }
  catch (e) { out[u] = null; }
}
JSON.stringify(out);
""" % json.dumps(list(uuids))
    return jxa(script) or {}

def save_manifest(entries):
    """Write the moves done to STATE_DIR, one file a run; return its path or None."""
    if not entries:
        return None
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    path = STATE_DIR / time.strftime("moves-%Y%m%dT%H%M%S.json")
    path.write_text(json.dumps(entries, indent=1, ensure_ascii=False))
    return path


def run_moves(plan, apply, limit=None, plain_rename=False):
    """Do the PLAN; return a report dict.  Nothing happens without APPLY.

    The run stops at the first move DEVONthink did not make as asked."""
    report = {"applied": apply, "moved": [], "renamed": [], "stopped": None,
              "to_move": len(plan["move"]), "plain": len(plan["plain"]),
              "done": len(plan["done"]), "missing": [list(m) for m in plan["missing"]],
              "blocked": [list(b) for b in plan["blocked"]]}
    todo = plan["move"][:limit] if limit else plan["move"]
    if apply:
        for src, dst, record in todo:
            after = dt_move(record["uuid"], str(Path(dst).parent))
            if not moved_ok(src, dst, record, after):
                report["stopped"] = {"from": src, "to": dst, "uuid": record["uuid"],
                                     "answer": after}
                break
            report["moved"].append({"uuid": record["uuid"], "from": src, "to": dst})
        if plain_rename and not report["stopped"]:
            for src, dst in plan["plain"][:limit] if limit else plan["plain"]:
                os.rename(src, dst)
                report["renamed"].append({"from": src, "to": dst})
        report["manifest"] = str(save_manifest(report["moved"] + report["renamed"]) or "")
    return report


def print_report(r):
    mode = "" if r["applied"] else "  (dry run)"
    print("through DEVONthink: %d to move, %d moved%s" % (r["to_move"], len(r["moved"]), mode))
    print("not in DEVONthink: %d%s" % (r["plain"], "; renamed %d" % len(r["renamed"])
                                       if r["renamed"] else "; left alone (--plain-rename moves them on disk)"
                                       if r["plain"] else ""))
    print("already moved: %d, missing: %d, blocked: %d" % (r["done"], len(r["missing"]), len(r["blocked"])))
    for src, dst, why in r["blocked"][:10]:
        print("  blocked: %s (%s)" % (src, why))
    if r["stopped"]:
        s = r["stopped"]
        print("STOPPED: DEVONthink did not move %s as asked (answer: %s)" % (s["from"], s["answer"]))
    if r.get("manifest"):
        print("manifest: %s" % r["manifest"])


def cmd_move(args):
    if args.moves:
        moves, left = read_moves(args.moves), []
    elif args.flatten:
        if not args.library:
            raise SystemExit("devonthink-move: --flatten needs --library")
        moves, left = flatten_moves(args.library, args.flatten)
    else:
        raise SystemExit("devonthink-move: give --moves FILE or --library DIR --flatten SUBDIR")
    found = dt_lookup([m[0] for m in moves if os.path.exists(m[0])])
    plan = plan_moves(moves, found)
    report = run_moves(plan, args.apply, args.limit, args.plain_rename)
    report["left_out"] = left
    if args.json:
        print(json.dumps(report))
    else:
        print_report(report)
        if left:
            print("left out, the name is taken at the top: %d" % len(left))
    return 1 if report["stopped"] else 0


def cmd_check(args):
    notes = note_uuids(args.dirs)
    known = dt_resolve(sorted(notes)) if notes else {}
    dangling = {u: p for u, p in notes.items() if known.get(u) is None}
    if args.json:
        print(json.dumps({"checked": len(notes), "dangling": dangling}))
    else:
        print("%d UUIDs in the notes, %d that DEVONthink does not know" % (len(notes), len(dangling)))
        for u, paths in sorted(dangling.items()):
            print("  %s  %s" % (u, ", ".join(paths)))
    return 1 if dangling else 0


def main(argv=None):
    p = argparse.ArgumentParser(description="Move indexed PDFs through DEVONthink.")
    sub = p.add_subparsers(dest="command", required=True)
    m = sub.add_parser("move", help="move files through DEVONthink (a dry run without --apply)")
    m.add_argument("--apply", action="store_true", help="really move")
    m.add_argument("--limit", type=int, help="move at most this many records")
    m.add_argument("--moves", help="file of FROM<TAB>TO absolute paths")
    m.add_argument("--library", help="the library folder, with --flatten")
    m.add_argument("--flatten", nargs="+", metavar="SUBDIR",
                   help="move every file below LIBRARY/SUBDIR to the top of LIBRARY")
    m.add_argument("--plain-rename", action="store_true",
                   help="also rename files that DEVONthink does not index, on disk")
    m.add_argument("--json", action="store_true")
    c = sub.add_parser("check", help="list UUIDs in notes that DEVONthink does not know")
    c.add_argument("dirs", nargs="+", metavar="NOTES_DIR")
    c.add_argument("--json", action="store_true")
    args = p.parse_args(argv)
    return cmd_move(args) if args.command == "move" else cmd_check(args)


if __name__ == "__main__":
    sys.exit(main())
