#!/usr/bin/env python3
"""Print the highlights of a PDF as JSON, for `sp-devonthink-highlights'.

Run it with litdb's own Python, which has PyMuPDF:

    ~/.local/share/uv/tools/litdb/bin/python tools/devonthink-highlights.py FILE.pdf

The output is a JSON list with one object per page that has highlights:

    [{"page": 6, "highlights": ["exchange abstraction", "value form"]}]

Pages are counted from 1, as printed.  The reading is done by
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


def main(argv):
    if len(argv) != 2:
        print("usage: devonthink-highlights.py FILE.pdf", file=sys.stderr)
        return 2
    if not Path(argv[1]).is_file():
        print("no such file: %s" % argv[1], file=sys.stderr)
        return 1
    print(json.dumps(highlights_of(argv[1]), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
