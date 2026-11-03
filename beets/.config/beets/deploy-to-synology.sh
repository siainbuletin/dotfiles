#!/usr/bin/env bash
# deploy-to-synology.sh: tangle beets.org and copy the beets configuration
# for the Synology container to the NAS with scp.
#
# Documented in beets.org, section "Copying the configuration to the Synology".
#
# Usage: deploy-to-synology.sh [-H host] [-u user] [-p port] [-d dest] [-f] [-n] [-h]
#
# Settings, by precedence: options, then environment variables, then defaults.
#   -H  SYNOLOGY_HOST        NAS host name or address  (default 192.168.88.10)
#   -u  SYNOLOGY_USER        DSM user to copy as       (default: $USER)
#   -p  SYNOLOGY_PORT        SSH port                  (default 22)
#   -d  SYNOLOGY_DEST        folder mounted as /config (default /volume1/docker/beets)
#   -f                       tangle even if the files are up to date
#   -n                       dry run: print the commands, run nothing
#       SYNOLOGY_SCP_LEGACY  1 (default) passes -O to scp (old SCP protocol, no SFTP needed)
#       EMACS                Emacs binary used to tangle (default emacs)

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
org_file="$script_dir/beets.org"
out_dir="$script_dir/synology"
tangled=(config.yaml compose.yaml)

host=${SYNOLOGY_HOST:-192.168.88.10}
user=${SYNOLOGY_USER:-${USER:-$(id -un)}}
port=${SYNOLOGY_PORT:-22}
dest=${SYNOLOGY_DEST:-/volume1/docker/beets}
legacy=${SYNOLOGY_SCP_LEGACY:-1}
emacs_bin=${EMACS:-emacs}
force=0
dry_run=0

die() { printf 'deploy-to-synology: error: %s\n' "$*" >&2; exit 1; }
info() { printf 'deploy-to-synology: %s\n' "$*"; }
usage() { sed -n '2,/^$/{s/^# \{0,1\}//;p}' "${BASH_SOURCE[0]}"; }

run() {
    if (( dry_run )); then
        printf '+'; printf ' %q' "$@"; printf '\n'
    else
        "$@"
    fi
}

while getopts ':H:u:p:d:fnh' opt; do
    case $opt in
        H) host=$OPTARG ;;
        u) user=$OPTARG ;;
        p) port=$OPTARG ;;
        d) dest=$OPTARG ;;
        f) force=1 ;;
        n) dry_run=1 ;;
        h) usage; exit 0 ;;
        :) die "option -$OPTARG needs a value (see -h)" ;;
        *) die "unknown option -$OPTARG (see -h)" ;;
    esac
done
shift $((OPTIND - 1))
(( $# == 0 )) || die "unexpected argument: $1 (see -h)"

[[ -f $org_file ]] || die "cannot find $org_file"
[[ $port =~ ^[0-9]+$ ]] || die "port must be a number, got '$port'"
[[ $dest == /* ]] || die "destination must be an absolute path on the NAS, got '$dest'"
command -v scp >/dev/null || die "scp is not installed"
command -v ssh >/dev/null || die "ssh is not installed"

# 1. Tangle when a tangled file is missing or older than beets.org.
needs_tangle=$force
for f in "${tangled[@]}"; do
    [[ -f $out_dir/$f && ! $org_file -nt $out_dir/$f ]] || needs_tangle=1
done

if (( needs_tangle )); then
    command -v "$emacs_bin" >/dev/null \
        || die "the files in $out_dir need tangling but '$emacs_bin' is not on PATH (set EMACS, or tangle with C-c C-v t)"
    info "tangling $org_file"
    # -Q: no init file, so the user's configuration cannot change the result.
    run "$emacs_bin" -Q --batch -l org \
        --eval "(setq org-confirm-babel-evaluate nil)" \
        --eval "(org-babel-tangle-file \"$org_file\")" \
        || die "tangling $org_file failed"
    if (( ! dry_run )); then
        for f in "${tangled[@]}"; do
            [[ -s $out_dir/$f ]] || die "tangling did not produce $out_dir/$f"
            touch "$out_dir/$f"  # Org leaves unchanged files alone; mark them current.
        done
    fi
else
    info "tangled files are up to date"
fi

# 2. Copy.
remote="$user@$host"
ssh_opts=(-p "$port")
scp_opts=(-P "$port")
(( legacy )) && scp_opts+=(-O)

files=("${tangled[@]/#/$out_dir/}")
if [[ -f $out_dir/secrets.yaml ]]; then
    files+=("$out_dir/secrets.yaml")
    have_secrets=1
else
    have_secrets=0
fi

info "copying to $remote:$dest/"
run ssh "${ssh_opts[@]}" "$remote" "mkdir -p '$dest'" \
    || die "could not reach $remote over SSH (is SSH on in DSM: Control Panel > Terminal & SNMP?)"

if (( ! have_secrets )); then
    # config.yaml includes secrets.yaml; beets complains on every command if it is missing.
    info "no local secrets.yaml; making sure an (empty) one exists on the NAS"
    run ssh "${ssh_opts[@]}" "$remote" "[ -e '$dest/secrets.yaml' ] || : > '$dest/secrets.yaml'" \
        || die "could not create $dest/secrets.yaml on the NAS"
fi

run scp "${scp_opts[@]}" "${files[@]}" "$remote:$dest/" \
    || die "scp to $remote:$dest/ failed (check that $user may write there; set SYNOLOGY_SCP_LEGACY=0 if your scp has no -O)"

info "done; restart the beets project in Container Manager to load the new configuration"
