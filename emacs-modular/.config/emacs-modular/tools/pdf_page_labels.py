"""Read and write PDF page labels for the literature tools.

Shared by tools/pdf-labels-articles.py, tools/pdf-labels-book.py and
tools/pdf-labels-read.py.  Needs pikepdf for anything that opens a PDF.

Tangled from docs/tangles/academic/pdf-page-labels.org; edit that file.
"""

import io
import os
import re
import shutil
import sys
import tempfile
import unicodedata
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

try:
    import pikepdf
except ImportError:          # require_pikepdf() explains it when a command needs it
    pikepdf = None

DEFAULT_LIBRARY = Path.home() / "Documents" / "literature"
DEFAULT_BIB_DIR = Path.home() / "Documents" / "bibliography"
DEFAULT_BACKUP_DIR = Path.home() / ".local" / "state" / "pdf-page-labels" / "backups"


def require_pikepdf():
    """Stop with an install hint when pikepdf is missing."""
    if pikepdf is None:
        sys.exit("pikepdf is needed to read PDFs: pip install pikepdf "
                 "(it bundles qpdf), or run the script with `uv run`.")

@dataclass(frozen=True)
class LabelRange:
    """One page-label rule: from physical page INDEX (0-based) on."""
    index: int
    style: str = None
    start: int = 1
    prefix: str = ""


class Unparseable(ValueError):
    """A pages field (or a roman numeral) that cannot give a first page."""

_ROMAN_RE = re.compile(
    r"(?=[mdclxvi])m{0,3}(cm|cd|d?c{0,3})(xc|xl|l?x{0,3})(ix|iv|v?i{0,3})", re.I)
_ROMAN_VALUES = {"i": 1, "v": 5, "x": 10, "l": 50, "c": 100, "d": 500, "m": 1000}
_SEPARATOR_RE = re.compile(r"\s*[-\u2013\u2014,;]+\s*")


def roman_to_int(text):
    """The value of the roman numeral TEXT, or Unparseable."""
    if not _ROMAN_RE.fullmatch(text):
        raise Unparseable(f"{text!r} is not a roman numeral")
    total, previous = 0, 0
    for char in reversed(text.lower()):
        value = _ROMAN_VALUES[char]
        if value < previous:
            total -= value
        else:
            total += value
            previous = value
    return total


def _clean_pages(pages):
    text = (pages or "").strip().strip("{}").strip()
    return re.sub(r"^pp?\.?\s*", "", text, flags=re.I)


def first_page_token(pages):
    """The text of the first page in the BibTeX PAGES string."""
    text = _clean_pages(pages)
    if not text:
        raise Unparseable("empty pages field")
    return _SEPARATOR_RE.split(text, maxsplit=1)[0].strip().rstrip("+").strip()


def parse_first_page(pages):
    """The LabelRange that makes physical page 1 carry the first page of PAGES."""
    token = first_page_token(pages)
    match = re.fullmatch(r"([A-Za-z]{1,4})?(\d+)", token)
    if match:
        number = int(match.group(2))
        if number < 1:
            raise Unparseable(f"page {number} is not positive")
        return LabelRange(0, "D", number, match.group(1) or "")
    try:
        number = roman_to_int(token)
    except Unparseable:
        raise Unparseable(f"cannot read a first page from {pages!r}") from None
    return LabelRange(0, "R" if token.isupper() else "r", number)


def page_span(pages):
    """How many pages the decimal range in PAGES covers, or None.

    =360--364= gives 5.  An abbreviated end (=1234--45=) is completed from the start."""
    parts = _SEPARATOR_RE.split(_clean_pages(pages))
    if len(parts) != 2:
        return None
    first, last = parts[0].strip(), parts[1].strip()
    if not (first.isdigit() and last.isdigit()):
        return None
    if len(last) < len(first):
        last = first[:len(first) - len(last)] + last
    span = int(last) - int(first) + 1
    return span if span >= 1 else None

def open_pdf(path):
    """Open PATH from memory, so that the file can be replaced while open."""
    require_pikepdf()
    return pikepdf.open(io.BytesIO(Path(path).read_bytes()))


def has_labels(pdf):
    return "/PageLabels" in pdf.Root


def labels_of(pdf):
    """The label of every page, in physical order."""
    return [page.label for page in pdf.pages]


def existing_ranges(pdf):
    """The label rules of PDF as a list of LabelRange, empty when it has none."""
    if not has_labels(pdf):
        return []
    ranges = []
    for index, rule in sorted(pikepdf.NumberTree(pdf.Root.PageLabels).items()):
        style = str(rule.S)[1:] if "/S" in rule else None
        prefix = str(rule.P) if "/P" in rule else ""
        start = int(rule.St) if "/St" in rule else 1
        ranges.append(LabelRange(int(index), style, start, prefix))
    return ranges


def set_labels(pdf, ranges):
    """Replace the page labels of PDF with RANGES."""
    nums = pikepdf.Array()
    for item in sorted(ranges, key=lambda r: r.index):
        rule = pikepdf.Dictionary()
        if item.style:
            rule["/S"] = pikepdf.Name("/" + item.style)
        if item.prefix:
            rule["/P"] = pikepdf.String(item.prefix)
        if item.start != 1:
            rule["/St"] = item.start
        nums.append(item.index)
        nums.append(rule)
    pdf.Root["/PageLabels"] = pdf.make_indirect(pikepdf.Dictionary(Nums=nums))


def find_pages(pdf, label):
    """The physical pages (counted from 1) whose label is LABEL."""
    labels = labels_of(pdf)
    exact = [i + 1 for i, found in enumerate(labels) if found == label]
    return exact or [i + 1 for i, found in enumerate(labels)
                     if found.casefold() == label.casefold()]


def describe(ranges):
    """A short text for RANGES, for reports."""
    if not ranges:
        return "no page labels"
    names = {"D": "1,2,3", "r": "i,ii,iii", "R": "I,II,III", None: "no number"}
    return "; ".join(
        f"from PDF page {r.index + 1}: {r.prefix}{r.start} ({names.get(r.style, r.style)})"
        if r.style else f"from PDF page {r.index + 1}: unnumbered"
        for r in ranges)

def backup_path(path, backup_root):
    """Where the backup of PATH goes below BACKUP_ROOT."""
    return Path(backup_root).joinpath(*Path(path).resolve().parts[1:])


def new_backup_root(base):
    """A fresh folder for one run's backups, named by the time."""
    return Path(base).expanduser() / datetime.now().strftime("%Y%m%d-%H%M%S")


def write_labels(path, ranges, backup_root):
    """Back PATH up below BACKUP_ROOT, then rewrite it with the labels RANGES.

    Returns the path of the backup."""
    path = Path(path)
    ranges = sorted(ranges, key=lambda r: r.index)
    pdf = open_pdf(path)
    pages = len(pdf.pages)
    set_labels(pdf, ranges)
    handle, temp = tempfile.mkstemp(suffix=".pdf", prefix=".labels-", dir=path.parent)
    os.close(handle)
    try:
        pdf.save(temp)
        with pikepdf.open(temp) as check:
            if len(check.pages) != pages or existing_ranges(check) != ranges:
                raise RuntimeError("the saved file does not match: left the original alone")
        backup = backup_path(path, backup_root)
        backup.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, backup)
        shutil.copymode(path, temp)
        os.replace(temp, path)
    except BaseException:
        if os.path.exists(temp):
            os.remove(temp)
        raise
    return backup

_ENTRY_START = re.compile(r"@\s*([A-Za-z]+)\s*([{(])\s*([^,\s{}()]*)\s*(,?)")
_FIELD_START = re.compile(r"[\s,]*([A-Za-z][\w:\-]*)\s*=\s*")
_NOT_ENTRIES = {"string", "comment", "preamble"}


@dataclass
class Entry:
    key: str
    type: str
    fields: dict
    source: Path = None


def _balanced(text, start, open_char, close_char):
    """The index just after the bracket that closes the one at TEXT[START]."""
    depth, i = 0, start
    while i < len(text):
        char = text[i]
        if char == "\\":
            i += 2
            continue
        if char == open_char:
            depth += 1
        elif char == close_char:
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return len(text)


def _parse_fields(body):
    fields, i = {}, 0
    while True:
        match = _FIELD_START.match(body, i)
        if not match or match.end() >= len(body):
            return fields
        name, i = match.group(1).lower(), match.end()
        if body[i] == "{":
            end = _balanced(body, i, "{", "}")
            value = body[i + 1:end - 1]
        elif body[i] == '"':
            end = i + 1
            depth = 0
            while end < len(body) and not (body[end] == '"' and depth == 0):
                if body[end] == "\\":
                    end += 1
                elif body[end] == "{":
                    depth += 1
                elif body[end] == "}":
                    depth -= 1
                end += 1
            value = body[i + 1:end]
            end += 1
        else:
            end = re.compile(r"[^,]*").match(body, i).end()
            value = body[i:end].strip()
        fields.setdefault(name, " ".join(value.split()))
        i = end


def parse_bib(text, source=None):
    """The entries of the BibTeX TEXT, as a list of Entry."""
    entries, position = [], 0
    while True:
        match = _ENTRY_START.search(text, position)
        if not match:
            return entries
        close = "}" if match.group(2) == "{" else ")"
        end = _balanced(text, match.start(2), match.group(2), close)
        position = end
        kind = match.group(1).lower()
        if kind in _NOT_ENTRIES or not match.group(4):
            continue
        entries.append(Entry(match.group(3), kind,
                             _parse_fields(text[match.end():end - 1]), source))


def bib_files(bib_dir):
    """Every .bib file directly in BIB_DIR."""
    return sorted(Path(bib_dir).expanduser().glob("*.bib"))


def load_bibs(paths):
    """Entries of the .bib files PATHS by citekey, and the keys found twice."""
    entries, duplicates = {}, []
    for path in paths:
        for entry in parse_bib(Path(path).read_text(encoding="utf-8", errors="replace"), path):
            if entry.key in entries:
                duplicates.append(entry.key)
            else:
                entries[entry.key] = entry
    return entries, duplicates

def _normal(name):
    return unicodedata.normalize("NFC", name).casefold()


class Library:
    """The literature folder, with a lazy index of its files by name."""

    def __init__(self, root):
        self.root = Path(root).expanduser()
        self._index = None

    def find(self, name):
        """The files below the library called like the path NAME."""
        if self._index is None:
            self._index = {}
            for folder, dirs, files in os.walk(self.root):
                dirs[:] = [d for d in dirs if not d.startswith(".")]
                for file in files:
                    self._index.setdefault(_normal(file), []).append(Path(folder) / file)
        return self._index.get(_normal(Path(name).name), [])

    def pdfs_of(self, entry):
        """The existing PDFs of ENTRY, without duplicates."""
        found = []
        pieces = [p.strip() for p in entry.fields.get("file", "").split(";") if p.strip()]
        for piece in pieces:
            parts = piece.split(":")
            if len(parts) >= 3:
                piece = parts[1]
            if not piece.lower().endswith(".pdf"):
                continue
            path = Path(piece).expanduser()
            if not path.is_absolute():
                path = self.root / path
            found.extend([path] if path.is_file() else self.find(piece))
        if not pieces:
            found.extend(self.find(entry.key + ".pdf"))
        return list(dict.fromkeys(p for p in found if p.suffix.lower() == ".pdf"))

def add_common_arguments(parser):
    parser.add_argument("--apply", action="store_true",
                        help="write the labels (the default is a dry run)")
    parser.add_argument("--library", default=str(DEFAULT_LIBRARY),
                        help="the folder of the PDFs (default %(default)s)")
    parser.add_argument("--bib-dir", default=str(DEFAULT_BIB_DIR),
                        help="the folder of the .bib files (default %(default)s)")
    parser.add_argument("--bib", action="append", default=[],
                        help="a .bib file; repeat it; replaces --bib-dir")
    parser.add_argument("--backup-dir", default=str(DEFAULT_BACKUP_DIR),
                        help="where originals are copied before they change (default %(default)s)")


def bib_paths(args):
    """The .bib files the arguments select."""
    return [Path(b).expanduser() for b in args.bib] or bib_files(args.bib_dir)


class Report:
    """Collects one outcome per file and prints them."""

    def __init__(self, apply):
        self.apply = apply
        self.counts = {}

    def line(self, status, name, text="", show=True):
        self.counts[status] = self.counts.get(status, 0) + 1
        if show:
            print(f"{status:<10} {name}" + (f"  {text}" if text else ""))

    def summary(self):
        print()
        print(", ".join(f"{n} {status}" for status, n in sorted(self.counts.items())) or "nothing to do")
        if not self.apply and any(s in self.counts for s in ("would-label",)):
            print("This was a dry run: nothing was written.  Add --apply to write.")
