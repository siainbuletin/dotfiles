#!/usr/bin/env python3
# /// script
# dependencies = ["pikepdf"]
# ///
"""Write PDF page labels from the BibTeX `pages` field, for articles.

    pdf-labels-articles.py [--only KEY] [--apply]

A dry run unless --apply is given.  Only entries that are not tied to a book:
type article (or inproceedings, conference, suppperiodical) without crossref.
For books use pdf-labels-book.py.

Tangled from docs/tangles/academic/pdf-page-labels.org; edit that file.
"""

import argparse
import sys
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pdf_page_labels as pl  # noqa: E402

DEFAULT_TYPES = ("article", "inproceedings", "conference", "suppperiodical")


@dataclass
class Plan:
    key: str
    status: str                  # label, unchanged or skip
    reason: str = ""
    path: Path = None
    ranges: list = field(default_factory=list)
    warning: str = ""
    quiet: bool = False          # a skip that is only counted


def plan_entry(entry, library, types, force):
    """What to do for ENTRY.  Opens its PDF read-only; never writes."""
    if entry.type not in types:
        return Plan(entry.key, "skip", f"type {entry.type} is not handled", quiet=True)
    for tie in ("crossref", "xref"):
        if entry.fields.get(tie):
            return Plan(entry.key, "skip", f"tied to {entry.fields[tie]} ({tie}); use pdf-labels-book.py",
                        quiet=True)
    pages = entry.fields.get("pages", "")
    if not pages.strip():
        return Plan(entry.key, "skip", "no pages field")
    try:
        wanted = pl.parse_first_page(pages)
    except pl.Unparseable as error:
        return Plan(entry.key, "skip", str(error))
    pdfs = library.pdfs_of(entry)
    if not pdfs:
        return Plan(entry.key, "skip", "no PDF found")
    if len(pdfs) > 1:
        return Plan(entry.key, "skip", "several PDFs: " + ", ".join(p.name for p in pdfs))
    path = pdfs[0]
    try:
        pdf = pl.open_pdf(path)
        count = len(pdf.pages)
        current = pl.existing_ranges(pdf)
    except Exception as error:   # encrypted, damaged, not a PDF
        return Plan(entry.key, "skip", f"cannot open {path.name}: {error}", path)
    plan = Plan(entry.key, "label", f"pages {pages!r} -> first page {wanted.prefix}{wanted.start}",
                path, [wanted])
    span = pl.page_span(pages)
    if span and span != count:
        plan.warning = f"range has {span} pages, the PDF has {count}: check for a cover sheet"
    if current == [wanted]:
        plan.status = "unchanged"
    elif current and not force:
        plan.status = "skip"
        plan.reason = f"already has labels ({pl.describe(current)}); --force replaces them"
    return plan


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    pl.add_common_arguments(parser)
    parser.add_argument("--only", action="append", default=[], metavar="KEY",
                        help="only this citekey; repeat it")
    parser.add_argument("--types", default=",".join(DEFAULT_TYPES),
                        help="comma-separated BibTeX types to handle (default %(default)s)")
    parser.add_argument("--force", action="store_true",
                        help="replace page labels the PDF already has")
    parser.add_argument("--verbose", action="store_true",
                        help="also list the entries skipped for their type or crossref")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    pl.require_pikepdf()
    entries, duplicates = pl.load_bibs(pl.bib_paths(args))
    for key in duplicates:
        print(f"warning: citekey {key} occurs twice; the first entry is used", file=sys.stderr)
    types = {t.strip().lower() for t in args.types.split(",") if t.strip()}
    library = pl.Library(args.library)
    report = pl.Report(args.apply)
    backup_root = pl.new_backup_root(args.backup_dir)
    wanted_keys = set(args.only)
    for missing in sorted(wanted_keys - set(entries)):
        report.line("skip", missing, "not in the .bib files")
    for entry in entries.values():
        if wanted_keys and entry.key not in wanted_keys:
            continue
        plan = plan_entry(entry, library, types, args.force)
        suffix = f" [warning: {plan.warning}]" if plan.warning else ""
        if plan.status == "skip":
            report.line("skip", entry.key, plan.reason, show=args.verbose or not plan.quiet)
        elif plan.status == "unchanged":
            report.line("unchanged", entry.key, plan.path.name, show=args.verbose)
        elif not args.apply:
            report.line("would-label", entry.key, f"{plan.path.name}: {plan.reason}{suffix}")
        else:
            try:
                pl.write_labels(plan.path, plan.ranges, backup_root)
                report.line("labelled", entry.key, f"{plan.path.name}: {plan.reason}{suffix}")
            except Exception as error:
                report.line("failed", entry.key, f"{plan.path.name}: {error}")
    report.summary()
    if args.apply and report.counts.get("labelled"):
        print(f"Originals are in {backup_root}")
    return 1 if report.counts.get("failed") else 0


if __name__ == "__main__":
    sys.exit(main())
