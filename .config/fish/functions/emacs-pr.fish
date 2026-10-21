# ~/.config/fish/functions/emacs-pr.fish
# Run PR N of siainbuletin/dotfiles in an isolated Emacs (no checkout in ~).
# Usage: emacs-pr 7        fetch/refresh PR 7 into ~/src/dotfiles-wt/pr-7 and launch
#        emacs-pr rm 7     remove that worktree and its ref
#        emacs-pr reset    throw away the sandbox HOME (fresh copy of ~/notes next time)
#        emacs-pr reseed   throw away the shared package cache (cloned from the live one next time)
#
# Packages: every PR worktree gets var/elpaca and the native-compile cache as symlinks into ONE
# sandbox cache, which is cloned (APFS, instant) from your live var/elpaca on first use. So no
# PR reinstalls anything except packages the live config doesn't have. Don't run two sandboxes at once.
#
# Usage notes and the reasoning: "Testing a pull request in a sandbox" in
# ~/.config/emacs-modular/README.org.

function emacs-pr --description 'Isolated Emacs for a dotfiles PR'
    set -l real $HOME
    set -l fake $real/.cache/emacs-sandbox-home   # becomes HOME inside the sandbox

    switch $argv[1]
        case reset
            rm -rf $fake
            return
        case reseed
            rm -rf $real/.cache/emacs-sandbox
            return
        case rm
            set -l n $argv[2]
            yadm worktree remove --force $real/src/dotfiles-wt/pr-$n
            yadm update-ref -d refs/sandbox/pr-$n
            return
    end

    set -l n $argv[1]
    set -l wt $real/src/dotfiles-wt/pr-$n

    # Non-branch ref, so re-running never collides with a checked-out branch.
    yadm fetch origin +pull/$n/head:refs/sandbox/pr-$n; or return
    if test -d $wt
        git -C $wt checkout --detach refs/sandbox/pr-$n; or return
    else
        yadm worktree add --detach $wt refs/sandbox/pr-$n; or return
    end

    # ~/notes etc. resolve inside the fake HOME. cp -c = APFS clone: instant, no extra disk.
    mkdir -p $fake
    test -d $fake/notes; or cp -cR $real/notes $fake/notes

    # Shared package cache, seeded once from the live one. Elpaca's build dirs hold absolute
    # symlinks into sources/, so repoint those at the copy or they would reach the live config.
    set -l cache $real/.cache/emacs-sandbox
    set -l live $real/.config/emacs-modular/var/elpaca
    if not test -d $cache/elpaca
        mkdir -p $cache; or return
        cp -cR $live $cache/elpaca; or return
        for l in (find $cache/elpaca -type l)
            set -l t (readlink $l)
            string match -q "$live/*" -- $t; and ln -sfn (string replace $live $cache/elpaca $t) $l
        end
    end
    mkdir -p $cache/eln-cache $wt/.config/emacs-modular/var/cache
    # A var/ directory left by an earlier plain launch would swallow the link, so clear it first.
    for pair in "$cache/elpaca $wt/.config/emacs-modular/var/elpaca" "$cache/eln-cache $wt/.config/emacs-modular/var/cache/eln-cache"
        set -l p (string split ' ' -- $pair)
        test -L $p[2]; or rm -rf $p[2]
        ln -sfn $p[1] $p[2]
    end

    # init.el has absolute /Users/... paths in org-agenda-files; point them at the fake HOME.
    set -l remap "(when (boundp 'org-agenda-files) (setq org-agenda-files (mapcar (lambda (f) (string-replace \"$real/\" \"$fake/\" f)) org-agenda-files)))"

    env HOME=$fake GIT_CONFIG_GLOBAL=$real/.gitconfig \
        emacs --init-directory $wt/.config/emacs-modular --eval $remap &
    disown
end
