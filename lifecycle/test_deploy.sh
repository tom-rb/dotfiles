#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
}

setUp() {
  # Source deploy.sh with a defined DOTFILES path
  DOTFILES="$(CDPATH='' cd -- "$THISDIR/.." >/dev/null && pwd -P)" \
    dotfiles_dont_run=1 . "$THISDIR/../deploy.sh"
  # Keep the deploy profile these tests write inside the temp dir
  # shellcheck disable=SC2034 # read by the deploy.sh sourced above
  XDG_STATE_HOME=${SHUNIT_TMPDIR:?}/state
  DOTFILES_ANSWERS=''
}

tearDown() {
  cleanupSpies
  cleanupTestDir
}

#
# Tests
#

test_deploy_wizard_installs_basic_packages() {
  createSpy -u -r "$SHUNIT_TRUE" check_supported_pm
  # Basic packages not installed
  createSpy -u -r "$SHUNIT_FALSE" command_exists
  createSpy -u install_from_pm
  createSpy -u start_module_wizard
  createSpy -u activate_asdf

  message="$(yes | deploy_wizard)"

  assertContains "Expected continuation message" \
    "$message" "Basic packages needed:"
  assertCallCount install_from_pm 1
  # The step line and its ✓ are install_from_pm's own doing; utils/test_pm.sh
  # covers them. Here only the label it was asked to report under matters.
  assertCalledWith install_from_pm --as "basic packages" \
    --die "Couldn't install basic packages" -- wget tar gzip
  # Once unconditionally at startup, once more after a fresh asdf install.
  assertCallCount activate_asdf 2
  assertCallCount start_module_wizard 7
  assertCalledWith start_module_wizard zsh
  assertCalledWith start_module_wizard zimfw
  assertCalledWith start_module_wizard asdf
  assertCalledWith start_module_wizard tmux
  assertCalledWith start_module_wizard git
  assertCalledWith start_module_wizard pi
  assertCalledWith start_module_wizard claude
}

test_deploy_wizard_skips_basic_packages_if_installed() {
  # Basic packages are installed
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  createSpy -u start_module_wizard
  createSpy -u activate_asdf

  message="$(yes | deploy_wizard)"

  assertNotContains "Continuation message not expected" \
    "$message" "Basic packages needed:"
  assertCallCount install_from_pm 0
  assertCallCount start_module_wizard 7
  assertCalledWith start_module_wizard zsh
  assertCalledWith start_module_wizard zimfw
  assertCalledWith start_module_wizard asdf
  assertCalledWith start_module_wizard tmux
  assertCalledWith start_module_wizard git
  assertCalledWith start_module_wizard pi
  assertCalledWith start_module_wizard claude
}

test_deploy_wizard_skips_zimfw_when_zsh_declined() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  createSpy -u start_module_wizard

  # Decline zsh; accept the rest. confirm reads one byte per call.
  printf 'n\ny\ny\ny\ny\n' | deploy_wizard >/dev/null

  assertCallCount start_module_wizard 4
  assertCalledWith start_module_wizard tmux
  assertCalledWith start_module_wizard git
  assertCalledWith start_module_wizard pi
  assertCalledWith start_module_wizard claude
}

test_deploy_wizard_calls_activate_asdf_even_when_zsh_declined() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  createSpy -u start_module_wizard
  createSpy -u activate_asdf

  # Decline zsh; accept the rest. confirm reads one byte per call.
  printf 'n\ny\ny\ny\ny\n' | deploy_wizard >/dev/null

  assertCalledOnceWith activate_asdf
}

test_deploy_wizard_numbers_module_sections() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  createSpy -u start_module_wizard
  createSpy -u activate_asdf

  message="$(yes | deploy_wizard)"

  assertContains "Expected first module section" "$message" "▸ zsh  (1/7)"
  assertContains "Expected last module section" "$message" "▸ claude  (7/7)"
}

test_deploy_wizard_keeps_module_numbers_when_zsh_declined() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  createSpy -u start_module_wizard

  # Decline zsh; accept the rest. confirm reads one byte per call.
  message="$(printf 'n\ny\ny\ny\ny\n' | deploy_wizard)"

  # zimfw and asdf were never offered, but tmux keeps its own position.
  assertContains "Expected tmux to keep its position" "$message" "▸ tmux  (4/7)"
  assertNotContains "zimfw was not offered" "$message" "▸ zimfw"
}

#
# Deploy profile
#

# Run the wizard in a subshell so a die inside cannot take the test runner with
# it, feeding stdin from a file rather than a pipe. The spies record to files, so
# they are still readable afterwards, as is the profile the run writes.
# $1: (optional) keystrokes to answer with, escapes interpreted
_deploy_with() {
  printf '%b' "${1:-}" > "${SHUNIT_TMPDIR:?}/answers"
  ( deploy_wizard ) < "$SHUNIT_TMPDIR/answers" > "$SHUNIT_TMPDIR/output" 2>&1
}

_deploy_output() {
  cat "${SHUNIT_TMPDIR:?}/output" 2>/dev/null
}

_saved_profile() {
  cat "$(get_deploy_profile_path)" 2>/dev/null
}

# Writes $1 as the profile a previous deploy would have left behind.
_given_saved_profile() {
  local path
  path=$(get_deploy_profile_path)
  mkdir -p "${path%/*}"
  printf '%s\n' "${1:?}" > "$path"
}

# Nobody has said what to run, so the last deploy's answers stand in.
test_deploy_wizard_replays_the_saved_profile() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  createSpy -u start_module_wizard
  createSpy -u activate_asdf

  _given_saved_profile 'zsh=y
zimfw=n
asdf=n
tmux=y
git=n
pi=n
claude=n'
  unset DOTFILES_ANSWERS
  _deploy_with

  assertCallCount start_module_wizard 2
  assertCalledWith start_module_wizard zsh
  assertCalledWith start_module_wizard tmux
}

# Every question answering itself is startling if you do not know a profile
# exists, and there is no way to guess how to get the questions back. Say both,
# once, only on a run that actually replayed something.
test_deploy_wizard_says_where_the_replayed_answers_came_from() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  createSpy -u start_module_wizard
  createSpy -u activate_asdf

  _given_saved_profile 'zsh=n
zimfw=n
asdf=n
tmux=n
git=n
pi=n
claude=n'
  unset DOTFILES_ANSWERS
  _deploy_with

  assertContains "should name the profile it replayed" \
    "$(_deploy_output)" "$(get_deploy_profile_path)"
  assertContains "should say how to answer again" \
    "$(_deploy_output)" "DOTFILES_ANSWERS=''"
}

test_deploy_wizard_says_nothing_about_a_profile_it_did_not_replay() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  createSpy -u start_module_wizard
  createSpy -u activate_asdf

  _deploy_with 'nnnnnnn'

  assertNotContains "a first run has nothing to explain" \
    "$(_deploy_output)" "DOTFILES_ANSWERS=''"
}

# A map that is set, even to nothing, is the caller's word and outranks the
# profile — which is how `dotfiles deploy` asks for a fresh interview.
test_deploy_wizard_asks_everything_when_handed_an_empty_map() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  createSpy -u start_module_wizard
  createSpy -u activate_asdf

  _given_saved_profile 'zsh=y
zimfw=y
asdf=y
tmux=y
git=y
pi=y
claude=y'
  DOTFILES_ANSWERS=''
  _deploy_with 'nnnnn'

  assertCallCount start_module_wizard 0
}

test_deploy_wizard_runs_exactly_the_modules_the_profile_records() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  createSpy -u start_module_wizard
  createSpy -u activate_asdf

  DOTFILES_ANSWERS='zsh=y zimfw=n asdf=n tmux=y git=n pi=n claude=y'
  # No keystrokes at all: every question is already answered.
  _deploy_with

  assertCallCount start_module_wizard 3
  assertCalledWith start_module_wizard zsh
  assertCalledWith start_module_wizard tmux
  assertCalledWith start_module_wizard claude
}

test_deploy_wizard_saves_the_answers_it_was_given() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  createSpy -u start_module_wizard
  createSpy -u activate_asdf

  # Accept everything, one keystroke per prompt.
  _deploy_with 'yyyyyyy'

  assertEquals 'zsh=y
zimfw=y
asdf=y
tmux=y
git=y
pi=y
claude=y' "$(_saved_profile)"
}

# A pull can add a module the profile predates. That module's question is the
# one thing an otherwise replayed run still asks, and the answer joins the
# profile so it is only ever asked once.
test_deploy_wizard_asks_about_a_module_the_profile_predates() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  createSpy -u start_module_wizard
  createSpy -u activate_asdf

  DOTFILES_ANSWERS='zsh=y zimfw=n asdf=n tmux=n git=n pi=n'
  # One keystroke, for the one unanswered question.
  _deploy_with 'y'

  # assertCalledWith walks the invocations in order, so zsh comes first.
  assertCallCount start_module_wizard 2
  assertCalledWith start_module_wizard zsh
  assertCalledWith start_module_wizard claude
  assertContains "the new answer should join the profile" \
    "$(_saved_profile)" 'claude=y'
}

# Answers, not outcomes. Recording what succeeded would turn one bad network day
# into a permanently shrunken install.
test_deploy_wizard_records_a_module_that_failed() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  createSpy -u -r "$SHUNIT_FALSE" start_module_wizard
  createSpy -u activate_asdf

  # zsh is accepted and fails, which takes zimfw and asdf off the table; the
  # four questions after it are still asked.
  _deploy_with 'yyyyy'

  assertContains "a module that failed is still what was asked for" \
    "$(_saved_profile)" 'zsh=y'
}

# The profile is a record, not a request. A key it holds for a module the repo
# no longer ships is drift, and refusing to deploy over it would strand every
# user who already has a profile behind an upstream rename.
test_deploy_wizard_drops_a_profile_key_for_a_module_that_is_gone() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  createSpy -u start_module_wizard
  createSpy -u activate_asdf

  # `nvim` is a module this repo has since renamed or dropped: the profile still
  # holds an answer for it, and no prompt in the run claims it.
  _given_saved_profile 'zsh=y
nvim=y'
  unset DOTFILES_ANSWERS
  # zsh replays; the six modules that do exist are still asked about.
  _deploy_with 'nnnnnn'

  assertTrue "a module that is gone should not stop the run" $?
  assertCallCount start_module_wizard 1
  assertCalledWith start_module_wizard zsh
  assertContains "should say which answer it dropped" "$(_deploy_output)" 'nvim'
  assertNotContains "the dropped key should not be written back" \
    "$(_saved_profile)" 'nvim'
}

# A map handed in by a caller is a request, and a key no prompt claims can only
# be a typo — which stays fatal, unlike the drift above.
test_deploy_wizard_refuses_a_map_with_a_key_no_prompt_claims() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  createSpy -u start_module_wizard
  createSpy -u activate_asdf

  DOTFILES_ANSWERS='zsh=y tmxu=n'
  output=$(deploy_wizard < /dev/null 2>&1)

  assertFalse "an unknown key should stop the run" $?
  assertContains "should name the offending key" "$output" 'tmxu'
  assertCallCount start_module_wizard 0
}

test_deploy_wizard_ends_with_epilogue() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  createSpy -u start_module_wizard
  createSpy -u activate_asdf

  message="$(yes | deploy_wizard)"

  # shellcheck disable=SC2016 # the backticks are literal, quoting a command
  assertContains "Expected closing epilogue" \
    "$message" 'Done. Restart your shell with `exec zsh`'
}

test_deploy_wizard_epilogue_drops_exec_zsh_when_zsh_missing() {
  createSpy -u -r "$SHUNIT_TRUE" check_supported_pm
  # zsh (like every other command) is not installed
  createSpy -u -r "$SHUNIT_FALSE" command_exists
  createSpy -u install_from_pm
  createSpy -u start_module_wizard
  createSpy -u activate_asdf

  message="$(yes | deploy_wizard)"

  assertContains "Expected shell-agnostic epilogue" \
    "$message" 'Done. Restart your shell to pick up the changes.'
  assertNotContains "Command not expected without zsh" "$message" 'exec zsh'
}

#
# Modules that don't complete
#

# A module that stops early — a failed step, or one the user cancelled — is
# reported by name, since the module's own ✗ (when it has one) doesn't say
# which module it came from.
test_deploy_wizard_reports_a_module_that_did_not_complete() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  createSpy -u -r 1 -r 0 start_module_wizard
  createSpy -u activate_asdf

  message="$(yes | deploy_wizard 2>&1)"

  assertContains "Expected the module to be named" \
    "$message" "✗ zsh did not complete"
}

test_deploy_wizard_skips_zsh_dependents_when_zsh_does_not_complete() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  createSpy -u -r 1 -r 0 start_module_wizard
  createSpy -u activate_asdf

  message="$(yes | deploy_wizard 2>&1)"

  # zimfw and asdf write into the dotfiles zsh never laid down.
  assertNotContains "zimfw depends on zsh" "$message" "▸ zimfw"
  assertNotContains "asdf depends on zsh" "$message" "▸ asdf"
  # The modules that don't are still offered. assertCalledWith walks the calls
  # in order, so zsh's own call is claimed first.
  assertCallCount start_module_wizard 5
  assertCalledWith start_module_wizard zsh
  assertCalledWith start_module_wizard tmux
  assertCalledWith start_module_wizard git
  assertCalledWith start_module_wizard pi
  assertCalledWith start_module_wizard claude
}

test_deploy_wizard_keeps_going_after_an_independent_module_fails() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  # tmux is the fourth module asked about; the last -r repeats from then on.
  createSpy -u -r 0 -r 0 -r 0 -r 1 -r 0 start_module_wizard
  createSpy -u activate_asdf

  message="$(yes | deploy_wizard 2>&1)"

  assertContains "Expected the failed module to be named" \
    "$message" "✗ tmux did not complete"
  # assertCalledWith walks the calls in order, so the three before tmux are
  # claimed first.
  assertCallCount start_module_wizard 7
  assertCalledWith start_module_wizard zsh
  assertCalledWith start_module_wizard zimfw
  assertCalledWith start_module_wizard asdf
  assertCalledWith start_module_wizard tmux
  assertCalledWith start_module_wizard git
  assertCalledWith start_module_wizard pi
  assertCalledWith start_module_wizard claude
}

test_deploy_wizard_epilogue_names_every_module_that_did_not_complete() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  # zsh fails, so zimfw and asdf are never asked and tmux is the second call.
  createSpy -u -r 1 -r 1 -r 0 start_module_wizard
  createSpy -u activate_asdf

  message="$(yes | deploy_wizard 2>&1)"

  assertContains "Expected an honest closing line" \
    "$message" "! Done, but zsh and tmux did not complete."
  assertNotContains "A run with failures is not a clean one" "$message" "✓ Done"
}

test_deploy_wizard_fails_when_a_module_did_not_complete() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  createSpy -u -r 1 -r 0 start_module_wizard
  createSpy -u activate_asdf

  yes | deploy_wizard >/dev/null 2>&1

  assertFalse "Error code expected" $?
}

test_deploy_wizard_succeeds_when_every_module_completes() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  createSpy -u start_module_wizard
  createSpy -u activate_asdf

  yes | deploy_wizard >/dev/null 2>&1

  assertTrue "Success code expected" $?
}

test_deploy_wizard_dies_if_basic_packages_fail() {
  createSpy -u -r "$SHUNIT_TRUE" check_supported_pm
  # Basic packages not installed
  createSpy -u -r "$SHUNIT_FALSE" command_exists
  # Installing packages fail. Spied one level down, so the real install_from_pm
  # runs and the --die it was handed is what stops the deploy.
  createSpy -u -o 'apt-get' get_supported_pm
  createSpy -u -r "$SHUNIT_FALSE" _install_from_pm

  message="$(yes | deploy_wizard 2>&1)"

  assertFalse "Error code expected" $?
  assertContains "Expected dying message" \
    "$message" "Couldn't install basic packages"
}

# Run tests
SHPY_PATH="$THISDIR/../tests/shpy"
export SHPY_PATH
. "$THISDIR/../tests/shpy"
. "$THISDIR/../tests/shpy-shunit2"
. "$THISDIR/../tests/shunit2"
