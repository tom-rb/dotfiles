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

# Stage $1 as the answers to come, for `... < "$KEYS"`. printf interprets
# backslash escapes, so '\n' is the Enter that means "take the default".
_given_keystrokes() {
  KEYS="${SHUNIT_TMPDIR:?}/keystrokes"
  printf '%b' "${1:?}" > "$KEYS"
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

# The package-manager branch of ensure_node_installed: node absent, no asdf,
# apt-get available. Spies confirm as accepting; a test that needs it declined
# re-declares that one spy.
_given_no_node_and_a_supported_pm() {
  command_exists() { return 1; }
  createSpy -u -r "$SHUNIT_TRUE" check_supported_pm
  createSpy -u -o "apt-get" get_supported_pm
  createSpy -u -r "$SHUNIT_TRUE" confirm
}

test_ensure_node_installs_via_pm_when_user_confirms() {
  _given_no_node_and_a_supported_pm
  createSpy -u install_from_pm
  createSpy -u ensure_node_runtime_libs

  quietly ensure_node_installed
  assertTrue "Should succeed on the package-manager path" $?

  assertCalledOnceWith install_from_pm --as node \
    --die "Couldn't install node from apt-get" -- nodejs npm
  assertCalledOnceWith ensure_node_runtime_libs
}

test_ensure_node_dies_when_the_pm_install_fails() {
  _given_no_node_and_a_supported_pm
  createSpy -u -r "$SHUNIT_FALSE" _install_from_pm

  output=$( (ensure_node_installed) 2>&1 )

  assertFalse "Should not walk past a failed node install" $?
  assertContains "Should name the package manager it tried" \
    "$output" "Couldn't install node from apt-get"
}

test_ensure_node_dies_when_pm_install_is_declined() {
  _given_no_node_and_a_supported_pm
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

  assertCalledOnceWith install_from_pm \
    --die "Couldn't install libatomic" -- libatomic
}

# node is already known to be unable to load its libraries here, so a PM that
# cannot supply them leaves nothing to fall back to.
test_node_runtime_libs_dies_when_libatomic_cannot_be_installed() {
  createSpy -u -r "$SHUNIT_FALSE" node
  createSpy -u -r "$SHUNIT_TRUE" check_supported_pm
  createSpy -u -o 'apt-get' get_supported_pm
  createSpy -u -r "$SHUNIT_FALSE" _install_from_pm

  output=$( (ensure_node_runtime_libs) 2>&1 )

  assertFalse "Should not report a runtime it could not repair" $?
  assertContains "Should say what failed" "$output" "Couldn't install libatomic"
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

test_get_pi_version_reads_the_bare_version_line() {
  createSpy -u -o "0.79.1" pi

  assertEquals "0.79.1" "$(get_pi_version)"
}

test_install_pi_program_short_circuits_when_already_installed() {
  createSpy -u -r "$SHUNIT_TRUE" is_pi_installed
  createSpy -u -o "0.78.0" get_pi_version
  createSpy -u ensure_node_installed
  createSpy -u npm

  output=$(install_pi_program)

  assertTrue "Already-installed should not be an error" $?
  assertContains "Should report already installed" \
    "$output" "pi 0.78.0 already installed"
  assertNeverCalled ensure_node_installed
  assertNeverCalled npm
}

test_install_pi_program_installs_pinned_package_globally() {
  createSpy -u -r "$SHUNIT_FALSE" is_pi_installed
  createSpy -u -o "0.78.0" get_pi_version
  createSpy -u ensure_node_installed
  createSpy -u npm
  command_exists() { return 1; }   # asdf absent

  output=$(install_pi_program)

  assertTrue "Install should not be an error" $?
  assertCalledOnceWith npm install -g --loglevel=error --ignore-scripts \
    "@earendil-works/pi-coding-agent@${PI_VERSION}"
  assertContains "Should report the installed version" \
    "$output" "pi 0.78.0 installed"
}

test_install_pi_program_hides_npm_output_without_debug() {
  createSpy -u -r "$SHUNIT_FALSE" is_pi_installed
  createSpy -u -o "0.78.0" get_pi_version
  createSpy -u ensure_node_installed
  createSpy -u -o 'npm install tree' npm
  command_exists() { return 1; }   # asdf absent

  output=$(install_pi_program)

  assertNotContains "Should hide npm's own stdout by default" \
    "$output" "npm install tree"
}

test_install_pi_program_shows_npm_output_with_debug() {
  createSpy -u -r "$SHUNIT_FALSE" is_pi_installed
  createSpy -u -o "0.78.0" get_pi_version
  createSpy -u ensure_node_installed
  createSpy -u -o 'npm install tree' npm
  command_exists() { return 1; }   # asdf absent

  output=$(DEBUG=1 install_pi_program)

  assertContains "Should show indented npm output under DEBUG=1" \
    "$output" "npm install tree"
}

test_install_pi_program_reports_the_version_before_the_reshim() {
  createSpy -u -r "$SHUNIT_FALSE" is_pi_installed
  # An asdf-managed npm drops the binary outside PATH, so `pi --version`
  # answers with nothing until the reshim below has run.
  createSpy -u -o '' get_pi_version
  createSpy -u ensure_node_installed
  createSpy -u npm
  command_exists() { [ "$1" = asdf ]; }   # asdf present
  createSpy -u asdf

  output=$(install_pi_program)

  assertTrue "Install should not be an error" $?
  assertContains "Should report the pinned version regardless" \
    "$output" "✓ pi ${PI_VERSION} installed"
}

test_install_pi_program_reshims_when_node_is_asdf_managed() {
  createSpy -u -r "$SHUNIT_FALSE" is_pi_installed
  createSpy -u -o "0.78.0" get_pi_version
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
  createSpy -u -o "0.78.0" get_pi_version
  createSpy -u ensure_node_installed
  createSpy -u npm
  command_exists() { return 1; }   # asdf absent
  createSpy -u asdf

  quietly install_pi_program

  assertNeverCalled asdf
}

test_install_pi_program_fails_when_npm_install_fails() {
  createSpy -u -r "$SHUNIT_FALSE" is_pi_installed
  createSpy -u -o "0.78.0" get_pi_version
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
# install_pi_skills
#
# utils/test_skills.sh proves how the installer installs and prunes. These tests
# cover this module's wiring: where pi's skills go, and where they deliberately
# do not.
#

test_install_pi_skills_links_into_the_agents_directory() {
  _given_keystrokes '\n'

  quietly install_pi_skills < "$KEYS"
  assertTrue "A clean machine is not an error" $?

  assertEquals "$DOTFILES/pi/skills/ste-writing" \
    "$(readlink "$HOME/.agents/skills/ste-writing")"
}

# ~/.claude/skills has one owner, the claude module. If two modules pruned one
# directory, each would remove the other's links on every deploy.
test_install_pi_skills_leaves_claudes_directory_alone() {
  _given_keystrokes '\n'

  quietly install_pi_skills < "$KEYS"

  assertFalse "pi must not write into Claude's skills" \
    "[ -d \"$HOME/.claude/skills\" ]"
}

test_install_pi_skills_copies_when_the_second_option_is_chosen() {
  _given_keystrokes '2'

  quietly install_pi_skills < "$KEYS"

  assertFalse "A copy is not a link" "[ -L \"$HOME/.agents/skills/ste-writing\" ]"
  assertTrue "The skill should still be there" \
    "[ -f \"$HOME/.agents/skills/ste-writing/SKILL.md\" ]"
}

test_install_pi_skills_reports_a_quit_and_writes_nothing() {
  _given_keystrokes 'q'

  quietly install_pi_skills < "$KEYS"

  assertFalse "A declined step has not run" $?
  assertFalse "Nothing should be written" "[ -d \"$HOME/.agents/skills\" ]"
}

# The regression that made this rewrite necessary: the old step cleared
# ~/.agents/skills wholesale, and took every skill that came from anywhere else.
test_install_pi_skills_keeps_skills_it_did_not_install() {
  mkdir -p "$HOME/.agents/skills/handoff"
  : > "$HOME/.agents/skills/handoff/SKILL.md"
  _given_keystrokes '\n'

  quietly install_pi_skills < "$KEYS"

  assertTrue "A skill from elsewhere must survive" \
    "[ -f \"$HOME/.agents/skills/handoff/SKILL.md\" ]"
}

# The prune must also cover the case where the repo drops everything. If it does
# not, the last links stay behind and point at sources that are gone.
test_install_pi_skills_prunes_when_the_repo_ships_nothing() {
  _given_keystrokes '\n'
  quietly install_pi_skills < "$KEYS"
  createSpy -u -o "" entry_names

  output=$(install_pi_skills)

  assertTrue "Nothing to install is not an error" $?
  assertContains "Should say there was nothing to install" "$output" "No skills found"
  assertFalse "The link it made should be taken back" \
    "[ -L \"$HOME/.agents/skills/ste-writing\" ]"
}

test_install_pi_skills_is_a_no_op_on_a_second_run() {
  _given_keystrokes '\n'
  quietly install_pi_skills < "$KEYS"

  _given_keystrokes '\n'
  output=$(install_pi_skills < "$KEYS")

  assertContains "Should report it is already done" "$output" "nothing to do"
  assertEquals "The link should be untouched" "$DOTFILES/pi/skills/ste-writing" \
    "$(readlink "$HOME/.agents/skills/ste-writing")"
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

test_wizard_does_not_install_skills_when_npm_install_fails() {
  createSpy -u -r "$SHUNIT_FALSE" is_pi_installed
  createSpy -u -o "0.78.0" get_pi_version
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
