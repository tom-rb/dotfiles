#!/usr/bin/env sh
#
# Installs programs (zsh, tmux, vim) and configure them to use the respective dotfiles.
#
# Many configurations come from several repos out there.
#
# Honorable inspirations:
# https://github.com/Parth/dotfiles
# https://github.com/codehearts/dotfiles
#

# Try locate project's root folder
if [ -z "$DOTFILES" ]; then
  DOTFILES=$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null 2>&1 && pwd -P)
fi

if [ ! -f "$DOTFILES/utils/utils.sh" ]; then
  echo "Cannot find installation files. Please, run this script from dotfiles root folder." >&2
  exit 1
fi

export DOTFILES

# shellcheck source=utils/utils.sh
. "$DOTFILES/utils/utils.sh"

# Packages required for basic operations
basic_packages="wget tar gzip"

check_basic_packages() {
  for cmd in $basic_packages; do
    command_exists "$cmd" || return 1
  done
}

install_basic_packages() {
  # shellcheck disable=SC2086 # splitting on purpose
  install_from_pm $basic_packages
}

start_tmux_wizard() {
  sh -- "$DOTFILES/tmux/install_tmux.sh" --wizard
}

deploy_wizard() {
  if ! check_supported_pm; then
    echo "Sorry, this OS is not supported."
    return 1
  fi

  if ! check_basic_packages; then
    printf "Lets install basic packages first: %s (press any key)" "$basic_packages"
    read_char silent
    install_basic_packages || die "Couldn't install basic packages"
  fi

  if confirm "Install tmux?"; then
    start_tmux_wizard
  fi
}

# Run installation if not called with dotfiles_dont_run
# shellcheck disable=SC2154
if [ -z "$dotfiles_dont_run" ]; then
  deploy_wizard
fi
