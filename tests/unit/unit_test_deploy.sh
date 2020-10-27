#!/usr/bin/env sh

readonly THISDIR=$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)

oneTimeSetUp() {
  # shellcheck source=../utils_for_test.sh
  . "$THISDIR/../utils_for_test.sh"
}

# Source and mock deploy.sh script
deploy() {
  # shellcheck source=../../deploy.sh
  dotfiles_dont_run=1 . "$THISDIR/../../deploy.sh"

  eval "$(extract_mock_functions)" || exit 2
}

#
# Tests
#

test_deploy_wizard() {
  mock_install_basic_packages() {
    echo 'installed basic'
  }
  mock_start_tmux_wizard() {
    echo 'tmux wizard'
  }

  # [Y]es for basic, [y]es for tmux
  output=$(deploy ; echo 'Yy' | deploy_wizard)

  assertContains "Install basic should've been called" \
    "$output" "installed basic"
  assertContains "Tmux installation should've been called" \
    "$output" "tmux wizard"
}

# Run tests
# shellcheck source=../shunit2
. "$THISDIR/../shunit2"