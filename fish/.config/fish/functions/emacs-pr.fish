# ~/.config/fish/functions/emacs-pr.fish
# Run PR N of siainbuletin/dotfiles in an isolated Emacs (no checkout in ~).
# Usage: emacs-pr 7          fetch/refresh PR 7 into ~/src/dotfiles-wt/pr-7 and launch
#        emacs-pr rm 7       remove that worktree, its packages, its home and its ref
#        emacs-pr reset 7    give PR 7 a fresh copy of ~/notes next time
#        emacs-pr reseed     drop the package seed (re-cloned from the live one next time)
#        emacs-pr --help     print this usage (and where things live)
#
# Every PR gets its own copy of everything it can write to, so any number of sandboxes can run
# next to each other and next to your live Emacs:
#   - the worktree, with its own var/ (packages, caches)
#   - var/elpaca, an APFS clone (instant, no extra disk) of a seed that is itself a clone of
#     your live var/elpaca
#   - a HOME of its own, holding a clone of ~/notes
# Only the native-compile cache is shared between sandboxes (Emacs is built to share it).
#
# Usage notes and the reasoning: "Testing a pull request in a sandbox" in
# ~/.config/emacs-modular/README.org.

# Repoint the absolute symlinks of an elpaca tree that was cloned from OLD so they target NEW.
function __emacs_pr_repoint --argument-names old new
    OLD=$old NEW=$new sh -c 'find "$NEW" -type l | while IFS= read -r l; do
        t=$(readlink "$l")
        case $t in "$OLD"/*) ln -sfn "$NEW${t#"$OLD"}" "$l";; esac
    done'
end

# Print the usage text (emacs-pr --help).
function __emacs_pr_help
    echo 'emacs-pr: run a pull request of the dotfiles in a sandboxed Emacs

Usage:
  emacs-pr N          Fetch PR N and start an Emacs on it. Running it again updates the
                      sandbox to the latest commit of the PR and starts it again.
  emacs-pr rm N       Remove everything of PR N: worktree, packages, notes copy and ref.
  emacs-pr reset N    Give PR N a fresh copy of ~/notes the next time it starts.
  emacs-pr reseed     Drop the package seed; the next new sandbox clones your live
                      packages again (sandboxes that exist keep theirs).
  emacs-pr -h|--help  Show this text.

Where things are:
  ~/src/dotfiles-wt/pr-N                 the PR\'s worktree (detached, with its own var/)
  ~/.cache/emacs-sandbox/home/pr-N       the HOME of the sandbox, holding a copy of ~/notes
  ~/.cache/emacs-sandbox/seed            clone of your live var/elpaca; each PR clones it
  ~/.cache/emacs-sandbox/eln-cache       native-compile cache, shared by all sandboxes

Each sandbox has its own packages and notes, so any number can run next to each other and
next to your live Emacs. The same commands exist inside Emacs as M-x sp-sandbox-pr,
sp-sandbox-remove, sp-sandbox-reset-notes and sp-sandbox-reseed.

Needs yadm, git and Emacs 29+, and macOS (APFS, for cp -c). More: "Testing a pull request
in a sandbox" in ~/.config/emacs-modular/README.org.'
end

function emacs-pr --description 'Isolated Emacs for a dotfiles PR'
    set -l real $HOME
    set -l cache $real/.cache/emacs-sandbox
    set -l seed $cache/seed
    set -l live $real/.config/emacs-modular/var/elpaca

    switch $argv[1]
        case '' -h --help help
            __emacs_pr_help
            return
        case reseed
            rm -rf $seed
            return
        case rm
            set -l n $argv[2]
            yadm worktree remove --force $real/src/dotfiles-wt/pr-$n
            yadm update-ref -d refs/sandbox/pr-$n
            rm -rf $cache/home/pr-$n
            return
        case reset
            rm -rf $cache/home/pr-$argv[2]
            return
    end

    set -l n $argv[1]
    set -l wt $real/src/dotfiles-wt/pr-$n
    set -l var $wt/.config/emacs-modular/var
    set -l fake $cache/home/pr-$n   # becomes HOME inside this sandbox

    # Non-branch ref, so re-running never collides with a checked-out branch.
    yadm fetch origin +pull/$n/head:refs/sandbox/pr-$n; or return
    if test -d $wt
        git -C $wt checkout --detach refs/sandbox/pr-$n; or return
    else
        yadm worktree add --detach $wt refs/sandbox/pr-$n; or return
    end

    # ~/notes etc. resolve inside the fake HOME. cp -c = APFS clone: instant, no extra disk.
    if not test -d $fake/notes
        mkdir -p $fake; or return
        cp -cR $real/notes $fake/notes; or return
    end

    # Packages: seed once from the live elpaca, then clone the seed for this PR. Elpaca's build
    # dirs hold absolute symlinks into sources/, so repoint them or they would reach another tree.
    if not test -d $seed
        mkdir -p $cache; or return
        cp -cR $live $seed; or return
        __emacs_pr_repoint $live $seed
    end
    test -L $var/elpaca; and rm $var/elpaca   # left by an earlier version that shared one cache
    if not test -d $var/elpaca
        mkdir -p $var; or return
        cp -cR $seed $var/elpaca; or return
        __emacs_pr_repoint $seed $var/elpaca
    end

    # Emacs is built to share the native-compile cache between running instances.
    mkdir -p $cache/eln-cache $var/cache
    test -L $var/cache/eln-cache; or rm -rf $var/cache/eln-cache
    ln -sfn $cache/eln-cache $var/cache/eln-cache

    # init.el has absolute /Users/... paths in org-agenda-files; point them at the fake HOME.
    set -l remap "(when (boundp 'org-agenda-files) (setq org-agenda-files (mapcar (lambda (f) (string-replace \"$real/\" \"$fake/\" f)) org-agenda-files)))"

    env HOME=$fake GIT_CONFIG_GLOBAL=$real/.gitconfig \
        emacs --init-directory $wt/.config/emacs-modular --eval $remap &
    disown
end
