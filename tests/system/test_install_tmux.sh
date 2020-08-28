#!/usr/bin/env sh

THISDIR=$(a="/$0"; a=${a%/*}; a=${a#/}; a=${a:-.}; command cd "$a" && pwd)

oneTimeSetUp() {
  # shellcheck source=../../tmux/install-tmux.sh
  . "$THISDIR/../../tmux/install-tmux.sh"
}

test_check_tmux_is_not_installed() {
  is_tmux_installed
  assertFalse "Expected tmux not installed" $?
}

test_read_available_tmux_package_version() {
  output=$(get_tmux_package_version)
  echo "$output" | grep -qE '^[0-9]\.[0-9][abc]?$'
  assertTrue "Expected a tmux version, got <$output>" $?
}

test_check_tmux_is_installed_with_package_manager() {
  install_tmux_from_pm >/dev/null 2>&1
  assertTrue "Error on installing tmux" $?
  is_tmux_installed
  assertTrue "Expected tmux to be installed" $?
}


# Run tests
# shellcheck source=/usr/bin/shunit2
. shunit2