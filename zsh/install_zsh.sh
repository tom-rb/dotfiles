#!/usr/bin/env sh

# shellcheck source=../utils/utils.sh
. "${DOTFILES:?}/utils/utils.sh"

# Check if zsh is installed
is_zsh_installed() {
  command_exists zsh
}

# Absolute path of the zsh binary
get_zsh_path() {
  command -v zsh
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

# Render $HOME/.zshenv with a marker block sourcing zshenv-base.
# Idempotent: replaces the block in place if already present; preserves any
# user content outside the markers. Other installers (e.g. install_zimfw)
# append their own marker blocks to the same file.
install_zsh_zshenv() {
  local zshenv block start end
  (
    set -e
    zshenv="$HOME/.zshenv"
    start='# >>> dotfiles:zsh >>>'
    end='# <<< dotfiles:zsh <<<'

    block=$(cat <<-EOF
		$start
		# Managed by zsh/install_zsh.sh — edits inside this block will be overwritten.
		export DOTFILES=${DOTFILES:?}
		source "\$DOTFILES/zsh/zshenv-base"
		$end
EOF
    )

    if [ -e "$zshenv" ] && grep -qF "$start" "$zshenv"; then
      # Replace existing block in place
      awk -v s="$start" -v e="$end" -v b="$block" '
        $0==s {print b; skip=1; next}
        skip && $0==e {skip=0; next}
        !skip
      ' "$zshenv" > "$zshenv.tmp" && mv "$zshenv.tmp" "$zshenv"
    else
      # Append block (creates file if absent)
      [ -e "$zshenv" ] && printf '\n' >> "$zshenv"
      printf '%s\n' "$block" >> "$zshenv"
    fi

    echo "****************************"
    echo "$zshenv configured."
    echo "****************************"
  )
}

# Resolve $ZDOTDIR (matches zshenv-base default; honors caller override)
get_zdotdir() {
  echo "${ZDOTDIR:-${XDG_CONFIG_HOME:-$HOME/.config}/zsh}"
}

# Render $ZDOTDIR/.zshrc stub with a marker block sourcing the repo base .zshrc.
# The marker block is idempotent: re-running replaces it in place, preserving
# user content outside the markers. Other installers (e.g. install_zimfw)
# append their own marker blocks to the same file.
install_zsh_zshrc_stub() {
  local zdotdir zshrc block start end
  (
    set -e
    zdotdir=$(get_zdotdir)
    zshrc="$zdotdir/.zshrc"
    start='# >>> dotfiles:zsh >>>'
    end='# <<< dotfiles:zsh <<<'

    block=$(cat <<-EOF
		$start
		# Managed by zsh/install_zsh.sh — edits inside this block will be overwritten.
		source "\$DOTFILES/zsh/zshrc-base"
		$end
EOF
    )

    mkdir -p "$zdotdir"
    mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/zsh"

    # Polite note about pre-existing $HOME/.zshrc (ZDOTDIR moved here)
    if [ -e "$HOME/.zshrc" ] && [ "$zdotdir" != "$HOME" ]; then
      echo "Note: \$HOME/.zshrc exists but ZDOTDIR is now $zdotdir."
      echo "      Consider moving its contents to $zshrc."
    fi

    if [ -e "$zshrc" ] && grep -qF "$start" "$zshrc"; then
      # Replace existing block in place
      awk -v s="$start" -v e="$end" -v b="$block" '
        $0==s {print b; skip=1; next}
        skip && $0==e {skip=0; next}
        !skip
      ' "$zshrc" > "$zshrc.tmp" && mv "$zshrc.tmp" "$zshrc"
    else
      # Append block (creates file if absent)
      [ -e "$zshrc" ] && printf '\n' >> "$zshrc"
      printf '%s\n' "$block" >> "$zshrc"
    fi

    echo "****************************"
    echo "$zshrc configured."
    echo "****************************"
  )
}

# Render $HOME/.zshenv stub that sources $DOTFILES/zsh/zshenv-base, then
# render $ZDOTDIR/.zshrc stub with a marker block sourcing the repo base.
install_zsh_dotfiles() {
  install_zsh_zshenv && install_zsh_zshrc_stub
}

# Ensure chsh is available; install it from the PM if not.
# Warns and returns 0 on install failure (caller handles missing chsh).
ensure_chsh_available() {
  if command_exists chsh; then
    return 0
  fi
  # shellcheck disable=SC2046  # intentional word-splitting of resolved names
  install_from_pm $(pm_packages_for chsh) || {
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
