#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  # shellcheck source=../tests/utils_for_test.sh
  . "$THISDIR/../tests/utils_for_test.sh"
  DOTFILES="$(get_abs_path "$THISDIR/..")"
}

setUp() {
  # shellcheck source=install_zsh.sh
  . "$THISDIR/install_zsh.sh"
  # Isolate $HOME for tests
  HOME=${SHUNIT_TMPDIR:?}/home
  mkdir -p "$HOME"
}

tearDown() {
  cleanupSpies
  cleanupTestDir
}

#
# Tests
#

test_install_returns_true_if_zsh_is_already_installed() {
  createSpy -u -r "$SHUNIT_TRUE" is_zsh_installed
  createSpy -u install_from_pm

  output=$(install_zsh_program)

  assertTrue "zsh already installed should not be an error" $?
  assertContains "Should report already installed" \
    "$output" "zsh already installed"
  assertNeverCalled install_from_pm
}

test_install_zsh_from_package_manager_when_not_installed() {
  createSpy -u -r "$SHUNIT_FALSE" is_zsh_installed
  createSpy -u install_from_pm

  output=$(install_zsh_program)

  assertTrue "zsh installed from package manager should not be an error" $?
  assertCalledOnceWith install_from_pm zsh
  assertContains "Should report installed" "$output" "zsh installed"
}

test_zsh_dotfiles_are_installed() {
  quietly install_zsh_dotfiles

  assertTrue "Should have created \$HOME/.zshenv" "test -f $HOME/.zshenv"

  # shellcheck disable=SC2016
  assertContains "Should source zshenv-base from dotfiles repo" \
    "$(cat "$HOME/.zshenv")" 'source "$DOTFILES/zsh/zshenv-base"'

  assertContains "Should export real DOTFILES path" \
    "$(cat "$HOME/.zshenv")" "export DOTFILES=$DOTFILES"
}

test_existing_zshenv_is_echoed_for_user_inspection() {
  echo "# Some existing config" > "$HOME/.zshenv"

  output=$(echo 1 | install_zsh_dotfiles) # choose whatever option

  assertContains "Contents of existing file should be printed" \
    "$output" "# Some existing config"
}

test_existing_zshenv_is_backed_up() {
  echo "# Some existing config" > "$HOME/.zshenv"

  output=$(echo 1 | install_zsh_dotfiles) # choose backup

  assertTrue "Expected bkp" "test -f $HOME/.zshenv.bkp"

  # shellcheck disable=SC2016
  assertContains "Should source zshenv-base in conf file" \
    "$(cat "$HOME/.zshenv")" 'source "$DOTFILES/zsh/zshenv-base"'
}

test_existing_zshenv_is_appended() {
  echo "# Some existing config" > "$HOME/.zshenv"

  output=$(echo 2 | install_zsh_dotfiles) # choose append

  assertContains "Should include original contents of conf file" \
    "$(cat "$HOME/.zshenv")" "# Some existing config"

  # shellcheck disable=SC2016
  assertContains "Should source zshenv-base in conf file" \
    "$(cat "$HOME/.zshenv")" 'source "$DOTFILES/zsh/zshenv-base"'
}

test_existing_zshenv_is_overwritten() {
  echo "# Some existing config" > "$HOME/.zshenv"

  output=$(echo 3 | install_zsh_dotfiles) # choose overwrite

  assertNotContains "Should not include original contents of conf file" \
    "$(cat "$HOME/.zshenv")" "# Some existing config"

  # shellcheck disable=SC2016
  assertContains "Should source zshenv-base in conf file" \
    "$(cat "$HOME/.zshenv")" 'source "$DOTFILES/zsh/zshenv-base"'
}

test_with_existing_zshenv_user_can_cancel() {
  echo "# Some existing config" > "$HOME/.zshenv"

  output=$(echo q | install_zsh_dotfiles) # choose quit

  assertContains "Expected cancellation message" \
    "$output" ".zshenv not configured!"

  assertEquals "Should include only original contents of conf file" \
    "# Some existing config" "$(cat "$HOME/.zshenv")"
}

test_wizard_installs_dotfiles_when_zsh_is_installed() {
  createSpy -u install_zsh_program
  createSpy -u install_zsh_dotfiles

  install_zsh_wizard

  assertCallCount install_zsh_program 1
  assertCallCount install_zsh_dotfiles 1
}

test_wizard_does_not_install_dotfiles_when_zsh_installation_fails() {
  createSpy -u -r "$SHUNIT_FALSE" install_zsh_program
  createSpy -u install_zsh_dotfiles

  install_zsh_wizard

  assertCallCount install_zsh_program 1
  assertNeverCalled install_zsh_dotfiles
}

# Run tests
SHPY_PATH="$THISDIR/../tests/shpy"
export SHPY_PATH
# shellcheck source=../tests/shpy
. "$THISDIR/../tests/shpy"
# shellcheck source=../tests/shpy-shunit2
. "$THISDIR/../tests/shpy-shunit2"
# shellcheck source=../tests/shunit2
. "$THISDIR/../tests/shunit2"
