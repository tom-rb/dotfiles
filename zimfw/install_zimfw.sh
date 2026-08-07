#!/usr/bin/env sh

# shellcheck source=../utils/utils.sh
. "${DOTFILES:?}/utils/utils.sh"

ZIMFW_BLOCK_TAG="dotfiles:zimfw"

# Pinned zimfw release. Bump deliberately.
ZIMFW_VERSION="1.19.1"
ZIMFW_URL="https://github.com/zimfw/zimfw/releases/download/v${ZIMFW_VERSION}/zimfw.zsh"

# Check if zimfw is installed
is_zimfw_installed() {
  test -s "$(get_zim_home)/zimfw.zsh"
}

# Version of the installed zimfw, read out of the script itself (it declares
# `_zversion='1.19.1'`). Empty if the shape changes.
get_zimfw_version() {
  sed -n "s/.*_zversion='\([^']*\)'.*/\1/p" "$(get_zim_home)/zimfw.zsh" 2>/dev/null \
    | head -n1
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
  (
    set -e
    zim_home=$(get_zim_home)
    mkdir -p "$zim_home"
    # -q hides wget's own diagnostics too, so say why the download failed here.
    wget -q -O "$zim_home/zimfw.zsh" "$ZIMFW_URL" \
      || die "Couldn't download zimfw ${ZIMFW_VERSION} from $ZIMFW_URL"
  )
}

# Download zimfw.zsh if not already present
install_zimfw_program() {
  local version
  (
    set -e
    if is_zimfw_installed; then
      version=$(get_zimfw_version)
      tui_skip "zimfw${version:+ $version} already installed"
      return 0
    fi
    tui_step "downloading zimfw ${ZIMFW_VERSION}…"
    download_zimfw
    version=$(get_zimfw_version)
    tui_ok "zimfw ${version:-$ZIMFW_VERSION} installed"
  )
}

# Append managed block to $HOME/.zshenv setting specific configs.
install_zimfw_zshenv_block() {
  local zshenv content
  (
    set -e
    zshenv="$HOME/.zshenv"
    content=$(cat <<-'EOF'
		# Managed by zimfw/install_zimfw.sh — edits inside this block will be overwritten.
		# Disable global compinit call in Ubuntu (since zimfw will call it)
		skip_global_compinit=1
EOF
    )
    install_managed_block --as "$(tui_path "$zshenv") (zimfw block)" \
      "$zshenv" "$ZIMFW_BLOCK_TAG" "$content"
  )
}

# Insert managed block into $ZDOTDIR/.zshrc sourcing zimfw/zshrc-zim, anchored
# immediately after the dotfiles:zsh:base block so zsh's overrides layer keeps
# winning conflicts against zimfw modules.
install_zimfw_zshrc_block() {
  local zdotdir zshrc content
  (
    set -e
    zdotdir=$(get_zdotdir)
    zshrc="$zdotdir/.zshrc"
    content=$(cat <<-'EOF'
		# Managed by zimfw/install_zimfw.sh — edits inside this block will be overwritten.
		source "$DOTFILES/zimfw/zshrc-zim"
EOF
    )
    install_managed_block --after "dotfiles:zsh:base" --as "$(tui_path "$zshrc") (zimfw block)" \
      "$zshrc" "$ZIMFW_BLOCK_TAG" "$content"
  )
}

# Write $ZDOTDIR/<name> as a managed-block stub sourcing the repo file.
# $1: target basename (e.g. .zimrc), $2: repo source path
install_zimfw_zdotdir_stub() {
  local zdotdir target contents
  (
    set -e
    zdotdir=$(get_zdotdir)
    target="$zdotdir/${1:?}"

    contents=$(printf '# Managed by zimfw/install_zimfw.sh — edits inside this block will be overwritten.\nsource "%s"' "${2:?}")

    install_managed_block --as "$(tui_path "$target")" \
      "$target" "$ZIMFW_BLOCK_TAG" "$contents"
  )
}

# Render all zimfw-owned dotfiles ($HOME/.zshenv block + $ZDOTDIR files)
install_zimfw_dotfiles() {
  (
    set -e
    install_zimfw_zshenv_block
    install_zimfw_zshrc_block
    # shellcheck disable=SC2016
    install_zimfw_zdotdir_stub .zimrc '$DOTFILES/zimfw/zimrc-base'
  )
}

# Run `zimfw install` to populate modules listed in .zimrc
install_zimfw_modules() {
  (
    set -e
    ZIM_HOME=$(get_zim_home)
    export ZIM_HOME
    tui_task "installing zim modules…" \
      --ok "zim modules installed" \
      --die "Couldn't install the zim modules" \
      -- zsh "$ZIM_HOME/zimfw.zsh" install
  )
}

# Coordinates the install: preconditions, framework, dotfiles, modules.
# -y: accepts default answer for all questions
install_zimfw_wizard() {
  check_zsh_prerequisites || return $?
  wizard_run "$@" -- install_zimfw_program install_zimfw_dotfiles install_zimfw_modules
}

# Run installation if called with --wizard
wizard_main install_zimfw_wizard "$@"
