tmux-prepare-env () {
  local session_name=${1}
  # Find different variables between the current env and tmux global
  # (excluding some known/irrelevant differences) and:
  #  1. Declare them in the tmux session "env space"
  #  2. Include them to be updated when attaching
  # (xargs trick https://stackoverflow.com/a/6958957/4783169)
  (tmux show-env -g ; tmux show-env -g ; printenv) \
    | grep -vE '_=|SHLVL|(OLD)?PWD|LESS_TERMCAP|WSL_INTEROP' \
    | sort | uniq -u | cut -d'=' -f1 \
    | xargs -d $'\n' sh -c "for arg do \
        tmux set-env -t \"${session_name}\" \"\$arg\" '' ;\
        tmux set-opt -a update-environment \"\$arg\" ;\
        done" _
}


# Enter a shared main session creating a new client (groupped) session.
# Useful for having several GUI windows sharing the "same" TMUX session.
# arg 1: group session name (default: client)
tmux-enter () {
  local group_name=${1:-client}
  # Create the main shared session if not yet created (assign client group to it)
  local main_name="main-${group_name}"
  tmux has-session -t "=${main_name}" >&/dev/null || tmux new-session -d -s "${main_name}" -t "${group_name}"
  # Count how many client sessions already exist (or none)
  local client_count=$(tmux list-sessions | grep -oP "(?<=^${group_name}-)[0-9]+" | sort -nr | head -n1)
  # Create a client grouped session
  local client_name="${group_name}-$((client_count + 1))"
  tmux new-session -d -s "${client_name}" -t "${group_name}"
  # Create a new window if this is not the first client
  (( client_count > 0 )) && tmux new-window
  # Automatically pass enviroment variables forward
  tmux-prepare-env "${client_name}"
  # TODO: command above only updates tmux session env; zsh should read and apply those e.g.
  #       for var in $(tmux show-environment | grep -v "^-"); do eval "export $var"; done;
  # ALSO: use a parameter in tmux-enter to invoke this env passing or not
  # read -rn 1
  # Client session will destroy itself upon detach
  tmux set-option destroy-unattached \; attach-session
}