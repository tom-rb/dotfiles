#!/usr/bin/env sh
#
# Snippets here are single-quoted on purpose: they are shell source destined for
# the pty, so $DOTFILES and $? must survive this file unexpanded.
# shellcheck disable=SC2016

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
  . "$THISDIR/../tests/pty.sh"
}

tearDown() {
  cleanupTestDir
}

# Run a shell snippet against a pty, with the dotfiles utils already sourced.
# Quote the snippet with single quotes so $? and friends reach the pty intact.
# $1: keystrokes to feed (printf %b escapes)
# $2: shell snippet
run_tui() {
  local snippet
  snippet="$SHUNIT_TMPDIR/snippet.sh"
  { echo '. "$DOTFILES/utils/utils.sh"'; echo "${2:?}"; } > "$snippet"
  pty_run "${1?}" "sh $snippet"
}

#
# Tests
#

it_reads_one_keypress_without_enter() {
  out=$(run_tui 'y' 'read_char')

  assertEquals "The keypress alone should be read, with no Enter" 'y' "$out"
}

it_suppresses_echo_when_reading_silently() {
  out=$(run_tui 'y' 'read_char silent')

  assertEquals "A silent read should leave no trace of the keypress" '' "$out"
}

it_restores_terminal_modes_after_reading() {
  out=$(run_tui 'y' 'read_char silent
    modes=$(stty -a | tr " ;" "\n\n")
    echo "$modes" | grep -qx icanon && echo ICANON_ON || echo ICANON_OFF
    echo "$modes" | grep -qx echo && echo ECHO_ON || echo ECHO_OFF')

  assertContains "Canonical mode should be restored" "$out" 'ICANON_ON'
  assertContains "Echo should be restored" "$out" 'ECHO_ON'
}

it_treats_ctrl_d_as_end_of_input_in_raw_mode() {
  # A raw-mode terminal hands Ctrl-D over as an ordinary byte rather than
  # closing the stream, which is the case EOT_CHAR exists for and the only one
  # a piped unit test cannot reach.
  out=$(run_tui '\004' 'read_char; printf "rc=%s" "$?"')

  assertEquals "Ctrl-D should report exhausted input" 'rc=1' "$out"
}

it_reports_exhausted_input_when_nothing_is_typed() {
  out=$(run_tui '' 'read_char; printf "rc=%s" "$?"')

  assertEquals "A closed terminal should report exhausted input" 'rc=1' "$out"
}

it_confirms_with_a_single_keystroke() {
  out=$(run_tui 'n' 'confirm "Install zsh?"; printf "rc=%s" "$?"')

  assertContains "The prompt should offer a yes default" "$out" 'Install zsh? (Y/n)'
  assertContains "A single n should decline" "$out" 'rc=1'
  # die on exhausted input also exits 1, so rc alone cannot tell a declined
  # prompt from a keystroke that never arrived.
  assertNotContains "The keystroke should have answered the prompt" "$out" 'Aborted'
}

it_takes_the_default_when_enter_is_pressed() {
  # Enter arrives as CR from a terminal; icrnl turns it into the newline that
  # confirm reads as "take the default".
  out=$(run_tui '\r' 'confirm "Install zsh?"; printf "rc=%s" "$?"')

  assertContains "Enter should accept the yes default" "$out" 'rc=0'
  assertNotContains "Enter should have answered the prompt" "$out" 'Aborted'
}

# shellcheck source=../tests/shunit2
. shunit2
