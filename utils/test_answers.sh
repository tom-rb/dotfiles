#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
  DOTFILES="$(get_abs_path "$THISDIR/..")"
}

setUp() {
  . "$THISDIR/utils.sh"
  DOTFILES_ANSWERS=''
}

tearDown() {
  cleanupSpies
  cleanupTestDir
}

#
# The answer map
#

test_record_answer_replaces_an_answer_already_held() {
  DOTFILES_ANSWERS='zsh=y tmux=n git=y'
  record_answer tmux y
  assertEquals 'zsh=y git=y tmux=y' "$DOTFILES_ANSWERS"
}

# Two answers for one key would let the stale one win, since answer_for stops at
# the first match.
test_record_answer_never_holds_a_key_twice() {
  record_answer tmux n
  record_answer tmux y
  record_answer tmux n
  assertEquals 'tmux=n' "$DOTFILES_ANSWERS"
}

# A `*` reaching the map — from a corrupted profile, or an environment that has
# one — would otherwise expand against the working directory, so the run would
# report filenames instead of the entry that is actually wrong.
test_validate_answers_does_not_expand_a_star_against_the_working_directory() {
  local here status
  here=$PWD
  mkdir -p "${SHUNIT_TMPDIR:?}/globbable"
  touch "$SHUNIT_TMPDIR/globbable/zsh=y" "$SHUNIT_TMPDIR/globbable/tmux=n"
  cd "$SHUNIT_TMPDIR/globbable" || fail "could not enter the test dir"

  DOTFILES_ANSWERS='*'
  output=$(validate_answers 'zsh zimfw tmux' 2>&1)
  status=$?
  cd "$here" || fail "could not return to the working directory"

  assertFalse "a star is not a declared key" "$status"
  assertContains "should name the entry, not what it globbed to" "$output" '"*"'
}

# Disabling globbing to split the map changes it for the whole process, so every
# function that does it has to put it back.
test_the_answer_map_leaves_pathname_expansion_as_it_found_it() {
  DOTFILES_ANSWERS='zsh=y'
  set +f
  validate_answers 'zsh tmux'
  record_answer tmux n
  drop_unknown_answers 'zsh tmux'
  answer_for zsh > /dev/null
  case $- in
    *f*) fail "pathname expansion should have been restored" ;;
  esac
}

#
# Keyed prompts
#

test_confirm_keyed_answers_from_the_map_without_reading_stdin() {
  DOTFILES_ANSWERS='zimfw=n zsh=y'
  # stdin says no. The recorded yes has to win, which it only can if the
  # keystroke was never read.
  echo 'n' | confirm_keyed zsh 'Install zsh?' > /dev/null
  assertTrue "recorded y should win over stdin" $?

  echo 'y' | confirm_keyed zimfw 'Install zimfw?' > /dev/null
  assertFalse "recorded n should win over stdin" $?
}

# A module added upstream after the profile was written has no recorded answer,
# so its prompt has to reach the user the way an unkeyed one does.
test_confirm_keyed_asks_when_its_key_is_unrecorded() {
  DOTFILES_ANSWERS='zsh=y'
  echo 'n' | confirm_keyed claude 'Configure claude code?' > /dev/null
  assertFalse "unrecorded key should read stdin" $?

  DOTFILES_ANSWERS=''
  echo 'n' | confirm_keyed zsh 'Install zsh?' > /dev/null
  assertFalse "empty map should read stdin" $?
}

test_confirm_keyed_does_not_match_a_partial_key() {
  DOTFILES_ANSWERS='zsh=y'
  echo 'n' | confirm_keyed zsh.default-shell 'Set zsh as the default shell?' > /dev/null
  assertFalse "zsh should not answer for zsh.default-shell" $?

  DOTFILES_ANSWERS='zsh.default-shell=y'
  echo 'n' | confirm_keyed zsh 'Install zsh?' > /dev/null
  assertFalse "zsh.default-shell should not answer for zsh" $?
}

# Feed stdin from a file, not a pipe. A pipe would run confirm_keyed in a
# subshell, where the answer it records could not outlive the prompt.
# $1: keystrokes, with escapes interpreted so '\n' stands for Enter (an *empty*
#     file is exhausted input, which confirm treats as fatal — not as Enter)
# $2+: the command to run
_answer_with() {
  printf '%b' "${1?}" > "${SHUNIT_TMPDIR:?}/answer"
  shift
  "$@" < "$SHUNIT_TMPDIR/answer" > /dev/null
}

# An answer given at the prompt joins the map, so a run started from a profile
# that predates a module writes that module's answer back into it.
test_confirm_keyed_records_the_answer_it_was_given() {
  _answer_with 'y' confirm_keyed tmux 'Install tmux?'
  assertEquals 'tmux=y' "$DOTFILES_ANSWERS"
}

test_confirm_keyed_records_the_default_taken_on_enter() {
  _answer_with '\n' confirm_keyed pi -n 'Install pi?'
  assertEquals 'pi=n' "$DOTFILES_ANSWERS"
}

test_confirm_keyed_adds_its_answer_to_the_answers_already_held() {
  DOTFILES_ANSWERS='zsh=y git=y'
  _answer_with 'y' confirm_keyed tmux 'Install tmux?'
  assertEquals 'zsh=y git=y tmux=y' "$DOTFILES_ANSWERS"
}

# The key is positional so that confirm's own flags travel to it verbatim.
test_confirm_keyed_forwards_the_flags_it_was_given() {
  message=$(echo '' | confirm_keyed tmux -n 'Install tmux?')
  assertEquals "  ? Install tmux?  [y/N] n" "$message"
}

# Replaying it would draw a line reading "yes" and then act on the no that
# `confirm -a` makes of it, which is the one outcome worse than asking again.
test_confirm_keyed_asks_when_the_recorded_answer_is_not_y_or_n() {
  DOTFILES_ANSWERS='tmux=link'
  _answer_with 'y' confirm_keyed tmux 'Install tmux?'
  assertEquals 'tmux=y' "$DOTFILES_ANSWERS"
}

# validate_answers cannot judge a value it has no vocabulary for, so this is the
# only place the entry gets named. Without it a non-interactive run reaches the
# prompt and dies on exhausted input, naming neither the answer nor its source.
test_confirm_keyed_names_the_answer_it_refused_to_replay() {
  DOTFILES_ANSWERS='tmux=yes'
  message=$(echo 'y' | confirm_keyed tmux 'Install tmux?' 2>&1)
  assertContains "should name the entry it ignored" \
    "$message" 'Ignoring "tmux=yes": not a "y" or "n"'
}

#
# choose_keyed
#

test_choose_keyed_records_the_word_of_the_option_chosen() {
  _answer_with '2' choose_keyed claude_skills 'link copy' \
    -d 1 'How?' 'link them' 'copy them'
  assertEquals 'claude_skills=copy' "$DOTFILES_ANSWERS"
}

test_choose_keyed_records_the_default_taken_on_enter() {
  _answer_with '\n' choose_keyed claude_skills 'link copy' \
    -d 1 'How?' 'link them' 'copy them'
  assertEquals 'claude_skills=link' "$DOTFILES_ANSWERS"
}

test_choose_keyed_replays_a_recorded_word_without_reading_stdin() {
  DOTFILES_ANSWERS='claude_skills=copy'
  # stdin says option 1. The recorded copy has to win, which it only can if the
  # keystroke was never read.
  echo '1' | choose_keyed claude_skills 'link copy' \
    -d 1 'How?' 'link them' 'copy them' > /dev/null
  assertEquals "recorded copy should win over stdin" 2 $?
}

# The replayed line names the option, not the number the menu happened to give
# it, and the menu itself stays off screen.
test_choose_keyed_names_the_replayed_option() {
  DOTFILES_ANSWERS='claude_skills=copy'
  message=$(echo '' | choose_keyed claude_skills 'link copy' \
    -d 1 'How?' 'link them' 'copy them')
  assertEquals "  ? How?  copy them" "$message"
}

# A word the options no longer carry is drift from a rename upstream, not an
# answer. Honouring it would pick whatever now sits at that position.
test_choose_keyed_asks_when_the_recorded_word_names_no_option() {
  DOTFILES_ANSWERS='claude_skills=symlink'
  _answer_with '2' choose_keyed claude_skills 'link copy' \
    -d 1 'How?' 'link them' 'copy them'
  assertEquals 'claude_skills=copy' "$DOTFILES_ANSWERS"
}

# Quitting leaves the module unfinished and the deploy non-zero. Recorded, that
# would repeat on every run with no prompt left to take it back.
test_choose_keyed_records_nothing_when_the_user_quits() {
  DOTFILES_ANSWERS='zsh=y'
  _answer_with 'q' choose_keyed claude_skills 'link copy' \
    -d 1 -q 'leave them alone' 'How?' 'link them' 'copy them'
  assertEquals 'zsh=y' "$DOTFILES_ANSWERS"
}

# The words and the options are two lists a caller has to keep in step. When a
# recorded word points past the options, `choose` refuses the replay and asks —
# and the answer given to that prompt is the one that has to be kept, or the
# stale entry survives and the question returns on every run.
test_choose_keyed_records_the_answer_that_replaced_a_refused_replay() {
  DOTFILES_ANSWERS='claude_skills=each'
  _answer_with '2' choose_keyed claude_skills 'link copy each' \
    -d 1 'How?' 'link them' 'copy them'
  assertEquals 'claude_skills=copy' "$DOTFILES_ANSWERS"
}

# A words list shorter than the options list names nothing for the choice made.
# record_answer rejects an empty value by aborting the shell, which would take
# the install down with it, so nothing is recorded instead.
test_choose_keyed_records_nothing_when_no_word_names_the_choice() {
  DOTFILES_ANSWERS='zsh=y'
  _answer_with '3' choose_keyed claude_skills 'link copy' \
    -d 1 'How?' 'link them' 'copy them' 'decide one by one'
  assertEquals "the run should survive an incomplete words list" 3 $?
  assertEquals 'zsh=y' "$DOTFILES_ANSWERS"
}

test_choose_keyed_adds_its_answer_to_the_answers_already_held() {
  DOTFILES_ANSWERS='zsh=y git=y'
  _answer_with '1' choose_keyed pi_skills 'link copy' \
    -d 1 'How?' 'link them' 'copy them'
  assertEquals 'zsh=y git=y pi_skills=link' "$DOTFILES_ANSWERS"
}

#
# Crossing a process boundary
#

# A real `sh -c`, not a spy: the whole point is what survives a fork, and a
# function called in-process would prove nothing.
test_with_answers_lets_another_process_read_the_map() {
  DOTFILES_ANSWERS='claude_skills=copy'
  # shellcheck disable=SC2016 # the child expands it, which is the point
  message=$(with_answers sh -c 'printf "%s" "$DOTFILES_ANSWERS"')
  assertEquals 'claude_skills=copy' "$message"
}

test_with_answers_takes_back_an_answer_recorded_in_another_process() {
  DOTFILES_ANSWERS='zsh=y'
  # shellcheck disable=SC2016 # the child expands it, which is the point
  with_answers sh -c 'printf "pi_skills=copy\n" >> "$DOTFILES_ANSWERS_OUT"'
  assertEquals 'zsh=y pi_skills=copy' "$DOTFILES_ANSWERS"
}

# The child's answer is the newer one, so it wins over what the parent held.
test_with_answers_lets_the_child_replace_an_answer_already_held() {
  DOTFILES_ANSWERS='zsh=y pi_skills=link'
  # shellcheck disable=SC2016 # the child expands it, which is the point
  with_answers sh -c 'printf "pi_skills=copy\n" >> "$DOTFILES_ANSWERS_OUT"'
  assertEquals 'zsh=y pi_skills=copy' "$DOTFILES_ANSWERS"
}

# The read-back runs in the deploy's own process, so record_answer's argument
# check would take the whole run down rather than the one bad line. A line with
# no `=` would otherwise land in the map as its own key and value.
test_with_answers_skips_a_line_that_carries_no_key_and_value() {
  DOTFILES_ANSWERS='zsh=y'
  # shellcheck disable=SC2016 # the child expands it, which is the point
  with_answers sh -c 'printf "pi_skills=\n=copy\nnonsense\ntmux=y\n" >> "$DOTFILES_ANSWERS_OUT"'
  assertTrue "a malformed line should not stop the run" $?
  assertEquals 'zsh=y tmux=y' "$DOTFILES_ANSWERS"
}

test_with_answers_returns_the_status_of_the_command() {
  with_answers sh -c 'exit 3'
  assertEquals "a module that did not finish still reads as unfinished" 3 $?
}

# Left set, it would append the parent's own recording to the file it is
# reading, which on a slow enough loop never ends.
test_with_answers_stops_collecting_once_the_command_is_done() {
  with_answers sh -c ':'
  record_answer tmux y
  assertEquals "the collector should be closed" '' "${DOTFILES_ANSWERS_OUT:-}"
}

#
# Validation
#

test_validate_answers_accepts_a_subset_of_the_declared_keys() {
  DOTFILES_ANSWERS='zsh=y tmux=n'
  validate_answers 'zsh zimfw tmux'
  assertTrue "declared keys should be accepted" $?
}

test_validate_answers_accepts_an_empty_map() {
  validate_answers 'zsh zimfw tmux'
  assertTrue "no answers is a valid map" $?
}

# Silently ignoring a misspelled key would reintroduce exactly the bug that
# naming the answers removes: a run that is quietly different from the one asked
# for, with nothing to show for it.
test_validate_answers_dies_on_a_key_no_prompt_claims() {
  DOTFILES_ANSWERS='zsh=y tmxu=n'
  output=$(validate_answers 'zsh zimfw tmux' 2>&1)
  assertFalse "an unknown key should be fatal" $?
  assertContains "should name the offending key" "$output" "tmxu"
}

test_validate_answers_dies_on_an_answer_with_no_value() {
  DOTFILES_ANSWERS='zsh='
  output=$(validate_answers 'zsh zimfw tmux' 2>&1)
  assertFalse "an unreadable answer should be fatal" $?
  assertContains "should name the offending entry" "$output" "zsh="
}

# The map holds option words as well as y and n, so it cannot tell one prompt's
# vocabulary from another's. A value only the prompt can judge has to reach it.
test_validate_answers_accepts_a_value_that_is_not_y_or_n() {
  DOTFILES_ANSWERS='claude_skills=link'
  validate_answers 'zsh claude_skills'
  assertTrue "an option word is a readable answer" $?
}

# An entry with nothing before the `=` has an empty key. It must still travel
# the paths above as an unclaimed one, so a truncated write gets reported
# instead of an expansion error that names neither the file nor the entry.
test_validate_answers_dies_on_an_entry_with_no_key() {
  DOTFILES_ANSWERS='zsh=y =y'
  output=$(validate_answers 'zsh zimfw tmux' 2>&1)
  assertFalse "an empty key should be fatal" $?
  assertContains "should say which check the entry failed" \
    "$output" 'Unknown answer key'
}

test_drop_unknown_answers_drops_an_entry_with_no_key() {
  # This runs twice: once to capture the message, which requires a subshell,
  # and once with quietly so the rewritten map survives.
  DOTFILES_ANSWERS='zsh=y =y tmux=n'
  output=$(drop_unknown_answers 'zsh zimfw tmux' 2>&1)
  assertTrue "a malformed profile line should not stop the run" $?
  assertContains "should name the entry it dropped" "$output" '=y'

  DOTFILES_ANSWERS='zsh=y =y tmux=n'
  quietly drop_unknown_answers 'zsh zimfw tmux'
  assertEquals "should keep only the claimed answers" 'zsh=y tmux=n' "$DOTFILES_ANSWERS"
}

# Run tests
SHPY_PATH="$THISDIR/../tests/shpy"
export SHPY_PATH
. "$THISDIR/../tests/shpy"
. "$THISDIR/../tests/shpy-shunit2"
. "$THISDIR/../tests/shunit2"
