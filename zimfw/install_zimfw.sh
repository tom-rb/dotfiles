#!/usr/bin/env sh

# shellcheck source=../utils/utils.sh
. "${DOTFILES:?}/utils/utils.sh"

ZIMFW_BLOCK_TAG="dotfiles:zimfw"

# Pinned zimfw release. Bump deliberately, never to a moving branch.
ZIMFW_URL='https://github.com/zimfw/zimfw/releases/download/v1.19.1/zimfw.zsh'

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
  say_step "downloading zimfw"
  run_quiet wget -q -O "$zim_home/zimfw.zsh" "$ZIMFW_URL"
}

# Download zimfw.zsh if not already present
install_zimfw_program() {
  (
    set -e
    if is_zimfw_installed; then
      say_ok "zimfw already installed"
      return 0
    fi
    download_zimfw
    say_ok "zimfw installed"
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
    install_managed_block "$zshenv" "$ZIMFW_BLOCK_TAG" "$content"

    say_ok "$zshenv updated"
  )
}

# Append managed block to $ZDOTDIR/.zshrc sourcing zimfw/zshrc-zim.
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
    install_managed_block "$zshrc" "$ZIMFW_BLOCK_TAG" "$content"

    say_ok "$zshrc updated"
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

    install_managed_block "$target" "$ZIMFW_BLOCK_TAG" "$contents"

    say_ok "$target configured"
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

# Run `zimfw install` to populate modules listed in .zimrc.
# Each module clones a git repo and prints a line; we collapse the wall into
# a single count, replaying full output on failure (or under DEBUG=1).
install_zimfw_modules() {
  local zim_home log rc count
  zim_home=$(get_zim_home)
  say_step "installing zim modules"
  if [ "${DEBUG:-}" = "1" ]; then
    ZIM_HOME="$zim_home" zsh "$zim_home/zimfw.zsh" install
    return $?
  fi
  log=$(mktemp 2>/dev/null || printf '/tmp/zimfw_install.%d' $$)
  ZIM_HOME="$zim_home" zsh "$zim_home/zimfw.zsh" install >"$log" 2>&1
  rc=$?
  if [ "$rc" -ne 0 ]; then
    cat "$log" >&2
    rm -f "$log"
    return $rc
  fi
  count=$(grep -c ': Installed' "$log" 2>/dev/null || echo 0)
  rm -f "$log"
  say_ok "$count zim modules installed"
}

# Coordinates the install: preconditions, framework, dotfiles, modules.
# -y: accepts default answer for all questions
install_zimfw_wizard() {
  check_zsh_prerequisites || return $?
  wizard_run "$@" -- install_zimfw_program install_zimfw_dotfiles install_zimfw_modules
}

# Run installation if called with --wizard
wizard_main install_zimfw_wizard "$@"
