#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
  DOTFILES="$(get_abs_path "$THISDIR/..")"
}

setUp() {
  . "$THISDIR/install_pi.sh"
  HOME=${SHUNIT_TMPDIR:?}/home
  mkdir -p "$HOME"
}

tearDown() {
  cleanupSpies
  cleanupTestDir
}

#
# ensure_node_installed
#

test_ensure_node_returns_early_when_node_is_present() {
  # node present; neither bootstrap path should be touched.
  command_exists() { [ "$1" = node ]; }
  createSpy -u asdf
  createSpy -u install_from_pm

  ensure_node_installed

  assertTrue "Should succeed when node is already present" $?
  assertNeverCalled asdf
  assertNeverCalled install_from_pm
}

test_ensure_node_installs_via_asdf_when_user_confirms() {
  # node absent, asdf present, user accepts.
  command_exists() { [ "$1" = asdf ]; }
  createSpy -u -r "$SHUNIT_TRUE" confirm
  createSpy -u asdf
  createSpy -u ensure_node_runtime_libs

  quietly ensure_node_installed
  assertTrue "Should succeed on the asdf path" $?

  assertCalledWith asdf plugin add nodejs
  assertCalledWith asdf install nodejs latest
  assertCalledWith asdf set -u nodejs latest
  assertCalledWith asdf reshim nodejs
  assertCalledOnceWith ensure_node_runtime_libs
}

test_ensure_node_dies_when_asdf_install_is_declined() {
  command_exists() { [ "$1" = asdf ]; }
  createSpy -u -r "$SHUNIT_FALSE" confirm
  createSpy -u asdf

  output=$( (ensure_node_installed) 2>&1 )

  assertFalse "Should fail when the asdf install is declined" $?
  assertContains "Should explain node is required" \
    "$output" "node is required to install pi."
  assertNeverCalled asdf
}

test_ensure_node_installs_via_pm_when_user_confirms() {
  # node absent, no asdf, supported package manager, user accepts.
  command_exists() { return 1; }
  createSpy -u -r "$SHUNIT_TRUE" check_supported_pm
  createSpy -u -o "apt-get" get_supported_pm
  createSpy -u -r "$SHUNIT_TRUE" confirm
  createSpy -u install_from_pm
  createSpy -u ensure_node_runtime_libs

  quietly ensure_node_installed
  assertTrue "Should succeed on the package-manager path" $?

  assertCalledOnceWith install_from_pm nodejs npm
  assertCalledOnceWith ensure_node_runtime_libs
}

test_ensure_node_dies_when_pm_install_is_declined() {
  command_exists() { return 1; }
  createSpy -u -r "$SHUNIT_TRUE" check_supported_pm
  createSpy -u -o "apt-get" get_supported_pm
  createSpy -u -r "$SHUNIT_FALSE" confirm
  createSpy -u install_from_pm

  output=$( (ensure_node_installed) 2>&1 )

  assertFalse "Should fail when the package-manager install is declined" $?
  assertContains "Should explain node is required" \
    "$output" "node is required to install pi."
  assertNeverCalled install_from_pm
}

test_ensure_node_dies_when_no_asdf_and_no_supported_pm() {
  command_exists() { return 1; }
  createSpy -u -r "$SHUNIT_FALSE" check_supported_pm

  output=$( (ensure_node_installed) 2>&1 )

  assertFalse "Should fail when no install method is available" $?
  assertContains "Should tell the user to install node manually" \
    "$output" "Install node manually"
}

#
# ensure_node_runtime_libs
#

test_node_runtime_libs_noop_when_node_runs() {
  createSpy -u node   # default spy returns 0: `node --version` "works"
  createSpy -u install_from_pm

  ensure_node_runtime_libs

  assertTrue "Should succeed when node already runs" $?
  assertNeverCalled install_from_pm
}

test_node_runtime_libs_installs_libatomic_when_node_cannot_load() {
  createSpy -u -r "$SHUNIT_FALSE" node   # node can't load its shared libraries
  createSpy -u -r "$SHUNIT_TRUE" check_supported_pm
  createSpy -u install_from_pm

  ensure_node_runtime_libs

  assertCalledOnceWith install_from_pm libatomic
}

test_node_runtime_libs_noop_when_no_package_manager() {
  createSpy -u -r "$SHUNIT_FALSE" node
  createSpy -u -r "$SHUNIT_FALSE" check_supported_pm
  createSpy -u install_from_pm

  ensure_node_runtime_libs

  assertTrue "Should not error when no PM is available" $?
  assertNeverCalled install_from_pm
}

#
# install_pi_program
#

test_install_pi_program_short_circuits_when_already_installed() {
  createSpy -u -r "$SHUNIT_TRUE" is_pi_installed
  createSpy -u ensure_node_installed
  createSpy -u npm

  output=$(install_pi_program)

  assertTrue "Already-installed should not be an error" $?
  assertContains "Should report already installed" \
    "$output" "pi already installed"
  assertNeverCalled ensure_node_installed
  assertNeverCalled npm
}

test_install_pi_program_installs_pinned_package_globally() {
  createSpy -u -r "$SHUNIT_FALSE" is_pi_installed
  createSpy -u ensure_node_installed
  createSpy -u npm
  command_exists() { return 1; }   # asdf absent

  output=$(install_pi_program)

  assertTrue "Install should not be an error" $?
  assertCalledOnceWith npm install -g --ignore-scripts \
    "@earendil-works/pi-coding-agent@${PI_VERSION}"
  assertContains "Should report the pinned version installed" \
    "$output" "pi ${PI_VERSION} installed"
}

test_install_pi_program_reshims_when_node_is_asdf_managed() {
  createSpy -u -r "$SHUNIT_FALSE" is_pi_installed
  createSpy -u ensure_node_installed
  createSpy -u npm
  command_exists() { [ "$1" = asdf ]; }   # asdf present
  createSpy -u asdf

  quietly install_pi_program
  assertTrue "Install should not be an error" $?

  assertCalledOnceWith asdf reshim nodejs
}

test_install_pi_program_skips_reshim_when_asdf_absent() {
  createSpy -u -r "$SHUNIT_FALSE" is_pi_installed
  createSpy -u ensure_node_installed
  createSpy -u npm
  command_exists() { return 1; }   # asdf absent
  createSpy -u asdf

  quietly install_pi_program

  assertNeverCalled asdf
}

test_install_pi_program_fails_when_npm_install_fails() {
  createSpy -u -r "$SHUNIT_FALSE" is_pi_installed
  createSpy -u ensure_node_installed
  createSpy -u -r "$SHUNIT_FALSE" npm   # npm exits non-zero
  command_exists() { return 1; }   # asdf absent
  createSpy -u asdf

  output=$(install_pi_program 2>&1)

  assertFalse "Should fail when npm install fails" $?
  assertNotContains "Must not falsely report success" \
    "$output" "pi ${PI_VERSION} installed"
  assertContains "Should surface the failure" "$output" "Failed to install"
  assertNeverCalled asdf   # must not reshim after a failed install
}

test_install_pi_program_aborts_when_node_bootstrap_fails() {
  createSpy -u -r "$SHUNIT_FALSE" is_pi_installed
  createSpy -u -r "$SHUNIT_FALSE" ensure_node_installed
  createSpy -u npm

  quietly install_pi_program

  assertFalse "Should propagate the node bootstrap failure" $?
  assertNeverCalled npm
}

#
# install_pi_wizard
#

test_wizard_delegates_step_list_to_wizard_run() {
  createSpy -u wizard_run

  # shellcheck disable=SC2119
  install_pi_wizard

  assertCalledOnceWith wizard_run -- install_pi_program install_pi_skills
}

test_wizard_skips_skills_when_program_step_fails() {
  createSpy -u -r "$SHUNIT_FALSE" install_pi_program
  createSpy -u install_pi_skills

  # shellcheck disable=SC2119
  install_pi_wizard

  assertFalse "Wizard should fail when the program step fails" $?
  assertNeverCalled install_pi_skills
}

# Regression: a failing npm install used to slip through wizard_run because the
# `step || ...` call site disables `set -e` inside install_pi_program's
# subshell, so it reported success and the wizard went on to install skills.
test_wizard_does_not_install_skills_when_npm_install_fails() {
  createSpy -u -r "$SHUNIT_FALSE" is_pi_installed
  createSpy -u ensure_node_installed
  createSpy -u -r "$SHUNIT_FALSE" npm
  command_exists() { return 1; }   # asdf absent
  createSpy -u install_pi_skills

  quietly install_pi_wizard -y

  assertFalse "Wizard should fail when npm install fails" $?
  assertNeverCalled install_pi_skills
}

SHPY_PATH="$THISDIR/../tests/shpy"
export SHPY_PATH
. "$THISDIR/../tests/shpy"
. "$THISDIR/../tests/shpy-shunit2"
. "$THISDIR/../tests/shunit2"
