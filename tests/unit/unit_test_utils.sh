#!/usr/bin/env sh

readonly THISDIR=$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)

oneTimeSetUp() {
  # shellcheck source=../utils_for_test.sh
  . "$THISDIR/../utils_for_test.sh"
}

setUp() {
  # shellcheck source=../../utils/utils.sh
  . "$THISDIR/../../utils/utils.sh"
}

tearDown() {
  cleanupSpies
  cleanupTestDir
}


#
# Tests
#

test_die_with_default_message_and_code() {
  message=$(die)
  assertEquals 1 $?
  assertEquals "Aborted." "$message"
}

test_die_with_custom_message_and_code() {
  message=$(die Bye)
  assertEquals 1 $?
  assertEquals "Bye" "$message"

  message=$(die 'Custom code' 129)
  assertEquals 129 $?
  assertEquals "Custom code" "$message"
}

test_check_a_command_exists() {
  command_exists cat
  assertTrue "Command cat should be found" $?

  command_exists no_such_command
  assertFalse "Command no_such_command should not be found" $?
}

#
# CLI utils
#

test_read_char_from_pipe() {
  char=$(echo 'a' | read_char)
  assertEquals "a" "$char"
}

test_read_char_silent_from_pipe() {
  char=$(echo 'a' | read_char silent)
  # Used for "waiting for input" case
  assertEquals "" "$char"
}

test_confirm_has_default_message() {
  message=$(yes | confirm)
  assertEquals "Continue? (Y/n)" "${message% *}"
}

test_confirm_has_default_no_message() {
  message=$(yes | confirm -n)
  assertEquals "Continue? (y/N)" "${message% *}"
}

test_confirm_trims_given_message() {
  message=$(yes | confirm 'Sure?   ')
  assertEquals "Sure? (Y/n) y" "${message}"

  message=$(yes | confirm -n 'Not sure?   ')
  assertEquals "Not sure? (y/N) y" "${message}"
}

test_confirm_returns_ok_on_y() {
  echo 'y' | confirm > /dev/null
  assertTrue "y should return ok" $?

  echo 'Y' | confirm > /dev/null
  assertTrue "Y should return ok" $?
}

test_confirm_returns_error_on_n() {
  echo 'n' | confirm > /dev/null
  assertFalse "n should return error" $?

  echo 'N' | confirm > /dev/null
  assertFalse "N should return error" $?
}

test_confirm_asks_for_correct_input() {
  # Send not valid answer 'x' first
  output=$(echo 'xy' | confirm)
  assertTrue "y should be accepted" $?

  assertContains "Confirmation output expected" \
    "$output" "Choose y or n"
}

test_confirm_returns_yes_on_enter() {
  echo '' | confirm > /dev/null
  assertTrue "Enter should return true" $?
}

test_confirm_returns_no_on_enter() {
  echo '' | confirm -n > /dev/null
  assertFalse "Enter should return false" $?

  echo '' | confirm -n 'Custom msg' > /dev/null
  assertFalse "Enter should return false" $?
}

test_confirm_echoes_right_inputs() {
  message=$(echo 'y' | confirm)
  # message ends with y
  assertEquals "y" "${message##*[!y]}"

  message=$(echo 'N' | confirm)
  # message ends with N
  assertEquals "N" "${message##*[!N]}"
}

test_confirm_write_y_for_enter() {
  message=$(echo '' | confirm)
  assertEquals "y" "${message##*[!y]}"
}

test_choose_print_the_options() {
  output=$(echo 1 | choose "first option" second)
  assertContains "Should print first option" \
    "$output" "1) first option"
  assertContains "Should print second option" \
    "$output" "2) second"
}

test_choose_returns_valid_choice_number() {
  output=$(echo 1 | choose first second)
  assertEquals 1 $?
  assertEquals "Should echo answer" "1" "${output##*[!1]}"

  output=$(echo 2 | choose first second)
  assertEquals 2 $?
  assertEquals "Should echo answer" "2" "${output##*[!2]}"
}

test_choose_returns_zero_when_canceled_with_q() {
  output=$(echo q | choose first second)
  assertEquals 0 $?
  assertContains "$output" "Cancelled"
}

test_choose_dont_print_anything_on_invalid_answer() {
  output=$(printf '%s\n%d' "034_all_invalid_except:" 1 | choose first second)
  assertEquals 1 $?
  assertEquals "1) first|2) second|q) Quit|1|" \
    "$(echo "$output" | tr '\n' '|')"
}

#
# File utils
#

test_backup_fails_if_arg_is_empty_or_file_does_not_exist() {
  backup_file "inexistent" 2> /dev/null
  assertFalse "Expected failure for inexistent file" $?

  (backup_file) 2> /dev/null
  assertFalse "Expected failure for no argument" $?
}

test_backup_file_copies_it() {
  # TODO: check all functions that accept files putting spaces in them
  file="${SHUNIT_TMPDIR:?}/original with spaces"
  echo "original" > "$file"

  backup_file "$file"

  assertTrue "No errors expected" $?
  assertTrue "Expected backup copy" "[ -f \"$file.bkp\" ]"
}

test_backup_file_increments_bkp_number_if_backup_exists() {
  file="${SHUNIT_TMPDIR:?}/original with spaces"
  echo "original" > "$file"

  backup_file "$file"
  backup_file "$file"
  assertTrue "Expected 2nd backup copy" "[ -f \"$file.bkp1\" ]"

  backup_file "$file"
  assertTrue "Expected 3rd backup copy" "[ -f \"$file.bkp2\" ]"
}

#
# Package Manager utilities
#

test_get_version_in_package_manager_fails_for_unsupported_pm() {
  createSpy -u -r "$SHUNIT_FALSE" command_exists

  err_msg=$({ get_version_in_pm htop 1>/dev/null; } 2>&1)

  assertContains "Should get an error message" \
    "${err_msg}" "find package manager"
}

test_install_from_package_manager_fails_for_unsupported_pm() {
  createSpy -u -r "$SHUNIT_FALSE" command_exists

  err_msg=$({ install_from_pm htop 1>/dev/null; } 2>&1)

  assertContains "Should get an error message" \
    "${err_msg}" "find package manager"
}


# Run tests
SHPY_PATH="$THISDIR/../shpy"
export SHPY_PATH
# shellcheck source=../shpy
. "$THISDIR/../shpy"
# shellcheck source=../shpy-shunit2
. "$THISDIR/../shpy-shunit2"
# shellcheck source=../shunit2
. "$THISDIR/../shunit2"