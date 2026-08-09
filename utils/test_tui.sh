#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
  DOTFILES="$(get_abs_path "$THISDIR/..")"
}

setUp() {
  . "$THISDIR/utils.sh"
  # `DEBUG=1 tui_task …` is a variable-assignment prefix on a *function* call,
  # which POSIX leaves unspecified: dash drops it afterwards, bash in sh mode
  # keeps it for the rest of the shell. Clear it here so a DEBUG test cannot
  # leak into the ones that follow.
  DEBUG=''
}

tearDown() {
  cleanupSpies
  cleanupTestDir
  # Undo a skip declared by a single test, so it stops there.
  endSkipping
}

# True when `( set -e; failing-command )` reports the command's own status.
# bash 4.2 in sh mode (amazonlinux-2's /bin/sh) reports 1 instead, and no
# wrapper can recover a status the shell has already thrown away.
_shell_keeps_errexit_status() {
  [ "$(sh -c '( set -e; sh -c "exit 42" ); echo $?')" = 42 ]
}

# A command for tui_task to wrap, standing in for the third-party tools that
# diagnose on stderr. Each line is written verbatim, so a test shows only what
# it varies.
# $1: exit status; $2+: one stderr line each
_noisy_command() {
  local status
  status=${1:?}
  shift
  if [ $# -gt 0 ]; then
    printf '%s\n' "$@" >&2
  fi
  return "$status"
}

# An --ok-cmd stand-in: wording a caller can only know once the command it
# describes has succeeded.
_deferred_message() {
  echo "zsh 5.9 installed"
}


#
# read_char
#

test_read_char_from_pipe() {
  char=$(echo 'a' | read_char)
  assertEquals "a" "$char"
}

test_read_char_silent_from_pipe() {
  char=$(echo 'a' | read_char silent)
  # Used for "waiting for input" case
  assertEquals "" "$char"
}

test_read_char_reports_eof_as_failure() {
  char=$(printf '' | read_char)
  assertFalse "Exhausted input should fail" $?
  assertEquals "" "$char"
}

test_read_char_reports_eof_as_failure_when_silent() {
  printf '' | read_char silent
  assertFalse "Exhausted input should fail in silent mode too" $?
}

test_read_char_reports_ctrl_d_as_end_of_input() {
  # What a raw-mode terminal sends instead of closing the stream; without this
  # the wizard would take it for an invalid keypress and re-prompt forever.
  char=$(printf '\004' | read_char)
  assertFalse "Ctrl-D should be reported as failure" $?
  assertEquals "" "$char"
}

test_read_char_treats_newline_as_input_not_eof() {
  # Both a newline keypress and EOF echo nothing, so only the return code can
  # tell them apart. This is what keeps Enter meaning "take the default".
  char=$(printf '\n' | read_char)
  assertTrue "A newline is a keypress, not EOF" $?
  assertEquals "" "$char"
}

#
# confirm
#

test_confirm_has_default_message() {
  message=$(yes | confirm)
  assertEquals "  ? Continue?  [Y/n]" "${message% *}"
}

test_confirm_has_default_no_message() {
  message=$(yes | confirm -n)
  assertEquals "  ? Continue?  [y/N]" "${message% *}"
}

test_confirm_trims_given_message() {
  message=$(yes | confirm 'Sure?   ')
  assertEquals "  ? Sure?  [Y/n] y" "${message}"

  message=$(yes | confirm -n 'Not sure?   ')
  assertEquals "  ? Not sure?  [y/N] y" "${message}"
}

test_confirm_returns_ok_on_y() {
  echo 'y' | confirm > /dev/null
  assertTrue "y should return ok" $?

  echo 'Y' | confirm > /dev/null
  assertTrue "Y should return ok" $?
}

test_confirm_returns_error_on_n() {
  echo 'n' | confirm > /dev/null
  assertFalse "n should return error" $?

  echo 'N' | confirm > /dev/null
  assertFalse "N should return error" $?
}

test_confirm_asks_for_correct_input() {
  # Send not valid answer 'x' first
  output=$(echo 'xy' | confirm)
  assertTrue "y should be accepted" $?

  assertContains "Confirmation output expected" \
    "$output" "Choose y or n"
}

test_confirm_returns_yes_on_enter() {
  echo '' | confirm > /dev/null
  assertTrue "Enter should return true" $?
}

test_confirm_returns_no_on_enter() {
  echo '' | confirm -n > /dev/null
  assertFalse "Enter should return false" $?

  echo '' | confirm -n 'Custom msg' > /dev/null
  assertFalse "Enter should return false" $?
}

test_confirm_echoes_right_inputs() {
  message=$(echo 'y' | confirm)
  # message ends with y
  assertEquals "y" "${message##*[!y]}"

  message=$(echo 'N' | confirm)
  # message ends with N
  assertEquals "N" "${message##*[!N]}"
}

test_confirm_write_y_for_enter() {
  message=$(echo '' | confirm)
  assertEquals "y" "${message##*[!y]}"
}

test_confirm_aborts_when_input_is_exhausted() {
  # Silently answering the default here would mean an under-fed scripted run
  # accepts every remaining prompt, so exhausted input has to be fatal.
  output=$(printf '' | confirm 'Install zsh?' 2>&1)
  assertFalse "Should not consent at EOF" $?
  assertContains "Should say why it aborted" "$output" "input ended"
  assertContains "Should name the unanswered prompt" "$output" "Install zsh?"
}

#
# confirm -a (already answered)
#

test_confirm_renders_a_given_answer_as_if_it_had_been_typed() {
  message=$(printf '' | confirm -n -a n 'Install tmux?')
  assertEquals "  ? Install tmux?  [y/N] n" "$message"

  message=$(printf '' | confirm -a y 'Install tmux?   ')
  assertEquals "  ? Install tmux?  [Y/n] y" "$message"
}

test_confirm_returns_the_answer_it_was_given() {
  printf '' | confirm -a y 'Install tmux?' > /dev/null
  assertTrue "a given y should return ok" $?

  printf '' | confirm -a n 'Install tmux?' > /dev/null
  assertFalse "a given n should return error" $?
}

# A given answer costs no input, so the prompt after it still finds its own
# keystroke waiting.
test_confirm_does_not_read_stdin_for_a_given_answer() {
  output=$(printf 'y' | { confirm -a n 'Install tmux?'; confirm 'Install zsh?'; })
  assertTrue "the next prompt should have found its keystroke" $?
  assertEquals "  ? Install tmux?  [Y/n] n
  ? Install zsh?  [Y/n] y" "$output"
}

#
# press_any_key
#

test_press_any_key_prints_message_and_newline() {
  output=$(echo 'y' | press_any_key "Notice")
  assertEquals "  ! Notice (press any key)" "$output"
}

test_press_any_key_consumes_exactly_one_byte() {
  # If it consumed more than one byte, "second" would be partially eaten
  # instead of being left on stdin for whatever reads next.
  output=$(printf 'asecond' | { press_any_key "Msg" > /dev/null; cat; })
  assertEquals "second" "$output"
}

test_press_any_key_echoes_nothing_of_the_keypress() {
  # A letter absent from the "(press any key)" suffix, so finding it could only
  # mean the keypress was echoed.
  output=$(echo 'z' | press_any_key "Msg")
  assertNotContains "The keypress itself should not be echoed" "$output" "z"
}

test_press_any_key_aborts_when_input_is_exhausted() {
  output=$(printf '' | press_any_key "Install basic packages" 2>&1)
  assertFalse "Should not continue at EOF" $?
  assertContains "Should say why it aborted" "$output" "input ended"
  assertContains "Should name the unanswered prompt" "$output" "Install basic packages"
}

#
# choose
#

test_choose_print_the_options() {
  output=$(echo 1 | choose "Which one?" "first option" second)
  assertContains "Should print first option" \
    "$output" "1) first option"
  assertContains "Should print second option" \
    "$output" "2) second"
}

test_choose_prints_the_question() {
  output=$(echo 1 | choose "Which one?" first second)
  assertContains "Should ask before listing" "$output" "  ? Which one?"
}

test_choose_marks_the_default_option() {
  output=$(echo 1 | choose -d 2 "Which one?" first second)
  assertContains "Should mark the default" "$output" "2) second  (default)"
  assertNotContains "Should mark only the default" "$output" "1) first  (default)"
}

test_choose_labels_the_quit_option() {
  output=$(echo 1 | choose -q "leave it alone" "Which one?" first second)
  assertContains "Should use the given quit label" "$output" "q) leave it alone"
}

test_choose_returns_valid_choice_number() {
  output=$(echo 1 | choose "Which one?" first second)
  assertEquals 1 $?
  assertEquals "Should echo answer" "1" "${output##*[!1]}"

  output=$(echo 2 | choose "Which one?" first second)
  assertEquals 2 $?
  assertEquals "Should echo answer" "2" "${output##*[!2]}"
}

test_choose_returns_zero_when_canceled_with_q() {
  output=$(echo q | choose "Which one?" first second)
  assertEquals 0 $?
  assertEquals "Should echo the keypress" "q" "${output##*[!q]}"
}

test_choose_returns_default_on_enter() {
  output=$(printf '\n' | choose -d 2 "Which one?" first second third)
  assertEquals 2 $?
  assertEquals "Should echo default answer" "2" "${output##*[!2]}"
}

test_choose_with_default_still_accepts_explicit_choice() {
  output=$(echo 3 | choose -d 1 "Which one?" first second third)
  assertEquals 3 $?
  assertEquals "Should echo explicit answer" "3" "${output##*[!3]}"
}

test_choose_with_default_still_cancels_on_q() {
  output=$(echo q | choose -d 1 "Which one?" first second)
  assertEquals 0 $?
  assertEquals "Should echo the keypress" "q" "${output##*[!q]}"
}

test_choose_aborts_when_input_is_exhausted() {
  # Without a default this used to busy-loop forever on exhausted input.
  output=$(printf '' | choose "Which one?" first second 2>&1)
  assertFalse "Should not loop forever at EOF" $?
  assertContains "Should say why it aborted" "$output" "input ended"
}

test_choose_aborts_at_eof_even_with_a_default() {
  # A default answers Enter, not a stdin that has run out.
  output=$(printf '' | choose -d 1 "Which one?" first second 2>&1)
  assertFalse "Should not fall back to the default at EOF" $?
  assertContains "Should say why it aborted" "$output" "input ended"
}

test_choose_dont_print_anything_on_invalid_answer() {
  output=$(printf '%s\n%d' "034_all_invalid_except:" 1 | choose "Which one?" first second)
  assertEquals 1 $?
  assertEquals "  ? Which one?|      1) first|      2) second|      q) quit|    › 1|" \
    "$(echo "$output" | tr '\n' '|')"
}

#
# prompt_line
#

test_prompt_line_reads_input_into_named_var() {
  answer=
  answer=$(echo "Alice" | { prompt_line "Name: " answer > /dev/null; echo "$answer"; })
  assertEquals "Alice" "$answer"
}

test_prompt_line_prints_the_prompt_message_behind_a_cursor() {
  message=$(echo "ignored" | prompt_line "Name: " answer)
  assertEquals "    › Name: " "$message"
}

test_prompt_line_prints_a_bare_cursor_without_a_message() {
  message=$(echo "ignored" | prompt_line "" answer)
  assertEquals "    › " "$message"
}

test_prompt_line_trims_leading_and_trailing_whitespace() {
  answer=$(echo "  spaced value  " | { prompt_line "> " answer > /dev/null; echo "$answer"; })
  assertEquals "spaced value" "$answer"
}

test_prompt_line_sets_empty_when_input_is_blank() {
  answer=PRESET
  answer=$(echo "" | { prompt_line "> " answer > /dev/null; echo "$answer"; })
  assertEquals "" "$answer"
}

test_prompt_line_aborts_when_input_is_exhausted() {
  # A blank line is an answer; a closed stream is not, and recording it as one
  # would hand the caller a value the user never typed.
  output=$(printf '' | prompt_line "Name: " answer 2>&1)
  assertFalse "Should not report an empty answer at EOF" $?
  assertContains "Should say why it aborted" "$output" "input ended"
  assertContains "Should name the unanswered prompt" "$output" "Name: "
}

#
# prompt_new_path
#

test_prompt_new_path_creates_dir_and_sets_var() {
  target="$SHUNIT_TMPDIR/newdir"
  result=$(printf '%s\ny\n' "$target" \
    | { prompt_new_path "Use %s?" result > /dev/null; echo "$result"; })
  assertEquals "$target" "$result"
  assertTrue "Directory should have been created" "[ -d '$target' ]"
}

test_prompt_new_path_strips_trailing_slash() {
  target="$SHUNIT_TMPDIR/trailing"
  result=$(printf '%s/\ny\n' "$target" \
    | { prompt_new_path "Use %s?" result > /dev/null; echo "$result"; })
  assertEquals "$target" "$result"
}

test_prompt_new_path_expands_shell_variables() {
  base="$SHUNIT_TMPDIR/expand"
  # shellcheck disable=SC2016 # literal $base on purpose: prompt_new_path's eval expands it
  result=$(printf '$base/sub\ny\n' \
    | { prompt_new_path "Use %s?" result > /dev/null; echo "$result"; })
  assertEquals "$base/sub" "$result"
}

test_prompt_new_path_reprompts_when_path_exists() {
  existing="$SHUNIT_TMPDIR/exists"
  fresh="$SHUNIT_TMPDIR/fresh"
  mkdir -p "$existing"
  output=$(printf '%s\n%s\ny\n' "$existing" "$fresh" \
    | { prompt_new_path "Use %s?" result; echo "RESULT=$result"; })
  assertContains "Should reject the existing path" \
    "$output" "The $existing already exists"
  assertContains "Should settle on the fresh path" "$output" "RESULT=$fresh"
}

test_prompt_new_path_reprompts_when_declined() {
  first="$SHUNIT_TMPDIR/first"
  second="$SHUNIT_TMPDIR/second"
  # 'first' line, then 'n' declines it, then 'second' line accepted with 'y'.
  result=$(printf '%s\nn%s\ny\n' "$first" "$second" \
    | { prompt_new_path "Use %s?" result > /dev/null; echo "$result"; })
  assertEquals "$second" "$result"
  assertFalse "Declined path should not be created" "[ -d '$first' ]"
}

test_prompt_new_path_aborts_when_input_is_exhausted() {
  # Empty input re-prompts, and at EOF there is nothing left to block on, so
  # before this was fatal the retry loop spun on the CPU forever.
  output=$(printf '' | prompt_new_path "Use %s?" result 2>&1)
  assertFalse "Should not loop forever at EOF" $?
  assertContains "Should say why it aborted" "$output" "input ended"
}

test_prompt_new_path_renders_confirm_message_template() {
  target="$SHUNIT_TMPDIR/tmpl"
  output=$(printf '%s\ny\n' "$target" \
    | prompt_new_path "Install under %s/bin/tmux?" result)
  assertContains "Should interpolate the path into the template" \
    "$output" "Install under $target/bin/tmux?"
}

#
# tui_ok / tui_skip / tui_warn / tui_fail
#

test_tui_ok_renders_indented_message_on_stdout() {
  output=$(tui_ok "zsh installed")
  assertContains "$output" "zsh installed"
  assertEquals "  " "$(printf '%s' "$output" | cut -c1-2)"
}

test_tui_ok_writes_nothing_to_stderr() {
  err=$(tui_ok "zsh installed" 2>&1 1>/dev/null)
  assertEquals "" "$err"
}

test_tui_skip_renders_indented_message_on_stdout() {
  output=$(tui_skip "asdf already installed")
  assertContains "$output" "asdf already installed"
  assertEquals "  " "$(printf '%s' "$output" | cut -c1-2)"
}

test_tui_warn_renders_indented_message_on_stdout() {
  output=$(tui_warn "missing basic packages")
  assertContains "$output" "missing basic packages"
  assertEquals "  " "$(printf '%s' "$output" | cut -c1-2)"
}

test_tui_fail_renders_indented_message_on_stderr() {
  err=$(tui_fail "zsh install failed" 2>&1 1>/dev/null)
  assertContains "$err" "zsh install failed"
  assertEquals "  " "$(printf '%s' "$err" | cut -c1-2)"
}

test_tui_fail_without_a_wrapped_command_stays_a_bare_line() {
  err=$(tui_fail "zsh not installed. Run zsh/install_zsh.sh --wizard first." 2>&1 1>/dev/null)
  assertEquals "  ✗ zsh not installed. Run zsh/install_zsh.sh --wizard first." "$err"
}

test_tui_fail_writes_nothing_to_stdout() {
  out=$(tui_fail "zsh install failed" 2>/dev/null)
  assertEquals "" "$out"
}

#
# die
#

test_die_with_default_message_and_code() {
  message=$(die 2>&1 1>/dev/null)
  assertEquals 1 $?
  assertContains "Should default to Aborted." "$message" "Aborted."
}

test_die_with_custom_message_and_code() {
  message=$(die Bye 2>&1 1>/dev/null)
  assertEquals 1 $?
  assertContains "Should carry the custom message" "$message" "Bye"

  message=$(die 'Custom code' 129 2>&1 1>/dev/null)
  assertEquals 129 $?
  assertContains "Should carry the custom message" "$message" "Custom code"
}

test_die_writes_nothing_to_stdout() {
  message=$(die 'Bye' 2>/dev/null)
  assertEquals "" "$message"
}

#
# tui_step
#

test_tui_step_piped_renders_standalone_line() {
  output=$(tui_step "installing zsh (apt-get)…")
  assertEquals "  → installing zsh (apt-get)…" "$output"
}

test_tui_step_then_tui_ok_are_two_plain_lines_when_piped() {
  output=$(tui_step "installing zsh"; tui_ok "zsh installed")
  assertEquals "  → installing zsh|  ✓ zsh installed|" \
    "$(printf '%s\n' "$output" | tr '\n' '|')"
  assertNotContains "No carriage return should appear off a tty" \
    "$output" "$(printf '\r')"
}

test_tui_step_then_tui_skip_are_two_plain_lines_when_piped() {
  output=$(tui_step "checking asdf"; tui_skip "asdf already installed")
  assertEquals "  → checking asdf|  • asdf already installed|" \
    "$(printf '%s\n' "$output" | tr '\n' '|')"
  assertNotContains "No carriage return should appear off a tty" \
    "$output" "$(printf '\r')"
}

test_tui_step_then_tui_warn_are_two_plain_lines_when_piped() {
  output=$(tui_step "checking packages"; tui_warn "missing basic packages")
  assertEquals "  → checking packages|  ! missing basic packages|" \
    "$(printf '%s\n' "$output" | tr '\n' '|')"
  assertNotContains "No carriage return should appear off a tty" \
    "$output" "$(printf '\r')"
}

test_tui_step_then_tui_fail_are_two_plain_lines_when_piped() {
  output=$( { tui_step "installing zsh"; tui_fail "zsh install failed"; } 2>&1)
  assertEquals "  → installing zsh|  ✗ zsh install failed|" \
    "$(printf '%s\n' "$output" | tr '\n' '|')"
  assertNotContains "No carriage return should appear off a tty" \
    "$output" "$(printf '\r')"
}

test_tui_ok_without_an_open_step_renders_as_before() {
  output=$(tui_ok "zsh installed")
  assertEquals "  ✓ zsh installed" "$output"
}

test_tui_step_hides_no_cursor_off_a_tty() {
  output=$(tui_step "installing zsh"; tui_ok "zsh installed")
  assertNotContains "A log file should not collect cursor sequences" \
    "$output" "$(printf '\033[?25')"
}

test_tui_task_hides_no_cursor_off_a_tty() {
  output=$(tui_task "listing root" --ok "listed root" --fail "nope" -- true)
  assertNotContains "A log file should not collect cursor sequences" \
    "$output" "$(printf '\033[?25')"
}

#
# tui_indent
#

test_tui_indent_prefixes_each_line_with_4_spaces() {
  output=$(printf 'first\nsecond\nthird\n' | tui_indent)
  assertEquals "    first|    second|    third|" \
    "$(printf '%s\n' "$output" | tr '\n' '|')"
}

#
# tui_task
#

test_tui_task_prints_the_task_message() {
  output=$(tui_task "cloning TPM 3.1.0…" --ok "TPM 3.1.0 installed" \
    --die "Couldn't clone TPM" -- true)
  assertContains "$output" "cloning TPM 3.1.0…"
}

test_tui_task_closes_a_successful_command_with_the_ok_wording() {
  output=$(tui_task "cloning TPM 3.1.0…" --ok "TPM 3.1.0 installed" \
    --die "Couldn't clone TPM" -- true)
  assertContains "$output" "✓ TPM 3.1.0 installed"
}

test_tui_task_returns_zero_when_the_command_succeeds() {
  tui_task "checking thing" --ok "checked" --fail "nope" -- true >/dev/null
  assertEquals 0 $?
}

test_tui_task_returns_zero_when_the_command_succeeds_with_debug() {
  DEBUG=1 tui_task "checking thing" --ok "checked" --fail "nope" -- true >/dev/null
  assertEquals 0 $?
}

# The mirror of the rule tui_run used to be held to. A terminator was the
# caller's job then, and one printed here would have been a second; now there
# is nobody else to print it, so its absence would leave the line open.
test_tui_task_always_closes_its_own_line() {
  output=$(tui_task "checking thing" --ok "checked" --die "nope" -- true)
  assertContains "$output" "✓"
}

test_tui_task_takes_the_ok_wording_from_ok_cmd() {
  output=$(tui_task "installing zsh…" --ok-cmd _deferred_message \
    --die "Couldn't install zsh" -- true)
  assertContains "The ✓ should say what the helper answered" \
    "$output" "✓ zsh 5.9 installed"
}

# Asking before the command has run is the whole reason --ok-cmd exists over a
# plain --ok string: there is nothing to read back off disk yet.
test_tui_task_does_not_consult_ok_cmd_when_the_command_fails() {
  createSpy -u -o 'zsh 5.9 installed' _deferred_message

  tui_task "installing zsh…" --ok-cmd _deferred_message \
    --fail "Couldn't install zsh" -- false >/dev/null 2>&1

  assertNeverCalled _deferred_message
}

test_tui_task_runs_the_command_with_its_arguments() {
  createSpy -u git

  tui_task "cloning TPM…" --ok "TPM installed" --die "Couldn't clone TPM" \
    -- git clone --quiet --depth=1 https://example.invalid/tpm >/dev/null 2>&1

  assertCalledOnceWith git clone --quiet --depth=1 https://example.invalid/tpm
}

# -- ends the flag parsing for good, so a command of its own with an --ok or a
# --die keeps them.
test_tui_task_leaves_flags_after_the_separator_to_the_command() {
  createSpy -u git

  tui_task "cloning…" --ok "cloned" --die "Couldn't clone" \
    -- git clone --ok --die >/dev/null 2>&1

  assertCalledOnceWith git clone --ok --die
}

test_tui_task_closes_a_failed_command_with_the_fail_reason() {
  err=$(tui_task "installing git (apt-get)…" --ok "git installed" \
    --fail "Couldn't install git" -- false 2>&1 1>/dev/null)
  assertContains "$err" "✗ Couldn't install git"
}

test_tui_task_returns_the_commands_status_under_fail() {
  tui_task "installing git (apt-get)…" --ok "git installed" \
    --fail "Couldn't install git" -- sh -c 'exit 42' >/dev/null 2>&1
  assertEquals "The caller decides what a given failure means" 42 $?
}

test_tui_task_closes_a_failed_command_with_a_warning() {
  output=$(tui_task "installing chsh…" --ok "chsh installed" \
    --warn "Couldn't install chsh" -- false 2>&1)
  assertContains "$output" "! Couldn't install chsh"
}

test_tui_task_returns_the_commands_status_under_warn() {
  tui_task "installing chsh…" --ok "chsh installed" \
    --warn "Couldn't install chsh" -- sh -c 'exit 42' >/dev/null 2>&1
  assertEquals 42 $?
}

test_tui_task_returns_the_commands_status_with_debug() {
  DEBUG=1 tui_task "installing git (apt-get)…" --ok "git installed" \
    --fail "Couldn't install git" -- sh -c 'exit 42' >/dev/null 2>&1
  assertEquals 42 $?
}

test_tui_task_dies_on_failure_under_die() {
  output=$( (tui_task "installing git (apt-get)…" --ok "git installed" \
    --die "Couldn't install git" -- false; echo SHOULD-NOT-RUN) 2>&1)
  assertContains "Should close the task with the reason" \
    "$output" "✗ Couldn't install git"
  assertNotContains "die does not come back" "$output" "SHOULD-NOT-RUN"
}

test_tui_task_replays_stderr_under_its_failure() {
  output=$(tui_task "installing git (apt-get)…" --ok "git installed" \
    --fail "Couldn't install git" -- _noisy_command 1 "E: Unable to fetch" 2>&1)
  assertContains "$output" "✗ Couldn't install git"
  assertContains "The tail belongs under the ✗, indented 4" \
    "$output" "    E: Unable to fetch"
}

test_tui_task_replays_stderr_under_its_ok() {
  output=$(tui_task "cloning TPM 3.1.0…" --ok "TPM 3.1.0 installed" \
    --die "Couldn't clone TPM" -- _noisy_command 0 "warning: not a commit!" 2>&1)
  assertContains "$output" "✓ TPM 3.1.0 installed"
  assertContains "The warning should follow the ✓" \
    "$output" "    warning: not a commit!"
}

test_tui_task_keeps_command_stderr_off_the_open_task_line() {
  # Letting it through is what used to break the line mid-word and print the
  # rest at column 0; it is captured now, and replayed by the Outcome.
  err=$(tui_task "checking thing" --ok "checked" --die "nope" \
    -- _noisy_command 0 "err line" 2>&1 1>/dev/null)
  assertEquals "Nothing should reach the terminal while the task is open" "" "$err"
}

test_tui_task_shows_command_stderr_indented_with_debug() {
  # DEBUG=1 sends stderr through the same tui_indent pipe as stdout, so the
  # two interleave in the order the command wrote them.
  output=$(DEBUG=1 tui_task "checking thing" --ok "checked" --die "nope" \
    -- _noisy_command 0 "err line" 2>&1)
  assertContains "$output" "    err line"
}

test_tui_task_keeps_only_the_last_five_stderr_lines() {
  # One offline apt-get produced 44 full-width lines; the last few are the ones
  # that say what went wrong.
  err=$(tui_task "installing git (apt-get)…" --ok "git installed" \
    --fail "Couldn't install git" -- _noisy_command 1 \
    "line 1" "line 2" "line 3" "line 4" "line 5" "line 6" "line 7" "line 8" \
    2>&1 1>/dev/null)
  assertContains "Should keep the last line" "$err" "    line 8"
  assertContains "Should keep five lines back" "$err" "    line 4"
  assertNotContains "Should drop everything older than that" "$err" "line 3"
}

# Diagnostics that separate their paragraphs with a blank line are ordinary
# (npm, python tracebacks, build tools). A blank line must survive the replay
# rather than truncating the tail at the paragraph break.
test_tui_task_replays_a_tail_containing_a_blank_line() {
  output=$(tui_task "cloning TPM 3.1.0…" --ok "TPM 3.1.0 installed" \
    --die "Couldn't clone TPM" \
    -- _noisy_command 0 "warn one" "" "warn three" 2>&1)
  assertContains "Should replay the line before the blank" "$output" "    warn one"
  assertContains "Should replay the line after the blank" "$output" "    warn three"
  assertNotContains "Should not leak a shell diagnostic" "$output" "parameter"
}

test_tui_task_hints_at_debug_alongside_a_captured_tail() {
  err=$(tui_task "installing git (apt-get)…" --ok "git installed" \
    --fail "Couldn't install git" -- _noisy_command 1 "E: Unable to fetch" \
    2>&1 1>/dev/null)
  assertContains "The tail should be there" "$err" "    E: Unable to fetch"
  assertContains "And the way to see the rest" \
    "$err" "    Re-run with DEBUG=1 for full output."
}

test_tui_task_hints_at_debug_when_the_failed_command_said_nothing() {
  # An empty stderr means whatever the command had to say went to the stdout
  # tui_task hid — which is exactly what DEBUG=1 brings back.
  err=$(tui_task "installing git (apt-get)…" --ok "git installed" \
    --fail "Couldn't install git" -- sh -c 'echo "chatter"; exit 1' \
    2>&1 1>/dev/null)
  assertContains "The hint should stand in for the hidden stdout" \
    "$err" "    Re-run with DEBUG=1 for full output."
  assertNotContains "There was nothing captured to replay" "$err" "chatter"
}

test_tui_task_does_not_hint_at_debug_when_nothing_failed() {
  output=$(tui_task "cloning TPM 3.1.0…" --ok "TPM 3.1.0 installed" \
    --die "Couldn't clone TPM" \
    -- _noisy_command 0 "warning: not a commit!" 2>&1)
  assertNotContains "Nothing failed, so there is nothing to re-run" \
    "$output" "DEBUG=1"
}

test_tui_task_does_not_replay_the_stderr_shown_live_by_debug() {
  output=$(DEBUG=1 tui_task "installing git (apt-get)…" --ok "git installed" \
    --fail "Couldn't install git" -- _noisy_command 1 "E: Unable to fetch" 2>&1)
  assertContains "DEBUG should indent stderr as it happens" \
    "$output" "    E: Unable to fetch"
  assertEquals "And the Outcome should not repeat it" \
    1 "$(printf '%s\n' "$output" | grep -c 'E: Unable to fetch')"
  assertNotContains "The full output is already on screen" \
    "$output" "Re-run with DEBUG=1"
}

test_tui_task_hides_command_stdout_by_default() {
  output=$(tui_task "checking thing" --ok "checked" --die "nope" \
    -- echo "command output")
  assertNotContains "$output" "command output"
}

test_tui_task_shows_command_stdout_indented_with_debug() {
  output=$(DEBUG=1 tui_task "checking thing" --ok "checked" --die "nope" \
    -- echo "command output")
  assertContains "$output" "    command output"
}

# Every caller wraps tui_task in a `( set -e; ... )` subshell, which is where
# stashing the status inside a pipeline is easiest to get wrong: a bare failing
# command there kills the pipeline's left side before it can record anything.
# These spawn a real `sh`, so DOTFILES has to be handed over explicitly —
# oneTimeSetUp only sets it, and utils.sh refuses to source without it.
test_tui_task_returns_the_commands_status_under_set_e() {
  if ! _shell_keeps_errexit_status; then
    echo "Skipping: this /bin/sh drops the status of an errexit subshell"
    startSkipping
    return 0
  fi
  output=$(DOTFILES="$DOTFILES" sh -c ". $THISDIR/utils.sh; ( set -e; tui_task step --ok ok --fail nope -- sh -c 'exit 42' ); echo \$?" 2>&1)
  assertContains "Should surface the command's own status, not the shell's" \
    "$output" "42"
}

test_tui_task_returns_the_commands_status_under_set_e_with_debug() {
  if ! _shell_keeps_errexit_status; then
    echo "Skipping: this /bin/sh drops the status of an errexit subshell"
    startSkipping
    return 0
  fi
  output=$(DOTFILES="$DOTFILES" DEBUG=1 sh -c ". $THISDIR/utils.sh; ( set -e; tui_task step --ok ok --fail nope -- sh -c 'exit 42' ); echo \$?" 2>&1)
  assertContains "Should surface the command's own status, not the shell's" \
    "$output" "42"
  assertNotContains "The status stash must be reachable under set -e" \
    "$output" "Illegal number"
}

# The status stash must not be bought by disabling errexit for the command
# itself. A multi-statement function is the only shape that catches this: with
# errexit lost, cmd_b runs after cmd_a fails and the whole thing reports 0.
# tmux's ./configure && make -j4 followed by `sudo make install` is exactly
# this shape, so getting it wrong installs an unbuilt tree.
test_tui_task_keeps_errexit_inside_a_multi_statement_command() {
  output=$(DOTFILES="$DOTFILES" sh -c ". $THISDIR/utils.sh; two() { false; echo SECOND-RAN; }; ( set -e; tui_task step --ok ok --fail nope -- two ); echo rc=\$?" 2>&1)
  assertNotContains "Should stop at the first failing line" "$output" "SECOND-RAN"
  assertContains "Should report the failure" "$output" "rc=1"
}

test_tui_task_keeps_errexit_inside_a_multi_statement_command_with_debug() {
  output=$(DOTFILES="$DOTFILES" DEBUG=1 sh -c ". $THISDIR/utils.sh; two() { false; echo SECOND-RAN; }; ( set -e; tui_task step --ok ok --fail nope -- two ); echo rc=\$?" 2>&1)
  assertNotContains "Should stop at the first failing line" "$output" "SECOND-RAN"
  assertContains "Should report the failure" "$output" "rc=1"
}

test_tui_task_leaves_errexit_off_when_the_caller_had_it_off() {
  # The wrapper must not impose errexit either — the command should behave
  # exactly as it would without tui_task.
  output=$(DOTFILES="$DOTFILES" sh -c ". $THISDIR/utils.sh; two() { false; echo SECOND-RAN; }; tui_task step --ok ok --fail nope -- two; echo rc=\$?" 2>&1)
  assertContains "Should run on past the failure, as it would unwrapped" \
    "$output" "rc=0"
}

# The quiet path turns errexit off around its own bookkeeping, with no pipeline
# subshell to confine that. A caller that had it on must get it back, or every
# command after the first tui_task runs unguarded.
test_tui_task_restores_the_callers_errexit() {
  output=$(DOTFILES="$DOTFILES" sh -c ". $THISDIR/utils.sh; ( set -e; tui_task step --ok ok --fail nope -- true; false; echo SHOULD-NOT-RUN )" 2>&1)
  assertNotContains "errexit must survive tui_task" "$output" "SHOULD-NOT-RUN"
}

# Running the command in its own subshell is what lets the bookkeeping happen
# at all: errexit used to tear the caller down at the failing command, before
# the capture file could be read or removed.
test_tui_task_removes_its_capture_file_when_the_command_fails_under_errexit() {
  TMPDIR="$SHUNIT_TMPDIR" DOTFILES="$DOTFILES" \
    sh -c ". $THISDIR/utils.sh; ( set -e; tui_task step --ok ok --fail nope -- false )" >/dev/null 2>&1
  assertEquals "The capture file should not outlive the failure" \
    "" "$(command ls -qA -- "$SHUNIT_TMPDIR")"
}

# The bookkeeping around the command is a run of tests and assignments, any of
# which would tear an errexit caller down if it landed last.
test_tui_task_does_not_abort_a_set_e_caller_on_success() {
  output=$(DOTFILES="$DOTFILES" sh -c ". $THISDIR/utils.sh; ( set -e; tui_task step --ok ok --fail nope -- true; echo AFTER )" 2>&1)
  assertContains "A closed ✓ must not read as a failure" "$output" "AFTER"
}

# The command has already succeeded by the time the wording is asked for, so a
# helper that answers and then reports a bad status must not undo that.
test_tui_task_keeps_the_ok_when_its_wording_helper_stumbles() {
  output=$(DOTFILES="$DOTFILES" sh -c ". $THISDIR/utils.sh; half() { echo 'zsh installed'; return 3; }; ( set -e; tui_task step --ok-cmd half --fail nope -- true; echo AFTER )" 2>&1)
  assertContains "Should still close with what the helper managed to say" \
    "$output" "✓ zsh installed"
  assertContains "And the helper's status should stop there" "$output" "AFTER"
}

#
# tui_task misuse
#

test_tui_task_requires_a_failure_flag() {
  output=$( (tui_task "checking thing" --ok "checked" -- true) 2>&1)
  assertContains "A Task with no failure wording could not close its own line" \
    "$output" "--die, --fail or --warn is required"
}

test_tui_task_requires_a_success_flag() {
  output=$( (tui_task "checking thing" --die "nope" -- true) 2>&1)
  assertContains "$output" "--ok or --ok-cmd is required"
}

test_tui_task_rejects_two_success_flags() {
  output=$( (tui_task "checking thing" --ok "checked" --ok-cmd _deferred_message \
    --die "nope" -- true) 2>&1)
  assertContains "$output" "--ok and --ok-cmd are exclusive"
}

test_tui_task_rejects_two_failure_flags() {
  output=$( (tui_task "checking thing" --ok "checked" --die "nope" --warn "hm" \
    -- true) 2>&1)
  assertContains "$output" "--die, --fail and --warn are exclusive"
}

test_tui_task_rejects_a_command_without_the_separator() {
  output=$( (tui_task "checking thing" --ok "checked" --die "nope" true) 2>&1)
  assertContains "The command sits behind --, so its own flags stay its own" \
    "$output" 'unexpected argument "true"'
}

test_tui_task_rejects_a_separator_with_no_command() {
  output=$( (tui_task "checking thing" --ok "checked" --die "nope" --) 2>&1)
  assertContains "$output" "no command to run"
}

#
# tui_detail
#

test_tui_detail_renders_indented_continuation_line() {
  # shellcheck disable=SC2088 # literal "~" expected, not a path to expand
  output=$(tui_detail "~/.zshenv")
  # shellcheck disable=SC2088 # literal "~" expected, not a path to expand
  assertContains "$output" "~/.zshenv"
  assertEquals "    " "$(printf '%s' "$output" | cut -c1-4)"
}

#
# tui_section
#

test_tui_section_emits_one_leading_blank_line() {
  output=$(tui_section "zsh")
  assertEquals "" "$(printf '%s\n' "$output" | sed -n '1p')"
}

test_tui_section_renders_bare_title_without_counters() {
  output=$(tui_section "zsh")
  header=$(printf '%s\n' "$output" | sed -n '2p')
  assertContains "$header" "zsh"
  assertNotContains "$header" "("
}

test_tui_section_renders_counters_when_given() {
  output=$(tui_section "zsh" 1 4)
  header=$(printf '%s\n' "$output" | sed -n '2p')
  assertContains "$header" "zsh"
  assertContains "$header" "(1/4)"
}

test_tui_section_has_no_trailing_blank_line() {
  output=$(tui_section "zsh" 1 4)
  assertEquals 2 "$(printf '%s\n' "$output" | wc -l)"
}

#
# tui_path
#

test_tui_path_replaces_home_prefix_with_tilde() {
  output=$(tui_path "$HOME/.zshenv")
  # shellcheck disable=SC2088 # literal "~" expected, not a path to expand
  assertEquals "~/.zshenv" "$output"
}

test_tui_path_leaves_paths_outside_home_untouched() {
  output=$(tui_path "/etc/passwd")
  assertEquals "/etc/passwd" "$output"
}

test_tui_path_renders_home_itself_as_tilde() {
  output=$(tui_path "$HOME")
  assertEquals "~" "$output"
}

#
# tui_init / NO_COLOR
#

test_tui_init_clears_a_previously_resolved_palette_under_no_color() {
  # Unit tests never run on a tty, so tui_init already resolves to an empty
  # palette and comparing its output before/after would prove nothing. Seed a
  # sentinel instead, so a tui_init that stopped honouring NO_COLOR — or
  # stopped being re-runnable — leaves the sentinel behind and fails here.
  _TUI_GREEN='SENTINEL'
  assertContains "Sentinel should reach the output before re-init" \
    "$(tui_ok 'zsh installed')" "SENTINEL"

  NO_COLOR=1 tui_init

  assertNotContains "NO_COLOR should resolve the palette to empty strings" \
    "$(tui_ok 'zsh installed')" "SENTINEL"
}


# Run tests
SHPY_PATH="$THISDIR/../tests/shpy"
export SHPY_PATH
. "$THISDIR/../tests/shpy"
. "$THISDIR/../tests/shpy-shunit2"
. "$THISDIR/../tests/shunit2"
