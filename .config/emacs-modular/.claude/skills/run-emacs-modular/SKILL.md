---
name: run-emacs-modular
description: Run, test and smoke-check Sia's modular Emacs config (.config/emacs-modular) headless in a container. Use to load the modules, see which fail, eval a form in them, or run an ERT file.
---

# Running emacs-modular headless

Paths are relative to `.config/emacs-modular/`. The driver is `.claude/skills/run-emacs-modular/driver.sh`; it copies the config to `/tmp/emacs-modular-run/` first (override with `SP_RUN_DIR`), so nothing is written into the repo, and it points `SP_NOTES_DIR` at an empty folder, so `~/notes` is never touched.

It deliberately does **not** run `init.el`. `init.el` bootstraps Elpaca, which fetches every package recipe from MELPA/GNU ELPA; in the cloud container those hosts are blocked, so a real boot stalls forever on the first `:ensure (:wait t)`. The harness (`harness.el`) sources only `early-init.el` (paths, load-path), turns `use-package` `:ensure` into a no-op, and `require`s the default modules one by one.

## Prerequisites

```sh
apt-get update && apt-get install -y emacs-nox   # 29.3 on this image
```

## Use

```sh
.claude/skills/run-emacs-modular/driver.sh report
```
One line per module in `lem--default-modules`, ending `== 59 ok, 13 failed` (about 2 s plus the copy). Failures are modules whose external packages are absent (vulpea, org-ql, which-key, ...): compare against that baseline, a new `FAILED` line is a regression.

```sh
.claude/skills/run-emacs-modular/driver.sh eval '(sp-path sp-notes-dir "a" "b")' sp-paths
```
Requires the listed modules (after the harness), prints the form's value: `"/tmp/emacs-modular-run/notes/a/b"`.

```sh
.claude/skills/run-emacs-modular/driver.sh test tests/sp-foo-test.el
```
Loads all default modules, then the ERT file, then runs it. Pure functions are testable here; anything needing a package must be stubbed in the test file (`(when noninteractive (provide 'vulpea))`), as in `/mnt/project-files/tdd/tdd-with-claude.md`.

## Gotchas

- `emacs --batch` skips the init file unless given `-u ""`. (`-u root` switches HOME to `/root`.) Only needed if you try a real boot.
- `--init-directory` and `--headless-host` are not usable in batch; `--headless-host` is handled by `early-init.el` only when it runs as the init.
- Real boot (`emacs --fg-daemon -u ""`, `HOME` pointed at a copy) needs melpa.org and elpa.gnu.org allowed in the environment's network settings; GitHub alone is not enough, since Elpaca reads MELPA's recipes. Symptom: `[FAILED] sp-base-libraries (json-parse-error "invalid token near 'request'")`, then silence at `sp-keys`.
- `report` prints `Error (use-package): ...` lines for `org-other-agenda` and `elegant-agenda-mode`; they are noise from absent packages.
- Not covered: GUI, fonts, keybindings in a live frame, Magit, TRAMP. For those use `emacs-pr` on the Mac (`/mnt/project-files/emacs-sandbox/`).
- Don't `pkill -f` an emacs pattern from the same Bash call; it matches the shell itself.
