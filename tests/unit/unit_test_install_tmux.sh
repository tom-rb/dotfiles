#!/usr/bin/env sh

readonly THISDIR=$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)

oneTimeSetUp() {
  # shellcheck source=../utils_for_test.sh
  . "$THISDIR/../utils_for_test.sh"
}

setUp() {
  # shellcheck source=../../tmux/install_tmux.sh
  . "$THISDIR/../../tmux/install_tmux.sh"
}

tearDown() {
  cleanupSpies
  cleanupTestDir
}

#
# Tests
#

test_get_tmux_package_version_extracts_tmux_version() {
  createSpy -u -o '3.1-ubuntu-suffix' get_version_in_pm

  assertContains "Should contain the version only" \
    "$(get_tmux_package_version)" "3.1"

  createSpy -u -o '3.1b-ubuntu-suffix' get_version_in_pm

  assertContains "Should contain the version only" \
    "$(get_tmux_package_version)" "3.1b"
}

test_tmux_dotfiles_are_installed() {
  XDG_CONFIG_HOME=${SHUNIT_TMPDIR:?}/.config
  XDG_DATA_HOME=${SHUNIT_TMPDIR:?}/.local/share

  output=$(install_tmux_dotfiles)

  assertTrue "Should have created .local/share/tmux dir" \
    "test -d $XDG_CONFIG_HOME/tmux"
  assertTrue "Should have created .config/tmux dir" \
    "test -d $XDG_DATA_HOME/tmux"

  assertContains "Should include tmux source command in conf file" \
    "$(cat "$XDG_CONFIG_HOME"/tmux/tmux.conf)" "source-file"
}

test_existing_tmux_dotfiles_is_echoed_for_user_inspection() {
  XDG_CONFIG_HOME="${SHUNIT_TMPDIR:?}/user  name/.config"
  XDG_DATA_HOME=${SHUNIT_TMPDIR:?}/.local/share
  mkdir -p "$XDG_CONFIG_HOME/tmux"

  echo "# Some existing config" > "$XDG_CONFIG_HOME/tmux/tmux.conf"

  output=$(echo 1 | install_tmux_dotfiles) # choose whatever option

  assertContains "Contents of existing file should be printed" \
    "$output" "# Some existing config"
}

test_existing_tmux_dotfiles_are_backed_up() {
  XDG_CONFIG_HOME="${SHUNIT_TMPDIR:?}/user  name/.config"
  XDG_DATA_HOME=${SHUNIT_TMPDIR:?}/.local/share
  mkdir -p "$XDG_CONFIG_HOME/tmux"

  echo "# Some existing config" > "$XDG_CONFIG_HOME/tmux/tmux.conf"

  output=$(echo 1 | install_tmux_dotfiles) # choose backup

  assertTrue "Expected bkp" "test -f \"$XDG_CONFIG_HOME/tmux/tmux.conf.bkp\""

  assertContains "Should include tmux source command in conf file" \
    "$(cat "$XDG_CONFIG_HOME"/tmux/tmux.conf)" "source-file"
}

test_existing_tmux_dotfiles_is_appended() {
  XDG_CONFIG_HOME="${SHUNIT_TMPDIR:?}/user  name/.config"
  XDG_DATA_HOME=${SHUNIT_TMPDIR:?}/.local/share
  mkdir -p "$XDG_CONFIG_HOME/tmux"

  echo "# Some existing config" > "$XDG_CONFIG_HOME/tmux/tmux.conf"

  output=$(echo 2 | install_tmux_dotfiles) # choose append

  assertContains "Should include original contents of conf file" \
    "$(cat "$XDG_CONFIG_HOME"/tmux/tmux.conf)" "existing config"

  assertContains "Should include tmux source command in conf file" \
    "$(cat "$XDG_CONFIG_HOME"/tmux/tmux.conf)" "source-file"
}

test_existing_tmux_dotfiles_is_overwritten() {
  XDG_CONFIG_HOME="${SHUNIT_TMPDIR:?}/user  name/.config"
  XDG_DATA_HOME=${SHUNIT_TMPDIR:?}/.local/share
  mkdir -p "$XDG_CONFIG_HOME/tmux"

  echo "# Some existing config" > "$XDG_CONFIG_HOME/tmux/tmux.conf"

  output=$(echo 3 | install_tmux_dotfiles) # choose overwrite

  assertNotContains "Should not include original contents of conf file" \
    "$(cat "$XDG_CONFIG_HOME"/tmux/tmux.conf)" "existing config"

  assertContains "Should include tmux source command in conf file" \
    "$(cat "$XDG_CONFIG_HOME"/tmux/tmux.conf)" "source-file"
}

test_with_existing_tmux_dotfiles_user_can_cancel() {
  XDG_CONFIG_HOME="${SHUNIT_TMPDIR:?}/user  name/.config"
  XDG_DATA_HOME=${SHUNIT_TMPDIR:?}/.local/share
  mkdir -p "$XDG_CONFIG_HOME/tmux"

  echo "# Some existing config" > "$XDG_CONFIG_HOME/tmux/tmux.conf"

  output=$(echo q | install_tmux_dotfiles) # choose quit

  assertContains "Expected cancellation message" \
    "$output" "tmux.conf not configured!"

  assertEquals "Should include only original contents of conf file" \
    "# Some existing config" "$(cat "$XDG_CONFIG_HOME"/tmux/tmux.conf)"
}

test_install_returns_true_if_tmux_is_installed_with_desired_version() {
  createSpy -u -r "$SHUNIT_TRUE" is_tmux_installed
  createSpy -o 'tmux 3.1b' tmux

  output=$(install_tmux_program 3.1b)

  assertTrue "Tmux already installed should not be an error" $?
  assertContains "Should return immediately with msg" \
    "$output" "3.1b already installed"
}

test_install_returns_error_if_tmux_is_installed_with_another_version() {
  createSpy -u -r "$SHUNIT_TRUE" is_tmux_installed
  createSpy -o 'tmux 3.1a' tmux
  createSpy -u read_char

  output=$(install_tmux_program 3.1b)

  assertFalse "Tmux installed with different version should be an error" $?
  assertContains "Should return after key press with msg" \
    "$output" "installed version: 3.1a"
  assertCalledOnceWith read_char silent
}

test_install_tmux_from_package_manager_when_version_matches() {
  createSpy -u -r "$SHUNIT_FALSE" is_tmux_installed
  createSpy -u -o '3.1b' get_tmux_package_version
  createSpy -u read_char
  createSpy -u install_from_pm

  output=$(install_tmux_program 3.1b)

  assertTrue "Tmux installed from package manager should not be an error" $?
  assertContains "Should return after key press with msg" \
    "$output" "3.1b installed"
  assertCallCount read_char 1
}

test_install_tmux_from_source_in_custom_location() {
  createSpy -u -r "$SHUNIT_FALSE" is_tmux_installed
  createSpy -u -o '3.1b' get_tmux_package_version
  createSpy mkdir
  createSpy -u install_tmux_from_source

  # [n]ot install from package manager, [y]es in a custom location
  output=$(echo 'n''y''custom_location' | install_tmux_program 3.1b)

  assertTrue "Tmux installed from source should not be an error" $?
  assertCalledOnceWith mkdir -p "custom_location"
  assertCalledOnceWith install_tmux_from_source 3.1b "custom_location"
  assertContains "Should return after key press with msg" \
    "$output" "3.1b installed"
}

test_wizard_installs_dotfiles_when_tmux_is_installed() {
  createSpy -u install_tmux_program
  createSpy -u install_tmux_dotfiles

  install_tmux_wizard

  assertCallCount install_tmux_program 1
  assertCallCount install_tmux_dotfiles 1
}

test_wizard_does_not_install_dotfiles_when_tmux_installation_fails() {
  createSpy -u -r "$SHUNIT_FALSE" install_tmux_program
  createSpy -u install_tmux_dotfiles

  install_tmux_wizard

  assertCallCount install_tmux_program 1
  assertNeverCalled install_tmux_dotfiles
}

# Run tests
SHPY_PATH="$THISDIR/../shpy"
export SHPY_PATH
# shellcheck source=../shpy
. "$THISDIR/../shpy"
# shellcheck source=../shpy-shunit2
. "$THISDIR/../shpy-shunit2"
# shellcheck source=../shunit2
. "$THISDIR/../shunit2"