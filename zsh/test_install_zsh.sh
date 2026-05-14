#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
  DOTFILES="$(get_abs_path "$THISDIR/..")"
}

setUp() {
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

test_ensure_chsh_skips_when_already_installed() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm

  ensure_chsh_available

  assertTrue "Should succeed when chsh is present" $?
  assertCalledOnceWith command_exists chsh
  assertNeverCalled install_from_pm
}

test_ensure_chsh_installs_util_linux_user_on_yum() {
  createSpy -u -r "$SHUNIT_FALSE" command_exists
  createSpy -u -o 'yum' get_supported_pm
  createSpy -u install_from_pm

  ensure_chsh_available

  assertTrue "Should succeed after install" $?
  assertCalledOnceWith install_from_pm util-linux-user
}

test_ensure_chsh_warns_and_returns_zero_when_install_fails() {
  createSpy -u -r "$SHUNIT_FALSE" command_exists
  createSpy -u -o 'yum' get_supported_pm
  createSpy -u -r "$SHUNIT_FALSE" install_from_pm

  output=$(ensure_chsh_available)

  assertTrue "Should still return success on install failure" $?
  assertContains "Should print recovery hint" "$output" "Couldn't install chsh"
}

test_set_default_shell_skips_when_zsh_is_already_default() {
  createSpy -u ensure_chsh_available
  createSpy -u -o "/usr/bin/zsh" get_zsh_path
  createSpy -u -o '/usr/bin/zsh' get_current_default_shell
  createSpy -u confirm
  createSpy -u sudo

  output=$(set_zsh_as_default_shell)

  assertTrue "Should succeed when already default" $?
  assertContains "$output" "already the default shell"
  assertNeverCalled confirm
  assertNeverCalled sudo
}

test_set_default_shell_skips_when_user_declines() {
  createSpy -u ensure_chsh_available
  createSpy -u -o "/usr/bin/zsh" get_zsh_path
  createSpy -u -o '/bin/bash' get_current_default_shell
  createSpy -u -r "$SHUNIT_FALSE" confirm
  createSpy -u sudo

  set_zsh_as_default_shell

  assertTrue "Should succeed when user declines" $?
  assertCallCount confirm 1
  assertNeverCalled sudo
}

test_set_default_shell_calls_chsh_when_accepted() {
  createSpy -u ensure_chsh_available
  createSpy -u -o "/usr/bin/zsh" get_zsh_path
  createSpy -u -o '/bin/bash' get_current_default_shell
  createSpy -u -r "$SHUNIT_TRUE" confirm
  createSpy -u sudo

  quietly set_zsh_as_default_shell

  assertTrue "Should succeed on chsh success" $?
  assertCalledOnceWith sudo chsh -s /usr/bin/zsh "$(id -un)"
}

test_set_default_shell_returns_success_with_hint_when_chsh_fails() {
  createSpy -u ensure_chsh_available
  createSpy -u -o "/usr/bin/zsh" get_zsh_path
  createSpy -u -o '/bin/bash' get_current_default_shell
  createSpy -u -r "$SHUNIT_TRUE" confirm
  createSpy -u -r "$SHUNIT_FALSE" sudo

  output=$(set_zsh_as_default_shell)

  assertTrue "Should still return success on chsh failure" $?
  assertContains "Should print recovery hint" "$output" "chsh -s /usr/bin/zsh"
}

test_wizard_installs_dotfiles_when_zsh_is_installed() {
  createSpy -u install_zsh_program
  createSpy -u install_zsh_dotfiles
  createSpy -u set_zsh_as_default_shell

  install_zsh_wizard

  assertCallCount install_zsh_program 1
  assertCallCount install_zsh_dotfiles 1
  assertCallCount set_zsh_as_default_shell 1
}

test_wizard_does_not_install_dotfiles_when_zsh_installation_fails() {
  createSpy -u -r "$SHUNIT_FALSE" install_zsh_program
  createSpy -u install_zsh_dotfiles
  createSpy -u set_zsh_as_default_shell

  install_zsh_wizard

  assertCallCount install_zsh_program 1
  assertNeverCalled install_zsh_dotfiles
}

# Run tests
SHPY_PATH="$THISDIR/../tests/shpy"
export SHPY_PATH
. "$THISDIR/../tests/shpy"
. "$THISDIR/../tests/shpy-shunit2"
. "$THISDIR/../tests/shunit2"
