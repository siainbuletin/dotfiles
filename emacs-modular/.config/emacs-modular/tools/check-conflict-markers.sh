#!/usr/bin/env bash
# Fail if a tracked text file still has a git conflict marker (<<<<<<<, =======, >>>>>>>).
# In an .el data file such as sp-org-tag-registry.el the markers read as symbols and
# break org with "Invalid association in tag alist: <<<<<<<".
# Run from anywhere inside the repository: tools/check-conflict-markers.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# Start/end markers are 7 characters followed by a space or end of line; the middle
# one is only reported when a start marker is in the same file (Org and Markdown
# headings use ======= as an underline).
hits=$(git grep -InE '^(<{7}|>{7})( |$)' -- . ':!*.svg' ':!*.patch' ':!*.diff' || true)
files=$(echo "$hits" | sed '/^$/d' | cut -d: -f1 | sort -u)
mid=""
for f in $files; do
  mid+=$(git grep -nE '^={7}$' -- "$f" || true)$'\n'
done

if [ -n "$hits" ]; then
  echo "Conflict markers left in:"
  echo "$hits"
  echo "$mid" | sed '/^$/d'
  exit 1
fi
echo "No conflict markers."
