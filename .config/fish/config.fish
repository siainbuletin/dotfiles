source ~/.bash_aliases

################
## ON STARTUP ##
################

## Run fastfetch as welcome message
function fish_greeting
    fastfetch
end

if status is-interactive
    # Commands to run in interactive sessions can go here
end

##############
### STYLING ##
##############

# Format man pages
set -x MANROFFOPT "-c"
set -x MANPAGER "sh -c 'col -bx | bat -l man -p'"

#######################
## ENVIRONMENT SETUP ##
#######################

# Apply .profile: use this to put fish compatible .profile stuff in
if test -f ~/.fish_profile
  source ~/.fish_profile
end

# Fish command history
function history
    builtin history --show-time='%F %T '
end

function backup --argument filename
    cp $filename $filename.bak
end

#################
## KEYBINDINGS ##
#################

# removes the mapping <C-t> which is being used to close the terminal in NeoVim
bind --erase \ct

if type -q zoxide
    zoxide init fish --cmd cd | source # removes the mapping <C-t> which is being used to close the terminal in NeoVim
end



####################
## EXIT FUNCTIONS ##
####################

function on_exit --on-event fish_exit
	echo fish is now exiting
end
