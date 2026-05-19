#!/usr/bin/env sh

# shellcheck source=../utils/utils.sh
. "${DOTFILES:?}/utils/utils.sh"

BLOCK_TAG="dotfiles:zsh"

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

# Render $HOME/.zshenv with a managed block that inlines the read-sequence doc
# from zshenv-doc plus the XDG/ZDOTDIR exports. Inlined (not sourced) so zsh
# startup avoids an extra file read; the tradeoff is that edits to defaults
# only take effect after re-running this installer.
install_zsh_zshenv() {
  local zshenv doc content
  (
    set -e
    zshenv="$HOME/.zshenv"
    doc=$(cat "${DOTFILES:?}/zsh/zshenv-doc")
    content=$(cat <<-EOF
		# Managed by zsh/install_zsh.sh — edits inside this block will be overwritten.
		export DOTFILES=${DOTFILES:?}
		${doc}

		# Define default XDG Base Directory Specification directories
		(( ! \${+XDG_CONFIG_HOME} )) && export XDG_CONFIG_HOME=\${HOME}/$XDG_CONFIG_DEFAULT_SUBPATH && mkdir -p \$XDG_CONFIG_HOME
		(( ! \${+XDG_CACHE_HOME} )) && export XDG_CACHE_HOME=\${HOME}/$XDG_CACHE_DEFAULT_SUBPATH && mkdir -p \$XDG_CACHE_HOME
		(( ! \${+XDG_DATA_HOME} )) && export XDG_DATA_HOME=\${HOME}/$XDG_DATA_DEFAULT_SUBPATH && mkdir -p \$XDG_DATA_HOME

		# Setup ZDOTDIR — where zsh reads .zshrc, .zlogin, etc.
		export ZDOTDIR=\${XDG_CONFIG_HOME}/$ZDOTDIR_SUBPATH
EOF
    )
    install_managed_block "$zshenv" "$BLOCK_TAG" "$content"

    echo "****************************"
    echo "$zshenv configured."
    echo "****************************"
  )
}

# Render $ZDOTDIR/.zshrc stub with a managed block sourcing the repo base .zshrc.
install_zsh_zshrc_stub() {
  local zdotdir zshrc content
  (
    set -e
    zdotdir=$(get_zdotdir)
    zshrc="$zdotdir/.zshrc"
    content=$(cat <<-'EOF'
		# Managed by zsh/install_zsh.sh — edits inside this block will be overwritten.
		source "$DOTFILES/zsh/zshrc-base"
EOF
    )

    mkdir -p "$zdotdir"
    mkdir -p "$(xdg_data_home)/$ZDOTDIR_SUBPATH"
    mkdir -p "$(xdg_cache_home)/$ZDOTDIR_SUBPATH"

    # Polite note about pre-existing $HOME/.zshrc (ZDOTDIR moved here)
    if [ -e "$HOME/.zshrc" ] && [ "$zdotdir" != "$HOME" ]; then
      echo "Note: \$HOME/.zshrc exists but ZDOTDIR is now $zdotdir."
      echo "      Consider moving its contents to $zshrc."
    fi

    install_managed_block "$zshrc" "$BLOCK_TAG" "$content"

    echo "****************************"
    echo "$zshrc configured."
    echo "****************************"
  )
}

# Render $HOME/.zshenv with the inlined env block (XDG defaults + ZDOTDIR),
# then render $ZDOTDIR/.zshrc stub with a marker block sourcing the repo base.
install_zsh_dotfiles() {
  install_zsh_zshenv && install_zsh_zshrc_stub
}

# Ensure chsh is available; install it from the PM if not.
# Warns and returns 0 on install failure (caller handles missing chsh).
ensure_chsh_available() {
  if command_exists chsh; then
    return 0
  fi
  install_from_pm chsh || {
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
  wizard_run "$@" -- install_zsh_program install_zsh_dotfiles set_zsh_as_default_shell
}

# Run installation if called with --wizard
wizard_main install_zsh_wizard "$@"
