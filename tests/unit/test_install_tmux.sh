#!/usr/bin/env sh

readonly THISDIR=$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)

oneTimeSetUp() {
  # shellcheck source=../utils.sh
  . "$THISDIR/../utils.sh"
}

# Source and mock install_tmux.sh script
source_script() {
  # shellcheck source=../../tmux/install_tmux.sh
  . "$THISDIR/../../tmux/install_tmux.sh"

  eval "$(extract_mock_functions)" || exit 2
}

#
# Tests
#

test_get_package_version_fails_for_unsupported_package_manager() {
  mock_command_exists() { false; }
  err_msg=$({ source_script ; get_tmux_package_version 1>/dev/null ;} 2>&1)
  assertContains "Should get an error message" "${err_msg}" "find package manager"
}

test_install_from_pm_fails_for_unsupported_package_manager() {
  mock_command_exists() { false; }
  err_msg=$({ source_script ; install_tmux_from_pm 1>/dev/null ;} 2>&1)
  assertContains "Should get an error message" "${err_msg}" "find package manager"
}

test_install_from_source_fails_for_unsupported_package_manager() {
  mock_command_exists() { false; }
  err_msg=$({ source_script ; install_tmux_from_source '3.0' 1>/dev/null ;} 2>&1)
  assertContains "Should get an error message" "${err_msg}" "find package manager"
}

# Run tests
# shellcheck source=../shunit2
. "$THISDIR/../shunit2"