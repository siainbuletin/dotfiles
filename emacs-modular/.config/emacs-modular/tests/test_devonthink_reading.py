"""Tests for tools/devonthink-reading.py, with DEVONthink faked.

Run from emacs-modular/.config/emacs-modular:
    python3 -m unittest tests/test_devonthink_reading.py
"""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    "devonthink_reading", HERE.parent / "tools" / "devonthink-reading.py")
dr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dr)

NOTE_A = """:PROPERTIES:
:ID:       a1
:ROAM_REFS: @smith-2017-atten
:END:
#+title: Smith 2017

- pub-year :: 2017
- read-status :: to-be-read
"""
NOTE_B = """:PROPERTIES:
:ID:       b1
:END:
#+title: Jones
#+reference:  jones-2010-value

- read-status :: [[id:xyz][Reading]]
"""
NOTE_C = """#+title: Done
#+reference: done-2001-x
- read-status :: read
"""
NOTE_D = """:PROPERTIES:
:ID: d1
:ROAM_REFS: [cite:@other-1999-y]
:READ-STATUS: to-be-read
:END:
"""

BIB_THESIS = """@string{foo = "bar"}
@book{smith-2017-atten,
  title = {A},
}
@Article{ jones-2010-value ,
  title = {B}}
"""
BIB_MARX = """@comment{x}
@incollection{done-2001-x, title={C}}
@book{other-1999-y, title={D}}
@book{smith-2017-atten, title={dup}}
"""


class Parsing(unittest.TestCase):
    def test_bib_keys_skip_string_and_comment(self):
        self.assertEqual(dr.bib_keys(BIB_THESIS), ["smith-2017-atten", "jones-2010-value"])
        self.assertEqual(dr.bib_keys(BIB_MARX),
                         ["done-2001-x", "other-1999-y", "smith-2017-atten"])

    def test_litnote_roam_refs_and_meta(self):
        self.assertEqual(dr.parse_litnote(NOTE_A), (["smith-2017-atten"], "to-be-read"))

    def test_litnote_reference_and_link_status(self):
        self.assertEqual(dr.parse_litnote(NOTE_B), (["jones-2010-value"], "reading"))

    def test_litnote_property_status_and_cite_ref(self):
        self.assertEqual(dr.parse_litnote(NOTE_D), (["other-1999-y"], "to-be-read"))

    def test_ref_keys_forms(self):
        self.assertEqual(dr.ref_keys("@a cite:b [cite:@c; @d] e https://x.org"),
                         ["a", "b", "c", "d", "e"])


class Planning(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        (root / "notes").mkdir()
        (root / "bib").mkdir()
        for name, text in (("a", NOTE_A), ("b", NOTE_B), ("c", NOTE_C), ("d", NOTE_D)):
            (root / "notes" / (name + ".org")).write_text(text)
        (root / "bib" / "thesis.bib").write_text(BIB_THESIS)
        (root / "bib" / "marx.bib").write_text(BIB_MARX)
        self.root = root

    def tearDown(self):
        self.tmp.cleanup()

    def test_rule_status_and_bib(self):
        notes = dr.litnote_statuses(self.root / "notes")
        bibs = dr.bib_index(dr.resolve_bib_files(["thesis"], self.root / "bib"))
        self.assertEqual(dr.wanted_keys(["to-be-read"], notes, bibs),
                         {"smith-2017-atten": "thesis"})
        bibs = dr.bib_index(dr.resolve_bib_files([], self.root / "bib"))
        # all bibs, sorted: marx.bib first, so smith is filed under marx
        self.assertEqual(dr.wanted_keys(["TO-BE-READ", "reading"], notes, bibs),
                         {"smith-2017-atten": "marx", "jones-2010-value": "thesis",
                          "other-1999-y": "marx"})

    def test_unknown_bib_is_an_error(self):
        with self.assertRaises(SystemExit):
            dr.resolve_bib_files(["nope"], self.root / "bib")

    def test_plan_budget_and_return(self):
        wanted = {"a": "thesis", "b": "marx", "gone": "thesis"}
        source = [{"uuid": "1", "filename": "a.pdf", "size": 4, "location": "/x/"},
                  {"uuid": "2", "filename": "b.pdf", "size": 5, "location": "/"}]
        reading = [{"uuid": "3", "filename": "old.pdf", "size": 3, "location": "/thesis/"},
                   {"uuid": "4", "filename": "b.pdf", "size": 5, "location": "/marx/"}]
        plan = dr.plan_moves(wanted, source, reading, 100, True, do_return=True)
        self.assertEqual([r["key"] for r in plan["send"]], ["a"])
        self.assertEqual(plan["send"][0]["target"], "/thesis")
        self.assertEqual([r["key"] for r in plan["keep"]], ["b"])
        self.assertEqual([r["key"] for r in plan["back"]], ["old"])
        self.assertEqual(plan["missing"], ["gone"])
        self.assertEqual(plan["after_bytes"], 3 + 5 - 3 + 4)
        self.assertFalse(plan["over_budget"])
        plan = dr.plan_moves(wanted, source, reading, 8, True, do_return=False)
        self.assertEqual(plan["back"], [])
        self.assertTrue(plan["over_budget"])


class Commands(unittest.TestCase):
    """Run `send` end to end with the DEVONthink calls replaced."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        (root / "notes").mkdir()
        (root / "bib").mkdir()
        (root / "notes" / "a.org").write_text(NOTE_A)
        (root / "bib" / "thesis.bib").write_text(BIB_THESIS)
        self.root = root
        self.state = root / "state.json"

    def tearDown(self):
        self.tmp.cleanup()

    def run_send(self, *extra):
        moves = []
        records = {
            "literature": [{"uuid": "u1", "filename": "smith-2017-atten.pdf",
                            "size": 10, "location": "/Inbox/"}],
            "reading": [],
        }
        argv = ["send", "--notes-dir", str(self.root / "notes"),
                 "--bib-dir", str(self.root / "bib"), *extra]
        with mock.patch.object(dr, "CONFIG_PATH", self.root / "none.json"), \
             mock.patch.object(dr, "STATE_PATH", self.state), \
             mock.patch.object(dr, "dt_database_state", return_value="open"), \
             mock.patch.object(dr, "dt_pdf_records", side_effect=lambda db: records[db]), \
             mock.patch.object(dr, "dt_move", side_effect=lambda *a: moves.append(a)):
            code = dr.main(argv)
        return code, moves

    def test_dry_run_moves_nothing(self):
        code, moves = self.run_send()
        self.assertEqual(code, 0)
        self.assertEqual(moves, [])
        self.assertFalse(self.state.exists())

    def test_apply_moves_and_remembers_origin(self):
        code, moves = self.run_send("--apply")
        self.assertEqual(code, 0)
        self.assertEqual(moves, [("u1", "reading", "/thesis")])
        state = json.loads(self.state.read_text())
        self.assertEqual(state["u1"]["location"], "/Inbox/")

    def test_over_budget_refuses(self):
        code, moves = self.run_send("--apply", "--budget-gb", "0.000000001")
        self.assertEqual(code, 1)
        self.assertEqual(moves, [])


if __name__ == "__main__":
    unittest.main()
