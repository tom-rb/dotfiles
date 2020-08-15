#!/usr/bin/env sh

#
# Mocks
#

mock_read_char() {
  head -c 1 # just forward given char
}

deploy() {
  . ./deploy.sh
  # Install mocks (TODO: automatize)
  read_char(){ mock_read_char; }
}

#
# Tests
#

test_supported_os() {
  (deploy ; check_supported_os)
  assertTrue "OS should be supported" $?
}

test_confirm_has_default_message() {
  message=$(deploy ; echo 'y' | confirm)
  assertEquals "Continue?" "${message%% *}"
}

test_confirm_trims_given_message() {
  message=$(deploy ; echo 'y' | confirm 'Sure?  ')
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
  message=$(deploy ; echo 'xy' | confirm)
  assertTrue "y should return ok" $?
  assertTrue "Confirmation message expected" \
             "echo \"$message\" | grep 'Choose yes or no'"
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

# Run tests
. shunit2