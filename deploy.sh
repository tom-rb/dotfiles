#!/usr/bin/env sh
#
# Installs programs (zsh, tmux, vim) and configure them to use the respective dotfiles.
#
# Many configurations come from several repos out there.
# For this script, initial inspiration came from: https://github.com/Parth/dotfiles
#

check_supported_os() {
  # Only supporting Ubuntu for now
  if ! command -v apt-get > /dev/null; then
    echo "Sorry, this OS is not supported." && exit 1
  fi
}

# Read one char from terminal input
# https://stackoverflow.com/a/30022297/4783169
read_char() {
  stty -icanon -echo
  dd bs=1 count=1 2> /dev/null
  stty icanon echo
}

# Ask for user confirmation with a keystroke
#  $1 Confirmation message (optional)
#  Returns 0 on confirmation, 1 on deny
confirm() {
  # Remove trailing whitespace characters
  local c message="${1%"${1##*[![:space:]]}"}"
  printf "${message:-Continue?} (Y/n) "
  while true; do
    c=$(read_char)
    case "$c" in
      ([nN]) echo "$c"; return 1;;
      ([yY]) echo "$c"; return 0;;
      ("")   echo 'y'; return 0;;
      (*)    echo ' Choose yes or no.';;
    esac
  done
}

configure_interactive() {
  local doUpdate doUpgrade
  confirm "Do you want to update the package manager?"
  doUpdate=$?

  if [ $doUpdate -eq 0 ]; then
    confirm "Do you want to upgrade packages too?"
    doUpgrade=$?
  fi
}