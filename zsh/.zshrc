#
# User configuration sourced by interactive shells
#

#######################
# Tmux initialization #
#######################

() {
  # Load tmux helpers (if present) and initialize session
  if [[ -f "$DOTFILES/tmux/tmux-cmds.sh" ]]; then
    source $DOTFILES/tmux/tmux-cmds.sh
    # If tmux exists and isn't running
    if [ -z "${TMUX}" ] && command -v tmux >/dev/null; then
      # Open tmux in vscode integrated terminal
      if [[ "$TERM_PROGRAM" = 'vscode' ]]; then
        tmux-enter vscode
      # Open tmux when initiating a new terminal window (check some emulators)
	  elif [[ -n WT_SESSION ]]; then # Windows Terminal defines this
	    tmux-enter
      elif pstree -s $$ | grep -Eq "(gnome-terminal|wslbridge2?-back)"; then
        tmux-enter
      fi
    fi
  fi
}

###################
# Dotfiles update #
###################

#echo "Updating configuration"
#(cd ~/dotfiles && git pull && git submodule update --init --recursive)

################
# Theme Colors #
################

# ANSI Escape for colors https://stackoverflow.com/a/33206814/4783169
# Define few colors, most of the theme is actually defined in tmux/theme.conf

if (( terminfo[colors] >= 256 )); then
  # Less pager uses 8-bit colors
  export LESS_TERMCAP_mb=$'\E[1;38;5;166m'  # Begins blinking (bold orange)
  export LESS_TERMCAP_md=$'\E[1;38;5;160m'  # Begins bold (bold red)
  export LESS_TERMCAP_us=$'\E[1;38;5;37m'   # Begins underline (bold cyan)
  # Grep uses 4-bit color (97 Bright White; 104 Bright Blue Background)
  export GREP_COLORS='mt=97;104'
fi

# Colors used by steef theme to configure git-info
export PWD_COLOR=64
export BRANCH_COLOR=37

# Use pretty colors for ls
eval $(dircolors $DOTFILES/zsh/dircolors.ansi-universal)


########################
# Module configuration #
########################

##
## input
##

# Append `../` to your input for each `.` you type after an initial `..`
zstyle ':zim:input' double-dot-expand yes

##
## termtitle
##

# Set a custom terminal title format using prompt expansion escape sequences.
# See http://zsh.sourceforge.net/Doc/Release/Prompt-Expansion.html#Simple-Prompt-Escapes
# If none is provided, the default '%n@%m: %~' is used.
#zstyle ':zim:termtitle' format '%1~'

##
## zsh-autosuggestions
##

# Customize the style that the suggestions are shown with.
# See https://github.com/zsh-users/zsh-autosuggestions/blob/master/README.md#suggestion-highlight-style
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=23'

# Prevent suggestion of some huge paste buffer
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=40

##
## zsh-syntax-highlighting
##

# Set what highlighters will be used.
# See https://github.com/zsh-users/zsh-syntax-highlighting/blob/master/docs/highlighters.md
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets)

# Customize the main highlighter styles.
# See https://github.com/zsh-users/zsh-syntax-highlighting/blob/master/docs/highlighters/main.md#how-to-tweak-it
#typeset -A ZSH_HIGHLIGHT_STYLES
#ZSH_HIGHLIGHT_STYLES[comment]='fg=10'

##
## ssh
##

# Load these ssh identities with the ssh module
zstyle ':zim:ssh' ids 'id_rsa' # 'id_rsa2' 'id_rsa3'

##
## Git
##

# Use lowercase g as git alias
zstyle ':zim:git' aliases-prefix 'g'


######################
# Initialize modules #
######################

# asdf version manager
[ -f "$XDG_CONFIG_HOME/asdf/asdf.sh" ] && source $XDG_CONFIG_HOME/asdf/asdf.sh && fpath=(${ASDF_DIR}/completions ${fpath})

# Repeat ZIM_HOME def (from .zshenv) because `exec zsh` complains
ZIM_HOME=${XDG_CONFIG_HOME}/zim

if [[ ${ZIM_HOME}/init.zsh -ot ${ZDOTDIR:-${HOME}}/.zimrc ]]; then
  # Update static initialization script if it's outdated, before sourcing it
  source ${ZIM_HOME}/zimfw.zsh init -q
fi
source ${ZIM_HOME}/init.zsh

# Load autocomplete again (it was having problems with asdf autocomplete)
autoload -Uz compinit && compinit -d "${ZDOTDIR:-${HOME}}/.zcompdump"

##################################
# Post-init module configuration #
##################################

##
## Zsh general
##

# Disable Ctrl-s to pause/freeze terminal (where Ctrl-q would unfreeze it)
stty -ixon

# Turn off all beeps
unsetopt BEEP

# Default editors
export VISUAL=vim
export EDITOR=vim

# Output of time command and /usr/bin/time
export TIMEFMT=$'\nreal\t%*E\nuser\t%*U\nsys\t%*S\ncpu\t%P'
export TIME=$'\nreal\t%E\nuser\t%U\nsys\t%S\ncpu\t%P'

# Remove path separator from WORDCHARS.
WORDCHARS=${WORDCHARS//[\/]}

# Set editor default keymap to emacs (`-e`) or vi (`-v`)
bindkey -e


##
## History
##

# The file to save the history in.
HISTFILE="${XDG_DATA_HOME}/zsh/zsh_history"

# The maximum number of events stored in the internal history list and in the history file.
HISTSIZE=10000
SAVEHIST=50000

# Ignore certain commands from history (use zshaddhistory zsh hook)
function _ignore_cmds_in_history() {
  emulate -L zsh
  # Ignore VSCode enviroment setup when calling zsh
  if [[ "$1" =~ "(env )?sh /tmp/Microsoft"* ]]; then
    return 1
  fi
}
if (( zshaddhistory_functions[(Ie)_ignore_cmds_in_history] == 0 )); then
  zshaddhistory_functions+=('_ignore_cmds_in_history')
fi

## Local history navigation

# History navigation use local history (search is still global)
# Thanks https://superuser.com/a/691603
up-line-or-local-history() {
    zle set-local-history 1
    zle .up-line-or-history
    zle set-local-history 0
}
zle -N up-line-or-local-history
down-line-or-local-history() {
    zle set-local-history 1
    zle .down-line-or-history
    zle set-local-history 0
}
zle -N down-line-or-local-history

# Bind regular up/down navigation to local history
zle -N up-line-or-history up-line-or-local-history
zle -N down-line-or-history down-line-or-local-history

# Navigate in global history with Ctrl+arrows
bindkey "^[[1;5A" .up-line-or-history    # [CTRL] + Cursor up
bindkey "^[[1;5B" .down-line-or-history  # [CTRL] + Cursor down

##
## zsh-history-substring-search module
##

# Bind ^[[A/^[[B manually so up/down works both before and after zle-line-init
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down

# Bind up and down keys
zmodload -F zsh/terminfo +p:terminfo
if [[ -n ${terminfo[kcuu1]} && -n ${terminfo[kcud1]} ]]; then
 bindkey ${terminfo[kcuu1]} history-substring-search-up
 bindkey ${terminfo[kcud1]} history-substring-search-down
fi

bindkey '^P' history-substring-search-up
bindkey '^N' history-substring-search-down
# bindkey -M vicmd 'k' history-substring-search-up
# bindkey -M vicmd 'j' history-substring-search-down


##
## Completion
##

zstyle ':completion::commands' ignored-patterns '/mnt/c/*'

# Prompt for spelling correction of commands.
#setopt CORRECT

# Customize spelling correction prompt.
#SPROMPT='zsh: correct %F{red}%R%f to %F{green}%r%f [nyae]? '


##
## Utility module
##

# Append -F (*/=>@| annotations) to regular ls (or already aliased one)
if (( ${+aliases[ls]} )); then
  alias ls="${aliases[ls]} -F"
else
  alias ls='ls -F'
fi

# List directories stack and easy navigate to them
alias d='dirs -v | head -10'
alias d0='cd -'
alias d1='cd +1'
alias d2='cd +2'
alias d3='cd +3'
alias d4='cd +4'
alias d5='cd +5'
alias d6='cd +6'
alias d7='cd +7'
alias d8='cd +8'
alias d9='cd +9'

# Execute ls after cd (use chpwd zsh hook)
function _list_if_not_sub_shell() {
  ((! $ZSH_SUBSHELL)) && ls
}
if (( chpwd_functions[(Ie)_list_if_not_sub_shell] == 0 )); then
  chpwd_functions+=('_list_if_not_sub_shell')
fi

# Remove some folders from grep by default
if (( ${+aliases[grep]} )); then
  alias grep="${aliases[grep]} --exclude-dir=.git"
else
  alias grep='grep --exclude-dir=.git'
fi

##
## Keybindings
##

# Alt+k go up a folder
function cd-up() {
  cd .. >/dev/null
  zle reset-prompt
  zle -R
}
zle -N cd-up
bindkey "^[k" cd-up

# Ctrl+o accept and execute suggestion
bindkey "^o" autosuggest-execute

# Alt+o accept suggestion without moving the cursor
function autosuggest-accept-inplace() {
  local cursor_pos=$CURSOR
  zle autosuggest-accept
  CURSOR=cursor_pos
}
zle -N autosuggest-accept-inplace
bindkey "^[o" autosuggest-accept-inplace

# Alt+Enter to insert linebreaks in multiline command
bindkey '^[^M' self-insert-unmeta

# Ctrl+g for launching executables with nohup
function exec-nohup() {
  BUFFER="nohup $BUFFER &>/dev/null"
  zle accept-line
}
zle -N exec-nohup
bindkey "^g" exec-nohup

# The buffer stack (http://zsh.sourceforge.net/Guide/zshguide04.html#l102)
#  $ if [[ no = yes ]]; then
#  then> print<ESC>q<ESC>q
# The first \eq turns the two lines into a single buffer, then the second
# pushes the whole lot onto the buffer stack.
bindkey '\eq' push-line-or-edit


##
## Git module
##

() {
  local gprefix
  zstyle -s ':zim:git' aliases-prefix 'gprefix' || gprefix=g

  # Git Index Add All
  alias ${gprefix}iaa='git add -A'
  # Git Branch Create
  alias ${gprefix}bc="git checkout -b"
  # Git Branch All
  alias ${gprefix}ba="git branch -a"
  # Git Commit with Message
  alias ${gprefix}cm='git commit --verbose -m'
  # Git Commit ammend (or "force")
  alias ${gprefix}cf='git commit --verbose --amend'
  # Git Commit ammend (or "force") reusing message
  alias ${gprefix}cF='git commit --amend --reuse-message HEAD'
  # Git Fetch All
  alias ${gprefix}fa='git fetch --all --prune'
  # Git Merge Master
  alias ${gprefix}mm='git merge master'
  # Git Merge Origin/Master
  alias ${gprefix}mom='git merge origin/master'
  # Git Merge Upstream/Master
  alias ${gprefix}mum='git merge upstream/master'
  # Git Rebase Master
  alias ${gprefix}rm='git rebase master'
  # Git Rebase Origin/Master
  alias ${gprefix}rom='git rebase origin/master'
  # Git Rebase Upstream/Master
  alias ${gprefix}rum='git rebase upstream/master'
  # Git Rebase with autosquash
  alias ${gprefix}ri='git rebase --interactive --autosquash'
  # Git log graph (https://stackoverflow.com/a/9074343/4783169)
  alias ${gprefix}la="git log --graph --abbrev-commit --decorate --format=format:'%C(bold blue)%h%C(reset) %C(white)%s%C(reset) %C(auto)%d%C(reset)%n''          %C(dim white) %an%C(reset) - %C(bold cyan)%aD%C(reset) %C(bold green)%ar%C(reset)'"
  alias ${gprefix}lg='gla -6'
  # Git local branches (no remote tracking yet)
  alias ${gprefix}local="git branch -vv | cut -c 3- | awk '"'$3 !~ /\[origin/ { print $1 }'"'"
  # Git gone branches (gone remote tracking)
  alias ${gprefix}gone="git fetch --all --prune -q && git branch -vv | cut -c 3- | awk '"'/\[origin.*: gone\]/ { print $1 }'"'"
}


##
## Prompt
##

# Customizing the steeef theme
function _set_prompt() {
  # There's a non-breaking space at the end of the main line to ease prompt search in tmux
  PS1='%F{red}%(?..✘ %?)%f
%F{${PWD_COLOR}}%60<«<%~%<<%f${(e)git_info[prompt]}${VIRTUAL_ENV:+" (%F{blue}${VIRTUAL_ENV:t}%f)"} 
'
  # Check if sudo is active
  if sudo -n true >&/dev/null; then
    PS1+='%U%(!.#.$)%u '
  else
    PS1+='%(!.#.$) '
  fi
}
if (( precmd_functions[(Ie)_set_prompt] == 0 )); then
  precmd_functions+=('_set_prompt')
fi

# Right prompt format string is fixed, so no need for a function
RPS1='%F{243}%*$f'


##
## Other aliases
##

# A $PATH without Windows directories is expected, so extract current user name to
# create an alias for launching VS Code
() {
  if command -v /mnt/c/Windows/System32/cmd.exe >/dev/null; then
    local win_user=$(/mnt/c/Windows/System32/cmd.exe /D /C echo %username% 2>/dev/null | tr -d '\r')
    alias code="/mnt/c/Users/${win_user}/AppData/Local/Programs/Microsoft\\ VS\\ Code/bin/code"
  fi
}

# Run a script whenever it changes (e.g. for watch unit tests) with time stats
watch-test() {
  local script="$1"
  [ ! -x "$script" ] && echo "Must provide an executable file."
  # Executes the script a first time
  time $script
  # Internal watch executes script whenever modified time of sibling files has changed
  watch -t -n0.2 "watch -t -n0.2 -g ls -l --full-time ${script%/*} > /dev/null && time $script"
}

# Kubernetes
alias kube=kubectl
#if [ $commands[kubectl] ]; then source <(kubectl completion zsh); fi

# Scala
# Fix [ERROR] Failed to construct terminal; falling back to unsupported https://stackoverflow.com/a/44361749
alias sbt='TERM=xterm sbt'

# Databricks CLI
alias databricks='python ~/.local/lib/python3.6/site-packages/databricks_cli/cli.py'

# Set JAVA_HOME if asdf plugin is available
[ -f "$XDG_DATA_HOME/asdf/plugins/java/set-java-home.zsh" ] && source $XDG_DATA_HOME/asdf/plugins/java/set-java-home.zsh

# Create /etc/resolv.conf for WSL using DNS info from Windows
fixdns() {
  local ps='/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'
  if command -v $ps >/dev/null; then
    $ps "Get-DnsClientGlobalSetting | Select-Object -ExpandProperty SuffixSearchList" | tr -d '\r' | tr '\n' ' ' | sed "s/^/search /" | sed "s/ $/\n/" | sudo tee /etc/resolv.conf
    $ps "Get-DnsClientServerAddress -AddressFamily ipv4 | Select-Object -ExpandProperty ServerAddresses" | sed 's/^/nameserver /' | tr -d '\r' | sudo tee -a /etc/resolv.conf
  fi
}
