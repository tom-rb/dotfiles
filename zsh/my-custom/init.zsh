############################
#### MODULES OVERWRITES ####
############################

##
## Directory
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
function _list_if_shell() {
  ((! $ZSH_SUBSHELL)) && ls
}
chpwd_functions+=("_list_if_shell")

# Alt+k go up a folder
function cd-up() {
  cd .. >/dev/null
  zle reset-prompt
  zle -R
}
zle -N cd-up
bindkey "^[k" cd-up

##
## Keybindings
##

# Ctrl+o accept and execute suggestion
bindkey "^o" autosuggest-execute

# Alt+Enter to insert linebreaks in multiline command
bindkey '^[^M' self-insert-unmeta

# Ctrl+g for lauching executables with nohup
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
## Utility
##

# Remove some folders from grep by default
if (( ${+aliases[grep]} )); then
  alias grep="${aliases[grep]} --exclude-dir={.git}"
else
  alias grep='grep --exclude-dir={.git}'
fi


##
## Git
##

() {
  local gprefix
  zstyle -s ':zim:git' aliases-prefix 'gprefix' || gprefix=g
  
  # Git STatus
  alias ${gprefix}st='git status'
  # Git Index Add All
  alias ${gprefix}iaa='git add -A'
  # Git Branch Create
  alias ${gprefix}bc="git checkout -b"
  # Git Checkout Master
  alias ${gprefix}cm='git checkout master'
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
## History
##

# The file to save the history in.
HISTFILE="${XDG_DATA_HOME}/zsh/zsh_history"

# The maximum number of events stored in the internal history list and in the history file.
HISTSIZE=10000
SAVEHIST=50000

# History navigation use local history (search is still global)
# Thanks https://superuser.com/a/691603
zle -N up-line-or-history up-line-or-local-history
zle -N down-line-or-history down-line-or-local-history

# Navigate in global history with Ctrl+arrows
bindkey "^[[1;5A" .up-line-or-history    # [CTRL] + Cursor up
bindkey "^[[1;5B" .down-line-or-history  # [CTRL] + Cursor down

# Ignore certain commands from history (use zshaddhistory zsh hook)
function _ignore_cmds_in_history() {
	emulate -L zsh
	# Ignore VSCode enviroment setup when calling zsh
	if [[ "$1" =~ "(env )?sh /tmp/Microsoft"* ]] ; then
		return 1
	fi
}
zshaddhistory_functions+=("_ignore_cmds_in_history")

##
## Zsh-Autosuggestions
##

# ZSH autosuggestions color
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=23'

# Prevent suggestion of some huge paste buffer
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=40


##
## Prompt themes
##

function _set_prompt() {
  # There's a non-breaking space at the end of the main line to ease prompt search in tmux
  PS1='%F{red}%(?..✘ %?)%f
%F{118}%60<«<%~%<<%f$(prompt_steeef_git)$(prompt_steeef_virtualenv) 
'
  # Check if sudo is active
  if sudo -n true >&/dev/null; then
    PS1+='%U%(!.#.$)%u '
  else
    PS1+='%(!.#.$) '
  fi
}

if [[ ${zprompt_theme} == 'steeef' ]]; then
  precmd_functions+=("_set_prompt")

  # Right prompt format string is fixed, so no need for a function
  RPS1='%F{243}%*$f'
fi

###########################
#### MY-CUSTOM MODULES ####
###########################

# Source all *.zsh in my-custom folder
() {
  local zsh_file
  setopt localoptions extendedglob
  
  # For all *.zsh plain files (.), whithout complaining if none found by
  # activating NULL_GLOB (N), excluding ./init.zsh, source the file.
  for zsh_file in ${DOTFILES}/zsh/my-custom/*.zsh~*/init.zsh(.N); source ${zsh_file}
}
