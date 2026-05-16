#!/usr/bin/env sh

# shellcheck source=../utils/utils.sh
. "${DOTFILES:?}/utils/utils.sh"

# Pinned zimfw release. Bump deliberately, never to a moving branch.
ZIMFW_URL='https://github.com/zimfw/zimfw/releases/download/v1.19.1/zimfw.zsh'

# Resolve $ZIM_HOME (matches zimfw/zshrc-zim default)
get_zim_home() {
  echo "${ZIM_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/zim}"
}

# Resolve $ZDOTDIR (matches zshenv-base default)
get_zdotdir() {
  echo "${ZDOTDIR:-${XDG_CONFIG_HOME:-$HOME/.config}/zsh}"
}

# True if zimfw.zsh is present in $ZIM_HOME
is_zimfw_installed() {
  test -s "$(get_zim_home)/zimfw.zsh"
}

# Hard preconditions: install_zsh must have run already.
check_zsh_prerequisites() {
  local zdotdir
  zdotdir=$(get_zdotdir)
  command_exists zsh         || die "zsh not installed. Run zsh/install_zsh.sh --wizard first."
  [ -f "$HOME/.zshenv" ]     || die "$HOME/.zshenv missing. Run zsh/install_zsh.sh --wizard first."
  [ -f "$zdotdir/.zshrc" ]   || die "$zdotdir/.zshrc missing. Run zsh/install_zsh.sh --wizard first."
}

# Download zimfw.zsh into $ZIM_HOME via wget
download_zimfw() {
  local zim_home
  zim_home=$(get_zim_home)
  mkdir -p "$zim_home"
  wget -nv -O "$zim_home/zimfw.zsh" "$ZIMFW_URL"
}

# Download zimfw.zsh if not already present
install_zimfw_program() {
  (
    set -e
    if is_zimfw_installed; then
      echo "****************************"
      echo "zimfw already installed."
      echo "****************************"
      return 0
    fi
    download_zimfw
    echo "****************************"
    echo "zimfw installed."
    echo "****************************"
  )
}

# Append marker block to $HOME/.zshenv setting specific configs.
install_zimfw_zshenv_block() {
  local zshenv block start end
  (
    set -e
    zshenv="$HOME/.zshenv"
    start='# >>> dotfiles:zimfw >>>'
    end='# <<< dotfiles:zimfw <<<'

    block=$(cat <<-EOF
		$start
		# Managed by zimfw/install_zimfw.sh — edits inside this block will be overwritten.
		# Disable global compinit call in Ubuntu (since zimfw will call it)
		skip_global_compinit=1
		$end
EOF
    )

    if [ -e "$zshenv" ] && grep -qF "$start" "$zshenv"; then
      awk -v s="$start" -v e="$end" -v b="$block" '
        $0==s {print b; skip=1; next}
        skip && $0==e {skip=0; next}
        !skip
      ' "$zshenv" > "$zshenv.tmp" && mv "$zshenv.tmp" "$zshenv"
    else
      [ -e "$zshenv" ] && printf '\n' >> "$zshenv"
      printf '%s\n' "$block" >> "$zshenv"
    fi

    echo "$zshenv updated with zimfw block."
  )
}

# Append marker block to $ZDOTDIR/.zshrc sourcing zimfw/zshrc-zim.
# Idempotent: replaces the block in place if already present.
install_zimfw_zshrc_block() {
  local zdotdir zshrc block start end
  (
    set -e
    zdotdir=$(get_zdotdir)
    zshrc="$zdotdir/.zshrc"
    start='# >>> dotfiles:zimfw >>>'
    end='# <<< dotfiles:zimfw <<<'

    block=$(cat <<-EOF
		$start
		# Managed by zimfw/install_zimfw.sh — edits inside this block will be overwritten.
		source "\$DOTFILES/zimfw/zshrc-zim"
		$end
EOF
    )

    if [ -e "$zshrc" ] && grep -qF "$start" "$zshrc"; then
      awk -v s="$start" -v e="$end" -v b="$block" '
        $0==s {print b; skip=1; next}
        skip && $0==e {skip=0; next}
        !skip
      ' "$zshrc" > "$zshrc.tmp" && mv "$zshrc.tmp" "$zshrc"
    else
      [ -e "$zshrc" ] && printf '\n' >> "$zshrc"
      printf '%s\n' "$block" >> "$zshrc"
    fi

    echo "$zshrc updated with zimfw block."
  )
}

# Write $ZDOTDIR/<name> as a one-line stub sourcing the repo file.
# $1: target basename (e.g. .zimrc), $2: repo source path
# Asks user (backup/append/overwrite) if target exists.
install_zimfw_zdotdir_stub() {
  local zdotdir target src contents
  (
    set -e
    zdotdir=$(get_zdotdir)
    target="$zdotdir/${1:?}"
    src="${2:?}"

    contents=$(printf 'source "%s"' "$src")

    if [ -e "$target" ]; then
      echo "Found existing $target file: (tail of it)"
      echo ">>>"
      tail "$target"
      echo "<<<"
      if choose "Backup existing ${1}" \
                "Append to existing ${1}" \
                "Overwrite existing ${1}"
      then
        echo "$target not configured!"
        return 1
      else
        case "$?" in
          1) backup_file "$target" &&
              printf '%s\n' "$contents" > "$target" ;;
          2) printf '%s\n' "$contents" >> "$target" ;;
          3) rm -v -f "$target" &&
              printf '%s\n' "$contents" > "$target" ;;
        esac
      fi
    else
      printf '%s\n' "$contents" > "$target"
    fi

    echo "$target configured."
  )
}

# Render all zimfw-owned dotfiles ($HOME/.zshenv block + $ZDOTDIR files)
install_zimfw_dotfiles() {
  (
    set -e
    install_zimfw_zshenv_block
    install_zimfw_zshrc_block
    # shellcheck disable=SC2016
    install_zimfw_zdotdir_stub .zimrc  '$DOTFILES/zimfw/zimrc-base'
  )
}

# Run `zimfw install` to populate modules listed in .zimrc
install_zimfw_modules() {
  local zim_home
  zim_home=$(get_zim_home)
  ZIM_HOME="$zim_home" zsh "$zim_home/zimfw.zsh" install
}

# Coordinates the install: preconditions, framework, dotfiles, modules.
# -y: accepts default answer for all questions
install_zimfw_wizard() {
  check_zsh_prerequisites || return $?
  if [ "$1" = -y ]; then
    yes "
" | { install_zimfw_program && install_zimfw_dotfiles && install_zimfw_modules; }
  else
    install_zimfw_program && install_zimfw_dotfiles && install_zimfw_modules
  fi
}

# Run installation if called with --wizard
if [ "$1" = --wizard ]; then
  install_zimfw_wizard interactive
fi
