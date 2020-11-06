#!/usr/bin/env sh

readonly THISDIR=$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)

oneTimeSetUp() {
  # shellcheck source=../utils_for_test.sh
  . "$THISDIR/../utils_for_test.sh"
}

setUp() {
  # Source deploy.sh with a defined DOTFILES path
  # shellcheck source=../../deploy.sh
  DOTFILES="$(CDPATH='' cd -- "$THISDIR/../.." >/dev/null && pwd -P)" \
    dotfiles_dont_run=1 . "$THISDIR/../../deploy.sh"
}

tearDown() {
  cleanupSpies
  cleanupTestDir
}

#
# Tests
#

test_deploy_wizard_installs_basic_packages() {
  createSpy -u -r "$SHUNIT_TRUE" check_supported_pm
  # Basic packages not installed
  createSpy -u -r "$SHUNIT_FALSE" command_exists
  createSpy -u install_from_pm
  createSpy -u start_tmux_wizard

  message="$(yes | deploy_wizard)"

  assertContains "Expected continuation message" \
    "$message" "basic packages first"
  assertCallCount install_from_pm 1
  assertCallCount start_tmux_wizard 1
}

test_deploy_wizard_skips_basic_packages_if_installed() {
  # Basic packages are installed
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  createSpy -u start_tmux_wizard

  message="$(yes | deploy_wizard)"

  assertNotContains "Continuation message not expected" \
    "$message" "basic packages first"
  assertCallCount install_from_pm 0
  assertCallCount start_tmux_wizard 1
}

test_deploy_wizard_dies_if_basic_packages_fail() {
  createSpy -u -r "$SHUNIT_TRUE" check_supported_pm
  # Basic packages not installed
  createSpy -u -r "$SHUNIT_FALSE" command_exists
  # Installing packages fail
  createSpy -u -r "$SHUNIT_FALSE" install_from_pm

  message="$(yes | deploy_wizard)"

  assertFalse "Error code expected" $?
  assertContains "Expected dying message" \
    "$message" "Couldn't install basic packages"
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