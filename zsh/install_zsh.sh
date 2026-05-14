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

# Installs zsh and its dotfiles
# -y: accepts default answer for all questions
install_zsh_wizard() {
  if [ "$1" = -y ]; then
  # Sends "enter" continuously
  yes "
" | install_zsh_program && install_zsh_dotfiles
  else
    install_zsh_program && install_zsh_dotfiles
  fi
}

# Run installation if called with --wizard
if [ "$1" = --wizard ]; then
  install_zsh_wizard interactive
fi
