# ~/.config/fish/functions/fisher-bootstrap.fish
# Install fisher (the fish plugin manager) and restore the plugins in fish_plugins.
# Run it by hand on a new machine; nothing calls it at shell startup (no curl on every shell).
# Usage: fisher-bootstrap          install fisher if missing, then run `fisher update`
#        fisher-bootstrap v7.4.0   use that tag or branch of jorgebucaran/fisher instead of main
# Docs: "Fish plugins with fisher" in ~/dotfiles/README.org.
function fisher-bootstrap --description "Install fisher and restore the plugins in fish_plugins"
    set -l ref main
    if set -q argv[1]
        set ref $argv[1]
    end

    if functions -q fisher
        echo "fisher-bootstrap: fisher is already installed, running fisher update"
        fisher update
        return $status
    end

    if not type -q curl
        echo "fisher-bootstrap: curl is required" >&2
        return 1
    end

    set -l url https://raw.githubusercontent.com/jorgebucaran/fisher/$ref/functions/fisher.fish
    set -l tmp (mktemp)
    or return 1

    # Download to a file first: a failed download must not be sourced half-way.
    if not curl -fsSL $url -o $tmp
        echo "fisher-bootstrap: could not download $url" >&2
        command rm -f $tmp
        return 1
    end
    source $tmp
    command rm -f $tmp

    # With a fish_plugins file (Stow links it from ~/dotfiles) this installs everything in it,
    # including fisher itself. Without one, install fisher and let it create the file.
    if test -s $__fish_config_dir/fish_plugins
        fisher update
    else
        fisher install jorgebucaran/fisher
    end
end
