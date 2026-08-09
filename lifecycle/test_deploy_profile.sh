#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
  DOTFILES="$(get_abs_path "$THISDIR/..")"
}

setUp() {
  . "$THISDIR/../utils/utils.sh"
  . "$THISDIR/deploy_profile.sh"
  XDG_STATE_HOME=${SHUNIT_TMPDIR:?}/state
  DOTFILES_ANSWERS=''
}

tearDown() {
  cleanupSpies
  # A test may leave a deliberately unwritable profile behind.
  chmod -R u+w "${SHUNIT_TMPDIR:?}" 2>/dev/null
  cleanupTestDir
  # Undo a skip declared by a single test, so it stops there.
  endSkipping
}

#
# Loading
#

# Writes $1 verbatim as the profile file.
_given_profile() {
  local path
  path=$(get_deploy_profile_path)
  mkdir -p "${path%/*}"
  printf '%s\n' "${1?}" > "$path"
}

test_load_deploy_profile_reads_the_recorded_answers() {
  _given_profile 'zsh=y
zimfw=n
tmux=y'
  load_deploy_profile
  assertEquals 'zsh=y zimfw=n tmux=y' "$DOTFILES_ANSWERS"
}

# `read` reports failure on a final line with no newline after it, which would
# drop that answer on the floor. Only a hand-edited or interrupted write ends
# that way, and losing a module silently is not how it should show up.
test_load_deploy_profile_keeps_a_last_line_with_no_newline_after_it() {
  local path
  path=$(get_deploy_profile_path)
  mkdir -p "${path%/*}"
  printf 'zsh=y\nzimfw=n\ntmux=y' > "$path"
  load_deploy_profile
  assertEquals 'zsh=y zimfw=n tmux=y' "$DOTFILES_ANSWERS"
}

# A first deploy has no profile, and asking everything is the right answer to
# that — not an error.
test_load_deploy_profile_yields_no_answers_when_there_is_no_profile() {
  DOTFILES_ANSWERS='stale=y'
  load_deploy_profile
  assertEquals '' "$DOTFILES_ANSWERS"
  assertTrue "a missing profile is not a failure" $?
}

#
# Saving
#

test_save_deploy_profile_writes_one_answer_per_line() {
  DOTFILES_ANSWERS='zsh=y zimfw=n tmux=y'
  save_deploy_profile
  assertEquals 'zsh=y
zimfw=n
tmux=y' "$(cat "$(get_deploy_profile_path)")"
}

test_save_deploy_profile_creates_the_state_directory() {
  DOTFILES_ANSWERS='zsh=y'
  save_deploy_profile
  assertTrue "profile should exist" "[ -f '$(get_deploy_profile_path)' ]"
}

# Disabling globbing to split the map changes it for the whole process, so every
# function that does it has to put it back.
test_save_deploy_profile_leaves_pathname_expansion_as_it_found_it() {
  DOTFILES_ANSWERS='zsh=y'
  set +f
  save_deploy_profile
  case $- in
    *f*) fail "pathname expansion should have been restored" ;;
  esac
}

# The contract between a deploy that records and an update that replays: the
# answers a run ends with are the answers the next run starts from. This is the
# test that rots silently when someone adds a module.
test_deploy_profile_round_trips_the_answers() {
  DOTFILES_ANSWERS='zsh=y zimfw=n asdf=n tmux=y git=y pi=n claude=y'
  save_deploy_profile
  DOTFILES_ANSWERS='forgotten=y'
  load_deploy_profile
  assertEquals 'zsh=y zimfw=n asdf=n tmux=y git=y pi=n claude=y' "$DOTFILES_ANSWERS"
}

# Writing the profile is the last thing a run does. An unwritable state
# directory must not turn a deploy that worked into a deploy that failed.
test_save_deploy_profile_warns_rather_than_fails_when_it_cannot_write() {
  # shellcheck disable=SC2034 # read by get_deploy_profile_path
  XDG_STATE_HOME=/proc/nonexistent-by-construction
  DOTFILES_ANSWERS='zsh=y'
  output=$(save_deploy_profile 2>&1)
  assertTrue "an unwritable profile is not a failed deploy" $?
  assertContains "should say the profile was not saved" "$output" "profile"
}


# A profile left root-owned by an earlier `sudo sh deploy.sh` is writable by
# nobody but root, and its directory already exists — so the clean early return
# above is skipped and the redirection itself is what fails. The shell announces
# that on its own stderr unless the redirection order silences it first.
test_save_deploy_profile_warns_without_leaking_the_shells_own_error() {
  local path
  if [ "$(id -u)" = 0 ]; then
    echo "Skipping: root writes to an unwritable file anyway"
    startSkipping
  fi
  path=$(get_deploy_profile_path)
  mkdir -p "${path%/*}"
  : > "$path"
  chmod 444 "$path"

  DOTFILES_ANSWERS='zsh=y'
  output=$(save_deploy_profile 2>&1)

  assertTrue "an unwritable profile is not a failed deploy" $?
  assertContains "should say the profile was not saved" "$output" "profile"
  assertNotContains "should not leak the shell's own error" \
    "$output" "Permission denied"
}

# Run tests
SHPY_PATH="$THISDIR/../tests/shpy"
export SHPY_PATH
. "$THISDIR/../tests/shpy"
. "$THISDIR/../tests/shpy-shunit2"
. "$THISDIR/../tests/shunit2"
