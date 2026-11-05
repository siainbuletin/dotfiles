#!/usr/bin/env bash
# Migrate the dotfiles from yadm (bare repo, work tree = $HOME) to ~/dotfiles + GNU Stow.
# Guide: stow-migration/README.md. Works with macOS's bash 3.2.
#
# Nothing here deletes your files. Every step that changes $HOME first moves what it replaces
# into a backup folder, and `rollback` puts it all back.
#
#   migrate.sh preflight     read-only checks and a report
#   migrate.sh backup        tarball of the tracked files + copy of the yadm repo
#   migrate.sh restructure   clone the yadm repo to ~/dotfiles and move files into packages (branch stow-layout)
#   migrate.sh dryrun        stow -n into an empty scratch folder; shows what cutover would move; changes nothing
#   migrate.sh cutover       move the tracked files out of $HOME (into the backup) and stow the packages
#   migrate.sh verify        check every link points into the repo and the content matches the backup
#   migrate.sh retire        move ~/.git (gitfile) and the yadm repo aside so yadm cannot be used by accident
#   migrate.sh rollback      unstow, put the backed-up files and the yadm repo back
#
# Environment (all optional): STALE=ok (accept files in $HOME that differ from the repo), DOT (default ~/dotfiles), TARGET (default $HOME; set it to a scratch
# folder to rehearse), YADM_REPO, OS (darwin|linux; default from uname), BACKUP (backup folder).

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
MANIFEST=${MANIFEST:-$HERE/packages.tsv}
TARGET=${TARGET:-$HOME}
DOT=${DOT:-$HOME/dotfiles}
YADM_REPO=${YADM_REPO:-$HOME/.local/share/yadm/repo.git}
case "${OS:-$(uname -s)}" in Darwin|darwin) OS=darwin ;; Linux|linux) OS=linux ;; *) OS=${OS:-other} ;; esac
STATE=$TARGET/.dotfiles-migration-state     # remembers the backup folder between steps
STOW_OPTS=(--no-folding)                    # see "Folding" in the guide

die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
say()  { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
yg()   { git --git-dir="$YADM_REPO" --work-tree="$TARGET" "$@"; }

# ---------------------------------------------------------------- manifest
PKG=(); POS=(); PFX=(); DST=()
load_manifest() {
  local pkg os pfx dst
  [ -f "$MANIFEST" ] || die "manifest not found: $MANIFEST"
  while IFS=$'\t' read -r pkg os pfx dst || [ -n "$pkg" ]; do
    case "$pkg" in ''|'#'*) continue ;; esac
    PKG+=("$pkg"); POS+=("$os"); PFX+=("$pfx"); DST+=("${dst:-}")
  done < "$MANIFEST"
}

# map_path PATH -> prints "package<TAB>path-inside-package"; returns 1 when unmapped
map_path() {
  local p=$1 i best=-1 len=0 l
  for i in "${!PFX[@]}"; do
    if [ "$p" = "${PFX[$i]}" ] || [ "${p#"${PFX[$i]}"/}" != "$p" ]; then
      l=${#PFX[$i]}
      if [ "$l" -gt "$len" ]; then len=$l; best=$i; fi
    fi
  done
  [ "$best" -ge 0 ] || return 1
  if [ -n "${DST[$best]}" ]; then
    printf '%s\t%s\n' "${PKG[$best]}" "${DST[$best]}"
  else
    printf '%s\t%s\n' "${PKG[$best]}" "$p"
  fi
}

# packages to stow on this OS (never @root, -, or windows)
os_packages() {
  local i seen=" "
  for i in "${!PKG[@]}"; do
    case "${PKG[$i]}" in @root|-) continue ;; esac
    case "${POS[$i]}" in all|"$OS") ;; *) continue ;; esac
    case "$seen" in *" ${PKG[$i]} "*) ;; *) seen="$seen${PKG[$i]} "; printf '%s\n' "${PKG[$i]}" ;; esac
  done
}

need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found. ${2:-}"; }
install_hint() { [ "$OS" = darwin ] && echo "brew install stow" || echo "sudo pacman -S stow  (or your package manager)"; }

# ---------------------------------------------------------------- preflight
cmd_preflight() {
  load_manifest
  need git; need stow "Install it: $(install_hint)"
  [ -d "$YADM_REPO" ] || die "yadm repo not found at $YADM_REPO"
  say "yadm repo: $YADM_REPO   target: $TARGET   os: $OS   stow: $(stow --version | head -1)"
  local bad=0

  if [ -n "$(yg status --porcelain --untracked-files=no)" ]; then
    warn "yadm has staged or unstaged changes. Commit and push them first:"; yg status --short --untracked-files=no | head -20 >&2; bad=1
  fi
  local b up ahead
  while read -r b up; do
    if [ -z "$up" ]; then warn "branch $b has no upstream; push it (or it stays only in the old repo)"; bad=1; continue; fi
    ahead=$(yg rev-list --count "$up..$b" 2>/dev/null || echo 0)
    [ "$ahead" = 0 ] || { warn "branch $b is $ahead commit(s) ahead of $up: push first"; bad=1; }
  done < <(yg for-each-ref --format='%(refname:short) %(upstream:short)' refs/heads)
  if [ -n "$(yg stash list 2>/dev/null)" ]; then warn "yadm has stashes; they are NOT carried over (git stash apply them first)"; fi

  local n unmapped=0 f
  n=$(yg ls-files | wc -l | tr -d ' ')
  say "$n tracked files"
  while IFS= read -r -d '' f; do
    map_path "$f" >/dev/null || { warn "not in any package: $f"; unmapped=$((unmapped+1)); }
  done < <(yg ls-files -z)
  [ "$unmapped" = 0 ] || { warn "$unmapped unmapped file(s): add them to packages.tsv"; bad=1; }

  if [ -e "$DOT" ] && [ -n "$(ls -A "$DOT" 2>/dev/null)" ]; then warn "$DOT exists and is not empty"; bad=1; fi
  if [ -e "$TARGET/.git" ]; then
    if [ -f "$TARGET/.git" ]; then say "~/.git is a gitfile: $(cat "$TARGET/.git") (retire will move it aside)"
    else warn "~/.git is a DIRECTORY, not the gitfile from the yadm/Magit fix. Check it before going on"; bad=1; fi
  fi
  say "dropped on purpose (git rm in the new repo, still in the old history):"
  local i; for i in "${!PKG[@]}"; do [ "${PKG[$i]}" = "-" ] && echo "    ${PFX[$i]}"; done
  say "tracked files that are databases/cookies (kept, but consider untracking): "
  yg ls-files | grep -E '\.(db|sqlite)$|/cookies$' | sed 's/^/    /' || true
  [ "$bad" = 0 ] && say "preflight OK" || die "preflight found problems (see above)"
}

# ---------------------------------------------------------------- backup
backup_dir() {
  if [ -n "${BACKUP:-}" ]; then echo "$BACKUP"; return; fi
  if [ -f "$STATE" ]; then cat "$STATE"; return; fi
  echo "$TARGET/dotfiles-migration-backup-$(date +%Y%m%d-%H%M%S)"
}

cmd_backup() {
  load_manifest; need tar
  local b; b=$(backup_dir)
  [ ! -e "$b" ] || [ -f "$STATE" ] || die "$b already exists"
  mkdir -p "$b"; printf '%s\n' "$b" > "$STATE"
  say "backup folder: $b"
  # All tracked files, as they are on disk now. (A pure copy: nothing is touched.)
  yg ls-files -z | (cd "$TARGET" && tar --null -T - -czf "$b/tracked-files.tar.gz")
  # The whole yadm repo, with its history, stashes, hooks and config.
  cp -a "$YADM_REPO" "$b/yadm-repo.git"
  [ ! -f "$TARGET/.git" ] || cp -a "$TARGET/.git" "$b/home-dot-git-gitfile"
  yg ls-files > "$b/tracked-files.txt"
  say "done: $(du -sh "$b" | cut -f1)"
  say "to restore by hand: tar -xzf $b/tracked-files.tar.gz -C \$HOME"
}

# ---------------------------------------------------------------- restructure
cmd_restructure() {
  load_manifest; need git
  [ ! -e "$DOT" ] || [ -z "$(ls -A "$DOT")" ] || die "$DOT is not empty"
  say "cloning the yadm repo (history is kept)"
  git clone --quiet "$YADM_REPO" "$DOT"
  local url; url=$(yg remote get-url origin 2>/dev/null || true)
  [ -z "$url" ] || git -C "$DOT" remote set-url origin "$url"
  git -C "$DOT" config --unset core.worktree 2>/dev/null || true
  git -C "$DOT" checkout --quiet -b stow-layout
  say "moving files into packages"
  local f m pkg rel
  while IFS= read -r -d '' f; do
    m=$(map_path "$f") || die "unmapped file: $f"
    pkg=${m%%$'\t'*}; rel=${m#*$'\t'}
    case "$pkg" in
      @root) ;;
      -)     git -C "$DOT" rm -q -- "$f" ;;
      *)     mkdir -p "$DOT/$pkg/$(dirname "$rel")"
             git -C "$DOT" mv -- "$f" "$pkg/$rel" ;;
    esac
  done < <(git -C "$DOT" ls-files -z)
  # Stow's default ignore list skips README.*, .gitignore, .git*, LICENSE.* inside packages, which would
  # silently drop tracked files. A local ignore file in each package REPLACES that default list.
  local p
  for p in $(git -C "$DOT" ls-files | cut -d/ -f1 | sort -u); do
    case "$p" in README.org|adr|.github|stow-migration|.stow-global-ignore|.gitignore) continue ;; esac
    printf '%s\n' '# Replaces the stow default list, which would skip README.*, .gitignore and friends.' '\.DS_Store' \
      > "$DOT/$p/.stow-local-ignore"
  done
  # Read by stow when run from ~/dotfiles, so a plain `stow fish` does the right thing.
  printf '%s\n' '--no-folding' '--target=$HOME' > "$DOT/.stowrc"
  cat > "$DOT/.gitignore" <<'EOF'
.DS_Store
*~
\#*\#
.#*
EOF
  # CI workflows refer to the old path
  if [ -d "$DOT/.github/workflows" ]; then
    sed -i.bak 's#\.config/emacs-modular#emacs-modular/.config/emacs-modular#g' "$DOT"/.github/workflows/*.yml
    rm -f "$DOT"/.github/workflows/*.bak
  fi
  git -C "$DOT" add -A
  git -C "$DOT" commit -q -m "Reorganise into GNU Stow packages (one per tool)

Every tracked file is moved with git mv, so history follows. yadm alternate files become the
alacritty-darwin/-linux/-windows packages. Dropped: .Xauthority, yadm's config, the old blacklist
.gitignore. CI workflow paths updated."
  say "done: branch stow-layout in $DOT ($(git -C "$DOT" ls-files | wc -l | tr -d ' ') files)"
  say "next: migrate.sh dryrun"
}

# ---------------------------------------------------------------- planning helpers
# plan_files: every file that has to be a symlink in $TARGET, as "package<TAB>relative path"
plan_files() {
  local pkg f
  for pkg in $(os_packages); do
    [ -d "$DOT/$pkg" ] || continue
    (cd "$DOT/$pkg" && git ls-files -z --cached . 2>/dev/null) | while IFS= read -r -d '' f; do
      case "$(basename "$f")" in .stow-local-ignore|.DS_Store) continue ;; esac   # not linked by design
      printf '%s\t%s\n' "$pkg" "$f"
    done
  done
}

# ---------------------------------------------------------------- dryrun
cmd_dryrun() {
  load_manifest; need stow
  [ -d "$DOT/.git" ] || die "$DOT is not a git repo; run restructure first"
  local pkgs; pkgs=$(os_packages | tr '\n' ' ')
  say "packages for $OS: $pkgs"
  local scratch; scratch=$(mktemp -d)
  say "1/2 stow -n into an empty scratch folder (checks the package layout, conflicts between packages)"
  # shellcheck disable=SC2086
  stow -n "${STOW_OPTS[@]}" -d "$DOT" -t "$scratch" $pkgs || die "stow reported problems"
  # shellcheck disable=SC2086
  stow "${STOW_OPTS[@]}" -d "$DOT" -t "$scratch" $pkgs
  local want got
  want=$(plan_files | wc -l | tr -d ' ')
  got=$(find "$scratch" -type l | wc -l | tr -d ' ')
  rm -rf "$scratch"
  [ "$want" = "$got" ] || die "git tracks $want files in the packages but stow linked $got (stow ignore rules?)"
  say "ok: $got links, same as the number of tracked files in these packages"

  say "2/2 what cutover would do in $TARGET"
  local pkg rel dest same=0 move=0 missing=0 differ=0 link=0
  while IFS=$'\t' read -r pkg rel; do
    dest=$TARGET/$rel
    if [ -L "$dest" ]; then link=$((link+1))
    elif [ ! -e "$dest" ]; then missing=$((missing+1))
    elif cmp -s "$dest" "$DOT/$pkg/$rel"; then move=$((move+1))
    else differ=$((differ+1)); warn "differs from the repo: $rel  (package $pkg)"; fi
  done < <(plan_files)
  say "identical, would be moved to the backup then linked: $move"
  say "not present in \$HOME (just linked, e.g. other OS or deleted): $missing"
  say "already symlinks (left alone; stow decides): $link"
  if [ "$differ" != 0 ]; then
    # STALE=ok: the files in $HOME are older versions of repo files (the repo moved on since the
    # yadm checkout); cutover moves them into the backup like the identical ones.
    [ "${STALE:-}" = ok ] || die "$differ file(s) differ from the repo. If they are just old copies (yadm clean, repo newer), rerun with STALE=ok; if they hold local edits, commit them in yadm (or discard) and redo restructure"
    warn "$differ stale file(s) will be moved to the backup (STALE=ok)"
  fi
}

# ---------------------------------------------------------------- cutover
cmd_cutover() {
  load_manifest; need stow
  [ -d "$DOT/.git" ] || die "$DOT is not a git repo; run restructure first"
  [ -f "$STATE" ] || die "no backup yet: run backup first"
  local b; b=$(backup_dir); mkdir -p "$b/home"
  cmd_dryrun >/dev/null
  say "moving the files stow would link into $b/home"
  local pkg rel dest n=0
  while IFS=$'\t' read -r pkg rel; do
    dest=$TARGET/$rel
    if [ -e "$dest" ] && [ ! -L "$dest" ]; then
      mkdir -p "$b/home/$(dirname "$rel")"
      mv -- "$dest" "$b/home/$rel"; n=$((n+1))
    fi
  done < <(plan_files)
  say "$n file(s) moved"
  local pkgs; pkgs=$(os_packages | tr '\n' ' ')
  # shellcheck disable=SC2086
  stow -v "${STOW_OPTS[@]}" -d "$DOT" -t "$TARGET" $pkgs 2>&1 | tail -3 || {
    warn "stow failed; restoring"; cmd_rollback; die "stow failed (see above); everything was put back"; }
  say "linked. Next: migrate.sh verify"
}

# ---------------------------------------------------------------- verify
cmd_verify() {
  load_manifest
  local b; b=$(backup_dir)
  local pkg rel dest bad=0 ok=0
  while IFS=$'\t' read -r pkg rel; do
    dest=$TARGET/$rel
    if [ ! -L "$dest" ]; then warn "not a symlink: $rel"; bad=$((bad+1)); continue; fi
    if ! cmp -s "$dest" "$DOT/$pkg/$rel"; then warn "link does not reach the repo file: $rel"; bad=$((bad+1)); continue; fi
    if [ -f "$b/home/$rel" ] && ! cmp -s "$b/home/$rel" "$dest"; then warn "content differs from the backup: $rel"; bad=$((bad+1)); continue; fi
    ok=$((ok+1))
  done < <(plan_files)
  say "$ok ok, $bad problem(s)"
  [ "$bad" = 0 ] || die "verify failed"
}

# ---------------------------------------------------------------- retire
cmd_retire() {
  local b; b=$(backup_dir)
  [ -f "$STATE" ] || die "no backup yet"
  if [ -f "$TARGET/.git" ]; then mv "$TARGET/.git" "$b/home-dot-git-gitfile.retired"; say "moved the ~/.git gitfile into the backup"
  elif [ -e "$TARGET/.git" ]; then warn "~/.git is not a gitfile; left alone"; fi
  if [ -d "$YADM_REPO" ]; then mv "$YADM_REPO" "$YADM_REPO.retired"; say "yadm repo renamed to $YADM_REPO.retired"; fi
  say "yadm can no longer touch your files. Delete the .retired repo and the backup when you are confident."
}

# ---------------------------------------------------------------- rollback
cmd_rollback() {
  load_manifest; need stow
  [ -f "$STATE" ] || die "nothing to roll back (no state file)"
  local b; b=$(backup_dir)
  local pkgs; pkgs=$(os_packages | tr '\n' ' ')
  if [ -d "$DOT" ]; then
    # shellcheck disable=SC2086
    stow -D -v "${STOW_OPTS[@]}" -d "$DOT" -t "$TARGET" $pkgs 2>&1 | tail -3 || true
  fi
  if [ -d "$b/home" ]; then
    (cd "$b/home" && find . -type f -o -type l | sed 's#^\./##') | while IFS= read -r rel; do
      mkdir -p "$TARGET/$(dirname "$rel")"
      [ -e "$TARGET/$rel" ] || [ -L "$TARGET/$rel" ] || mv -- "$b/home/$rel" "$TARGET/$rel"
    done
  fi
  [ ! -d "$YADM_REPO.retired" ] || [ -e "$YADM_REPO" ] || mv "$YADM_REPO.retired" "$YADM_REPO"
  [ ! -f "$b/home-dot-git-gitfile.retired" ] || [ -e "$TARGET/.git" ] || mv "$b/home-dot-git-gitfile.retired" "$TARGET/.git"
  say "rolled back. yadm status should look as before. (~/dotfiles and the backup folder are kept.)"
}

case "${1:-}" in
  preflight|backup|restructure|dryrun|cutover|verify|retire|rollback) "cmd_$1" ;;
  *) sed -n '2,20p' "$0"; exit 2 ;;
esac
