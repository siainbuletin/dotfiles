#!/usr/bin/env python3
"""Keep a small DEVONthink `reading` database filled from litnote read-status.

    devonthink-reading.py create [--apply]
    devonthink-reading.py send [--apply] [--return] [--status S] [--bib B]
    devonthink-reading.py --json send

Both actions are dry runs unless --apply is given.  Settings: options, then
~/.config/devonthink-reading/config.json, then the defaults below.

Tangled from docs/tangles/devonthink/devonthink-reading.org; edit that file.
"""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
DEFAULTS = {
    "source_database": "literature",
    "reading_database": "reading",
    "reading_path": str(HOME / "Databases" / "reading.dtBase2"),
    "notes_dir": str(HOME / "notes" / "litnotes"),
    "bib_dir": str(HOME / "Documents" / "bibliography"),
    "bib_files": [],              # empty = every .bib in bib_dir
    "statuses": ["to-be-read"],
    "budget_gb": 20,
    "group_per_bib": True,
}
CONFIG_PATH = HOME / ".config" / "devonthink-reading" / "config.json"
STATE_PATH = HOME / ".local" / "state" / "devonthink-reading" / "origins.json"
APP = "DEVONthink"   # the scripting name of DEVONthink 4; "DEVONthink 3" for version 3

BIB_ENTRY_RE = re.compile(r"@\s*([A-Za-z]+)\s*[{(]\s*([^,\s]+)\s*,")
NOT_ENTRIES = {"string", "comment", "preamble"}


def bib_keys(text):
    """Return the entry keys of the BibTeX TEXT, in order."""
    return [key for kind, key in BIB_ENTRY_RE.findall(text)
            if kind.lower() not in NOT_ENTRIES]


def resolve_bib_files(names, bib_dir):
    """Turn NAMES (bare names or paths) into existing .bib paths.

    Empty NAMES means every .bib file in BIB_DIR.  A name that matches no
    file is an error, so a typo does not silently select nothing."""
    bib_dir = Path(bib_dir).expanduser()
    if not names:
        return sorted(bib_dir.glob("*.bib"))
    out = []
    for name in names:
        p = Path(name).expanduser()
        if not p.suffix:
            p = p.with_suffix(".bib")
        if not p.is_absolute() and not p.exists():
            p = bib_dir / p
        if not p.exists():
            raise SystemExit("devonthink-reading: no such .bib file: %s" % name)
        out.append(p)
    return out


def bib_index(paths):
    """Return {citekey: bib name} for PATHS; the first file that has a key wins."""
    index = {}
    for path in paths:
        with open(path, encoding="utf-8", errors="replace") as f:
            for key in bib_keys(f.read()):
                index.setdefault(key, path.stem)
    return index

LINK_RE = re.compile(r"\[\[[^]]*\]\[([^]]*)\]\]|\[\[([^]]*)\]\]")
REFS_RE = re.compile(r"^:ROAM_REFS:[ \t]*(.*)$", re.M | re.I)
REFERENCE_RE = re.compile(r"^#\+reference:[ \t]*(\S+)", re.M | re.I)
STATUS_META_RE = re.compile(r"^[ \t]*[-+][ \t]+read-status[ \t]+::[ \t]*(.*)$", re.M | re.I)
STATUS_PROP_RE = re.compile(r"^:READ-STATUS:[ \t]*(.*)$", re.M | re.I)


def normalise_status(value):
    """Lower-case VALUE, with an Org link reduced to its description."""
    value = LINK_RE.sub(lambda m: m.group(1) or m.group(2) or "", value)
    return value.strip().strip("#").strip().lower()


def ref_keys(value):
    """Citekeys in a ROAM_REFS value: @key, cite:key, [cite:@key; @k2] or bare."""
    keys = []
    for token in re.split(r"[\s;\[\]]+", value):
        token = token.strip()
        if not token or token.lower() == "cite":
            continue
        if token.lower().startswith("cite:"):
            token = token[5:]
        token = token.lstrip("@").rstrip(",")
        if token and "://" not in token:
            keys.append(token)
    return keys


def parse_litnote(text):
    """Return (citekeys, status) for the Org TEXT of a litnote."""
    keys = []
    for m in REFS_RE.finditer(text):
        keys += ref_keys(m.group(1))
    m = REFERENCE_RE.search(text)
    if m and m.group(1) not in keys:
        keys.append(m.group(1))
    m = STATUS_META_RE.search(text) or STATUS_PROP_RE.search(text)
    status = normalise_status(m.group(1)) if m else ""
    return keys, status


def litnote_statuses(notes_dir):
    """Return {citekey: (status, note path)} for every litnote in NOTES_DIR."""
    out = {}
    for path in sorted(Path(notes_dir).expanduser().glob("*.org")):
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError as e:
            print("devonthink-reading: skipped %s: %s" % (path, e), file=sys.stderr)
            continue
        keys, status = parse_litnote(text)
        for key in keys:
            out.setdefault(key, (status, str(path)))
    return out


def wanted_keys(statuses, notes, bibs):
    """Return {citekey: bib name} for the keys that should be in `reading`."""
    statuses = {s.lower() for s in statuses}
    return {key: bibs[key] for key, (status, _) in notes.items()
            if status in statuses and key in bibs}

def jxa(script):
    """Run the JavaScript for Automation SCRIPT and return its JSON result."""
    result = subprocess.run(["osascript", "-l", "JavaScript", "-e", script],
                            capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit("devonthink-reading: osascript failed: %s" % result.stderr.strip())
    out = result.stdout.strip()
    return json.loads(out) if out else None


JS_HEAD = "const app = Application(%s);\n" % json.dumps(APP)


def dt_database_state(name, path):
    """Return "open", "closed" (file exists) or "missing" for the database."""
    script = JS_HEAD + """
const names = app.databases.name();
JSON.stringify(names.indexOf(%s) >= 0 ? "open" : "");
""" % json.dumps(name)
    if jxa(script) == "open":
        return "open"
    return "closed" if Path(path).expanduser().exists() else "missing"


def dt_create_database(path, groups):
    script = JS_HEAD + """
const db = app.createDatabase(%s);
for (const g of %s) app.createLocation("/" + g, {in: db});
JSON.stringify(db.name());
""" % (json.dumps(str(Path(path).expanduser())), json.dumps(groups))
    return jxa(script)


def dt_open_database(path):
    script = JS_HEAD + "JSON.stringify(app.openDatabase(%s).name());" % json.dumps(
        str(Path(path).expanduser()))
    return jxa(script)


def dt_ensure_groups(database, groups):
    script = JS_HEAD + """
const db = app.databases.byName(%s);
for (const g of %s) app.createLocation("/" + g, {in: db});
JSON.stringify(true);
""" % (json.dumps(database), json.dumps(groups))
    return jxa(script)


def dt_pdf_records(database):
    """Return the PDF records of DATABASE: uuid, filename, size, location."""
    script = JS_HEAD + """
const db = app.databases.byName(%s);
const c = db.contents;
const ids = c.uuid(), files = c.filename(), sizes = c.size(), locs = c.location(), kinds = c.recordType();
const out = [];
for (let i = 0; i < ids.length; i++) {
  const f = files[i] || "";
  if (f.toLowerCase().endsWith(".pdf"))
    out.push({uuid: ids[i], filename: f, size: sizes[i], location: locs[i], kind: String(kinds[i])});
}
JSON.stringify(out);
""" % json.dumps(database)
    return jxa(script) or []


def dt_move(uuid, database, location):
    """Move the record UUID to LOCATION (a group path) in DATABASE."""
    script = JS_HEAD + """
const rec = app.getRecordWithUuid(%s);
const db = app.databases.byName(%s);
const grp = app.createLocation(%s, {in: db});
const moved = app.move({record: rec, to: grp});
JSON.stringify(moved ? moved.uuid() : null);
""" % (json.dumps(uuid), json.dumps(database), json.dumps(location or "/"))
    return jxa(script)

def key_of(filename):
    return filename[:-4] if filename.lower().endswith(".pdf") else filename


def plan_moves(wanted, source_records, reading_records, budget_bytes, group_per_bib,
               do_return):
    """Work out what to move.  Pure function, so it can be tested without DEVONthink.

    Returns a dict with lists `send`, `back`, `missing`, `keep` and the sizes."""
    in_reading = {key_of(r["filename"]): r for r in reading_records}
    in_source = {}
    for r in source_records:
        in_source.setdefault(key_of(r["filename"]), r)

    send, missing, keep = [], [], []
    for key in sorted(wanted):
        if key in in_reading:
            keep.append(dict(in_reading[key], key=key))
        elif key in in_source:
            r = in_source[key]
            target = "/" + wanted[key] if group_per_bib else "/"
            send.append(dict(r, key=key, target=target))
        else:
            missing.append(key)

    back = []
    if do_return:
        back = [dict(r, key=k) for k, r in sorted(in_reading.items()) if k not in wanted]

    kept_size = sum(r["size"] for r in keep)
    send_size = sum(r["size"] for r in send)
    back_size = sum(r["size"] for r in back)
    after = (sum(r["size"] for r in reading_records) - back_size) + send_size
    return {
        "send": send, "back": back, "missing": missing, "keep": keep,
        "kept_bytes": kept_size, "send_bytes": send_size, "back_bytes": back_size,
        "after_bytes": after, "budget_bytes": budget_bytes,
        "over_budget": after > budget_bytes,
    }


def human(n):
    for unit in ("B", "KB", "MB", "GB"):
        if abs(n) < 1000 or unit == "GB":
            return "%.1f %s" % (n, unit) if unit != "B" else "%d B" % n
        n /= 1000.0

def load_state():
    try:
        return json.loads(STATE_PATH.read_text())
    except (OSError, ValueError):
        return {}


def save_state(state):
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATE_PATH.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, indent=1, sort_keys=True))
    tmp.replace(STATE_PATH)

def load_settings(args):
    settings = dict(DEFAULTS)
    path = Path(args.config).expanduser() if args.config else CONFIG_PATH
    if path.exists():
        try:
            settings.update(json.loads(path.read_text()))
        except ValueError as e:
            raise SystemExit("devonthink-reading: bad JSON in %s: %s" % (path, e))
    elif args.config:
        raise SystemExit("devonthink-reading: no such config file: %s" % path)
    for name in ("source_database", "reading_database", "reading_path", "notes_dir",
                 "bib_dir", "budget_gb"):
        value = getattr(args, name, None)
        if value is not None:
            settings[name] = value
    if getattr(args, "status", None):
        settings["statuses"] = args.status
    if getattr(args, "bib", None):
        settings["bib_files"] = args.bib
    if getattr(args, "no_groups", False):
        settings["group_per_bib"] = False
    return settings


def cmd_create(args, s):
    bibs = resolve_bib_files(s["bib_files"], s["bib_dir"]) if s["group_per_bib"] else []
    groups = [p.stem for p in bibs]
    state = dt_database_state(s["reading_database"], s["reading_path"])
    report = {"database": s["reading_database"], "path": s["reading_path"],
              "state": state, "groups": groups, "applied": args.apply}
    if state == "missing":
        action = "create %s with groups %s" % (s["reading_path"], ", ".join(groups) or "(none)")
        if args.apply:
            dt_create_database(s["reading_path"], groups)
    elif state == "closed":
        action = "open %s and make sure its groups exist" % s["reading_path"]
        if args.apply:
            dt_open_database(s["reading_path"])
            dt_ensure_groups(s["reading_database"], groups)
    else:
        action = "already open; make sure its groups exist"
        if args.apply and groups:
            dt_ensure_groups(s["reading_database"], groups)
    report["action"] = action
    if args.json:
        print(json.dumps(report))
    else:
        print("%s: %s%s" % (s["reading_database"], action, "" if args.apply else "  (dry run)"))
    return 0


def cmd_send(args, s):
    if dt_database_state(s["reading_database"], s["reading_path"]) != "open":
        raise SystemExit("devonthink-reading: the %s database is not open; run `create` first"
                         % s["reading_database"])
    bibs = bib_index(resolve_bib_files(s["bib_files"], s["bib_dir"]))
    notes = litnote_statuses(s["notes_dir"])
    wanted = wanted_keys(s["statuses"], notes, bibs)
    source = dt_pdf_records(s["source_database"])
    reading = dt_pdf_records(s["reading_database"])
    plan = plan_moves(wanted, source, reading, int(float(s["budget_gb"]) * 1e9),
                      s["group_per_bib"], args.do_return)
    if args.limit is not None:
        plan["send"] = plan["send"][:args.limit]
        plan["back"] = plan["back"][:args.limit]

    if args.json:
        print(json.dumps(dict(plan, statuses=s["statuses"], applied=args.apply)))
    else:
        print("rule: read-status in %s, in %s" % (
            ", ".join(s["statuses"]), ", ".join(s["bib_files"]) or "every .bib file"))
        print("%d litnotes match; %d already in %s (%s)" % (
            len(wanted), len(plan["keep"]), s["reading_database"], human(plan["kept_bytes"])))
        for r in plan["send"]:
            print("send  %-50s %9s  -> %s" % (r["key"], human(r["size"]), r["target"]))
        for r in plan["back"]:
            print("back  %-50s %9s" % (r["key"], human(r["size"])))
        for k in plan["missing"]:
            print("none  %-50s no PDF named %s.pdf in %s" % (k, k, s["source_database"]))
        print("%s after the moves, budget %s" % (human(plan["after_bytes"]),
                                                human(plan["budget_bytes"])))

    if plan["over_budget"] and not args.over_budget:
        print("devonthink-reading: over budget; narrow the rule or pass --over-budget",
              file=sys.stderr)
        return 1
    if not args.apply:
        if not args.json:
            print("dry run: nothing moved. Re-run with --apply.")
        return 0

    state = load_state()
    moved = 0
    for r in plan["send"]:
        state[r["uuid"]] = {"database": s["source_database"], "location": r["location"],
                            "key": r["key"]}
        save_state(state)   # before the move, so a crash still remembers the origin
        dt_move(r["uuid"], s["reading_database"], r["target"])
        moved += 1
    for r in plan["back"]:
        origin = state.get(r["uuid"], {})
        dt_move(r["uuid"], origin.get("database", s["source_database"]),
                origin.get("location", "/From reading"))
        state.pop(r["uuid"], None)
        save_state(state)
        moved += 1
    if not args.json:
        print("moved %d record(s)" % moved)
    return 0

def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0],
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--config", help="JSON settings file (default %s)" % CONFIG_PATH)
    p.add_argument("--json", action="store_true", help="print the plan as JSON")
    sub = p.add_subparsers(dest="command", required=True)

    def common(sp):
        sp.add_argument("--apply", action="store_true", help="really do it (default: dry run)")
        sp.add_argument("--reading-database", dest="reading_database")
        sp.add_argument("--reading-path", dest="reading_path",
                        help="where to create the database (default ~/Databases/reading.dtBase2)")
        sp.add_argument("--bib", action="append",
                        help="a .bib file by name or path; repeat for more (default: all)")
        sp.add_argument("--bib-dir", dest="bib_dir")
        sp.add_argument("--no-groups", action="store_true",
                        help="don't make one group per .bib file")

    c = sub.add_parser("create", help="create or open the reading database")
    common(c)
    s = sub.add_parser("send", help="move matching records into the reading database")
    common(s)
    s.add_argument("--status", action="append",
                   help="a read-status value that selects a note; repeat for more "
                        "(default: to-be-read)")
    s.add_argument("--source-database", dest="source_database")
    s.add_argument("--notes-dir", dest="notes_dir")
    s.add_argument("--budget-gb", dest="budget_gb", type=float)
    s.add_argument("--return", dest="do_return", action="store_true",
                   help="also move records that no longer match back to the source")
    s.add_argument("--limit", type=int, help="move at most this many records in each direction")
    s.add_argument("--over-budget", action="store_true", help="move even when over the budget")

    args = p.parse_args(argv)
    settings = load_settings(args)
    return cmd_create(args, settings) if args.command == "create" else cmd_send(args, settings)


if __name__ == "__main__":
    sys.exit(main())
