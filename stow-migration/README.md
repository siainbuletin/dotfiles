# Moving the dotfiles from yadm to ~/dotfiles + GNU Stow

Decision record: `adr/0023-stow-instead-of-yadm.org`. Everything is run by `stow-migration/migrate.sh`
(bash 3.2 safe, so it works with macOS's own bash; you can keep using fish as your shell, just run
`bash stow-migration/migrate.sh <step>`). Nothing is deleted: files that Stow replaces are moved into a
backup folder, and `rollback` puts everything back.

## What changes

| | yadm today | Stow |
|---|---|---|
| Repo | bare repo in `~/.local/share/yadm`, work tree `~` | normal clone in `~/dotfiles` (history kept) |
| Files in `~` | real files | symlinks into `~/dotfiles/<package>/...` |
| Layout | paths relative to `~` | one folder per tool, the path under it is the path under `~` |
| Per-OS files | `shell.toml##os.Darwin` | packages `alacritty-darwin`, `alacritty-linux`, only stowed on that OS |
| Git tools | need `~/.git` gitfile + `GIT_CEILING_DIRECTORIES` | work unchanged in `~/dotfiles` |

`~/.config/emacs-modular` stays exactly where it is, as a tree of symlinks into
`~/dotfiles/emacs-modular/.config/emacs-modular`. Package list: `stow-migration/packages.tsv`
(`.config/fish` is the `fish` package, `.zshrc` is `zsh`, and so on; macOS-only ones are `aerospace`,
`hammerspoon`, `emacs-plus`; Linux-only ones are `i3`, `sway`, `polybar`, `rofi`, ...).

## Steps (each one is safe to stop after)

Install Stow first: `brew install stow` (macOS), `sudo pacman -S stow` (Arch).

1. **Push everything in yadm.** `yadm status` clean, every branch pushed (`preflight` checks this).
2. `migrate.sh preflight`: read-only. Lists unmapped files, unpushed work, the `~/.git` type.
3. `migrate.sh backup`: tarball of every tracked file plus a full copy of the yadm repo, in
   `~/dotfiles-migration-backup-<date>/`.
4. `migrate.sh restructure`: clones the yadm repo to `~/dotfiles` (all history) and `git mv`s files into
   packages on a branch `stow-layout`. Updates the CI workflow paths, drops `.Xauthority`, yadm's config
   and the old `$HOME`-blacklist `.gitignore`. Adds a `.stowrc` (`--no-folding`, `--target=$HOME`) and a
   `.stow-local-ignore` per package (see "Stow ignores README and .gitignore" below). Review with
   `git -C ~/dotfiles show --stat`.
5. `migrate.sh dryrun`: runs `stow -n`, then really stows into an empty scratch folder to prove the
   layout, checks the link count equals the number of tracked files, and reports how many files in `~`
   are identical to the repo (they will be moved) or differ (it stops; commit those in yadm and redo
   from step 4 after `rm -rf ~/dotfiles`). Changes nothing in `~`.
6. **Quit Emacs**, then `migrate.sh cutover`: moves each file Stow will replace into the backup
   folder (`.../home/...`) and runs `stow`. Untracked state (`var/`, `elpaca/`, `eln-cache/`) is never
   touched. `migrate.sh verify` then compares every link and its content.
7. Start Emacs and fish and use them for a few days. `~/dotfiles` merges into `main` through the usual PR.
8. `migrate.sh retire`: moves the `~/.git` gitfile into the backup and renames the yadm repo to
   `repo.git.retired`. From here `yadm` cannot act on `~` by accident. Delete the `.retired` repo and the
   backup only when you are sure.

**Undo at any point before step 8, or after:** `migrate.sh rollback` (unstows, moves the backup files
back, restores `repo.git` and `~/.git`). If the script itself is unavailable:
`tar -xzf ~/dotfiles-migration-backup-*/tracked-files.tar.gz -C ~` after `cd ~/dotfiles && stow -D <pkgs>`.

Stray files after the move: yadm's `shell.toml##os.*` copies in `~/.config/alacritty` stay behind as
plain files; remove them once `shell.toml` is a link.

## Daily use

**Pulling changes from GitHub into Emacs.** `~/.config/emacs-modular` is a tree of links into
`~/dotfiles`, so `git -C ~/dotfiles pull` is all that is needed for changed files: Emacs sees the new
content at once (restart Emacs, or reload the changed module). Re-stow only when the pull adds or removes files:
`cd ~/dotfiles && stow -R emacs-modular`. Never edit a file through a path that is not a link, and
never use `yadm` once the cutover has run.

```fish
cd ~/dotfiles
stow fish            # link a package (reads .stowrc)
stow -R emacs-modular   # re-link after adding/removing files in the repo
stow -D i3            # unlink
```

Set up another machine: `git clone <repo> ~/dotfiles && cd ~/dotfiles`, then
`for p in fish zsh emacs-modular ...; stow $p; end`. The OS-specific list is what
`migrate.sh` derives from `packages.tsv` (`OS=linux` or `darwin`).

**A new file** (for instance a new Emacs module): create it in the repo, not in `~`, then `stow -R <package>`.
If you created it in `~` by mistake: `mv ~/.config/foo/bar ~/dotfiles/foo/.config/foo/bar && stow -R foo`.
That is the safe way to do what `stow --adopt` does.

### "cannot stow ... neither a link nor a directory"
Stow found a real file where it wants a link. Run `stow -n -v <package>` to see the list. It means the
cutover has not run (or the files were recreated in `~`): `~/.config/...` is still the old yadm
checkout. Do **not** run plain `stow`/`--adopt` first. Check `yadm status` is clean, then run
`migrate.sh backup`, `dryrun`, `cutover`, `verify`. If `dryrun` stops on "differ from the repo" and yadm
is clean, the home files are just older than the repo: rerun with `STALE=ok` (they go to the backup
like the rest). Do not `yadm pull` once the repo uses the Stow layout; it would reshuffle `~`.
`verify` reports the stale files as "content differs from the backup" by design.

### `stow --adopt` caveats
`--adopt` moves the existing file from `~` into the package, **overwriting the repo's version**, then links
it. If the two differ you silently get the machine's version in the working tree. Use it only on a clean
repo, and check `git -C ~/dotfiles diff` right after; `git restore .` throws the adopted content away
and keeps the repo's. The script never uses it.

### Folding
`.stowrc` has `--no-folding`: Stow links each file, never a whole directory. Otherwise `~/.config/fish`
or `~/.claude` would become one symlink and everything the apps write there (`fish_variables`,
sessions, caches) would land inside the repo. The cost is that new files made by an app in `~` are not
in the repo until you move them (above). Optional later step for Emacs only: its own `.gitignore`
already covers `var/`, `elpaca/` and the rest, so you can fold it: quit Emacs, `rsync -a --ignore-existing
~/.config/emacs-modular/ ~/dotfiles/emacs-modular/.config/emacs-modular/`, move the old directory aside,
`stow --folding emacs-modular`. Then new modules appear in the repo by themselves.

### Stow ignores README and .gitignore
Stow's default ignore list skips `README.*`, `LICENSE.*`, `.gitignore`, `.git*` inside packages, which
would leave out `emacs-modular/README.org` and the `.gitignore`s that live in your config. Each package
therefore has a `.stow-local-ignore`, which replaces the default list (only `.DS_Store` is ignored).
Do not delete it.

## Git, Magit and Forge

- `~/dotfiles` is an ordinary repo: `magit-status` there, `gh`, SourceGit and GitKraken all work. The
  TRAMP method for yadm and the `~/.git` gitfile are no longer needed. `retire` removes the gitfile, so
  `~/Downloads` etc. are no longer "inside" a repo.
- `GIT_CEILING_DIRECTORIES=$HOME` (set in `sp-env.el` and the shell startup files to make yadm work):
  with the gitfile gone it is no longer needed. It is harmless; remove it in a follow-up PR (the line
  in the `exec-path-from-shell` list, plus the export in the fish/zsh config) once yadm is retired.
- **Opening files through a link.** Emacs asks "Symbolic link to Git-controlled source file; follow
  link?" for `~/.config/emacs-modular/...`. Say yes, or set `(setq vc-follow-symlinks t)` so the
  buffer belongs to `~/dotfiles` and Magit, diff-hl and `project.el` find the repo. Without it Magit
  reports "not a repository". Check what `sp-*` already sets for it.
- Forge keys its database by forge/owner/repo, not by path, so it follows the repo; the tracked
  `forge-database.sqlite` is a link into `~/dotfiles`. If Forge is slow, `forge-pull` once. Projectile
  and `project.el` known-projects may still contain `~/`; remove it and add `~/dotfiles`.
- `M-x yadm` (`sp-vcontrol.el`, `magit-status "~/"`) and the `sp-yadm-repo` variable (`sp-globals.el`)
  should become `~/dotfiles`; do that in a follow-up PR after the cutover.

## What the move breaks in the repo (and what is done)

Every path gains a package prefix: `.config/emacs-modular/x` becomes `emacs-modular/.config/emacs-modular/x`.
- Done by `restructure`: paths in `.github/workflows/*.yml`.
- To do afterwards: `emacs-pr.fish` uses `$wt/.config/emacs-modular` (the PR worktree), the
  `dotfiles-changelog` skill and the nightly CHANGELOG routine mention
  `.config/emacs-modular/CHANGELOG.org`, and `README.org`/`adr/` text that cites paths.
- Open PRs: Git follows the renames when you merge `main` into a branch, but a branch that edits a
  file the PR author expects at the old path (a CHANGELOG union merge, tangle paths in a script) needs a
  look. Best to cut over when few PRs are open, and merge the migration PR right before.

## Other things to know

- **Secrets.** Dropped: `.Xauthority` (an X cookie). Still tracked: `forge-database.sqlite` and
  `url/cookies` (cookies) under emacs-modular, and some tracked music/Emacs state (`cmus`,
  `audacious` scrobbler log, `emacs-distributions/*/var/cache`). The history still contains all of it;
  if the repo is public, consider `git rm --cached` for the cookies and a history scrub later. The script
  does not decide this for you.
- **Windows** has no Stow. `alacritty-windows` is kept in the repo but never stowed; copy it by hand
  or with the PowerShell bootstrap in ADR 0019.
- **Per-OS files** replace yadm alternates. For another file that differs by OS, make
  `<tool>-darwin` / `<tool>-linux` packages and add rows to `packages.tsv`.
- Stashes in the yadm repo are not carried over.
