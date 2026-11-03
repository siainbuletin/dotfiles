#!/usr/bin/env python3
"""A long-running litdb search process for Emacs.

Run it with litdb's own Python:

    ~/.local/share/uv/tools/litdb/bin/python tools/litdb-query.py

`litdb vsearch` loads the embedding model on every call, which takes many
seconds.  This keeps the model loaded and answers requests, one JSON object per
line on standard input:

    {"id": 1, "mode": "vector", "query": "value form", "n": 20}

`mode` is "vector" (meaning), "fulltext" (words) or "hybrid" (both, merged by
reciprocal rank).  Each answer is one JSON line:

    {"id": 1, "results": [{"source": ..., "score": ..., "snippet": ..., "extra": {...}}]}

or {"id": 1, "error": "..."}.  It prints "ready" on a line of its own when the
model is loaded.  It only reads the database.
"""

import json
import os
import re
import sys
from pathlib import Path

# Anything the libraries print goes to stderr; only answers use the real stdout.
OUT = sys.stdout
sys.stdout = sys.stderr


def reply(obj):
    OUT.write(json.dumps(obj) + "\n")
    OUT.flush()


def fts_query(text):
    """Make a safe FTS5 query: every word quoted, all of them required."""
    words = [w.replace('"', "") for w in re.split(r"\s+", text.strip()) if w]
    return " ".join('"%s"' % w for w in words)


def parse_extra(extra):
    try:
        return json.loads(extra) if extra else {}
    except (TypeError, ValueError):
        return {}


def snippet(text, width=240):
    """First WIDTH characters of the page text, after the highlights."""
    body = text.split("\n\n", 1)[1] if text.startswith("Highlights:") and "\n\n" in text else text
    return re.sub(r"\s+", " ", body).strip()[:width]


def vector(db, model, np, query, n):
    emb = model.encode([query]).astype(np.float32).tobytes()
    rows = db.execute(
        """select sources.source, sources.text, sources.extra,
                  vector_distance_cos(?, embedding)
           from vector_top_k('embedding_idx', ?, ?)
           join sources on sources.rowid = id""", (emb, emb, n)).fetchall()
    rows.sort(key=lambda r: r[3])
    return [{"source": s, "score": round(1 - d, 4), "snippet": snippet(t),
             "extra": parse_extra(e)} for s, t, e, d in rows]


def fulltext(db, query, n):
    match = fts_query(query)
    if not match:
        return []
    rows = db.execute(
        """select sources.source, snippet(fulltext, 1, '', '', ' ... ', 24),
                  sources.extra, bm25(fulltext)
           from fulltext join sources on fulltext.source = sources.source
           where fulltext.text match ? order by rank limit ?""", (match, n)).fetchall()
    return [{"source": s, "score": round(-b, 4), "snippet": sn,
             "extra": parse_extra(e)} for s, sn, e, b in rows]


def hybrid(db, model, np, query, n):
    """Merge the two rankings by reciprocal rank (k = 60)."""
    merged = {}
    for results in (vector(db, model, np, query, n), fulltext(db, query, n)):
        for rank, item in enumerate(results):
            entry = merged.setdefault(item["source"], dict(item, score=0.0))
            entry["score"] += 1.0 / (60 + rank)
            if item["snippet"] and len(item["snippet"]) > len(entry["snippet"]):
                entry["snippet"] = item["snippet"]
    ranked = sorted(merged.values(), key=lambda r: -r["score"])[:n]
    for item in ranked:
        item["score"] = round(item["score"], 4)
    return ranked


def main():
    os.environ.setdefault("LITDB_ROOT", str(Path.home()))
    os.chdir(os.environ["LITDB_ROOT"])
    import numpy as np
    from litdb.db import get_config, get_db
    from sentence_transformers import SentenceTransformer

    config = get_config()
    db = get_db()
    model = SentenceTransformer(config["embedding"]["model"])
    reply({"ready": True})
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        request = {}
        try:
            request = json.loads(line)
            query, n = request["query"], int(request.get("n", 20))
            mode = request.get("mode", "vector")
            if mode == "vector":
                results = vector(db, model, np, query, n)
            elif mode == "fulltext":
                results = fulltext(db, query, n)
            elif mode == "hybrid":
                results = hybrid(db, model, np, query, n)
            else:
                raise ValueError("unknown mode %r" % mode)
            reply({"id": request.get("id"), "results": results})
        except Exception as error:  # keep serving
            reply({"id": request.get("id"), "error": str(error)})


if __name__ == "__main__":
    main()
