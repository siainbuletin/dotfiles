"""Tests for tools/devonthink-move.py, with DEVONthink faked.

Run from emacs-modular/.config/emacs-modular:
    python3 -m unittest tests/test_devonthink_move.py
"""

import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    "devonthink_move", HERE.parent / "tools" / "devonthink-move.py")
dm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dm)

U1 = "11111111-2222-3333-4444-555555555555"
U2 = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"


class FakeDT:
    """A DEVONthink with records {uuid: path}; a move can be made to fail."""

    def __init__(self, records, honest=True):
        self.records, self.honest = dict(records), honest

    def lookup(self, paths):
        return {p: ({"uuid": u, "database": "literature", "count": 1}
                    if p in self.records.values() and (u := next(
                        k for k, v in self.records.items() if v == p)) else None)
                for p in paths}

    def move(self, uuid, folder):
        if self.honest:
            old = self.records[uuid]
            new = os.path.join(folder, os.path.basename(old))
            os.rename(old, new)
            self.records[uuid] = new
        return {"uuid": uuid, "path": self.records[uuid]}

    def resolve(self, uuids):
        return {u: ("name" if u in self.records else None) for u in uuids}

class Library(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.lib = Path(self.tmp.name).resolve()
        (self.lib / "inbox").mkdir()
        for name in ("a.pdf", "b.pdf", "c.pdf"):
            (self.lib / "inbox" / name).write_text(name)
        (self.lib / "b.pdf").write_text("taken at the top")
        (self.lib / "inbox" / ".hidden").write_text("")
        state = mock.patch.object(dm, "STATE_DIR", self.lib / "state")
        state.start()
        self.addCleanup(state.stop)
        self.addCleanup(self.tmp.cleanup)

    def path(self, *p):
        return str(self.lib.joinpath(*p))


class Planning(Library):
    def test_flatten_moves_and_leaves_clashes(self):
        moves, left = dm.flatten_moves(self.lib, ["inbox"])
        self.assertEqual([(self.path("inbox", "a.pdf"), self.path("a.pdf")),
                          (self.path("inbox", "c.pdf"), self.path("c.pdf"))], moves)
        self.assertEqual([self.path("inbox", "b.pdf")], left)

    def test_read_moves(self):
        f = self.lib / "moves.tsv"
        f.write_text("/a/x.pdf\t/b/x.pdf\n\n/a/y.pdf\t/b/y.pdf\n")
        self.assertEqual([("/a/x.pdf", "/b/x.pdf"), ("/a/y.pdf", "/b/y.pdf")], dm.read_moves(f))
        f.write_text("relative\t/b/x.pdf\n")
        with self.assertRaises(SystemExit):
            dm.read_moves(f)

    def test_plan_sorts_each_move(self):
        a, b, c = (self.path("inbox", n) for n in ("a.pdf", "b.pdf", "c.pdf"))
        moves = [(a, self.path("a.pdf")), (b, self.path("b.pdf")), (c, self.path("c.pdf")),
                 (self.path("gone.pdf"), self.path("g.pdf"))]
        found = {a: {"uuid": U1, "database": "d", "count": 1}}
        plan = dm.plan_moves(moves, found)
        self.assertEqual([a], [m[0] for m in plan["move"]])
        self.assertEqual([c], [m[0] for m in plan["plain"]])
        self.assertEqual([b], [m[0] for m in plan["blocked"]])
        self.assertEqual(1, len(plan["missing"]))

    def test_two_records_at_one_path_block(self):
        a = self.path("inbox", "a.pdf")
        plan = dm.plan_moves([(a, self.path("a.pdf"))], {a: {"uuid": U1, "database": "d", "count": 2}})
        self.assertEqual(1, len(plan["blocked"]))

    def test_moved_ok_wants_the_same_uuid_and_the_file_at_the_new_path(self):
        a, dst = self.path("inbox", "a.pdf"), self.path("a.pdf")
        rec = {"uuid": U1}
        self.assertFalse(dm.moved_ok(a, dst, rec, {"uuid": U1, "path": a}))       # file did not move
        self.assertFalse(dm.moved_ok(a, dst, rec, {"uuid": U2, "path": dst}))     # another record
        self.assertFalse(dm.moved_ok(a, dst, rec, None))
        os.rename(a, dst)
        self.assertTrue(dm.moved_ok(a, dst, rec, {"uuid": U1, "path": dst}))

    def test_uuids_in_notes(self):
        text = ("#+devonthink: %s\n[[x-devonthink-item://%s?page=3][p]] "
                "[[devonthink:%s::4][q]] %s\n" % (U1, U2.lower(), U1, U2))
        self.assertEqual([U1, U2], dm.uuids_in(text))


class Running(Library):
    def move(self, dt, apply=True, **kw):
        moves, _ = dm.flatten_moves(self.lib, ["inbox"])
        with mock.patch.object(dm, "dt_move", dt.move):
            return dm.run_moves(dm.plan_moves(moves, dt.lookup([m[0] for m in moves])), apply, **kw)

    def dt(self, honest=True):
        return FakeDT({U1: self.path("inbox", "a.pdf")}, honest)

    def test_dry_run_changes_nothing(self):
        r = self.move(self.dt(), apply=False)
        self.assertEqual(1, r["to_move"])
        self.assertTrue((self.lib / "inbox" / "a.pdf").exists())
        self.assertFalse((self.lib / "state").exists())

    def test_apply_moves_through_devonthink_and_keeps_the_uuid(self):
        dt = self.dt()
        r = self.move(dt)
        self.assertEqual([{"uuid": U1, "from": self.path("inbox", "a.pdf"), "to": self.path("a.pdf")}],
                         r["moved"])
        self.assertEqual(self.path("a.pdf"), dt.records[U1])
        self.assertTrue((self.lib / "a.pdf").exists())
        # c.pdf is not indexed: left alone without --plain-rename.
        self.assertTrue((self.lib / "inbox" / "c.pdf").exists())
        self.assertEqual(1, len(json.loads(Path(r["manifest"]).read_text())))

    def test_plain_rename_moves_files_devonthink_does_not_know(self):
        r = self.move(self.dt(), plain_rename=True)
        self.assertEqual([self.path("c.pdf")], [e["to"] for e in r["renamed"]])
        self.assertTrue((self.lib / "c.pdf").exists())

    def test_stops_when_devonthink_did_not_move_the_file(self):
        r = self.move(self.dt(honest=False))
        self.assertEqual([], r["moved"])
        self.assertEqual(self.path("inbox", "a.pdf"), r["stopped"]["from"])
        self.assertTrue((self.lib / "inbox" / "a.pdf").exists())

    def test_limit(self):
        dt = FakeDT({U1: self.path("inbox", "a.pdf"), U2: self.path("inbox", "c.pdf")})
        r = self.move(dt, limit=1)
        self.assertEqual(1, len(r["moved"]))


class Check(Library):
    def test_lists_the_uuids_devonthink_does_not_know(self):
        notes = self.lib / "notes"
        notes.mkdir()
        (notes / "a.org").write_text("#+devonthink: %s\n" % U1)
        (notes / "b.org").write_text("[[x-devonthink-item://%s][x]]\n" % U2)
        with mock.patch.object(dm, "dt_resolve", FakeDT({U1: "/x"}).resolve):
            code = dm.main(["check", str(notes), "--json"])
        self.assertEqual(1, code)

    def test_nothing_dangling_is_success(self):
        notes = self.lib / "notes"
        notes.mkdir()
        (notes / "a.org").write_text("#+devonthink: %s\n" % U1)
        with mock.patch.object(dm, "dt_resolve", FakeDT({U1: "/x"}).resolve):
            self.assertEqual(0, dm.main(["check", str(notes)]))


if __name__ == "__main__":
    unittest.main()
