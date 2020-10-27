#!/usr/bin/env sh

readonly THISDIR=$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)

setUp() {
  # shellcheck source=../../tmux/install_tmux.sh
  . "$THISDIR/../../tmux/install_tmux.sh"
}

tearDown() {
  cleanupSpies
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

test_wizard_returns_if_tmux_is_installed_with_desired_version() {
  createSpy -u -r "$SHUNIT_TRUE" is_tmux_installed
  createSpy -o 'tmux 3.1b' tmux

  output=$(install_tmux_wizard)

  assertTrue "Tmux already installed should not be an error" $?
  assertContains "Should return immediately with msg" \
    "$output" "3.1b already installed"
}

test_wizard_returns_error_if_tmux_is_installed_with_another_version() {
  createSpy -u -r "$SHUNIT_TRUE" is_tmux_installed
  createSpy -o 'tmux 3.1a' tmux
  createSpy -u read_char

  output=$(install_tmux_wizard)

  assertFalse "Tmux installed with different version should be an error" $?
  assertContains "Should return after key press with msg" \
    "$output" "installed version: 3.1a"
  assertCalledOnceWith read_char silent
}

test_wizard_installs_tmux_from_package_manager_if_version_matches() {
  createSpy -u -r "$SHUNIT_FALSE" is_tmux_installed
  createSpy -u -o '3.1b' get_tmux_package_version
  createSpy -u read_char
  createSpy -u install_from_pm

  output=$(install_tmux_wizard)

  assertTrue "Tmux installed from package manager should not be an error" $?
  assertContains "Should return after key press with msg" \
    "$output" "3.1b installed"
  assertCallCount read_char 1
}

test_wizard_installs_tmux_from_source_in_custom_location() {
  createSpy -u -r "$SHUNIT_FALSE" is_tmux_installed
  createSpy -u -o 'not_desired' get_tmux_package_version
  createSpy mkdir
  createSpy -u install_tmux_from_source

  output=$(echo 'y''custom_location' | install_tmux_wizard)

  assertTrue "Tmux installed from source should not be an error" $?
  assertCalledOnceWith mkdir -p "custom_location"
  assertCalledOnceWith install_tmux_from_source 3.1b "custom_location"
  assertContains "Should return after key press with msg" \
    "$output" "3.1b installed"
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