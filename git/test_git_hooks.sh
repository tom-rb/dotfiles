#!/usr/bin/env sh

readonly THISDIR=$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)

oneTimeSetUp() {
  # shellcheck source=../tests/utils_for_test.sh
  . "$THISDIR/../tests/utils_for_test.sh"

  # Temporary file where hook script will write to
  OUTFILE="${SHUNIT_TMPDIR:?}/prepare_msg"
}

tearDown() {
  cleanupSpies
  cleanupTestDir
}

# Call prepare-commit-msg hook in tmp file
# $1: initial contents of commit msg
prepare_msg() {
  rm -f "$OUTFILE"
  echo "$1" > "$OUTFILE"
  "$THISDIR/templates/hooks/prepare-commit-msg" "$OUTFILE"
}

#
# Tests
#

test_tag_is_inserted_at_message_start() {
  createSpy -o "ABC-123-my-feature" git
  prepare_msg ""
  assertEquals "[ABC-123] " "$(cat "$OUTFILE")"
}

test_tag_is_inserted_preserving_previous_message() {
  createSpy -o "ABC-123_my_feature" git
  prepare_msg "msg"
  assertEquals "[ABC-123] msg" "$(cat "$OUTFILE")"
}

test_tag_is_not_inserted_if_its_not_an_issue_like_format() {
  createSpy -o "HEAD^1" git
  prepare_msg "msg"
  assertEquals "msg" "$(cat "$OUTFILE")"

  createSpy -o "abc-123" git # lowercase is not tag
  prepare_msg "msg"
  assertEquals "msg" "$(cat "$OUTFILE")"
}

test_tag_is_not_re_inserted_if_message_already_has_tag() {
  createSpy -o "ABC-123" git
  prepare_msg "[DEF-456] msg"
  assertEquals "[DEF-456] msg" "$(cat "$OUTFILE")"

  createSpy -o "ABC-123" git
  prepare_msg "[FIX] msg"
  assertEquals "[FIX] msg" "$(cat "$OUTFILE")"
}

test_tag_is_not_inserted_if_message_is_some_automatic_git_message() {
  createSpy -o "ABC-123" git
  prepare_msg "Merge branch ..."
  assertEquals "Merge branch ..." "$(cat "$OUTFILE")"

  createSpy -o "ABC-123" git
  prepare_msg "fixup [FIX] msg"
  assertEquals "fixup [FIX] msg" "$(cat "$OUTFILE")"
}

test_branch_prefix_is_removed_to_infer_tag_name() {
  createSpy -o "feature/AB-42-my-feat" git
  prepare_msg "msg"
  assertEquals "[AB-42] msg" "$(cat "$OUTFILE")"

  createSpy -o "origin/fEaTurE/CD-84-my-feat" git
  prepare_msg "msg"
  assertEquals "[CD-84] msg" "$(cat "$OUTFILE")"
}

test_it_skips_commented_lines_when_inserting_tag_name() {
  createSpy -o "ABC-123" git
  prepare_msg "$(cat <<-EOF
	# Some comment git added
	msg
	EOF
  )"
  assertContains "$(cat "$OUTFILE")" "[ABC-123] msg"
}

# Run tests
SHPY_PATH="$THISDIR/../tests/shpy"
export SHPY_PATH
# shellcheck source=../tests/shpy
. "$THISDIR/../tests/shpy"
# shellcheck source=../tests/shpy-shunit2
. "$THISDIR/../tests/shpy-shunit2"
# shellcheck source=../tests/shunit2
. "$THISDIR/../tests/shunit2"