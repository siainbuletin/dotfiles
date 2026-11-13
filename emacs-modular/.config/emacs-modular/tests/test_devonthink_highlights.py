"""Tests for tools/devonthink-highlights.py.

Run from emacs-modular/.config/emacs-modular:
    python3 -m unittest tests/test_devonthink_highlights.py

The PDF test needs PyMuPDF (litdb's Python has it) and is skipped without it.
"""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    "devonthink_highlights", HERE.parent / "tools" / "devonthink-highlights.py")
dh = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dh)

try:
    import pymupdf
except ImportError:  # pragma: no cover
    pymupdf = None


class FakeIndexer:
    def record_pages(self, record):
        self.path = record["path"]
        return [(0, "page one", ["a"]), (5, "page six", ["b c", "d"])]


class HighlightsTest(unittest.TestCase):
    def test_pages_are_counted_from_one(self):
        fake = FakeIndexer()
        self.assertEqual(dh.highlights_of("/x.pdf", fake),
                         [{"page": 1, "highlights": ["a"]},
                          {"page": 6, "highlights": ["b c", "d"]}])
        self.assertEqual(fake.path, "/x.pdf")

    def test_main_prints_json(self):
        with mock.patch.object(dh, "highlights_of", return_value=[{"page": 2, "highlights": ["é"]}]), \
                tempfile.NamedTemporaryFile(suffix=".pdf") as f, \
                mock.patch("builtins.print") as out:
            self.assertEqual(dh.main(["x", f.name]), 0)
        self.assertEqual(json.loads(out.call_args[0][0]), [{"page": 2, "highlights": ["é"]}])

    def test_main_errors(self):
        self.assertEqual(dh.main(["x"]), 2)
        self.assertEqual(dh.main(["x", "/no/such.pdf"]), 1)

    @unittest.skipIf(pymupdf is None, "PyMuPDF is not installed")
    def test_real_pdf(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "k.pdf"
            doc = pymupdf.open()
            doc.new_page().insert_text((72, 72), "nothing here")
            page = doc.new_page()
            page.insert_text((72, 72), "exchange abstraction matters")
            page.add_highlight_annot(page.search_for("exchange abstraction"))
            doc.save(path)
            doc.close()
            self.assertEqual(dh.highlights_of(path),
                             [{"page": 2, "highlights": ["exchange abstraction"]}])

    @unittest.skipIf(pymupdf is None, "PyMuPDF is not installed")
    def test_real_pdf_annotations_have_dates_and_order(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "k.pdf"
            doc = pymupdf.open()
            page = doc.new_page()
            page.insert_text((72, 72), "exchange abstraction matters")
            annot = page.add_highlight_annot(page.search_for("exchange abstraction"))
            annot.set_info(content="my comment", creationDate="D:20261110143000+02'00'")
            annot.update()
            doc.save(path)
            doc.close()
            found = dh.annotations_of(path)
            self.assertEqual(len(found), 1)
            self.assertEqual(found[0]["page"], 1)
            self.assertEqual(found[0]["text"], "exchange abstraction")
            self.assertEqual(found[0]["note"], "my comment")
            self.assertEqual(found[0]["created"], "2026-11-10T12:30:00Z")

    def test_main_annotations_flag(self):
        with mock.patch.object(dh, "annotations_of", return_value=[{"page": 2, "text": "é"}]), \
                tempfile.NamedTemporaryFile(suffix=".pdf") as f, \
                mock.patch("builtins.print") as out:
            self.assertEqual(dh.main(["x", "--annotations", f.name]), 0)
        self.assertEqual(json.loads(out.call_args[0][0]), [{"page": 2, "text": "é"}])


class PdfDateTest(unittest.TestCase):
    def setUp(self):
        self.indexer = dh.load_indexer()

    def test_formats(self):
        d = self.indexer.pdf_date
        self.assertEqual(d("D:20261110143000Z"), "2026-11-10T14:30:00Z")
        self.assertEqual(d("D:20261110143000-05'00'"), "2026-11-10T19:30:00Z")
        self.assertEqual(d("D:20261110"), "2026-11-10T00:00:00Z")
        self.assertEqual(d("D:20261110143000"), "2026-11-10T14:30:00Z")

    def test_bad_values(self):
        d = self.indexer.pdf_date
        self.assertIsNone(d(None))
        self.assertIsNone(d(""))
        self.assertIsNone(d("garbage"))
        self.assertIsNone(d("D:20261340"))


if __name__ == "__main__":
    unittest.main()
