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

#
# confirm
#

test_confirm_has_default_message() {
  message=$(yes | confirm)
  assertEquals "Continue? (Y/n)" "${message% *}"
}

test_confirm_has_default_no_message() {
  message=$(yes | confirm -n)
  assertEquals "Continue? (y/N)" "${message% *}"
}

test_confirm_trims_given_message() {
  message=$(yes | confirm 'Sure?   ')
  assertEquals "Sure? (Y/n) y" "${message}"

  message=$(yes | confirm -n 'Not sure?   ')
  assertEquals "Not sure? (y/N) y" "${message}"
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

#
# choose
#

test_choose_print_the_options() {
  output=$(echo 1 | choose "first option" second)
  assertContains "Should print first option" \
    "$output" "1) first option"
  assertContains "Should print second option" \
    "$output" "2) second"
}

test_choose_returns_valid_choice_number() {
  output=$(echo 1 | choose first second)
  assertEquals 1 $?
  assertEquals "Should echo answer" "1" "${output##*[!1]}"

  output=$(echo 2 | choose first second)
  assertEquals 2 $?
  assertEquals "Should echo answer" "2" "${output##*[!2]}"
}

test_choose_returns_zero_when_canceled_with_q() {
  output=$(echo q | choose first second)
  assertEquals 0 $?
  assertContains "$output" "Cancelled"
}

test_choose_returns_default_on_enter() {
  output=$(printf '\n' | choose -d 2 first second third)
  assertEquals 2 $?
  assertEquals "Should echo default answer" "2" "${output##*[!2]}"
}

test_choose_with_default_still_accepts_explicit_choice() {
  output=$(echo 3 | choose -d 1 first second third)
  assertEquals 3 $?
  assertEquals "Should echo explicit answer" "3" "${output##*[!3]}"
}

test_choose_with_default_still_cancels_on_q() {
  output=$(echo q | choose -d 1 first second)
  assertEquals 0 $?
  assertContains "$output" "Cancelled"
}

test_choose_dont_print_anything_on_invalid_answer() {
  output=$(printf '%s\n%d' "034_all_invalid_except:" 1 | choose first second)
  assertEquals 1 $?
  assertEquals "1) first|2) second|q) Quit|1|" \
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

test_prompt_line_prints_the_prompt_message() {
  message=$(echo "ignored" | prompt_line "Name: " answer)
  assertEquals "Name: " "$message"
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


# Run tests
SHPY_PATH="$THISDIR/../tests/shpy"
export SHPY_PATH
. "$THISDIR/../tests/shpy"
. "$THISDIR/../tests/shpy-shunit2"
. "$THISDIR/../tests/shunit2"
