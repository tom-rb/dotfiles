#!/usr/bin/env sh

# shellcheck source=../utils/utils.sh
. "$DOTFILES/utils/utils.sh"

# Check if zsh is installed
is_zsh_installed() {
  command_exists zsh
}

# Installs zsh from the system package manager
install_zsh_program() {
  # Sub-shell for scoping set -e
  (
    set -e
    if is_zsh_installed; then
      echo "****************************"
      echo "zsh already installed."
      echo "****************************"
      return 0
    fi

    install_from_pm zsh
    echo "****************************"
    echo "zsh installed."
    echo "****************************"
  )
}

# Render $HOME/.zshenv stub that sources $DOTFILES/zsh/zshenv-base
install_zsh_dotfiles() {
  local zshenv contents
  # Sub-shell for scoping set -e
  (
    set -e
    zshenv="$HOME/.zshenv"

    contents=$(cat <<-EOF
		# Set DOTFILES so zshenv-base can locate the repo
		export DOTFILES=${DOTFILES:?}
		# Source base zsh env from dotfiles repo
		source "\$DOTFILES/zsh/zshenv-base"
		# Add machine custom config here
EOF
    )

    # Ask user what to do if .zshenv already exists
    if [ -e "$zshenv" ]; then
      echo "Found existing $zshenv file: (tail of it)"
      echo ">>>"
      tail "$zshenv"
      echo "<<<"
      if choose "Backup existing .zshenv" \
                "Append to existing .zshenv" \
                "Overwrite existing .zshenv"
      then # this is the cancel handling
        echo ".zshenv not configured!"
        return 1
      else # this is choice handling
        case "$?" in
          1) backup_file "$zshenv" &&
              printf "%s" "$contents" > "$zshenv" ;;
          2) printf "%s" "$contents" >> "$zshenv" ;;
          3) rm -v -f "$zshenv" &&
              printf "%s" "$contents" > "$zshenv" ;;
        esac
      fi
    else
      printf "%s" "$contents" > "$zshenv"
    fi

    echo "****************************"
    echo "$zshenv configured."
    echo "****************************"
  )
}

# Absolute path of the zsh binary
get_zsh_path() {
  command -v zsh
}

# Ensure chsh is available; install it from the PM if not.
# Warns and returns 0 on install failure (caller handles missing chsh).
ensure_chsh_available() {
  if command_exists chsh; then
    return 0
  fi
  case $(get_supported_pm) in
    apt-get) install_from_pm passwd;;
    yum)     install_from_pm util-linux-user;;
  esac || {
    echo "Couldn't install chsh from package manager."
    return 0
  }
}

# Current login shell for the running user, from /etc/passwd
get_current_default_shell() {
  getent passwd "$(id -un)" | cut -d: -f7
}

# Set zsh as the user's default login shell (via chsh).
# A failure here is non-fatal: prints a hint and still returns 0
set_zsh_as_default_shell() {
  local zsh_path current
  ensure_chsh_available
  zsh_path=$(get_zsh_path)
  current=$(get_current_default_shell)

  if [ "$current" = "$zsh_path" ]; then
    echo "zsh is already the default shell."
    return 0
  fi

  if ! confirm "Set zsh as your default shell?"; then
    return 0
  fi

  if ! sudo chsh -s "$zsh_path" "$(id -un)"; then
    echo "Couldn't change default shell. Run manually: chsh -s $zsh_path"
    return 0
  fi

  echo "****************************"
  echo "Default shell set to zsh."
  echo "****************************"
}

# Installs zsh and its dotfiles, then offers to set it as default shell
# -y: accepts default answer for all questions
install_zsh_wizard() {
  if [ "$1" = -y ]; then
  # Sends "enter" continuously
  yes "
" | { install_zsh_program && install_zsh_dotfiles && set_zsh_as_default_shell; }
  else
    install_zsh_program && install_zsh_dotfiles && set_zsh_as_default_shell
  fi
}

# Run installation if called with --wizard
if [ "$1" = --wizard ]; then
  install_zsh_wizard interactive
fi
