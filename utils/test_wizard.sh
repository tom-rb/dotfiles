#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
  # shellcheck disable=SC2034
  DOTFILES="$(get_abs_path "$THISDIR/..")"
}

setUp() {
  . "$THISDIR/utils.sh"
  ORDER_FILE="${SHUNIT_TMPDIR:?}/order"
}

tearDown() {
  cleanupSpies
  cleanupTestDir
}


#
# wizard_run
#

test_wizard_run_calls_steps_in_order() {
  step_a() { printf 'a\n' >> "$ORDER_FILE"; }
  step_b() { printf 'b\n' >> "$ORDER_FILE"; }
  step_c() { printf 'c\n' >> "$ORDER_FILE"; }

  wizard_run -- step_a step_b step_c

  assertEquals "a
b
c" "$(cat "$ORDER_FILE")"
}

test_wizard_run_short_circuits_on_first_failing_step() {
  step_ok()   { printf 'ok\n'   >> "$ORDER_FILE"; }
  step_fail() { printf 'fail\n' >> "$ORDER_FILE"; return 1; }
  step_skip() { printf 'skip\n' >> "$ORDER_FILE"; }

  wizard_run -- step_ok step_fail step_skip

  assertEquals "ok
fail" "$(cat "$ORDER_FILE")"
}

test_wizard_run_preserves_failing_step_exit_code() {
  step_code7() { return 7; }

  wizard_run -- step_code7
  assertEquals 7 $?
}

test_wizard_run_with_y_pipes_newlines_into_steps() {
  step_reads_stdin() {
    read -r line
    printf 'got=%s\n' "$line" >> "$ORDER_FILE"
  }

  wizard_run -y -- step_reads_stdin

  assertEquals "got=" "$(cat "$ORDER_FILE")"
}

test_wizard_run_without_y_leaves_stdin_alone() {
  step_reads_stdin() {
    read -r line
    printf 'got=%s\n' "$line" >> "$ORDER_FILE"
  }

  printf 'hello\n' | wizard_run -- step_reads_stdin

  assertEquals "got=hello" "$(cat "$ORDER_FILE")"
}

#
# wizard_main
#

test_wizard_main_invokes_function_when_arg_is_wizard() {
  my_wizard() { printf 'called\n' >> "$ORDER_FILE"; }

  wizard_main my_wizard --wizard

  assertEquals "called" "$(cat "$ORDER_FILE")"
}

test_wizard_main_noops_when_arg_is_not_wizard() {
  my_wizard() { printf 'called\n' >> "$ORDER_FILE"; }

  wizard_main my_wizard --other
  wizard_main my_wizard

  assertFalse "Order file should not exist" "[ -f \"$ORDER_FILE\" ]"
}

#
# start_module_wizard
#

test_start_module_wizard_shells_out_to_module_installer() {
  createSpy -u _sh

  start_module_wizard foo

  assertCalledOnceWith _sh -- "$DOTFILES/foo/install_foo.sh" --wizard
}

test_start_module_wizard_returns_subshell_exit_code() {
  createSpy -u -r 7 _sh

  start_module_wizard foo
  assertEquals 7 $?
}


# Run tests
SHPY_PATH="$THISDIR/../tests/shpy"
export SHPY_PATH
. "$THISDIR/../tests/shpy"
. "$THISDIR/../tests/shpy-shunit2"
. "$THISDIR/../tests/shunit2"
