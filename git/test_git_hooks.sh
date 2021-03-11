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

# Mock (any) git call to return a branch name
# $1: branch name to return
mock_branch() {
  createSpy -o "${1:?}" git
}

# Call prepare-commit-msg hook in tmp file
# $1: initial contents of commit msg
# $@ (remaining): passed to hook script
prepare_msg() {
  rm -f "$OUTFILE"
  echo "$1" > "$OUTFILE"; shift
  "$THISDIR/templates/hooks/prepare-commit-msg" "$OUTFILE" "$@"
}

#
# Tests
#

test_tag_is_inserted_at_message_start() {
  mock_branch "ABC-123-my-feature"
  prepare_msg ""
  assertEquals "[ABC-123] " "$(cat "$OUTFILE")"
}

test_tag_is_inserted_preserving_previous_message() {
  mock_branch "ABC-123_my_feature"
  prepare_msg "msg"
  assertEquals "[ABC-123] msg" "$(cat "$OUTFILE")"
}

test_tag_is_not_inserted_if_its_not_an_issue_like_format() {
  mock_branch "HEAD^1"
  prepare_msg "msg"
  assertEquals "msg" "$(cat "$OUTFILE")"

  mock_branch "abc-123" # lowercase is not a tag
  prepare_msg "msg"
  assertEquals "msg" "$(cat "$OUTFILE")"
}

test_tag_is_not_re_inserted_if_message_already_has_tag() {
  mock_branch "ABC-123"
  prepare_msg "[DEF-456] msg"
  assertEquals "[DEF-456] msg" "$(cat "$OUTFILE")"

  mock_branch "ABC-123"
  prepare_msg "[FIX] msg"
  assertEquals "[FIX] msg" "$(cat "$OUTFILE")"
}

test_tag_is_inserted_in_multiline_message() {
  mock_branch "ABC-123"
  prepare_msg "$(cat <<-EOF
	existing msg

	# Please enter the commit message for your changes.
	EOF
  )"
  assertContains "$(cat "$OUTFILE")" "[ABC-123] existing msg"
}

test_tag_is_not_inserted_if_message_is_some_automatic_git_message() {
  mock_branch "ABC-123"
  prepare_msg "Merge branch ..."
  assertEquals "Merge branch ..." "$(cat "$OUTFILE")"

  mock_branch "ABC-123"
  prepare_msg "fixup [FIX] msg"
  assertEquals "fixup [FIX] msg" "$(cat "$OUTFILE")"
}

test_tag_is_not_inserted_if_hook_is_called_with_merge_2nd_argument() {
  mock_branch "ABC-123"
  prepare_msg "" merge # git sends 'merge' in $2 for merge commits
  assertEquals "" "$(cat "$OUTFILE")"
}

test_branch_prefix_is_removed_to_infer_tag_name() {
  mock_branch "feature/AB-42-my-feat"
  prepare_msg "msg"
  assertEquals "[AB-42] msg" "$(cat "$OUTFILE")"

  mock_branch "origin/fEaTurE/CD-84-my-feat"
  prepare_msg "msg"
  assertEquals "[CD-84] msg" "$(cat "$OUTFILE")"
}

test_it_searches_first_non_comment_line_for_inserting_tag() {
  mock_branch "ABC-123"

  prepare_msg "$(cat <<-EOF
	# This is the 1st commit message:
	my commit
	EOF
  )"
  assertContains "$(cat "$OUTFILE")" "[ABC-123] my commit"

  prepare_msg "$(cat <<-EOF
	# This is the 1st commit message:

	msg on 2nd line
	EOF
  )"
  assertContains "$(cat "$OUTFILE")" "[ABC-123] msg on 2nd"

  prepare_msg "$(cat <<-EOF
	# This is the 1st commit message:

	[FIX] already has a tag!
	EOF
  )"
  assertNotContains "$(cat "$OUTFILE")" "[ABC-123]"
}

test_it_stops_the_search_to_insert_tag_before_the_scissors_mark() {
  mock_branch "ABC-123"
  prepare_msg "$(cat <<-EOF
	# This is the 1st commit message:

	# ------------- >8 -------------
	# Do not modify or remove the line above.
	this should not be picked as message
	EOF
  )"
  assertContains "$(cat "$OUTFILE")" "[ABC-123] "
  assertNotContains "$(cat "$OUTFILE")" "[ABC-123] this should not"
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