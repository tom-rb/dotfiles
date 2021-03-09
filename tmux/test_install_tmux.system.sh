#!/usr/bin/env sh

readonly THISDIR=$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)

oneTimeSetUp() {
  # shellcheck source=install_tmux.sh
  . "$THISDIR/install_tmux.sh"
}

it_checks_tmux_is_not_installed() {
  is_tmux_installed
  assertFalse "Expected tmux not installed" $?
}

it_reads_available_tmux_package_version() {
  version=$(get_tmux_package_version)
  echo "$version" | grep -qE '^[0-9]\.[0-9][abc]?$'
  assertTrue "Expected a tmux version, got <$version>" $?
}

# @image: with-basics
it_reads_current_tmux_release_version() {
  version=$(get_tmux_release_version)
  echo "$version" | grep -qE '^[0-9]\.[0-9][abc]?$'
  assertTrue "Expected a tmux version, got <$version>" $?
}

# @image: with-basics
it_installs_tmux_from_source_to_specified_location() {
  version=$(get_tmux_release_version)
  prefix="$HOME/apps/tmux"

  install_tmux_from_source "$version" "$prefix" >/dev/null 2>&1
  assertTrue "Expected no error on installing tmux" $?

  command -v "$prefix/bin/tmux" >/dev/null
  assertTrue "Expected tmux to be installed" $?
}

# @image: with-basics
it_installs_tmux_and_its_dotfiles() {
  install_tmux_wizard -y > /dev/null 2>&1

  assertTrue "Expect tmux to be installed" "is_tmux_installed"

  # Check config was set
  output=$(tmux start \; show -g @conf_dir)
  assertContains "$output" "@conf_dir"
  assertContains "$output" "/tmux"
}

# shellcheck source=../tests/shunit2
. shunit2