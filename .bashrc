# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# Env variables
export EDITOR='nvim'

# Created by `pipx` on 2025-10-29 16:42:48
export PATH="$PATH:/home/siainbuletin/.local/bin"

exec fish

. "$HOME/.local/bin/env"
