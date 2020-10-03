#!/usr/bin/env sh
#
# Installs programs (zsh, tmux, vim) and configure them to use the respective dotfiles.
#
# Many configurations come from several repos out there.
# For this script, initial inspiration came from: https://github.com/Parth/dotfiles
#

# Read one char from terminal input (or piped stdin)
# https://stackoverflow.com/a/30022297/4783169
read_char() {
  # TODO: block -isig chars too; restore only what was enabled before
  # Only apply stty changes if FD 0 is open (stdin is from tty)
  [ -t 0 ] && stty -icanon -echo
  dd bs=1 count=1 2>/dev/null
  [ -t 0 ] && stty icanon echo
}

# Ask for user confirmation with a keystroke
# $1 Confirmation message (optional)
confirm() {
  # Remove trailing whitespace characters
  message="${1%"${1##*[![:space:]]}"}"
  printf "%s" "${message:-Continue?} (Y/n) "
  while true; do
    c=$(read_char)
    case "$c" in
      [nN]) echo "$c"; return 1;;
      [yY]) echo "$c"; return 0;;
      "")   echo 'y'; return 0;;
      *)    echo ' Choose y or n.';;
    esac
  done
  unset message c
}

# Check if system package manager is supported
check_supported_pm() {
  # Only supporting apt for now
  command -v apt-get > /dev/null
}

# Install packages required for basic operations
install_basic_packages() {
  sudo apt-get update
  sudo apt-get install wget tar
}

upgrade_packages() {
  sudo apt-get upgrade -y
}

package_manager_wizard() {
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

  if confirm "Upgrade existing packages?"; then
    upgrade_packages
  fi
}