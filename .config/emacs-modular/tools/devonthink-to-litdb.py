#!/usr/bin/env python3
"""Index the highlighted pages of DEVONthink PDFs in litdb.

Run it with litdb's own Python, which has litdb, PyMuPDF and the embedding model:

    ~/.local/share/uv/tools/litdb/bin/python tools/devonthink-to-litdb.py [options]

For every PDF record of the DEVONthink database that has highlights, one litdb
row is made for each page that has a highlight.  The row's source is the
record's item link with the page (0-based, as DEVONthink writes it):

    x-devonthink-item://UUID?page=N

so a result opens at the right page in DEVONthink.  Records without highlights
are not indexed; DEVONthink's own search covers them.  The text of a page comes
from the PDF file (the records are indexed files), the highlights from its
highlight annotations.  A record is skipped when its modification date is the
one stored in the rows; a changed record has its rows replaced.  Nothing is
written to DEVONthink.
"""

import argparse
import datetime
import json
import os
import re
import subprocess
import sys
from pathlib import Path

SCHEME = "x-devonthink-item://"

LIST_RECORDS_JXA = """
const app = Application("DEVONthink");
const db = app.databases.byName(%s);
const c = db.contents;
const ids = c.uuid(), names = c.name(), paths = c.path();
const ann = c.annotationCount(), mod = c.modificationDate();
const out = [];
for (let i = 0; i < ids.length; i++) {
  if (ann[i] > 0 && paths[i] && paths[i].toLowerCase().endsWith(".pdf"))
    out.push({uuid: ids[i], name: names[i], path: paths[i],
              highlights: ann[i], mtime: mod[i].toISOString()});
}
JSON.stringify(out);
"""


def list_records(database):
    """Return the PDF records with highlights as a list of dicts."""
    script = LIST_RECORDS_JXA % json.dumps(database)
    result = subprocess.run(
        ["osascript", "-l", "JavaScript", "-e", script],
        capture_output=True, text=True, check=True)
    return json.loads(result.stdout)


def clean(text):
    """Collapse the whitespace of TEXT."""
    return re.sub(r"\s+", " ", text).strip()


def page_highlights(page):
    """Return the texts of the highlight annotations of PAGE."""
    import pymupdf
    found = []
    for annot in page.annots() or []:
        if annot.type[0] != pymupdf.PDF_ANNOT_HIGHLIGHT:
            continue
        vertices = annot.vertices or []
        parts = [
            page.get_textbox(pymupdf.Quad(vertices[i:i + 4]).rect)
            for i in range(0, len(vertices), 4)
        ]
        text = clean(" ".join(parts))
        if text and text not in found:
            found.append(text)
    return found


def record_pages(record):
    """Return [(page index, page text, highlights)] for the pages with highlights."""
    import pymupdf
    pymupdf.TOOLS.mupdf_display_errors(False)  # damaged PDFs are common; skip the noise
    pages = []
    with pymupdf.open(record["path"]) as doc:
        for index, page in enumerate(doc):
            highlights = page_highlights(page)
            if highlights:
                pages.append((index, page.get_text("text"), highlights))
    return pages


def row_text(highlights, page_text):
    """Text of a row: the highlights first, then the page."""
    marked = "\n".join("- " + h for h in highlights)
    return "Highlights:\n" + marked + "\n\n" + page_text


def stored_mtime(db, uuid):
    """Modification date stored for UUID's rows, or None."""
    row = db.execute(
        "select json_extract(extra, '$.mtime') from sources "
        "where source like ? limit 1", (SCHEME + uuid + "?page=%",)).fetchone()
    return row[0] if row else None


def delete_rows(db, uuid):
    """Remove the rows of UUID from sources and from the full-text table."""
    like = SCHEME + uuid + "?page=%"
    for (source,) in db.execute(
            "select source from sources where source like ?", (like,)).fetchall():
        db.execute("delete from fulltext where source = ?", (source,))
    db.execute("delete from sources where source like ?", (like,))


def index_record(db, model, splitter, record, pages):
    """Write the rows of RECORD's PAGES.  Returns the number of rows."""
    import numpy as np
    chunks, owners, rows = [], [], []
    for index, page_text, highlights in pages:
        text = row_text(highlights, page_text)
        rows.append((index, text, highlights))
        for chunk in splitter.split_text(text):
            chunks.append(chunk)
            owners.append(len(rows) - 1)
    vectors = model.encode(chunks, batch_size=64)
    delete_rows(db, record["uuid"])
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    for n, (index, text, highlights) in enumerate(rows):
        mine = [v for v, owner in zip(vectors, owners) if owner == n]
        embedding = np.mean(mine, axis=0).astype(np.float32).tobytes()
        source = "%s%s?page=%d" % (SCHEME, record["uuid"], index)
        extra = {"origin": "devonthink", "kind": "page", "uuid": record["uuid"],
                 "citekey": record["name"], "page": index + 1,
                 "highlights": highlights, "mtime": record["mtime"]}
        cursor = db.execute(
            "insert or ignore into sources(source, text, extra, embedding, date_added) "
            "values (?, ?, ?, ?, ?)",
            (source, text, json.dumps(extra), embedding, now))
        if cursor.rowcount > 0:
            db.execute("insert into fulltext(source, text) values (?, ?)", (source, text))
    db.commit()
    return len(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--database", default="literature",
                        help="DEVONthink database name (default: literature)")
    parser.add_argument("--uuid", action="append", default=[],
                        help="only this record; may be repeated")
    parser.add_argument("--limit", type=int, help="stop after this many records")
    parser.add_argument("--dry-run", action="store_true",
                        help="list the records and pages; write nothing")
    parser.add_argument("--force", action="store_true",
                        help="reindex records even when unchanged")
    args = parser.parse_args()

    os.environ.setdefault("LITDB_ROOT", str(Path.home()))
    os.chdir(os.environ["LITDB_ROOT"])

    records = list_records(args.database)
    if args.uuid:
        records = [r for r in records if r["uuid"] in args.uuid]
    if args.limit:
        records = records[:args.limit]
    print("%d records with highlights" % len(records), flush=True)

    if args.dry_run:
        for record in records:
            if os.path.exists(record["path"]):
                pages = record_pages(record)
                print("%s %s: %d highlights, %d pages" % (
                    record["uuid"], record["name"], record["highlights"], len(pages)))
        return

    from langchain_text_splitters import RecursiveCharacterTextSplitter
    from litdb.db import get_config, get_db
    from sentence_transformers import SentenceTransformer

    config = get_config()
    db = get_db()
    model = SentenceTransformer(config["embedding"]["model"])
    splitter = RecursiveCharacterTextSplitter(
        chunk_size=config["embedding"]["chunk_size"],
        chunk_overlap=config["embedding"]["chunk_overlap"])

    done = skipped = missing = 0
    total_rows = 0
    for number, record in enumerate(records, 1):
        if not os.path.exists(record["path"]):
            missing += 1
            continue
        if not args.force and stored_mtime(db, record["uuid"]) == record["mtime"]:
            skipped += 1
            continue
        pages = record_pages(record)
        if not pages:
            continue
        total_rows += index_record(db, model, splitter, record, pages)
        done += 1
        print("[%d/%d] %s: %d pages" % (number, len(records), record["name"], len(pages)),
              flush=True)
    print("indexed %d records (%d rows), %d unchanged, %d files missing"
          % (done, total_rows, skipped, missing))


if __name__ == "__main__":
    sys.exit(main())
