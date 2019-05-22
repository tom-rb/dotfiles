#
# User configuration sourced by interactive shells
#

# Define ZIM (Zsh IMproved framework) repository location
export ZIM_HOME=${XDG_CONFIG_HOME}/zim

# Open tmux when initiating a new terminal window
if [ -z "${TMUX}" ] && command -v tmux >/dev/null; then
  if pstree -s $$ | grep -Eq "(gnome-terminal|wslbridge-back)"; then
    # Create a session named main if not yet created
    tmux has-session -t main  >&/dev/null || tmux new-session -d -s main
    # Create a "client" grouped session
    if tmux list-session | grep -q "^main-"; then
      # Create a new window if this is not the first client session
      tmux new-session -d -t main \; new-window
    else
      tmux new-session -d -t main \;
    fi
    # Client session will destroy itself upon detach
    tmux set-option destroy-unattached \; attach-session
  fi
fi


#echo "Updating configuration"
#(cd ~/dotfiles && git pull && git submodule update --init --recursive)

# Start ZIM
[[ -s ${ZIM_HOME}/init.zsh ]] && source ${ZIM_HOME}/init.zsh
