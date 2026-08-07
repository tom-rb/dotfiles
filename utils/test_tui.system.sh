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

  assertContains "The prompt should offer a yes default" "$out" 'Install zsh?  [Y/n]'
  assertContains "A single n should decline" "$out" 'rc=1'
  # die on exhausted input also exits 1, so rc alone cannot tell a declined
  # prompt from a keystroke that never arrived.
  assertNotContains "The keystroke should have answered the prompt" "$out" 'Aborted'
}

it_press_any_key_needs_no_enter_and_moves_to_next_line() {
  out=$(run_tui 'y' 'press_any_key "Notice"; echo "next line"')

  assertContains "The message should be printed" "$out" 'Notice'
  assertNotContains "The keypress itself should not be echoed" "$out" 'key)y'
  # A literal newline between the two lines is what proves the cursor moved,
  # rather than the next output gluing onto the notice.
  assertContains "The next line should start on its own line" \
    "$out" "$(printf '(press any key)\nnext line')"
}

it_takes_the_default_when_enter_is_pressed() {
  # Enter arrives as CR from a terminal; icrnl turns it into the newline that
  # confirm reads as "take the default".
  out=$(run_tui '\r' 'confirm "Install zsh?"; printf "rc=%s" "$?"')

  assertContains "Enter should accept the yes default" "$out" 'rc=0'
  assertNotContains "Enter should have answered the prompt" "$out" 'Aborted'
}

#
# tui_ok / NO_COLOR
#

it_emits_the_green_sgr_sequence_on_a_terminal() {
  # PTY_KEEP_ESCAPES asks the harness to leave color codes in the capture
  # instead of normalizing them away, since this test's whole point is to
  # see them.
  out=$(PTY_KEEP_ESCAPES=1 run_tui '' 'tui_ok "zsh installed"')

  assertContains "A tty should get the green SGR code" "$out" "$(printf '\033[32m')"
}

it_emits_no_escape_sequences_on_a_terminal_with_no_color_set() {
  out=$(NO_COLOR=1 PTY_KEEP_ESCAPES=1 run_tui '' 'tui_ok "zsh installed"')

  assertNotContains "NO_COLOR should suppress the SGR code" "$out" "$(printf '\033[')"
}

#
# tui_step
#

it_rewrites_the_step_line_in_place_leaving_one_line_on_screen() {
  # The default (non-raw) capture strips every \r, including the mid-line one
  # tui_ok writes to rewrite the step: with no \n between them either, the
  # step and its result land concatenated on a single captured line — which
  # is exactly what "no extra newline was ever emitted" looks like from here.
  out=$(run_tui '' 'tui_step "installing zsh"; tui_ok "zsh installed"')

  assertContains "The result should be visible" "$out" "zsh installed"
  assertEquals "Exactly one line should remain on screen" 1 "$(printf '%s\n' "$out" | wc -l)"
}

it_leaves_no_residue_when_a_long_step_is_closed_by_a_short_result() {
  # Raw capture (no \r stripped) so the padding tui_ok writes after \r can be
  # measured directly. NO_COLOR keeps SGR codes out of the byte count, since
  # the padding math in tui.sh is on message length, not formatted width.
  cr=$(printf '\r')
  raw=$(NO_COLOR=1 PTY_KEEP_ESCAPES=1 run_tui '' \
    'tui_step "building tmux from source (a few minutes)…"; tui_ok "tmux 3.5a installed"')
  before=${raw%%"$cr"*}
  after=${raw#*"$cr"}

  # Assert the \r first: without it both halves collapse to the whole capture
  # and the width comparison below passes for free.
  assertContains "A tty rewrite goes through \\r" "$raw" "$cr"
  assertContains "The result should be visible" "$after" "tmux 3.5a installed"
  assertTrue "The rewritten segment should pad out to at least the step's width" \
    "[ ${#after} -ge ${#before} ]"
}

#
# Cursor
#

it_hides_the_cursor_while_a_step_is_open() {
  hide=$(printf '\033[?25l') show=$(printf '\033[?25h')
  raw=$(PTY_KEEP_ESCAPES=1 run_tui '' 'tui_step "installing zsh"; tui_ok "zsh installed"')

  assertContains "The step should take the cursor away" "$raw" "$hide"
  assertContains "The step's message should still be there to read" "$raw" 'installing zsh'
  # Anything after the last hide is what the terminal is left with, so a show
  # in there is the cursor coming back before the script hands the tty over.
  assertContains "The Outcome should give the cursor back" "${raw##*"$hide"}" "$show"
}

it_gives_the_cursor_back_when_a_task_fails() {
  show=$(printf '\033[?25h')
  raw=$(PTY_KEEP_ESCAPES=1 run_tui '' \
    'tui_task "installing zsh" --ok "zsh installed" --fail "zsh install failed" -- false')

  assertContains "The failure should be reported" "$raw" 'zsh install failed'
  assertContains "A failed task should still give the cursor back" "$raw" "$show"
}

it_gives_the_cursor_back_when_a_step_is_killed() {
  show=$(printf '\033[?25h')
  # SIGTERM stands in for the Ctrl-C this guards against: pty_run starts the
  # session in the background, and a background command inherits SIGINT
  # ignored, so an INT trap cannot even be installed there. Both signals reach
  # the same handler.
  raw=$(PTY_KEEP_ESCAPES=1 run_tui '' 'tui_step "installing zsh"
    kill -TERM $$
    printf "NOT_REACHED"')

  assertContains "A killed step should not keep the cursor" "$raw" "$show"
  assertNotContains "The signal should still stop the script" "$raw" 'NOT_REACHED'
}

it_hides_no_cursor_on_a_terminal_with_no_color_set() {
  raw=$(NO_COLOR=1 PTY_KEEP_ESCAPES=1 run_tui '' \
    'tui_step "installing zsh"; tui_ok "zsh installed"')

  assertNotContains "NO_COLOR should mean no escape sequences at all" \
    "$raw" "$(printf '\033[')"
}

#
# tui_task
#

it_keeps_the_task_line_on_one_line_while_a_quiet_command_runs_behind_it() {
  # Same "one captured line" trick as the tui_step test above: with the
  # command's stdout hidden and no extra newline emitted, the task and its
  # Outcome should still land concatenated on a single line.
  out=$(run_tui '' 'tui_task "listing root" --ok "listed root" --fail "could not list root" -- ls /')

  assertContains "The result should be visible" "$out" "listed root"
  assertEquals "Exactly one line should remain on screen" 1 "$(printf '%s\n' "$out" | wc -l)"
}

# @image: base
it_shows_the_sudo_password_prompt_while_capturing_stderr() {
  # sudo asks for its password on the terminal device, not on the stderr
  # tui_task captures, which is what makes capturing safe. Every command amy may
  # sudo is NOPASSWD though, and sudo-rs (ubuntu's sudo) refuses anything else
  # outright without ever asking, so grant a password-requiring entry first,
  # through the one file editor amy may run as root. The container is thrown
  # away after the test.
  sudo sed -i '$a amy ALL = /usr/bin/id' /etc/sudoers.d/amy

  # amy has no password, so sudo asks, takes the Ctrl-D as the end of the
  # answer and gives up. The failure is not the point — being asked is.
  out=$(run_tui '\004' 'tui_task "checking sudo" --ok "sudo works" --fail "sudo refused" \
    -- sh -c "sudo -p PROMPT-MARKER: id; echo STDERR-MARKER >&2; exit 1"')

  assertContains "The failure should be reported" "$out" '✗ sudo refused'
  # Everything before the ✗ was written while the task line was still open, so
  # a prompt found there is one tui_task let through to the terminal untouched.
  assertContains "The password prompt should reach the terminal as it is asked" \
    "${out%%✗*}" 'PROMPT-MARKER'
  assertContains "The command's stderr should be replayed under it, indented" \
    "$out" "$(printf '\n    STDERR-MARKER')"
  assertContains "And the way to see the rest" "$out" 'Re-run with DEBUG=1 for full output.'
}

# shellcheck source=../tests/shunit2
. shunit2
