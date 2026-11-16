"""Tests for tools/pdf_page_labels.py and the three pdf-labels-* tools.

Run from emacs-modular/.config/emacs-modular:
    python3 -m unittest tests/test_pdf_page_labels.py

Tangled from docs/tangles/academic/pdf-page-labels.org; edit that file.
"""

import contextlib
import importlib.util
import io
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
TOOLS = HERE.parent / "tools"
sys.path.insert(0, str(TOOLS))
import pdf_page_labels as pl  # noqa: E402


def load_tool(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), TOOLS / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


articles = load_tool("pdf-labels-articles")
book = load_tool("pdf-labels-book")
reader = load_tool("pdf-labels-read")

needs_pikepdf = unittest.skipIf(pl.pikepdf is None, "pikepdf is not installed")


def make_pdf(path, pages):
    pdf = pl.pikepdf.new()
    for _ in range(pages):
        pdf.add_blank_page()
    pdf.save(path)
    return Path(path)


def run(main, *argv):
    """Run a tool's main(); returns (status, stdout, stderr)."""
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            status = main(list(map(str, argv)))
        except SystemExit as exit_:
            status = exit_.code
    return status, out.getvalue(), err.getvalue()

class ParsePagesTest(unittest.TestCase):
    def first(self, pages):
        r = pl.parse_first_page(pages)
        return (r.prefix, r.style, r.start)

    def test_decimal_ranges(self):
        for pages in ("360--364", "360-364", " 360 – 364 ", "360—364", "360, 365", "360", "pp. 360--4", "360+"):
            self.assertEqual(self.first(pages), ("", "D", 360), pages)

    def test_letter_prefix(self):
        self.assertEqual(self.first("e123"), ("e", "D", 123))
        self.assertEqual(self.first("S45--S52"), ("S", "D", 45))

    def test_roman(self):
        self.assertEqual(self.first("xii--xv"), ("", "r", 12))
        self.assertEqual(self.first("XIV"), ("", "R", 14))
        self.assertEqual(self.first("iv"), ("", "r", 4))

    def test_unparseable(self):
        for pages in ("", "   ", None, "0", "A-5", "2:45", "abc", "iiii", "{}", "--"):
            with self.assertRaises(pl.Unparseable, msg=repr(pages)):
                pl.parse_first_page(pages)

    def test_page_span(self):
        self.assertEqual(pl.page_span("360--364"), 5)
        self.assertEqual(pl.page_span("1234--45"), 12)
        self.assertIsNone(pl.page_span("360"))
        self.assertIsNone(pl.page_span("xii--xv"))
        self.assertIsNone(pl.page_span("364--360"))

BIB = r"""
@comment{ ignored @article{nope, pages = {1}} }
@string{j = "Journal"}
@Article{smith-2017-x,
  author = {Smith, {J}ohn and Doe, A.},
  title = {A title, with {braces} and a comma},
  pages = {360--364},
  year = 2017,
  note = "quoted, value",
  file = {a/smith.pdf;b/other.pdf},
}
@incollection{chap-2001-y,
  crossref = {book-2000-z},
  pages = "45--67"
}
@book(book-2000-z, title = {Book}, file = {:book.pdf:PDF})
"""


class BibTest(unittest.TestCase):
    def test_parse_entries_and_fields(self):
        entries = {e.key: e for e in pl.parse_bib(BIB)}
        self.assertEqual(list(entries), ["smith-2017-x", "chap-2001-y", "book-2000-z"])
        smith = entries["smith-2017-x"]
        self.assertEqual(smith.type, "article")
        self.assertEqual(smith.fields["pages"], "360--364")
        self.assertEqual(smith.fields["year"], "2017")
        self.assertEqual(smith.fields["note"], "quoted, value")
        self.assertEqual(smith.fields["title"], "A title, with {braces} and a comma")
        self.assertEqual(entries["chap-2001-y"].fields["crossref"], "book-2000-z")
        self.assertEqual(entries["chap-2001-y"].fields["pages"], "45--67")
        self.assertEqual(entries["book-2000-z"].type, "book")

    def test_first_duplicate_wins(self):
        with tempfile.TemporaryDirectory() as tmp:
            a, b = Path(tmp, "a.bib"), Path(tmp, "b.bib")
            a.write_text("@article{k, pages={1--2}}")
            b.write_text("@article{k, pages={9--10}}")
            entries, duplicates = pl.load_bibs([a, b])
        self.assertEqual(entries["k"].fields["pages"], "1--2")
        self.assertEqual(duplicates, ["k"])


class LibraryTest(unittest.TestCase):
    def test_file_field_and_name_lookup(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "inbox").mkdir()
            (root / "inbox" / "Smith.PDF").write_bytes(b"x")
            (root / "key-a.pdf").write_bytes(b"x")
            lib = pl.Library(root)
            by_field = pl.Entry("k", "article", {"file": "inbox/Smith.PDF"})
            moved = pl.Entry("k", "article", {"file": "elsewhere/smith.pdf"})
            triple = pl.Entry("k", "article", {"file": ":inbox/Smith.PDF:PDF"})
            nofield = pl.Entry("key-a", "article", {})
            notpdf = pl.Entry("k", "article", {"file": "notes.txt"})
            self.assertEqual(lib.pdfs_of(by_field), [root / "inbox" / "Smith.PDF"])
            self.assertEqual(lib.pdfs_of(moved), [root / "inbox" / "Smith.PDF"])
            self.assertEqual(lib.pdfs_of(triple), [root / "inbox" / "Smith.PDF"])
            self.assertEqual(lib.pdfs_of(nofield), [root / "key-a.pdf"])
            self.assertEqual(lib.pdfs_of(notpdf), [])

@needs_pikepdf
class LabelsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.backups = self.dir / "backups"

    def test_article_labels_round_trip(self):
        path = make_pdf(self.dir / "a.pdf", 5)
        pl.write_labels(path, [pl.parse_first_page("360--364")], self.backups)
        pdf = pl.open_pdf(path)
        self.assertEqual(pl.labels_of(pdf), ["360", "361", "362", "363", "364"])
        self.assertEqual(pl.find_pages(pdf, "362"), [3])
        self.assertEqual(pl.find_pages(pdf, "999"), [])

    def test_prefix_and_roman(self):
        path = make_pdf(self.dir / "a.pdf", 3)
        pl.write_labels(path, [pl.parse_first_page("e123")], self.backups)
        self.assertEqual(pl.labels_of(pl.open_pdf(path)), ["e123", "e124", "e125"])
        pl.write_labels(path, [pl.parse_first_page("xii--xv")], self.backups)
        self.assertEqual(pl.labels_of(pl.open_pdf(path)), ["xii", "xiii", "xiv"])
        self.assertEqual(pl.find_pages(pl.open_pdf(path), "XIII"), [2])

    def test_backup_is_the_original_and_no_temp_file_is_left(self):
        path = make_pdf(self.dir / "a.pdf", 2)
        before = path.read_bytes()
        backup = pl.write_labels(path, [pl.LabelRange(0, "D", 10)], self.backups)
        self.assertEqual(backup.read_bytes(), before)
        self.assertNotEqual(path.read_bytes(), before)
        self.assertEqual([p.name for p in self.dir.iterdir() if p.suffix == ".pdf" or p.name.startswith(".")],
                         ["a.pdf"])

    def test_existing_ranges_read_back(self):
        path = make_pdf(self.dir / "a.pdf", 6)
        rules = [pl.LabelRange(0, "r", 1), pl.LabelRange(2, "D", 1), pl.LabelRange(4, "D", 50, "A-")]
        pl.write_labels(path, rules, self.backups)
        self.assertEqual(pl.existing_ranges(pl.open_pdf(path)), rules)
        self.assertEqual(pl.labels_of(pl.open_pdf(path)), ["i", "ii", "1", "2", "A-50", "A-51"])

    def test_a_failed_save_leaves_the_original(self):
        path = make_pdf(self.dir / "a.pdf", 2)
        before = path.read_bytes()
        with mock.patch.object(pl, "existing_ranges", return_value=[]):   # the check of the saved file fails
            with self.assertRaises(RuntimeError):
                pl.write_labels(path, [pl.LabelRange(0, "D", 5)], self.backups)
        self.assertEqual(path.read_bytes(), before)
        self.assertEqual([p.name for p in self.dir.iterdir() if p.is_file()], ["a.pdf"])

@needs_pikepdf
class ArticleToolTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.lib = self.dir / "lit"
        self.lib.mkdir()
        for name, pages in (("art.pdf", 5), ("odd.pdf", 6), ("inc.pdf", 4), ("bk.pdf", 20),
                            ("rom.pdf", 3), ("two.pdf", 2), ("two2.pdf", 2), ("done.pdf", 2)):
            make_pdf(self.lib / name, pages)
        pl.write_labels(self.lib / "done.pdf", [pl.LabelRange(0, "D", 7)], self.dir / "b0")
        self.bib = self.dir / "x.bib"
        self.bib.write_text("""
@article{art, pages = {360--364}, file = {art.pdf}}
@article{odd, pages = {10--14}, file = {odd.pdf}}
@article{rom, pages = {xii--xiv}, file = {rom.pdf}}
@article{nopages, file = {art.pdf}}
@article{weird, pages = {2:45}, file = {art.pdf}}
@article{nofile, pages = {1--2}, file = {gone.pdf}}
@article{two, pages = {1--2}, file = {two.pdf;two2.pdf}}
@article{done, pages = {7--8}, file = {done.pdf}}
@incollection{inc, pages = {45--48}, file = {inc.pdf}, crossref = {bk}}
@inproceedings{inpr, pages = {45--48}, file = {inc.pdf}, crossref = {bk}}
@book{bk, pages = {300}, file = {bk.pdf}}
""")
        self.args = ["--bib", self.bib, "--library", self.lib, "--backup-dir", self.dir / "backups"]

    def labels(self, name):
        return pl.labels_of(pl.open_pdf(self.lib / name))

    def test_dry_run_writes_nothing(self):
        before = {p.name: p.read_bytes() for p in self.lib.iterdir()}
        status, out, _ = run(articles.main, *self.args)
        self.assertEqual(status, 0)
        self.assertEqual({p.name: p.read_bytes() for p in self.lib.iterdir()}, before)
        self.assertFalse((self.dir / "backups").exists())
        self.assertIn("would-label art", out)
        self.assertIn("dry run", out)

    def test_apply_labels_articles_only(self):
        status, out, _ = run(articles.main, *self.args, "--apply")
        self.assertEqual(status, 0)
        self.assertEqual(self.labels("art.pdf"), ["360", "361", "362", "363", "364"])
        self.assertEqual(self.labels("rom.pdf"), ["xii", "xiii", "xiv"])
        self.assertEqual(self.labels("odd.pdf")[0], "10")
        self.assertEqual(self.labels("inc.pdf"), ["1", "2", "3", "4"])       # crossref: untouched
        self.assertEqual(self.labels("bk.pdf")[0], "1")                      # book: untouched
        self.assertEqual(self.labels("two.pdf"), ["1", "2"])                 # several PDFs: skipped
        self.assertIn("range has 5 pages, the PDF has 6", out)
        self.assertEqual(len(list((self.dir / "backups").rglob("*.pdf"))), 3)

    def test_skips_are_reported_with_reasons(self):
        _, out, _ = run(articles.main, *self.args)
        self.assertIn("no pages field", out)
        self.assertIn("cannot read a first page from '2:45'", out)
        self.assertIn("no PDF found", out)
        self.assertIn("several PDFs", out)
        self.assertNotIn("type book", out)               # counted, not listed
        _, verbose, _ = run(articles.main, *self.args, "--verbose")
        self.assertIn("type book is not handled", verbose)
        self.assertIn("tied to bk (crossref)", verbose)

    def test_second_run_is_unchanged_and_other_labels_need_force(self):
        run(articles.main, *self.args, "--apply")
        _, out, _ = run(articles.main, *self.args, "--apply")
        self.assertNotIn("labelled", out.replace("unlabelled", ""))
        self.assertIn("unchanged", out)
        make_pdf(self.lib / "art.pdf", 5)
        pl.write_labels(self.lib / "art.pdf", [pl.LabelRange(0, "D", 99)], self.dir / "b1")
        _, out, _ = run(articles.main, *self.args, "--apply", "--only", "art")
        self.assertIn("already has labels", out)
        self.assertEqual(self.labels("art.pdf")[0], "99")
        run(articles.main, *self.args, "--apply", "--only", "art", "--force")
        self.assertEqual(self.labels("art.pdf")[0], "360")

    def test_only_and_types(self):
        _, out, _ = run(articles.main, *self.args, "--only", "art")
        self.assertIn("art", out)
        self.assertNotIn("odd", out)
        _, out, _ = run(articles.main, *self.args, "--only", "nosuchkey")
        self.assertIn("not in the .bib files", out)
        _, out, _ = run(articles.main, *self.args, "--types", "book", "--only", "bk")
        self.assertIn("would-label bk", out)    # the user may widen the types

class BookRangesTest(unittest.TestCase):
    def test_plain_offset(self):
        self.assertEqual(book.book_ranges(9), [pl.LabelRange(0), pl.LabelRange(8, "D", 1)])

    def test_first_page_one_has_no_blank_rule(self):
        self.assertEqual(book.book_ranges(1), [pl.LabelRange(0, "D", 1)])

    def test_front_roman(self):
        self.assertEqual(book.book_ranges(9, True), [pl.LabelRange(0, "r", 1), pl.LabelRange(8, "D", 1)])
        self.assertEqual(book.book_ranges(9, True, True)[0].style, "R")
        self.assertEqual(book.book_ranges(9, True, False, 3),
                         [pl.LabelRange(0), pl.LabelRange(2, "r", 1), pl.LabelRange(8, "D", 1)])

    def test_bad_arguments(self):
        for call in (lambda: book.book_ranges(0), lambda: book.book_ranges(1, True),
                     lambda: book.book_ranges(5, True, False, 5), lambda: book.book_ranges(5, True, False, 0)):
            with self.assertRaises(ValueError):
                call()


@needs_pikepdf
class BookToolTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.lib = self.dir / "lit"
        self.lib.mkdir()
        self.pdf = make_pdf(self.lib / "bk.pdf", 14)
        self.bib = self.dir / "x.bib"
        self.bib.write_text("@book{book-2000-z, pages = {999}, file = {bk.pdf}}")
        self.args = ["--bib", self.bib, "--library", self.lib, "--backup-dir", self.dir / "backups"]

    def test_dry_run_then_apply_by_citekey(self):
        before = self.pdf.read_bytes()
        status, out, _ = run(book.main, "book-2000-z", "--first-page", 9, *self.args)
        self.assertEqual(status, 0)
        self.assertEqual(self.pdf.read_bytes(), before)
        self.assertIn("dry run", out)
        run(book.main, "book-2000-z", "--first-page", 9, "--front-roman", *self.args, "--apply")
        labels = pl.labels_of(pl.open_pdf(self.pdf))
        self.assertEqual(labels[:3], ["i", "ii", "iii"])
        self.assertEqual(labels[7:11], ["viii", "1", "2", "3"])       # page 9 is printed page 1
        self.assertEqual(len(list((self.dir / "backups").rglob("bk.pdf"))), 1)

    def test_the_bibtex_pages_field_is_not_used(self):
        run(book.main, "book-2000-z", "--first-page", 3, *self.args, "--apply")
        labels = pl.labels_of(pl.open_pdf(self.pdf))
        self.assertEqual(labels[2], "1")                  # not 999
        self.assertEqual(labels[0], "")

    def test_by_path_and_replaces_existing_labels(self):
        run(book.main, self.pdf, "--first-page", 3, *self.args, "--apply")
        run(book.main, self.pdf, "--first-page", 5, *self.args, "--apply")
        self.assertEqual(pl.labels_of(pl.open_pdf(self.pdf))[4], "1")

    def test_errors(self):
        status, _, _ = run(book.main, "book-2000-z", "--first-page", 99, *self.args)
        self.assertNotEqual(status, 0)
        status, _, _ = run(book.main, "no-such-key", "--first-page", 2, *self.args)
        self.assertNotEqual(status, 0)

@needs_pikepdf
class ReaderToolTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.pdf = make_pdf(self.dir / "a.pdf", 12)

    def test_resolve_codes(self):
        status, out, _ = run(reader.main, self.pdf, "--resolve", "3")
        self.assertEqual(status, reader.EXIT_NO_LABELS)               # no labels yet
        pl.write_labels(self.pdf, book.book_ranges(9, True), self.dir / "b")
        self.assertEqual(run(reader.main, self.pdf, "--resolve", "1")[:2], (0, "9\n"))
        self.assertEqual(run(reader.main, self.pdf, "--resolve", "4")[:2], (0, "12\n"))
        self.assertEqual(run(reader.main, self.pdf, "--resolve", "vi")[:2], (0, "6\n"))
        self.assertEqual(run(reader.main, self.pdf, "--resolve", "5")[0], reader.EXIT_NOT_FOUND)
        self.assertEqual(run(reader.main, self.dir / "missing.pdf", "--resolve", "1")[0], reader.EXIT_ERROR)

    def test_list_and_describe(self):
        pl.write_labels(self.pdf, [pl.LabelRange(0, "D", 360)], self.dir / "b")
        _, out, _ = run(reader.main, self.pdf, "--list")
        self.assertEqual(out.splitlines()[:2], ["1\t360", "2\t361"])
        _, out, _ = run(reader.main, self.pdf, "--describe")
        self.assertIn("from PDF page 1: 360", out)

    def test_runs_as_a_script(self):
        pl.write_labels(self.pdf, [pl.LabelRange(0, "D", 360)], self.dir / "b")
        done = subprocess.run([sys.executable, str(TOOLS / "pdf-labels-read.py"), str(self.pdf),
                               "--resolve", "362"], capture_output=True, text=True)
        self.assertEqual((done.returncode, done.stdout), (0, "3\n"))


if __name__ == "__main__":
    unittest.main()
