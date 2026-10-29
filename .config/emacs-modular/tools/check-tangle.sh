#!/usr/bin/env bash
# Check that the committed libraries/modules/**/*.el are what their docs tangle to.
# Run from anywhere inside the repository: tools/check-tangle.sh
#
# 1. Tangles every doc in place (tools/tangle-all.el).
# 2. Compares each .el with its committed version, ignoring trailing whitespace
#    and blank lines (the committed files have them stripped).
# 3. Files listed in tools/tangle-drift-allow.txt are known drift: reported, not
#    failing.  An entry that no longer drifts fails the check, so the list shrinks.
#
# It leaves the tangled files in the working tree: `git diff` shows the drift,
# `git checkout -- libraries` undoes it.
set -euo pipefail

cd "$(dirname "$0")/.."
allow=tools/tangle-drift-allow.txt
summary=${GITHUB_STEP_SUMMARY:-/dev/null}

emacs -Q --batch -l tools/tangle-all.el

drift=$(for f in $(git ls-files 'libraries/modules/*.el'); do
  n=$(git diff --ignore-space-at-eol --ignore-blank-lines -U0 -- "$f" | grep -c '^@@' || true)
  [ "$n" -gt 0 ] && echo "$f"
done || true)

allowed=$(grep -v '^#' "$allow" 2>/dev/null | sed '/^$/d' || true)
new=$(comm -23 <(echo "$drift" | sed '/^$/d' | sort) <(echo "$allowed" | sort) || true)
stale=$(comm -13 <(echo "$drift" | sed '/^$/d' | sort) <(echo "$allowed" | sort) || true)

{
  echo "### Tangle check"
  if [ -n "$new" ]; then
    echo "These modules differ from what their doc tangles to. Re-tangle the doc (\`M-x sp-tangle-changed\`, or \`emacs -Q --batch -l tools/tangle-all.el\`) and commit both, or move the edit into the doc:"
    echo "$new" | sed 's/^/- `/; s/$/`/'
  fi
  if [ -n "$stale" ]; then
    echo "These are in \`tools/tangle-drift-allow.txt\` but no longer drift; remove them from the list:"
    echo "$stale" | sed 's/^/- `/; s/$/`/'
  fi
  if [ -n "$allowed" ]; then
    echo "Known drift (allowed for now): $(echo "$allowed" | wc -l) module(s)."
  fi
  [ -z "$new$stale" ] && echo "All tangled modules match their docs."
} | tee -a "$summary"

[ -z "$new$stale" ]
