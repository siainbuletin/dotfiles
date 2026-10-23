#!/usr/bin/env python3
"""Give every `defcustom' in the config the group `spcustom'.

Usage: docs/tools/set-defcustom-group.py [--check] [ROOT]

Rewrites the .el files and the literate .org sources under ROOT (default:
the folder above docs/), so the tangled output stays identical to the
.el files. An existing `:group' is replaced; a defcustom without one gets
`:group 'spcustom' before its closing parenthesis. Vendored libraries in
libraries/modules/cloned/ are left alone, and so are .org files that
tangle nothing (and sp-appearance-overview.org). With --check nothing is written
and the exit status is 1 when a file would change. Safe to re-run.
"""
import os
import re
import sys

GROUP = "spcustom"
TANGLES = re.compile(r"^(#\+property:.*|#\+begin_src.*):tangle (?!no\b)", re.M | re.I)
# Prot's themes code quoted for reading; its tangle target is a stray file.
SKIP_FILES = {"sp-appearance-overview.org"}
SKIP_DIRS = {".git", "cloned", "elpaca", "straight"}


def form_end(text, start):
    """Index just past the sexp that opens at text[start] == '('."""
    depth, i, n = 0, start, len(text)
    while i < n:
        c = text[i]
        if c == '"':
            i += 1
            while text[i] != '"':
                i += 2 if text[i] == "\\" else 1
        elif c == ";":
            while i < n and text[i] != "\n":
                i += 1
            continue
        elif c == "?":
            i += 2 if text[i + 1] != "\\" else 3
            continue
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise ValueError("unbalanced form at offset %d" % start)


def top_level_group(form):
    """Span of the symbol after a depth-1 `:group' in FORM, or None."""
    depth, i, n = 0, 0, len(form)
    while i < n:
        c = form[i]
        if c == '"':
            i += 1
            while form[i] != '"':
                i += 2 if form[i] == "\\" else 1
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        elif c == "'" and depth > 1:
            pass
        elif depth == 1 and form.startswith(":group", i) \
                and form[i + 6].isspace():
            m = re.compile(r"\s+('?)([^\s()]+)").match(form, i + 6)
            return m.start(2), m.end(2), m.group(1) == "'"
        i += 1
    return None


def rewrite(text):
    out, pos = [], 0
    for m in re.finditer(r"^\(defcustom\s", text, re.M):
        if m.start() < pos:
            continue
        end = form_end(text, m.start())
        form = text[m.start():end]
        g = top_level_group(form)
        if g:
            s, e, quoted = g
            form = form[:s] + GROUP + form[e:]
            if not quoted:
                form = form[:s] + "'" + form[s:]
        else:
            form = form[:-1].rstrip() + "\n  :group '%s)" % GROUP
        out += [text[pos:m.start()], form]
        pos = end
    out.append(text[pos:])
    return "".join(out)


def main():
    args = [a for a in sys.argv[1:] if a != "--check"]
    check = "--check" in sys.argv
    root = args[0] if args else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "..")
    changed = 0
    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if x not in SKIP_DIRS]
        for f in files:
            if not f.endswith((".el", ".org")) or f in SKIP_FILES:
                continue
            p = os.path.join(d, f)
            with open(p, encoding="utf-8") as fh:
                old = fh.read()
            if f.endswith(".org") and not TANGLES.search(old):
                continue  # reference docs that no .el is tangled from
            new = rewrite(old)
            if new != old:
                changed += 1
                print(("would change " if check else "changed ") + os.path.relpath(p, root))
                if not check:
                    with open(p, "w", encoding="utf-8") as fh:
                        fh.write(new)
    sys.exit(1 if check and changed else 0)


main()
