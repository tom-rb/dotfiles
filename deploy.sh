#!/usr/bin/env sh
#
# Installs programs (zsh, tmux, vim) and configure them to use the respective dotfiles.
#
# Many configurations come from several repos out there.
# For this script, initial inspiration came from: https://github.com/Parth/dotfiles
#

# Read one char from terminal input
# https://stackoverflow.com/a/30022297/4783169
# Returns:
#   string: 1 char or empty if ENTER was pressed
read_char() {
  stty -icanon -echo
  dd bs=1 count=1 2> /dev/null
  stty icanon echo
}

# Ask for user confirmation with a keystroke
# Args:
#   $1 Confirmation message (optional)
# Returns:
#   int: 0 on confirmation, 1 on deny
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
# Returns:
#   void, or exit if pm not supported
check_supported_pm() {
  # Only supporting apt for now
  if ! command -v apt-get > /dev/null; then
    echo "Sorry, this OS is not supported." && exit 1
  fi
}

update_package_manager() {
  sudo apt-get update
}

upgrade_packages() {
  sudo apt-get upgrade -y
}

package_manager_wizard() {
  check_supported_pm

  confirm "Update the package manager?"
  doUpdate=$?
  confirm "Also upgrade outdated packages?"
  doUpgrade=$?

  [ $doUpdate -eq 0 ] && update_package_manager
  [ $doUpgrade -eq 0 ] && upgrade_packages

  unset doUpdate doUpgrade
}