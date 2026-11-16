#!/usr/bin/env python3
"""Print the highlights of a PDF as JSON, for `sp-devonthink-highlights'.

Run it with litdb's own Python, which has PyMuPDF:

    ~/.local/share/uv/tools/litdb/bin/python tools/devonthink-highlights.py FILE.pdf

The output is a JSON list with one object per page that has highlights:

    [{"page": 6, "highlights": ["exchange abstraction", "value form"]}]

With --annotations the output is one object per highlight instead, in file
order, for `sp-devonthink-insert-annotation-link':

    [{"page": 6, "text": "value form", "note": "", "created": "2026-11-10T14:30:00Z",
      "modified": "2026-11-10T14:30:00Z"}]

created and modified are ISO 8601 UTC, or null when the PDF has no date.

Pages are counted from 1 (physical PDF pages).  The reading is done by
tools/devonthink-to-litdb.py (record_pages), so the highlights are the same
ones litdb indexes.  Nothing is written, to the PDF or to DEVONthink.
"""

import importlib.util
import json
import sys
from pathlib import Path


def load_indexer():
    """Load tools/devonthink-to-litdb.py, whose name is not an importable module name."""
    path = Path(__file__).resolve().parent / "devonthink-to-litdb.py"
    spec = importlib.util.spec_from_file_location("devonthink_to_litdb", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def highlights_of(path, indexer=None):
    """The pages of the PDF at PATH that have highlights, as a list of dicts."""
    indexer = indexer or load_indexer()
    return [{"page": index + 1, "highlights": highlights}
            for index, _text, highlights in indexer.record_pages({"path": str(path)})]


def annotations_of(path, indexer=None):
    """Every highlight of the PDF at PATH as a dict, in file order (see the module doc)."""
    import pymupdf
    indexer = indexer or load_indexer()
    pymupdf.TOOLS.mupdf_display_errors(False)
    found = []
    with pymupdf.open(str(path)) as doc:
        for index, page in enumerate(doc):
            for detail in indexer.page_highlight_details(page):
                found.append(dict(detail, page=index + 1))
    return found


def main(argv):
    args = argv[1:]
    detailed = "--annotations" in args
    args = [a for a in args if a != "--annotations"]
    if len(args) != 1:
        print("usage: devonthink-highlights.py [--annotations] FILE.pdf", file=sys.stderr)
        return 2
    if not Path(args[0]).is_file():
        print("no such file: %s" % args[0], file=sys.stderr)
        return 1
    result = annotations_of(args[0]) if detailed else highlights_of(args[0])
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
