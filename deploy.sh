#!/usr/bin/env sh
#
# Installs programs (zsh, tmux, vim) and configure them to use the respective dotfiles.
#
# Many configurations come from several repos out there.
# For this script, initial inspiration came from: https://github.com/Parth/dotfiles
#

# shellcheck source=utils/utils.sh
. "$DOTFILES/utils/utils.sh"

# Install packages required for basic operations
install_basic_packages() {
  install_from_pm wget tar gzip
}

start_tmux_wizard() {
  sh -- "$DOTFILES"/tmux/install_tmux.sh --wizard
}

deploy_wizard() {
  if ! check_supported_pm; then
    echo "Sorry, this OS is not supported."
    return 1
  fi

  if confirm "Install basic packages (otherwise exit)?"; then
    install_basic_packages
  else
    echo "Bye"
    return 0
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
