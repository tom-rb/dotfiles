#!/usr/bin/env sh

readonly THISDIR=$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)

oneTimeSetUp() {
  # shellcheck source=../utils_for_test.sh
  . "$THISDIR/../utils_for_test.sh"
}

# Source and mock utils.sh script
utils() {
  # shellcheck source=../../utils/utils.sh
  . "$THISDIR/../../utils/utils.sh"

  eval "$(extract_mock_functions)" || exit 2
}

#
# Tests
#

test_die_with_message_and_code() {
  message=$(utils ; die Bye)
  assertEquals 1 $?
  assertEquals "Bye" "$message"

  message=$(utils ; die 'Custom code' 129)
  assertEquals 129 $?
  assertEquals "Custom code" "$message"
}

test_read_char_from_pipe() {
  char=$(utils ; echo 'a' | read_char)
  assertEquals "a" "$char"
}

test_read_char_silent_from_pipe() {
  char=$(utils ; echo 'a' | read_char silent)
  # Used for "waiting for input" case
  assertEquals "" "$char"
}

test_check_a_command_exists() {
  (utils ; command_exists cat)
  assertTrue "Command cat should be found" $?

  (utils ; command_exists no_such_command)
  assertFalse "Command no_such_command should not be found" $?
}

test_confirm_has_default_message() {
  message=$(utils ; yes | confirm)
  assertEquals "Continue? (Y/n)" "${message% *}"
}

test_confirm_has_default_no_message() {
  message=$(utils ; yes | confirm -n)
  assertEquals "Continue? (y/N)" "${message% *}"
}

test_confirm_trims_given_message() {
  message=$(utils ; yes | confirm 'Sure?   ')
  assertEquals "Sure? (Y/n) y" "${message}"

  message=$(utils ; yes | confirm -n 'Not sure?   ')
  assertEquals "Not sure? (y/N) y" "${message}"
}

test_confirm_returns_ok_on_y() {
  (utils ; echo 'y' | confirm) > /dev/null
  assertTrue "y should return ok" $?

  (utils ; echo 'Y' | confirm) > /dev/null
  assertTrue "Y should return ok" $?
}

test_confirm_returns_error_on_n() {
  (utils ; echo 'n' | confirm) > /dev/null
  assertFalse "n should return error" $?

  (utils ; echo 'N' | confirm) > /dev/null
  assertFalse "N should return error" $?
}

test_confirm_asks_for_correct_input() {
  # Send not valid answer 'x' first
  output=$(utils ; echo 'xy' | confirm)
  assertTrue "y should be accepted" $?

  assertContains "Confirmation output expected" \
    "$output" 'Choose y or n'
}

test_confirm_returns_yes_on_enter() {
  (utils ; echo '' | confirm) > /dev/null
  assertTrue "Enter should return true" $?
}

test_confirm_returns_no_on_enter() {
  (utils ; echo '' | confirm -n) > /dev/null
  assertFalse "Enter should return false" $?

  (utils ; echo '' | confirm -n 'Custom msg') > /dev/null
  assertFalse "Enter should return false" $?
}

test_confirm_echoes_right_inputs() {
  message=$(utils ; echo 'y' | confirm)
  # message ends with y
  assertEquals "y" "${message##*[!y]}"

  message=$(utils ; echo 'N' | confirm)
  # message ends with N
  assertEquals "N" "${message##*[!N]}"
}

test_confirm_write_y_for_enter() {
  message=$(utils ; echo '' | confirm)
  assertEquals "y" "${message##*[!y]}"
}

test_get_version_in_package_manager_fails_for_unsupported_pm() {
  mock_command_exists() { false; }
  err_msg=$({ utils; get_version_in_pm htop 1>/dev/null; } 2>&1)
  assertContains "Should get an error message" \
    "${err_msg}" "find package manager"
}

test_install_from_package_manager_fails_for_unsupported_pm() {
  mock_command_exists() { false; }
  err_msg=$({ utils; install_from_pm htop 1>/dev/null; } 2>&1)
  assertContains "Should get an error message" \
    "${err_msg}" "find package manager"
}

# Run tests
# shellcheck source=../shunit2
. "$THISDIR/../shunit2"