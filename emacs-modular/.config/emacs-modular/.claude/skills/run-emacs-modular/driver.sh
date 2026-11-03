#!/usr/bin/env bash
# Drive the emacs-modular config headless, with no package manager and no network.
#   driver.sh report            load every default module, print ok/FAILED per module
#   driver.sh eval 'FORM' [MOD…] require MODs (after the harness), then print FORM's value
#   driver.sh test FILE.el      run an ERT file (e.g. tests/sp-foo-test.el) against the modules
# Works on a throwaway copy of the config so var/ never lands in the repo.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
src=$(cd "$here/../../.." && pwd)                   # the emacs-modular directory
work=${SP_RUN_DIR:-${TMPDIR:-/tmp}/emacs-modular-run}
mkdir -p "$work/home"
# Fresh copy each time (config is ~60M mostly in cloned/; url/ and *.db are runtime junk).
rm -rf "$work/config"; mkdir -p "$work/config"
tar -C "$src" --exclude=./url --exclude='*.db' --exclude=./.claude -cf - . | tar -C "$work/config" -xf -
cp "$here/harness.el" "$work/harness.el"
export HOME="$work/home" SP_CONFIG_DIR="$work/config" SP_NOTES_DIR="$work/notes"
mkdir -p "$SP_NOTES_DIR"
run() { emacs -Q --batch -l "$work/harness.el" "$@" 2>&1 | grep -v '^Loading '; }
case "${1:-report}" in
  report) run --eval '(sp-harness-report)' ;;
  eval)   form=$2; shift 2
          reqs=""; for m in "$@"; do reqs="$reqs (sp-harness-require '$m)"; done
          run --eval "(progn $reqs (princ (format \"%S\n\" $form)))" ;;
  test)   f=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
          run --eval '(sp-harness-load-default-modules)' -l "$f" -f ert-run-tests-batch-and-exit ;;
  *) echo "usage: $0 report | eval FORM [MOD…] | test FILE" >&2; exit 2 ;;
esac
