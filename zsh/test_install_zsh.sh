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
  # Isolate XDG so $ZDOTDIR / $HISTFILE land inside the test tmpdir too
  XDG_CONFIG_HOME=${SHUNIT_TMPDIR:?}/xdg-config
  XDG_DATA_HOME=${SHUNIT_TMPDIR:?}/xdg-data
  mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
  unset ZDOTDIR
}

tearDown() {
  cleanupSpies
  cleanupTestDir
}

#
# install_zsh_program
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

#
# install_zsh_zshenv (deployed at $HOME/.zshenv)
#

test_zshenv_stub_is_installed() {
  quietly install_zsh_zshenv

  assertTrue "Should have created \$HOME/.zshenv" "test -f $HOME/.zshenv"

  # shellcheck disable=SC2016
  assertContains "Should source zshenv-base from dotfiles repo" \
    "$(cat "$HOME/.zshenv")" 'source "$DOTFILES/zsh/zshenv-base"'

  assertContains "Should export real DOTFILES path" \
    "$(cat "$HOME/.zshenv")" "export DOTFILES=$DOTFILES"
}

test_zshenv_stub_ends_with_a_newline() {
  quietly install_zsh_zshenv

  # $(...) strips trailing newlines, so an empty result means the last byte was \n
  assertEquals "Stub file should end with a newline" \
    "" "$(tail -c1 "$HOME/.zshenv")"
}

test_zshenv_block_has_start_and_end_markers() {
  quietly install_zsh_zshenv

  contents=$(cat "$HOME/.zshenv")
  assertContains "Should contain start marker" "$contents" "# >>> dotfiles:zsh >>>"
  assertContains "Should contain end marker"   "$contents" "# <<< dotfiles:zsh <<<"
}

#
# install_zsh_zshrc_stub (deployed at $ZDOTDIR/.zshrc with marker block)
#

test_zshrc_stub_is_created_with_marker_block() {
  quietly install_zsh_zshrc_stub

  zshrc="$XDG_CONFIG_HOME/zsh/.zshrc"
  assertTrue "Should have created \$ZDOTDIR/.zshrc" "test -f $zshrc"

  contents=$(cat "$zshrc")
  assertContains "Should contain start marker" "$contents" "# >>> dotfiles:zsh >>>"
  assertContains "Should contain end marker"   "$contents" "# <<< dotfiles:zsh <<<"
  # shellcheck disable=SC2016
  assertContains "Should source repo base .zshrc" \
    "$contents" 'source "$DOTFILES/zsh/zshrc-base"'
}

test_zshrc_stub_creates_zdotdir_if_missing() {
  quietly install_zsh_zshrc_stub
  assertTrue "Should create \$ZDOTDIR" "test -d $XDG_CONFIG_HOME/zsh"
}

test_zshrc_stub_creates_history_dir() {
  quietly install_zsh_zshrc_stub
  assertTrue "Should create \$XDG_DATA_HOME/zsh for HISTFILE" \
    "test -d $XDG_DATA_HOME/zsh"
}

test_zshrc_stub_creates_cache_dir() {
  XDG_CACHE_HOME=${SHUNIT_TMPDIR:?}/xdg-cache

  quietly install_zsh_zshrc_stub
  assertTrue "Should create \$XDG_CACHE_HOME/zsh for zcompdump/zcompcache" \
    "test -d $XDG_CACHE_HOME/zsh"
}

test_zshrc_stub_prints_polite_note_when_home_zshrc_exists() {
  echo "# legacy ~/.zshrc" > "$HOME/.zshrc"

  output=$(install_zsh_zshrc_stub)

  assertContains "Should warn about pre-existing \$HOME/.zshrc" \
    "$output" "\$HOME/.zshrc exists"
  assertContains "Should mention new ZDOTDIR location" \
    "$output" "$XDG_CONFIG_HOME/zsh"
}

test_zshrc_stub_does_not_print_note_when_no_home_zshrc() {
  output=$(install_zsh_zshrc_stub)
  assertNotContains "Should be silent about \$HOME/.zshrc when absent" \
    "$output" "\$HOME/.zshrc exists"
}

#
# install_zsh_dotfiles (orchestrates both stubs)
#

test_dotfiles_installs_both_zshenv_and_zshrc_stub() {
  createSpy -u install_zsh_zshenv
  createSpy -u install_zsh_zshrc_stub

  install_zsh_dotfiles

  assertCallCount install_zsh_zshenv 1
  assertCallCount install_zsh_zshrc_stub 1
}

test_dotfiles_skips_zshrc_stub_when_zshenv_fails() {
  createSpy -u -r "$SHUNIT_FALSE" install_zsh_zshenv
  createSpy -u install_zsh_zshrc_stub

  install_zsh_dotfiles

  assertCallCount install_zsh_zshenv 1
  assertNeverCalled install_zsh_zshrc_stub
}

#
# chsh / default-shell helpers
#

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

#
# wizard
#

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
