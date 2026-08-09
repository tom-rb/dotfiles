#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
  DOTFILES="$(get_abs_path "$THISDIR/..")"
}

setUp() {
  . "$THISDIR/install_claude.sh"
  HOME=${SHUNIT_TMPDIR:?}/home
  CLAUDE_CONFIG_DIR="$HOME/.claude"
  mkdir -p "$HOME"
  # The install mode is a keyed answer now. Left standing, the one a test
  # records would be replayed by the next instead of its own keystrokes.
  # shellcheck disable=SC2034 # read by the keyed prompts under test
  DOTFILES_ANSWERS=''
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
# report_claude_install
#

test_report_claude_install_names_the_version_when_present() {
  createSpy -u -r "$SHUNIT_TRUE" is_claude_installed
  createSpy -u -o '2.1.0 (Claude Code)' claude

  output=$(report_claude_install)

  assertTrue "A present claude is not an error" $?
  assertContains "Should report the version" "$output" "claude 2.1.0 (Claude Code) found"
}

test_report_claude_install_warns_but_succeeds_when_absent() {
  createSpy -u -r "$SHUNIT_FALSE" is_claude_installed

  output=$(report_claude_install)

  assertTrue "A missing claude must not stop the module" $?
  assertContains "Should say claude is missing" "$output" "claude is not on PATH"
  assertContains "Should say it configures anyway" "$output" "Configuring anyway"
}

#
# install_claude_settings
#
# utils/test_json_settings.sh proves what the shared helper does with a
# template. This test covers the wiring this module adds: which template lands
# in which file, under which label.
#

test_install_claude_settings_merges_the_module_template() {
  createSpy -u install_json_settings

  install_claude_settings

  assertCalledOnceWith install_json_settings "$DOTFILES/claude/settings.json" \
    "$CLAUDE_CONFIG_DIR/settings.json" claude
}

#
# install_claude_skills_and_rules
#
# utils/test_skills.sh proves how the installer links, copies, backs up and
# prunes. These tests cover the wiring this module adds: which sources reach
# which destination, and that pi's skills are among them.
#

test_skills_step_installs_the_repos_own_skills_and_rules() {
  _given_keystrokes '\n'

  quietly install_claude_skills_and_rules < "$KEYS"
  assertTrue "A clean machine is not an error" $?

  assertEquals "$DOTFILES/claude/skills/rate-limit-status" \
    "$(readlink "$CLAUDE_CONFIG_DIR/skills/rate-limit-status")"
  assertEquals "$DOTFILES/claude/rules/md.md" \
    "$(readlink "$CLAUDE_CONFIG_DIR/rules/md.md")"
}

# Claude Code does not read ~/.agents/skills, so pi's skills only reach it
# through this module.
test_skills_step_installs_pi_skills_into_claudes_own_directory() {
  _given_keystrokes '\n'

  quietly install_claude_skills_and_rules < "$KEYS"

  assertEquals "$DOTFILES/pi/skills/ste-writing" \
    "$(readlink "$CLAUDE_CONFIG_DIR/skills/ste-writing")"
}

test_skills_step_copies_when_the_second_option_is_chosen() {
  _given_keystrokes '2'

  quietly install_claude_skills_and_rules < "$KEYS"

  assertFalse "A copy is not a link" \
    "[ -L \"$CLAUDE_CONFIG_DIR/skills/rate-limit-status\" ]"
  assertTrue "The skill should still be there" \
    "[ -f \"$CLAUDE_CONFIG_DIR/skills/rate-limit-status/SKILL.md\" ]"
}

# A quit at the mode question leaves the directories untouched and reports the
# step as unfinished. It does not silently do what the user declined.
test_skills_step_reports_a_quit_and_writes_nothing() {
  _given_keystrokes 'q'

  quietly install_claude_skills_and_rules < "$KEYS"

  assertFalse "A declined step has not run" $?
  assertFalse "Nothing should be written" "[ -d \"$CLAUDE_CONFIG_DIR/skills\" ]"
}

# Quitting abandons the step and makes the module non-zero, so it reads as
# something that needs attention rather than as a settled choice.
test_skills_step_warns_that_a_quit_interrupted_the_install() {
  _given_keystrokes 'q'

  output=$(install_claude_skills_and_rules < "$KEYS" 2>&1)

  assertContains "should say the install was interrupted" \
    "$output" "! skills and rules installation interrupted"
}

# The two questions report differently: this one stopped with entries already
# on disk, and naming them is what tells the user where to go look.
test_skills_step_names_the_entries_left_in_place_on_a_collision_quit() {
  mkdir -p "$CLAUDE_CONFIG_DIR/skills/rate-limit-status"
  # Enter takes link mode, then q at the collision question.
  _given_keystrokes '\nq'

  output=$(install_claude_skills_and_rules < "$KEYS" 2>&1)

  assertContains "should say what was left behind" \
    "$output" "! skills and rules left in place, installation interrupted"
}

test_skills_step_asks_once_for_collisions_across_skills_and_rules() {
  mkdir -p "$CLAUDE_CONFIG_DIR/skills/rate-limit-status" "$CLAUDE_CONFIG_DIR/rules"
  : > "$CLAUDE_CONFIG_DIR/rules/md.md"
  # Enter for the mode, then Enter for one collision question that covers both
  # roots.
  _given_keystrokes '\n\n'

  output=$(install_claude_skills_and_rules < "$KEYS")

  assertTrue "The install should finish" $?
  assertContains "Should name the colliding skill" "$output" "skills/rate-limit-status"
  assertContains "Should name the colliding rule" "$output" "rules/md.md"
  assertTrue "The skill should be backed up" \
    "[ -d \"$CLAUDE_CONFIG_DIR/skills.bkp/rate-limit-status\" ]"
  assertTrue "The rule should be backed up" \
    "[ -f \"$CLAUDE_CONFIG_DIR/rules.bkp/md.md\" ]"
}

# Two sources feed ~/.claude/skills. A name in both would make each install undo
# the other, and file a backup of the loser on every deploy.
test_skills_step_stops_when_both_sources_ship_the_same_name() {
  createSpy -u -o "shared" duplicate_entry_names
  _given_keystrokes '\n'

  output=$( (install_claude_skills_and_rules < "$KEYS") 2>&1 )

  assertFalse "A packaging mistake should stop the deploy" $?
  assertContains "Should name the entry shipped twice" "$output" "shared"
  assertFalse "And write nothing" "[ -d \"$CLAUDE_CONFIG_DIR/skills\" ]"
}

# The prune must also cover the case where the repo drops everything. If it does
# not, the last links stay behind and point at sources that are gone.
test_skills_step_prunes_when_the_repo_ships_nothing() {
  _given_keystrokes '\n'
  quietly install_claude_skills_and_rules < "$KEYS"
  createSpy -u -o "" entry_names

  output=$(install_claude_skills_and_rules)

  assertTrue "Nothing to install is not an error" $?
  assertContains "Should say there was nothing to install" "$output" "No skills or rules"
  assertFalse "The link it made should be taken back" \
    "[ -L \"$CLAUDE_CONFIG_DIR/skills/rate-limit-status\" ]"
  assertFalse "Rules too" "[ -L \"$CLAUDE_CONFIG_DIR/rules/md.md\" ]"
}

test_skills_step_prunes_only_what_this_repo_installed() {
  _given_keystrokes '\n'
  quietly install_claude_skills_and_rules < "$KEYS"
  ln -s "$DOTFILES/claude/skills/dropped" "$CLAUDE_CONFIG_DIR/skills/dropped"
  ln -s ../../.agents/skills/handoff "$CLAUDE_CONFIG_DIR/skills/handoff"

  _given_keystrokes '\n'
  quietly install_claude_skills_and_rules < "$KEYS"

  assertFalse "A link to a skill the repo dropped goes" \
    "[ -L \"$CLAUDE_CONFIG_DIR/skills/dropped\" ]"
  assertTrue "A link the user made stays" \
    "[ -L \"$CLAUDE_CONFIG_DIR/skills/handoff\" ]"
}

#
# install_claude_wizard
#

test_wizard_delegates_step_list_to_wizard_run() {
  createSpy -u wizard_run

  # shellcheck disable=SC2119
  install_claude_wizard

  assertCalledOnceWith wizard_run -- report_claude_install \
    ensure_python3_installed install_claude_settings install_claude_skills_and_rules
}

test_wizard_skips_the_skills_when_the_settings_step_fails() {
  createSpy -u report_claude_install
  createSpy -u ensure_python3_installed
  createSpy -u -r "$SHUNIT_FALSE" install_claude_settings
  createSpy -u install_claude_skills_and_rules

  # shellcheck disable=SC2119
  install_claude_wizard

  assertFalse "Wizard should fail when the settings step fails" $?
  assertNeverCalled install_claude_skills_and_rules
}

test_wizard_skips_the_settings_when_python3_cannot_be_installed() {
  createSpy -u report_claude_install
  createSpy -u -r "$SHUNIT_FALSE" ensure_python3_installed
  createSpy -u install_claude_settings

  # shellcheck disable=SC2119
  install_claude_wizard

  assertFalse "Wizard should fail when python3 is missing" $?
  assertNeverCalled install_claude_settings
}

# Run tests
SHPY_PATH="$THISDIR/../tests/shpy"
export SHPY_PATH
. "$THISDIR/../tests/shpy"
. "$THISDIR/../tests/shpy-shunit2"
. "$THISDIR/../tests/shunit2"
