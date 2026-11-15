#!/usr/bin/env python3
# /// script
# dependencies = ["pikepdf"]
# ///
"""Write PDF page labels for one book, from the page where printed page 1 starts.

    pdf-labels-book.py CITEKEY-OR-PDF --first-page N [--front-roman] [--apply]

A dry run unless --apply is given.  It does not read the BibTeX `pages` field.

Tangled from docs/tangles/academic/pdf-page-labels.org; edit that file.
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pdf_page_labels as pl  # noqa: E402


def book_ranges(first_page, front_roman=False, roman_upper=False, roman_from=1):
    """The label rules for a book whose printed page 1 is physical page FIRST_PAGE."""
    if first_page < 1:
        raise ValueError("--first-page counts from 1")
    ranges = []
    if front_roman:
        if not 1 <= roman_from < first_page:
            raise ValueError("--front-roman-from must be at least 1 and before --first-page")
        if roman_from > 1:
            ranges.append(pl.LabelRange(0))
        ranges.append(pl.LabelRange(roman_from - 1, "R" if roman_upper else "r", 1))
    elif first_page > 1:
        ranges.append(pl.LabelRange(0))
    ranges.append(pl.LabelRange(first_page - 1, "D", 1))
    return ranges


def find_pdf(target, library, bib_files):
    """The PDF for TARGET, a path or a citekey; exits with a message when not exactly one."""
    path = Path(target).expanduser()
    if path.suffix.lower() == ".pdf" and path.is_file():
        return path
    entries, _ = pl.load_bibs(bib_files)
    if target in entries:
        pdfs = library.pdfs_of(entries[target])
    else:
        pdfs = library.find(target + ".pdf")
    if not pdfs:
        sys.exit(f"no PDF found for {target}")
    if len(pdfs) > 1:
        sys.exit(f"several PDFs for {target}; pass the path of one:\n  "
                 + "\n  ".join(map(str, pdfs)))
    return pdfs[0]


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("target", help="a citekey, or the path of a PDF")
    pl.add_common_arguments(parser)
    parser.add_argument("--first-page", type=int, required=True, metavar="N",
                        help="the PDF page (1 is the first page of the file) where printed page 1 is")
    parser.add_argument("--front-roman", action="store_true",
                        help="number the pages before --first-page i, ii, iii, ...")
    parser.add_argument("--front-roman-upper", action="store_true",
                        help="with --front-roman: I, II, III")
    parser.add_argument("--front-roman-from", type=int, default=1, metavar="N",
                        help="with --front-roman: the PDF page where i is (default 1)")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    pl.require_pikepdf()
    try:
        ranges = book_ranges(args.first_page, args.front_roman,
                             args.front_roman_upper, args.front_roman_from)
    except ValueError as error:
        sys.exit(str(error))
    path = find_pdf(args.target, pl.Library(args.library), pl.bib_paths(args))
    pdf = pl.open_pdf(path)
    count = len(pdf.pages)
    if args.first_page > count:
        sys.exit(f"{path.name} has {count} pages, --first-page {args.first_page} is past the end")
    current = pl.existing_ranges(pdf)
    print(f"file:     {path}")
    print(f"pages:    {count}")
    print(f"current:  {pl.describe(current)}")
    print(f"new:      {pl.describe(ranges)}")
    if current == ranges:
        print("nothing to do: the labels are already these")
        return 0
    if not args.apply:
        print("This was a dry run: nothing was written.  Add --apply to write.")
        return 0
    backup = pl.write_labels(path, ranges, pl.new_backup_root(args.backup_dir))
    print(f"written; the original is {backup}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
