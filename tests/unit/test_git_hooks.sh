#!/usr/bin/env sh

readonly THISDIR=$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)

oneTimeSetUp() {
  # shellcheck source=../utils.sh
  . "$THISDIR/../utils.sh"

  # Temporary file where hook script will write to
  OUTFILE="${SHUNIT_TMPDIR:?}/prepare_msg"
}

# Prepare mocks and call prepare-commit-msg script
# Args:
#   $1: initial contents of commit msg
prepare_msg() {
  eval "$(extract_mock_functions)" || exit 2

  rm -f "$OUTFILE"
  echo "$1" > "$OUTFILE"

  # Sourcing, instead of calling, to use mocked git functions in tests.
  # shellcheck source=../../git/templates/hooks/prepare-commit-msg
  (msgfile="$OUTFILE" . "$THISDIR/../../git/templates/hooks/prepare-commit-msg")
}

#
# Tests
#

test_tag_is_inserted_at_message_start() {
  mock_git() { echo 'ABC-123'; }
  prepare_msg ''
  assertEquals "[ABC-123] " "$(cat "$OUTFILE")"
}

test_tag_is_inserted_preserving_previous_message() {
  mock_git() { echo 'ABC-123'; }
  prepare_msg 'msg'
  assertEquals "[ABC-123] msg" "$(cat "$OUTFILE")"
}

test_tag_is_not_inserted_if_its_not_an_issue_like_format() {
  mock_git() { echo 'HEAD^1'; }
  prepare_msg 'msg'
  assertEquals "msg" "$(cat "$OUTFILE")"

  mock_git() { echo 'abc-123'; } # lowercase is not tag
  prepare_msg 'msg'
  assertEquals "msg" "$(cat "$OUTFILE")"
}

test_branch_prefix_is_removed_to_infer_tag_name() {
  mock_git() { echo 'feature/AB-42-my-feat'; }
  prepare_msg 'msg'
  assertEquals "[AB-42] msg" "$(cat "$OUTFILE")"

  mock_git() { echo 'origin/feature/CD-84-my-feat'; }
  prepare_msg 'msg'
  assertEquals "[CD-84] msg" "$(cat "$OUTFILE")"
}

test_tag_is_not_re_inserted_if_message_already_has_tag() {
  mock_git() { echo 'ABC-123'; }
  prepare_msg '[DEF-456] msg'
  assertEquals "[DEF-456] msg" "$(cat "$OUTFILE")"

  mock_git() { echo 'ABC-123'; }
  prepare_msg '[FIX] msg'
  assertEquals "[FIX] msg" "$(cat "$OUTFILE")"
}

# Run tests
# shellcheck source=../shunit2
. "$THISDIR/../shunit2"