#!/usr/bin/env sh

readonly THISDIR=$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)

oneTimeSetUp() {
  # shellcheck source=../utils.sh
  . "$THISDIR/../utils.sh"
}

# Source and mock deploy.sh script
deploy() {
  # shellcheck source=../../deploy.sh
  . "$THISDIR/../../deploy.sh"

  eval "$(extract_mock_functions)" || exit 2
}

#
# Tests
#

test_confirm_has_default_message() {
  message=$(deploy ; echo 'y' | confirm)
  assertEquals "Continue?" "${message%% *}"
}

test_confirm_trims_given_message() {
  message=$(deploy ; echo 'y' | confirm 'Sure?   ')
  assertEquals "Sure? (Y/n) y" "${message}"
}

test_confirm_returns_ok_on_y() {
  (deploy ; echo 'y' | confirm) > /dev/null
  assertTrue "y should return ok" $?

  (deploy ; echo 'Y' | confirm) > /dev/null
  assertTrue "Y should return ok" $?
}

test_confirm_returns_error_on_n() {
  (deploy ; echo 'n' | confirm) > /dev/null
  assertFalse "n should return error" $?

  (deploy ; echo 'N' | confirm) > /dev/null
  assertFalse "N should return error" $?
}

test_confirm_asks_for_correct_input() {
  output=$(deploy ; echo 'xy' | confirm)
  assertTrue "y should return ok" $?

  echo "$output" | grep -q 'Choose y or n'
  assertTrue "Confirmation output expected" $?
}

test_confirm_returns_yes_on_enter() {
  (deploy ; echo '' | confirm) > /dev/null
  assertTrue "Enter should return ok" $?
}

test_confirm_echoes_right_inputs() {
  message=$(deploy ; echo 'y' | confirm)
  # message ends with y
  assertEquals "y" "${message##*[!y]}"

  message=$(deploy ; echo 'N' | confirm)
  # message ends with N
  assertEquals "N" "${message##*[!N]}"
}

test_confirm_write_y_for_enter() {
  message=$(deploy ; echo '' | confirm)
  assertEquals "y" "${message##*[!y]}"
}

test_supported_pm() {
  (deploy ; check_supported_pm)
  assertTrue "PM should be supported" $?
}

test_package_manager_wizard() {
  mock_install_basic_packages() {
    echo 'installed basic'
  }
  mock_upgrade_packages() {
    echo 'upgrade called'
  }
  # [Y]es for basic, [n]o for upgrades
  output=$(deploy ; echo 'Yn' | package_manager_wizard)

  assertContains "Install basic should've been called" \
    "$output" "installed basic"

  assertNotContains "Upgrade shouldn't be called" \
    "$output" "upgrade called"
}

# Run tests
# shellcheck source=../shunit2
. "$THISDIR/../shunit2"