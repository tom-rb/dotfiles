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
# command_exists
#

test_check_a_command_exists() {
  command_exists cat
  assertTrue "Command cat should be found" $?

  command_exists no_such_command
  assertFalse "Command no_such_command should not be found" $?
}

#
# quietly
#

test_quietly_swallows_stdout_and_stderr() {
  output=$(quietly sh -c 'echo out; echo err >&2' 2>&1)
  assertEquals "" "$output"
}

test_quietly_restores_output_under_debug() {
  output=$(DEBUG=1 quietly sh -c 'echo out; echo err >&2' 2>&1)
  assertContains "Should show stdout" "$output" "out"
  assertContains "Should show stderr" "$output" "err"
}

test_quietly_forwards_exit_status() {
  quietly true
  assertTrue "Should forward success" $?

  quietly false
  assertFalse "Should forward failure" $?
}

#
# quietly_stdout
#

test_quietly_stdout_swallows_stdout_but_keeps_stderr() {
  # sudo asks for its password on stderr, so swallowing it leaves the user
  # staring at a frozen terminal while sudo waits for input.
  output=$(quietly_stdout sh -c 'echo out; echo err >&2' 2>&1)
  assertNotContains "Should hide stdout" "$output" "out"
  assertContains "Should keep stderr" "$output" "err"
}

test_quietly_stdout_restores_output_under_debug() {
  output=$(DEBUG=1 quietly_stdout sh -c 'echo out; echo err >&2' 2>&1)
  assertContains "Should show stdout" "$output" "out"
  assertContains "Should show stderr" "$output" "err"
}

test_quietly_stdout_forwards_exit_status() {
  quietly_stdout true
  assertTrue "Should forward success" $?

  quietly_stdout false
  assertFalse "Should forward failure" $?
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

test_backup_file_echoes_the_path_it_wrote() {
  file="${SHUNIT_TMPDIR:?}/original with spaces"
  echo "original" > "$file"

  assertEquals "$file.bkp" "$(backup_file "$file")"
  assertEquals "$file.bkp1" "$(backup_file "$file")"
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

test_verify_sha256_accepts_a_matching_digest() {
  file="${SHUNIT_TMPDIR:?}/payload with spaces"
  printf 'dotfiles\n' > "$file"

  verify_sha256 "$file" \
    "$(sha256sum "$file" | cut -d' ' -f1)"

  assertTrue "Expected the pinned digest to verify" $?
}

test_verify_sha256_rejects_a_different_digest() {
  file="${SHUNIT_TMPDIR:?}/payload"
  printf 'tampered\n' > "$file"

  verify_sha256 "$file" \
    "0000000000000000000000000000000000000000000000000000000000000000"

  assertFalse "Expected a mismatching digest to be rejected" $?
}

test_verify_sha256_fails_if_the_file_or_digest_is_missing() {
  verify_sha256 "inexistent" "0000" 2>/dev/null
  assertFalse "Expected failure for inexistent file" $?

  file="${SHUNIT_TMPDIR:?}/payload"
  printf 'dotfiles\n' > "$file"

  # Returning, not exiting: a half-finished version bump leaves an empty
  # digest constant, and the caller still has to reach its own cleanup.
  verify_sha256 "$file" "" 2>/dev/null
  assertFalse "Expected failure for an empty expected digest" $?

  verify_sha256 2>/dev/null
  assertFalse "Expected failure for no arguments at all" $?
}

test_verify_sha256_falls_back_to_shasum_without_sha256sum() {
  file="${SHUNIT_TMPDIR:?}/payload"
  printf 'dotfiles\n' > "$file"
  digest=$(sha256sum "$file" | cut -d' ' -f1)
  # No sha256sum (as on macOS), shasum answers instead.
  createSpy -u -r "$SHUNIT_FALSE" -r "$SHUNIT_TRUE" command_exists
  createSpy -u -o "$digest  $file" shasum

  verify_sha256 "$file" "$digest"

  assertTrue "Expected shasum's digest to verify" $?
  assertCalledOnceWith shasum -a 256 "$file"
}

test_verify_sha256_dies_when_no_hash_tool_exists() {
  file="${SHUNIT_TMPDIR:?}/payload"
  printf 'dotfiles\n' > "$file"
  createSpy -u -r "$SHUNIT_FALSE" -r "$SHUNIT_FALSE" command_exists

  output=$( (verify_sha256 "$file" "0000") 2>&1)

  assertFalse "Expected failure with no way to hash" $?
  # Not "mismatch": nothing was compared, so the download isn't what's wrong.
  assertContains "Should say the tool is what's missing" \
    "$output" "No SHA-256 tool found"
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

#
# english_list
#

test_english_list_renders_one_name_bare() {
  assertEquals "zsh" "$(english_list "zsh")"
}

test_english_list_joins_two_names_with_and() {
  assertEquals "zsh and tmux" "$(english_list "zsh tmux")"
}

test_english_list_commas_all_but_the_last_name() {
  assertEquals "zsh, tmux and git" "$(english_list "zsh tmux git")"
}


# Run tests
SHPY_PATH="$THISDIR/../tests/shpy"
export SHPY_PATH
. "$THISDIR/../tests/shpy"
. "$THISDIR/../tests/shpy-shunit2"
. "$THISDIR/../tests/shunit2"
