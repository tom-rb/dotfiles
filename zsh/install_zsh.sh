#!/usr/bin/env sh

# shellcheck source=../utils/utils.sh
. "${DOTFILES:?}/utils/utils.sh"

ZSH_BLOCK_TAG="dotfiles:zsh"
ZSH_BLOCK_TAG_BASE="dotfiles:zsh:base"
ZSH_BLOCK_TAG_OVERRIDES="dotfiles:zsh:overrides"

# Check if zsh is installed
is_zsh_installed() {
  command_exists zsh
}

# Absolute path of the zsh binary
get_zsh_path() {
  command -v zsh
}

# Version of the zsh on PATH (`zsh 5.9 (x86_64-ubuntu-linux-gnu)` -> 5.9).
get_zsh_version() {
  zsh --version | cut -d' ' -f2
}

# The ✓ wording for the package-manager install.
_zsh_installed_msg() {
  echo "zsh $(get_zsh_version) installed"
}

# Installs zsh from the system package manager
install_zsh_program() {
  (
    set -e
    if is_zsh_installed; then
      tui_skip "zsh $(get_zsh_version) already installed"
      return 0
    fi

    install_from_pm --ok-cmd _zsh_installed_msg \
      --die "Couldn't install zsh" \
      -- zsh
  )
}

# Render $HOME/.zshenv with a managed block that inlines the read-sequence doc
# from zshenv-doc plus the XDG/ZDOTDIR exports. Inlined (not sourced) so zsh
# startup avoids an extra file read.
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
    install_managed_block --as "$(tui_path "$zshenv")" \
      "$zshenv" "$ZSH_BLOCK_TAG" "$content"
  )
}

# Render $ZDOTDIR/.zshrc with the base managed block sourcing zshrc-base.
# Also prepares ZDOTDIR/data/cache dirs and prints the polite note about
# any legacy $HOME/.zshrc, since this step is the first to touch $ZDOTDIR.
install_zsh_zshrc_base() {
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
      tui_warn "\$HOME/.zshrc exists but ZDOTDIR is now $(tui_path "$zdotdir")"
      tui_detail "Consider moving its contents to $(tui_path "$zshrc")"
    fi

    install_managed_block --as "$(tui_path "$zshrc") (base)" \
      "$zshrc" "$ZSH_BLOCK_TAG_BASE" "$content"
  )
}

# Insert the overrides managed block into $ZDOTDIR/.zshrc, sourcing zshrc-overrides.
# No anchor needed: on first install this block lands at the end (after base).
# Position-preserving on re-install.
install_zsh_zshrc_overrides() {
  local zdotdir zshrc content
  (
    set -e
    zdotdir=$(get_zdotdir)
    zshrc="$zdotdir/.zshrc"
    content=$(cat <<-'EOF'
		# Managed by zsh/install_zsh.sh — edits inside this block will be overwritten.
		source "$DOTFILES/zsh/zshrc-overrides"
EOF
    )
    install_managed_block --as "$(tui_path "$zshrc") (overrides)" \
      "$zshrc" "$ZSH_BLOCK_TAG_OVERRIDES" "$content"
  )
}

# Render $HOME/.zshenv and $ZDOTDIR/.zshrc with the base + overrides managed blocks.
install_zsh_dotfiles() {
  (
    set -e
    install_zsh_zshenv
    install_zsh_zshrc_base
    install_zsh_zshrc_overrides
  )
}

# Ensure chsh is available; install it from the PM if not.
# Warns and returns 0 on install failure (caller handles missing chsh).
ensure_chsh_available() {
  if command_exists chsh; then
    return 0
  fi
  install_from_pm --warn "Couldn't install chsh from package manager" \
    -- chsh \
    || return 0
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
    tui_skip "zsh is already the default shell"
    return 0
  fi

  if ! confirm "Set zsh as the default shell?"; then
    return 0
  fi

  if ! sudo chsh -s "$zsh_path" "$(id -un)"; then
    tui_warn "Couldn't change default shell. Run manually: chsh -s $zsh_path"
    return 0
  fi

  tui_ok "default shell set to zsh"
}

# Installs zsh and its dotfiles, then offers to set it as default shell
# -y: accepts default answer for all questions
install_zsh_wizard() {
  wizard_run "$@" -- install_zsh_program install_zsh_dotfiles set_zsh_as_default_shell
}

# Run installation if called with --wizard
wizard_main install_zsh_wizard "$@"
