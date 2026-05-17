#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
  DOTFILES="$(get_abs_path "$THISDIR/..")"
}

setUp() {
  . "$THISDIR/utils.sh"
}

tearDown() {
  cleanupSpies
  cleanupTestDir
}


#
# die / command_exists
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
# version_ge
#

test_version_ge_equal_versions() {
  assertTrue  "3.1b >= 3.1b" "version_ge 3.1b 3.1b"
  assertTrue  "3.2  >= 3.2"  "version_ge 3.2 3.2"
  assertTrue  "3.1  >= 3.1"  "version_ge 3.1 3.1"
}

test_version_ge_major_difference() {
  assertTrue  "4.0  >= 3.6a" "version_ge 4.0 3.6a"
  assertTrue  "10.0 >= 3.6"  "version_ge 10.0 3.6"
  assertFalse "2.9  >= 3.0"  "version_ge 2.9 3.0"
  assertFalse "3.6a >= 4.0"  "version_ge 3.6a 4.0"
}

test_version_ge_minor_difference() {
  assertTrue  "3.2  >= 3.1b" "version_ge 3.2 3.1b"
  assertTrue  "3.10 >= 3.2"  "version_ge 3.10 3.2"
  assertFalse "3.1  >= 3.2"  "version_ge 3.1 3.2"
  assertFalse "3.1b >= 3.2"  "version_ge 3.1b 3.2"
}

test_version_ge_letter_suffix_difference() {
  assertTrue  "3.1b >= 3.1a" "version_ge 3.1b 3.1a"
  assertTrue  "3.1a >= 3.1"  "version_ge 3.1a 3.1"
  assertTrue  "3.6a >= 3.6"  "version_ge 3.6a 3.6"
  assertFalse "3.1a >= 3.1b" "version_ge 3.1a 3.1b"
  assertFalse "3.1  >= 3.1a" "version_ge 3.1 3.1a"
  assertFalse "3.6  >= 3.6a" "version_ge 3.6 3.6a"
}


# Run tests
SHPY_PATH="$THISDIR/../tests/shpy"
export SHPY_PATH
. "$THISDIR/../tests/shpy"
. "$THISDIR/../tests/shpy-shunit2"
. "$THISDIR/../tests/shunit2"
