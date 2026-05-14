#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  # shellcheck source=../tests/utils_for_test.sh
  . "$THISDIR/../tests/utils_for_test.sh"
  DOTFILES="$(get_abs_path "$THISDIR/..")"
}

setUp() {
  # shellcheck source=install_tmux.sh
  . "$THISDIR/install_tmux.sh"
  # Isolate $HOME for tests
  HOME=${SHUNIT_TMPDIR:?}/home
  mkdir -p "$HOME"
}

tearDown() {
  unset XDG_CONFIG_HOME XDG_DATA_HOME
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

  createSpy -u -o '3.4-1ubuntu0.1' get_version_in_pm

  assertContains "Should contain the version only" \
    "$(get_tmux_package_version)" "3.4"
}

test_get_tmux_release_version_extracts_version_from_redirect_header() {
  createSpy -u -o '  Location: https://github.com/tmux/tmux/releases/tag/3.1' get_tmux_release_headers
  assertEquals "3.1" "$(get_tmux_release_version)"

  createSpy -u -o '  Location: https://github.com/tmux/tmux/releases/tag/3.1b' get_tmux_release_headers
  assertEquals "3.1b" "$(get_tmux_release_version)"
}

test_get_tmux_release_version_returns_one_version_when_multiple_location_headers() {
  createSpy -u -o "  Location: https://github.com/tmux/tmux/releases/tag/3.6a
  Location: https://github.com/tmux/tmux/releases/tag/3.6a" get_tmux_release_headers

  assertEquals "3.6a" "$(get_tmux_release_version)"
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
  output=$(echo 'n''y''custom/location/' | install_tmux_program 3.1b)

  assertTrue "Tmux installed from source should not be an error" $?
  # It should trim trailing /
  assertCalledOnceWith mkdir -p "custom/location"
  assertCalledOnceWith install_tmux_from_source 3.1b "custom/location"
  assertContains "Should return after key press with msg" \
    "$output" "3.1b installed"
}

test_tmux_dotfiles_are_installed() {
  output=$(install_tmux_dotfiles)

  assertTrue "Should have created .local/share/tmux dir" \
    "test -d $HOME/.config/tmux"
  assertTrue "Should have created .config/tmux dir" \
    "test -d $HOME/.local/share/tmux"

  assertContains "Should include tmux source command in conf file" \
    "$(cat "$HOME"/.config/tmux/tmux.conf)" "source-file"
}

test_tmux_dotfiles_installation_respects_xdg_config_home() {
  XDG_CONFIG_HOME="$HOME/.myconfig"
  XDG_DATA_HOME="$HOME/.mydata"

  output=$(install_tmux_dotfiles)

  assertTrue "Should have created .myconfig/tmux dir" \
    "test -d $HOME/.myconfig/tmux"
  assertTrue "Should have created .mydata/tmux dir" \
    "test -d $HOME/.mydata/tmux"

  assertContains "Should include tmux source command in conf file" \
    "$(cat "$HOME"/.myconfig/tmux/tmux.conf)" "source-file"
}

test_existing_tmux_dotfiles_is_echoed_for_user_inspection() {
  mkdir -p "$HOME/.config/tmux"

  echo "# Some existing config" > "$HOME/.config/tmux/tmux.conf"

  output=$(echo 1 | install_tmux_dotfiles) # choose whatever option

  assertContains "Contents of existing file should be printed" \
    "$output" "# Some existing config"
}

test_existing_tmux_dotfiles_are_backed_up() {
  mkdir -p "$HOME/.config/tmux"

  echo "# Some existing config" > "$HOME/.config/tmux/tmux.conf"

  output=$(echo 1 | install_tmux_dotfiles) # choose backup

  assertTrue "Expected bkp" "test -f \"$HOME/.config/tmux/tmux.conf.bkp\""

  assertContains "Should include tmux source command in conf file" \
    "$(cat "$HOME"/.config/tmux/tmux.conf)" "source-file"
}

test_existing_tmux_dotfiles_is_appended() {
  mkdir -p "$HOME/.config/tmux"

  echo "# Some existing config" > "$HOME/.config/tmux/tmux.conf"

  output=$(echo 2 | install_tmux_dotfiles) # choose append

  assertContains "Should include original contents of conf file" \
    "$(cat "$HOME"/.config/tmux/tmux.conf)" "existing config"

  assertContains "Should include tmux source command in conf file" \
    "$(cat "$HOME"/.config/tmux/tmux.conf)" "source-file"
}

test_existing_tmux_dotfiles_is_overwritten() {
  mkdir -p "$HOME/.config/tmux"

  echo "# Some existing config" > "$HOME/.config/tmux/tmux.conf"

  output=$(echo 3 | install_tmux_dotfiles) # choose overwrite

  assertNotContains "Should not include original contents of conf file" \
    "$(cat "$HOME"/.config/tmux/tmux.conf)" "existing config"

  assertContains "Should include tmux source command in conf file" \
    "$(cat "$HOME"/.config/tmux/tmux.conf)" "source-file"
}

test_with_existing_tmux_dotfiles_user_can_cancel() {
  mkdir -p "$HOME/.config/tmux"

  echo "# Some existing config" > "$HOME/.config/tmux/tmux.conf"

  output=$(echo q | install_tmux_dotfiles) # choose quit

  assertContains "Expected cancellation message" \
    "$output" "tmux.conf not configured!"

  assertEquals "Should include only original contents of conf file" \
    "# Some existing config" "$(cat "$HOME"/.config/tmux/tmux.conf)"
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
SHPY_PATH="$THISDIR/../tests/shpy"
export SHPY_PATH
# shellcheck source=../tests/shpy
. "$THISDIR/../tests/shpy"
# shellcheck source=../tests/shpy-shunit2
. "$THISDIR/../tests/shpy-shunit2"
# shellcheck source=../tests/shunit2
. "$THISDIR/../tests/shunit2"