#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
  DOTFILES="$(get_abs_path "$THISDIR/..")"
}

setUp() {
  . "$THISDIR/install_zimfw.sh"
  HOME=${SHUNIT_TMPDIR:?}/home
  XDG_CONFIG_HOME=${SHUNIT_TMPDIR:?}/xdg-config
  mkdir -p "$HOME" "$XDG_CONFIG_HOME"
  unset ZDOTDIR ZIM_HOME
}

tearDown() {
  cleanupSpies
  cleanupTestDir
}

# Convenience: simulate a completed install_zsh
_simulate_install_zsh() {
  touch "$HOME/.zshenv"
  mkdir -p "$XDG_CONFIG_HOME/zsh"
  touch "$XDG_CONFIG_HOME/zsh/.zshrc"
}

#
# Preconditions
#

test_preconditions_die_if_zsh_missing() {
  _simulate_install_zsh
  createSpy -u -r "$SHUNIT_FALSE" command_exists

  output=$(check_zsh_prerequisites 2>&1)

  assertFalse "Should fail when zsh is not installed" $?
  assertContains "Should mention install_zsh.sh" "$output" "zsh/install_zsh.sh"
}

test_preconditions_die_if_zshenv_missing() {
  mkdir -p "$XDG_CONFIG_HOME/zsh"
  touch "$XDG_CONFIG_HOME/zsh/.zshrc"
  createSpy -u -r "$SHUNIT_TRUE" command_exists

  output=$(check_zsh_prerequisites 2>&1)

  assertFalse "Should fail when .zshenv is missing" $?
  assertContains "Should mention .zshenv" "$output" ".zshenv"
}

test_preconditions_die_if_zshrc_stub_missing() {
  touch "$HOME/.zshenv"
  createSpy -u -r "$SHUNIT_TRUE" command_exists

  output=$(check_zsh_prerequisites 2>&1)

  assertFalse "Should fail when ZDOTDIR/.zshrc is missing" $?
  assertContains "Should mention zshrc" "$output" ".zshrc"
}

test_preconditions_pass_when_all_present() {
  _simulate_install_zsh
  createSpy -u -r "$SHUNIT_TRUE" command_exists

  check_zsh_prerequisites
  assertTrue "Should succeed when prerequisites are present" $?
}

#
# install_zimfw_program
#

test_program_returns_true_if_already_installed() {
  createSpy -u -r "$SHUNIT_TRUE" is_zimfw_installed
  createSpy -u wget

  output=$(install_zimfw_program)

  assertTrue "Already installed should not be an error" $?
  assertContains "Should report already installed" \
    "$output" "zimfw already installed"
  assertNeverCalled wget
}

test_program_downloads_zimfw_when_missing() {
  createSpy -u -r "$SHUNIT_FALSE" is_zimfw_installed
  createSpy -u wget

  quietly install_zimfw_program

  assertTrue "Should return success on download success" $?
  assertCallCount wget 1
}

#
# install_zimfw_zshenv_block
#

test_zshenv_block_writes_skip_global_compinit() {
  _simulate_install_zsh

  quietly install_zimfw_zshenv_block

  contents=$(cat "$HOME/.zshenv")
  assertContains "Should contain start marker" "$contents" "# >>> dotfiles:zimfw >>>"
  assertContains "Should contain end marker"   "$contents" "# <<< dotfiles:zimfw <<<"
  assertContains "Should set skip_global_compinit" \
    "$contents" "skip_global_compinit=1"
}

#
# install_zimfw_zshrc_block
#

test_zshrc_block_appends_marker_block() {
  _simulate_install_zsh

  quietly install_zimfw_zshrc_block

  zshrc="$XDG_CONFIG_HOME/zsh/.zshrc"
  contents=$(cat "$zshrc")
  assertContains "Should contain start marker" "$contents" "# >>> dotfiles:zimfw >>>"
  assertContains "Should contain end marker"   "$contents" "# <<< dotfiles:zimfw <<<"
  # shellcheck disable=SC2016
  assertContains "Should source zshrc-zim" \
    "$contents" 'source "$DOTFILES/zimfw/zshrc-zim"'
}

#
# install_zimfw_zdotdir_stub
#

test_zdotdir_stub_creates_one_line_source() {
  _simulate_install_zsh

  # shellcheck disable=SC2016
  quietly install_zimfw_zdotdir_stub .zimrc '$DOTFILES/zimfw/zimrc-base'

  target="$XDG_CONFIG_HOME/zsh/.zimrc"
  assertTrue "Should create stub" "test -f $target"
  # shellcheck disable=SC2016
  assertContains "Should source repo zimrc-base" \
    "$(cat "$target")" 'source "$DOTFILES/zimfw/zimrc-base"'
}

test_zdotdir_stub_ends_with_a_newline() {
  _simulate_install_zsh

  # shellcheck disable=SC2016
  quietly install_zimfw_zdotdir_stub .zimrc '$DOTFILES/zimfw/zimrc-base'

  target="$XDG_CONFIG_HOME/zsh/.zimrc"
  # $(...) strips trailing newlines, so an empty result means the last byte was \n
  assertEquals "Stub file should end with a newline" \
    "" "$(tail -c1 "$target")"
}

test_zdotdir_stub_user_can_backup_existing() {
  _simulate_install_zsh
  target="$XDG_CONFIG_HOME/zsh/.zimrc"
  echo "# existing zimrc" > "$target"

  # shellcheck disable=SC2016
  echo 1 | quietly install_zimfw_zdotdir_stub .zimrc '$DOTFILES/zimfw/zimrc-base'

  assertTrue "Backup file should exist" "test -f $target.bkp"
  # shellcheck disable=SC2016
  assertContains "Target should now source repo" \
    "$(cat "$target")" 'source "$DOTFILES/zimfw/zimrc-base"'
}

test_zdotdir_stub_user_can_cancel() {
  _simulate_install_zsh
  target="$XDG_CONFIG_HOME/zsh/.zimrc"
  echo "# existing zimrc" > "$target"

  # shellcheck disable=SC2016
  output=$(echo q | install_zimfw_zdotdir_stub .zimrc '$DOTFILES/zimfw/zimrc-base')

  assertContains "Should show cancellation" "$output" "not configured"
  assertEquals "Original content preserved" \
    "# existing zimrc" "$(cat "$target")"
}

#
# install_zimfw_dotfiles (orchestrator)
#

test_dotfiles_calls_all_writers() {
  createSpy -u install_zimfw_zshenv_block
  createSpy -u install_zimfw_zshrc_block
  createSpy -u install_zimfw_zdotdir_stub

  install_zimfw_dotfiles

  assertCallCount install_zimfw_zshenv_block 1
  assertCallCount install_zimfw_zshrc_block 1
  assertCallCount install_zimfw_zdotdir_stub 1
  # shellcheck disable=SC2016
  assertCalledWith install_zimfw_zdotdir_stub .zimrc  '$DOTFILES/zimfw/zimrc-base'
}

#
# wizard
#

test_wizard_aborts_when_preconditions_fail() {
  createSpy -u -r "$SHUNIT_FALSE" check_zsh_prerequisites
  createSpy -u install_zimfw_program
  createSpy -u install_zimfw_dotfiles
  createSpy -u install_zimfw_modules

  install_zimfw_wizard

  assertCallCount check_zsh_prerequisites 1
  assertNeverCalled install_zimfw_program
  assertNeverCalled install_zimfw_dotfiles
  assertNeverCalled install_zimfw_modules
}

test_wizard_runs_full_chain_when_preconditions_pass() {
  createSpy -u check_zsh_prerequisites
  createSpy -u install_zimfw_program
  createSpy -u install_zimfw_dotfiles
  createSpy -u install_zimfw_modules

  install_zimfw_wizard

  assertCallCount install_zimfw_program 1
  assertCallCount install_zimfw_dotfiles 1
  assertCallCount install_zimfw_modules 1
}

test_wizard_stops_chain_when_program_fails() {
  createSpy -u check_zsh_prerequisites
  createSpy -u -r "$SHUNIT_FALSE" install_zimfw_program
  createSpy -u install_zimfw_dotfiles
  createSpy -u install_zimfw_modules

  install_zimfw_wizard

  assertCallCount install_zimfw_program 1
  assertNeverCalled install_zimfw_dotfiles
  assertNeverCalled install_zimfw_modules
}

# Run tests
SHPY_PATH="$THISDIR/../tests/shpy"
export SHPY_PATH
. "$THISDIR/../tests/shpy"
. "$THISDIR/../tests/shpy-shunit2"
. "$THISDIR/../tests/shunit2"
