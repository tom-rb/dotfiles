#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
}

setUp() {
  # Source deploy.sh with a defined DOTFILES path
  DOTFILES="$(CDPATH='' cd -- "$THISDIR/.." >/dev/null && pwd -P)" \
    dotfiles_dont_run=1 . "$THISDIR/../deploy.sh"
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
  createSpy -u start_module_wizard
  createSpy -u activate_asdf

  message="$(yes | deploy_wizard)"

  assertContains "Expected continuation message" \
    "$message" "Basic packages needed:"
  assertCallCount install_from_pm 1
  # The step line and its ✓ are install_from_pm's own doing; utils/test_pm.sh
  # covers them. Here only the label it was asked to report under matters.
  assertCalledWith install_from_pm --as "basic packages" \
    --die "Couldn't install basic packages" -- wget tar gzip
  # Once unconditionally at startup, once more after a fresh asdf install.
  assertCallCount activate_asdf 2
  assertCallCount start_module_wizard 6
  assertCalledWith start_module_wizard zsh
  assertCalledWith start_module_wizard zimfw
  assertCalledWith start_module_wizard asdf
  assertCalledWith start_module_wizard tmux
  assertCalledWith start_module_wizard git
  assertCalledWith start_module_wizard pi
}

test_deploy_wizard_skips_basic_packages_if_installed() {
  # Basic packages are installed
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  createSpy -u start_module_wizard
  createSpy -u activate_asdf

  message="$(yes | deploy_wizard)"

  assertNotContains "Continuation message not expected" \
    "$message" "Basic packages needed:"
  assertCallCount install_from_pm 0
  assertCallCount start_module_wizard 6
  assertCalledWith start_module_wizard zsh
  assertCalledWith start_module_wizard zimfw
  assertCalledWith start_module_wizard asdf
  assertCalledWith start_module_wizard tmux
  assertCalledWith start_module_wizard git
  assertCalledWith start_module_wizard pi
}

test_deploy_wizard_skips_zimfw_when_zsh_declined() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  createSpy -u start_module_wizard

  # Decline zsh; accept the rest. confirm reads one byte per call.
  printf 'n\ny\ny\ny\n' | deploy_wizard >/dev/null

  assertCallCount start_module_wizard 3
  assertCalledWith start_module_wizard tmux
  assertCalledWith start_module_wizard git
  assertCalledWith start_module_wizard pi
}

test_deploy_wizard_calls_activate_asdf_even_when_zsh_declined() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  createSpy -u start_module_wizard
  createSpy -u activate_asdf

  # Decline zsh; accept the rest. confirm reads one byte per call.
  printf 'n\ny\ny\ny\n' | deploy_wizard >/dev/null

  assertCalledOnceWith activate_asdf
}

test_deploy_wizard_numbers_module_sections() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  createSpy -u start_module_wizard
  createSpy -u activate_asdf

  message="$(yes | deploy_wizard)"

  assertContains "Expected first module section" "$message" "▸ zsh  (1/6)"
  assertContains "Expected last module section" "$message" "▸ pi  (6/6)"
}

test_deploy_wizard_keeps_module_numbers_when_zsh_declined() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  createSpy -u start_module_wizard

  # Decline zsh; accept the rest. confirm reads one byte per call.
  message="$(printf 'n\ny\ny\ny\n' | deploy_wizard)"

  # zimfw and asdf were never offered, but tmux keeps its own position.
  assertContains "Expected tmux to keep its position" "$message" "▸ tmux  (4/6)"
  assertNotContains "zimfw was not offered" "$message" "▸ zimfw"
}

test_deploy_wizard_ends_with_epilogue() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  createSpy -u start_module_wizard
  createSpy -u activate_asdf

  message="$(yes | deploy_wizard)"

  # shellcheck disable=SC2016 # the backticks are literal, quoting a command
  assertContains "Expected closing epilogue" \
    "$message" 'Done. Restart your shell with `exec zsh`'
}

test_deploy_wizard_epilogue_drops_exec_zsh_when_zsh_missing() {
  createSpy -u -r "$SHUNIT_TRUE" check_supported_pm
  # zsh (like every other command) is not installed
  createSpy -u -r "$SHUNIT_FALSE" command_exists
  createSpy -u install_from_pm
  createSpy -u start_module_wizard
  createSpy -u activate_asdf

  message="$(yes | deploy_wizard)"

  assertContains "Expected shell-agnostic epilogue" \
    "$message" 'Done. Restart your shell to pick up the changes.'
  assertNotContains "Command not expected without zsh" "$message" 'exec zsh'
}

#
# Modules that don't complete
#

# A module that stops early — a failed step, or one the user cancelled — is
# reported by name, since the module's own ✗ (when it has one) doesn't say
# which module it came from.
test_deploy_wizard_reports_a_module_that_did_not_complete() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  createSpy -u -r 1 -r 0 start_module_wizard
  createSpy -u activate_asdf

  message="$(yes | deploy_wizard 2>&1)"

  assertContains "Expected the module to be named" \
    "$message" "✗ zsh did not complete"
}

test_deploy_wizard_skips_zsh_dependents_when_zsh_does_not_complete() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  createSpy -u -r 1 -r 0 start_module_wizard
  createSpy -u activate_asdf

  message="$(yes | deploy_wizard 2>&1)"

  # zimfw and asdf write into the dotfiles zsh never laid down.
  assertNotContains "zimfw depends on zsh" "$message" "▸ zimfw"
  assertNotContains "asdf depends on zsh" "$message" "▸ asdf"
  # The modules that don't are still offered. assertCalledWith walks the calls
  # in order, so zsh's own call is claimed first.
  assertCallCount start_module_wizard 4
  assertCalledWith start_module_wizard zsh
  assertCalledWith start_module_wizard tmux
  assertCalledWith start_module_wizard git
  assertCalledWith start_module_wizard pi
}

test_deploy_wizard_keeps_going_after_an_independent_module_fails() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  # tmux is the fourth module asked about; the last -r repeats from then on.
  createSpy -u -r 0 -r 0 -r 0 -r 1 -r 0 start_module_wizard
  createSpy -u activate_asdf

  message="$(yes | deploy_wizard 2>&1)"

  assertContains "Expected the failed module to be named" \
    "$message" "✗ tmux did not complete"
  # assertCalledWith walks the calls in order, so the three before tmux are
  # claimed first.
  assertCallCount start_module_wizard 6
  assertCalledWith start_module_wizard zsh
  assertCalledWith start_module_wizard zimfw
  assertCalledWith start_module_wizard asdf
  assertCalledWith start_module_wizard tmux
  assertCalledWith start_module_wizard git
  assertCalledWith start_module_wizard pi
}

test_deploy_wizard_epilogue_names_every_module_that_did_not_complete() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  # zsh fails, so zimfw and asdf are never asked and tmux is the second call.
  createSpy -u -r 1 -r 1 -r 0 start_module_wizard
  createSpy -u activate_asdf

  message="$(yes | deploy_wizard 2>&1)"

  assertContains "Expected an honest closing line" \
    "$message" "! Done, but zsh and tmux did not complete."
  assertNotContains "A run with failures is not a clean one" "$message" "✓ Done"
}

test_deploy_wizard_fails_when_a_module_did_not_complete() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  createSpy -u -r 1 -r 0 start_module_wizard
  createSpy -u activate_asdf

  yes | deploy_wizard >/dev/null 2>&1

  assertFalse "Error code expected" $?
}

test_deploy_wizard_succeeds_when_every_module_completes() {
  createSpy -u -r "$SHUNIT_TRUE" command_exists
  createSpy -u install_from_pm
  createSpy -u start_module_wizard
  createSpy -u activate_asdf

  yes | deploy_wizard >/dev/null 2>&1

  assertTrue "Success code expected" $?
}

test_deploy_wizard_dies_if_basic_packages_fail() {
  createSpy -u -r "$SHUNIT_TRUE" check_supported_pm
  # Basic packages not installed
  createSpy -u -r "$SHUNIT_FALSE" command_exists
  # Installing packages fail. Spied one level down, so the real install_from_pm
  # runs and the --die it was handed is what stops the deploy.
  createSpy -u -o 'apt-get' get_supported_pm
  createSpy -u -r "$SHUNIT_FALSE" _install_from_pm

  message="$(yes | deploy_wizard 2>&1)"

  assertFalse "Error code expected" $?
  assertContains "Expected dying message" \
    "$message" "Couldn't install basic packages"
}

# Run tests
SHPY_PATH="$THISDIR/shpy"
export SHPY_PATH
. "$THISDIR/shpy"
. "$THISDIR/shpy-shunit2"
. "$THISDIR/shunit2"
