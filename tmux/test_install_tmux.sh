#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
  DOTFILES="$(get_abs_path "$THISDIR/..")"
}

setUp() {
  . "$THISDIR/install_tmux.sh"
  # Isolate $HOME and scrub inherited env that would leak from the user
  HOME=${SHUNIT_TMPDIR:?}/home
  unset ZDOTDIR XDG_CONFIG_HOME XDG_DATA_HOME
  mkdir -p "$HOME"
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

  createSpy -u -o '3.4-1ubuntu0.1' get_version_in_pm

  assertContains "Should contain the version only" \
    "$(get_tmux_package_version)" "3.4"
}

test_install_returns_true_if_tmux_is_installed_with_desired_version() {
  createSpy -u -r "$SHUNIT_TRUE" is_tmux_installed
  createSpy -o 'tmux 3.1b' tmux

  output=$(install_tmux_program 3.1b)

  assertTrue "Tmux already installed should not be an error" $?
  assertContains "Should return immediately with msg" \
    "$output" "3.1b installed"
}

test_install_returns_true_if_installed_version_is_higher_than_desired() {
  createSpy -u -r "$SHUNIT_TRUE" is_tmux_installed
  createSpy -o 'tmux 3.4' tmux

  output=$(install_tmux_program 3.1b)

  assertTrue "Newer installed tmux should be accepted" $?
  assertContains "Should report the actual installed version" \
    "$output" "3.4 installed"
}

test_install_proceeds_with_dotfiles_when_installed_is_below_min_and_user_accepts() {
  createSpy -u -r "$SHUNIT_TRUE" is_tmux_installed
  createSpy -o 'tmux 3.0' tmux

  output=$(echo y | install_tmux_program 3.1b)

  assertTrue "Should return success so wizard installs dotfiles" $?
  assertContains "Should warn about the older version" \
    "$output" "installed version:    3.0"
  assertContains "Should prompt the user about proceeding" \
    "$output" "Install dotfiles anyway?"
}

test_install_aborts_when_installed_is_below_min_and_user_declines() {
  createSpy -u -r "$SHUNIT_TRUE" is_tmux_installed
  createSpy -o 'tmux 3.0' tmux

  output=$(echo n | install_tmux_program 3.1b)

  assertFalse "Should return non-zero when user declines" $?
  assertContains "Should warn about the older version" \
    "$output" "installed version:    3.0"
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

test_install_tmux_from_package_manager_when_pm_version_is_higher() {
  createSpy -u -r "$SHUNIT_FALSE" is_tmux_installed
  createSpy -u -o '3.4' get_tmux_package_version
  createSpy -u read_char
  createSpy -u install_from_pm

  output=$(install_tmux_program 3.1b)

  assertTrue "Higher PM version should be accepted and installed" $?
  assertContains "Should report the actual PM version installed" \
    "$output" "3.4 installed"
  assertCalledOnceWith install_from_pm tmux
}

test_install_tmux_from_source_in_custom_location() {
  createSpy -u -r "$SHUNIT_FALSE" is_tmux_installed
  createSpy -u -o '3.1b' get_tmux_package_version
  createSpy -u install_tmux_from_source
  # Path picking is covered in test_tui.sh (prompt_new_path); fake it here so
  # this test only checks that install_tmux_program forwards the chosen
  # location to the source build.
  prompt_new_path() { eval "$2=/opt/custom"; }

  # [n]o to package manager, [y]es to a custom location
  output=$(echo 'ny' | install_tmux_program 3.1b)

  assertTrue "Tmux installed from source should not be an error" $?
  assertCalledOnceWith install_tmux_from_source 3.1b "/opt/custom"
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
  # shellcheck disable=SC2034  # used by install_tmux_dotfiles, export pollutes the whole env
  XDG_CONFIG_HOME="$HOME/.myconfig"
  # shellcheck disable=SC2034  # used by install_tmux_dotfiles, export pollutes the whole env
  XDG_DATA_HOME="$HOME/.mydata"

  output=$(install_tmux_dotfiles)

  assertTrue "Should have created .myconfig/tmux dir" \
    "test -d $HOME/.myconfig/tmux"
  assertTrue "Should have created .mydata/tmux dir" \
    "test -d $HOME/.mydata/tmux"

  assertContains "Should include tmux source command in conf file" \
    "$(cat "$HOME"/.myconfig/tmux/tmux.conf)" "source-file"
}

test_tmux_conf_stub_ends_with_a_newline() {
  quietly install_tmux_dotfiles

  # $(...) strips trailing newlines, so an empty result means the last byte was \n
  assertEquals "Stub file should end with a newline" \
    "" "$(tail -c1 "$HOME/.config/tmux/tmux.conf")"
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

# install_tmux_program_step

test_install_tmux_program_step_forwards_pinned_version() {
  createSpy -u install_tmux_program

  install_tmux_program_step

  assertCalledOnceWith install_tmux_program "$TMUX_DESIRED_VERSION"
}

#
# wizard

test_wizard_delegates_step_list_to_wizard_run() {
  createSpy -u wizard_run

  # shellcheck disable=SC2119
  install_tmux_wizard

  assertCalledOnceWith wizard_run -- install_tmux_program_step install_tmux_dotfiles install_tpm install_tpm_plugins install_tmux_shell_bridge
}

#
# install_tmux_dotfiles XDG independence
#

test_tmux_dotfiles_wrapper_bakes_absolute_tmux_plugin_manager_path() {
  quietly install_tmux_dotfiles

  # The wrapper must set TMUX_PLUGIN_MANAGER_PATH to an absolute path so the
  # repo tmux.conf does not depend on XDG_DATA_HOME being exported by the
  # login shell at tmux start.
  assertContains "Wrapper should set TMUX_PLUGIN_MANAGER_PATH" \
    "$(cat "$HOME"/.config/tmux/tmux.conf)" \
    "set-environment -g TMUX_PLUGIN_MANAGER_PATH \"$HOME/.local/share/tmux/plugins\""
  assertNotContains "Wrapper should not reference XDG_DATA_HOME literally" \
    "$(cat "$HOME"/.config/tmux/tmux.conf)" 'XDG_DATA_HOME'
}

test_tmux_dotfiles_wrapper_bakes_user_conf_and_theme_conf() {
  quietly install_tmux_dotfiles

  wrapper="$HOME/.config/tmux/tmux.conf"
  # @user_conf must point at the wrapper itself (for the reload binding to
  # re-source the stub, picking up any machine-local additions).
  assertContains "Wrapper should set @user_conf to its own absolute path" \
    "$(cat "$wrapper")" \
    "set -g @user_conf \"$wrapper\""
  # @theme_conf must point at the repo's theme.conf (absolute path).
  assertContains "Wrapper should set @theme_conf to repo theme.conf" \
    "$(cat "$wrapper")" \
    "set -g @theme_conf \"$DOTFILES/tmux/theme.conf\""
}

#
# install_tmux_shell_bridge
#

test_shell_bridge_skips_when_zshrc_absent() {
  output=$(install_tmux_shell_bridge)

  assertTrue "Should succeed even without zshrc" $?
  assertContains "Should print a hint pointing to install_zsh.sh" \
    "$output" "install_zsh.sh"
}

test_shell_bridge_writes_marker_block_when_zshrc_exists() {
  mkdir -p "$HOME/.config/zsh"
  : > "$HOME/.config/zsh/.zshrc"

  echo n | quietly install_tmux_shell_bridge   # decline auto-enter

  zshrc_contents=$(cat "$HOME/.config/zsh/.zshrc")
  assertContains "Should have start marker" "$zshrc_contents" '# >>> dotfiles:tmux >>>'
  assertContains "Should have end marker"   "$zshrc_contents" '# <<< dotfiles:tmux <<<'
  # shellcheck disable=SC2016
  assertContains "Should source tmux-cmds.sh" \
    "$zshrc_contents" 'source "$DOTFILES/tmux/tmux-cmds.sh"'
  assertNotContains "Should not include auto-enter when declined" \
    "$zshrc_contents" 'tmux-enter'
}

test_shell_bridge_injects_auto_enter_when_opted_in() {
  mkdir -p "$HOME/.config/zsh"
  : > "$HOME/.config/zsh/.zshrc"

  echo y | quietly install_tmux_shell_bridge   # accept auto-enter

  zshrc_contents=$(cat "$HOME/.config/zsh/.zshrc")
  assertContains "Should include auto-enter call" \
    "$zshrc_contents" 'tmux-enter'
  assertContains "Should include terminal-emulator detection" \
    "$zshrc_contents" 'WT_SESSION'
}

test_shell_bridge_defaults_prompt_to_previous_auto_enter_choice() {
  mkdir -p "$HOME/.config/zsh"
  : > "$HOME/.config/zsh/.zshrc"

  # First install with auto-enter ON
  echo y | quietly install_tmux_shell_bridge
  assertContains "Initial block should have auto-enter" \
    "$(cat "$HOME/.config/zsh/.zshrc")" 'tmux-enter'

  # Re-run accepting default (empty input -> default). Previous=YES => default=YES.
  echo '' | quietly install_tmux_shell_bridge
  assertContains "Re-run with empty answer should keep auto-enter (default preserved)" \
    "$(cat "$HOME/.config/zsh/.zshrc")" 'tmux-enter'

  # Now explicitly turn it off
  echo n | quietly install_tmux_shell_bridge
  assertNotContains "After declining, auto-enter should be removed" \
    "$(cat "$HOME/.config/zsh/.zshrc")" 'tmux-enter'

  # Re-run accepting default. Previous=NO => default=NO.
  echo '' | quietly install_tmux_shell_bridge
  assertNotContains "Re-run with empty answer should keep no-auto-enter" \
    "$(cat "$HOME/.config/zsh/.zshrc")" 'tmux-enter'
}

#
# TPM: install + plugin materialization
#

test_is_tpm_installed_true_when_tpm_script_present() {
  plugins_dir="$HOME/.local/share/tmux/plugins"
  mkdir -p "$plugins_dir/tpm"
  printf '#!/bin/sh\n' > "$plugins_dir/tpm/tpm"
  chmod +x "$plugins_dir/tpm/tpm"

  is_tpm_installed
  assertTrue "TPM should be detected when tpm script exists" $?
}

test_is_tpm_installed_false_when_missing() {
  is_tpm_installed
  assertFalse "TPM should not be detected when missing" $?
}

test_install_tpm_skips_when_already_installed() {
  plugins_dir="$HOME/.local/share/tmux/plugins"
  mkdir -p "$plugins_dir/tpm"
  printf '#!/bin/sh\n' > "$plugins_dir/tpm/tpm"
  chmod +x "$plugins_dir/tpm/tpm"
  createSpy -u install_from_pm
  createSpy -u git

  output=$(install_tpm)

  assertTrue "Should not error when TPM is already installed" $?
  assertContains "Should report already installed" \
    "$output" "already installed"
  assertNeverCalled install_from_pm
  assertNeverCalled git
}

test_install_tpm_clones_pinned_version() {
  plugins_dir="$HOME/.local/share/tmux/plugins"
  createSpy -u install_from_pm   # guard against sudo apt-get
  createSpy -u git               # guard against real network clone

  quietly install_tpm
  rc=$?

  assertTrue "install_tpm should succeed" $rc
  # git is ensured before the clone
  assertCalledOnceWith install_from_pm git
  # Pinned version is cloned shallowly into plugins/tpm
  assertCalledOnceWith git \
    clone --depth=1 --branch "v${TPM_VERSION}" \
    -c advice.detachedHead=false "$TPM_REPO" "$plugins_dir/tpm"
}

test_install_tpm_plugins_runs_install_plugins() {
  plugins_dir="$HOME/.local/share/tmux/plugins"
  mkdir -p "$plugins_dir/tpm/bin"
  # Stub install_plugins so we can verify it was invoked
  cat > "$plugins_dir/tpm/bin/install_plugins" <<'EOF'
#!/bin/sh
echo "install_plugins called"
EOF
  chmod +x "$plugins_dir/tpm/bin/install_plugins"

  output=$(install_tpm_plugins)

  assertTrue "install_tpm_plugins should succeed" $?
  assertContains "Should actually run install_plugins" \
    "$output" "install_plugins called"
}

# Run tests
SHPY_PATH="$THISDIR/../tests/shpy"
export SHPY_PATH
. "$THISDIR/../tests/shpy"
. "$THISDIR/../tests/shpy-shunit2"
. "$THISDIR/../tests/shunit2"