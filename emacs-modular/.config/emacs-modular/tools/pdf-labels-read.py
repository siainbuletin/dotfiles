#!/usr/bin/env python3
# /// script
# dependencies = ["pikepdf"]
# ///
"""Read the page labels of a PDF.

    pdf-labels-read.py FILE --resolve LABEL   print the PDF page (from 1)
    pdf-labels-read.py FILE --list            print PDF page and label
    pdf-labels-read.py FILE --describe        print the label rules

Exit status of --resolve: 0 found, 3 no page labels, 4 no such label, 2 error.

Tangled from docs/tangles/academic/pdf-page-labels.org; edit that file.
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pdf_page_labels as pl  # noqa: E402

EXIT_NO_LABELS, EXIT_NOT_FOUND, EXIT_ERROR = 3, 4, 2


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("file")
    what = parser.add_mutually_exclusive_group(required=True)
    what.add_argument("--resolve", metavar="LABEL")
    what.add_argument("--list", action="store_true")
    what.add_argument("--describe", action="store_true")
    args = parser.parse_args(argv)
    pl.require_pikepdf()
    try:
        pdf = pl.open_pdf(args.file)
    except Exception as error:
        print(f"cannot open {args.file}: {error}", file=sys.stderr)
        return EXIT_ERROR
    if args.describe:
        print(pl.describe(pl.existing_ranges(pdf)))
        return 0
    if args.list:
        for number, label in enumerate(pl.labels_of(pdf), 1):
            print(f"{number}\t{label}")
        return 0
    if not pl.has_labels(pdf):
        print("the PDF has no page labels", file=sys.stderr)
        return EXIT_NO_LABELS
    pages = pl.find_pages(pdf, args.resolve)
    if not pages:
        print(f"no page is labelled {args.resolve}", file=sys.stderr)
        return EXIT_NOT_FOUND
    if len(pages) > 1:
        print(f"warning: {len(pages)} pages are labelled {args.resolve}; using the first",
              file=sys.stderr)
    print(pages[0])
    return 0


if __name__ == "__main__":
    sys.exit(main())
