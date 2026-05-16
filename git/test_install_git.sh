#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
  DOTFILES="$(get_abs_path "$THISDIR/..")"
}

setUp() {
  . "$THISDIR/install_git.sh"
}

tearDown() {
  cleanupSpies
  cleanupTestDir
}

#
# install_git_program
#

test_install_returns_true_if_git_is_already_installed() {
  createSpy -u -r "$SHUNIT_TRUE" is_git_installed
  createSpy -u install_from_pm

  output=$(install_git_program)

  assertTrue "git already installed should not be an error" $?
  assertContains "Should report already installed" \
    "$output" "git already installed"
  assertNeverCalled install_from_pm
}

test_install_git_from_package_manager_when_not_installed() {
  createSpy -u -r "$SHUNIT_FALSE" is_git_installed
  createSpy -u install_from_pm

  output=$(install_git_program)

  assertTrue "git installed from package manager should not be an error" $?
  assertCalledOnceWith install_from_pm git
  assertContains "Should report installed" "$output" "git installed"
}

#
# set_git_global_config
#

test_set_git_global_config_sets_value_when_unconfigured() {
  createSpy -u -o "" git

  output=$(set_git_global_config init.templateDir "/some/path" "git templates")

  assertCallCount git 2
  assertCalledWith git config --global --get init.templateDir
  assertCalledWith git config --global init.templateDir "/some/path"
  assertContains "$output" "git templates configured"
}

test_set_git_global_config_skips_when_current_equals_target() {
  createSpy -u -o "/some/path" git

  output=$(set_git_global_config init.templateDir "/some/path" "git templates")

  assertCallCount git 1
  assertContains "$output" "already configured"
}

test_set_git_global_config_overwrites_when_user_confirms() {
  createSpy -u -o "/other/path" git

  output=$(echo y | set_git_global_config init.templateDir "/some/path" "git templates")

  assertCallCount git 2
  assertCalledWith git config --global --get init.templateDir
  assertCalledWith git config --global init.templateDir "/some/path"
  assertContains "$output" "git templates configured"
}

test_set_git_global_config_keeps_existing_when_user_declines() {
  createSpy -u -o "/other/path" git

  output=$(echo n | set_git_global_config init.templateDir "/some/path" "git templates")

  assertCallCount git 1
  assertContains "$output" "not configured"
}

test_set_git_global_config_defaults_label_to_key_when_omitted() {
  createSpy -u -o "" git

  output=$(set_git_global_config init.templateDir "/some/path")

  assertContains "Should use key as label" "$output" "init.templateDir configured"
}

#
# install_git_templates
#

test_templates_delegates_to_set_git_global_config() {
  createSpy -u set_git_global_config

  install_git_templates

  assertCalledOnceWith set_git_global_config \
    init.templateDir "$DOTFILES/git/templates" "git templates"
}

#
# install_git_excludesfile
#

test_excludesfile_delegates_to_set_git_global_config() {
  createSpy -u set_git_global_config

  install_git_excludesfile

  assertCalledOnceWith set_git_global_config \
    core.excludesfile "$DOTFILES/git/.gitignore.global" "git excludesfile"
}

#
# install_git_default_branch
#

test_default_branch_delegates_to_set_git_global_config() {
  createSpy -u set_git_global_config

  install_git_default_branch

  assertCalledOnceWith set_git_global_config \
    init.defaultBranch "main" "git init.defaultBranch"
}

#
# configure_git_user
#

test_configure_user_offers_change_for_existing_values_default_no() {
  # Two reads return current values; no writes follow when user declines (default N).
  createSpy -u -o "Alice" -o "bob@example.com" git

  output=$(printf '\n\n' | configure_git_user)

  assertCallCount git 2
  assertContains "Should display existing user.name" "$output" "[Alice]"
  assertContains "Should display existing user.email" "$output" "[bob@example.com]"
}

test_configure_user_sets_values_when_unset_and_user_accepts() {
  # Reads return empty (default Y); writes happen after prompt_line input.
  createSpy -u -o "" git

  # Per loop iter: confirm-y (newline → default Y), prompt_line answer
  printf '\nMy Name\n\nme@example.com\n' | quietly configure_git_user

  assertCallCount git 4
  assertCalledWith git config --global --get user.name
  assertCalledWith git config --global user.name "My Name"
  assertCalledWith git config --global --get user.email
  assertCalledWith git config --global user.email "me@example.com"
}

test_configure_user_skips_when_value_input_is_empty() {
  createSpy -u -o "" git

  # Confirm yes for both, but provide empty answers
  printf '\n\n\n\n' | quietly configure_git_user

  # Only the two reads, no writes
  assertCallCount git 2
}

#
# install_git_wizard
#

test_wizard_chains_calls() {
  createSpy -u install_git_program
  createSpy -u install_git_templates
  createSpy -u install_git_excludesfile
  createSpy -u install_git_default_branch
  createSpy -u configure_git_user

  install_git_wizard

  assertCallCount install_git_program 1
  assertCallCount install_git_templates 1
  assertCallCount install_git_excludesfile 1
  assertCallCount install_git_default_branch 1
  assertCallCount configure_git_user 1
}

test_wizard_stops_when_program_install_fails() {
  createSpy -u -r "$SHUNIT_FALSE" install_git_program
  createSpy -u install_git_templates
  createSpy -u install_git_excludesfile
  createSpy -u install_git_default_branch
  createSpy -u configure_git_user

  install_git_wizard

  assertCallCount install_git_program 1
  assertNeverCalled install_git_templates
  assertNeverCalled install_git_excludesfile
  assertNeverCalled install_git_default_branch
  assertNeverCalled configure_git_user
}

test_wizard_stops_when_templates_install_fails() {
  createSpy -u install_git_program
  createSpy -u -r "$SHUNIT_FALSE" install_git_templates
  createSpy -u install_git_excludesfile
  createSpy -u install_git_default_branch
  createSpy -u configure_git_user

  install_git_wizard

  assertCallCount install_git_templates 1
  assertNeverCalled install_git_excludesfile
  assertNeverCalled install_git_default_branch
  assertNeverCalled configure_git_user
}

test_wizard_stops_when_excludesfile_install_fails() {
  createSpy -u install_git_program
  createSpy -u install_git_templates
  createSpy -u -r "$SHUNIT_FALSE" install_git_excludesfile
  createSpy -u install_git_default_branch
  createSpy -u configure_git_user

  install_git_wizard

  assertCallCount install_git_excludesfile 1
  assertNeverCalled install_git_default_branch
  assertNeverCalled configure_git_user
}

test_wizard_stops_when_default_branch_install_fails() {
  createSpy -u install_git_program
  createSpy -u install_git_templates
  createSpy -u install_git_excludesfile
  createSpy -u -r "$SHUNIT_FALSE" install_git_default_branch
  createSpy -u configure_git_user

  install_git_wizard

  assertCallCount install_git_default_branch 1
  assertNeverCalled configure_git_user
}

# Run tests
SHPY_PATH="$THISDIR/../tests/shpy"
export SHPY_PATH
. "$THISDIR/../tests/shpy"
. "$THISDIR/../tests/shpy-shunit2"
. "$THISDIR/../tests/shunit2"
