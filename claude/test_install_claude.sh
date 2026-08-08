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
}

tearDown() {
  cleanupSpies
  cleanupTestDir
}

# Write $1 as the machine's settings.json.
_given_settings() {
  mkdir -p "$CLAUDE_CONFIG_DIR"
  printf '%s\n' "$1" > "$CLAUDE_CONFIG_DIR/settings.json"
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
# ensure_python3_installed
#

test_ensure_python3_returns_early_when_present() {
  command_exists() { [ "$1" = python3 ]; }
  createSpy -u install_from_pm

  output=$(ensure_python3_installed)

  assertTrue "Should succeed when python3 is already present" $?
  assertContains "Should report it is already there" "$output" "python3 already installed"
  assertNeverCalled install_from_pm
}

test_ensure_python3_installs_from_the_package_manager() {
  command_exists() { return 1; }
  createSpy -u -r "$SHUNIT_TRUE" check_supported_pm
  createSpy -u install_from_pm

  quietly ensure_python3_installed

  assertTrue "Should succeed on the package-manager path" $?
  assertCalledOnceWith install_from_pm --as python3 \
    --die "Couldn't install python3" -- python3
}

test_ensure_python3_dies_when_the_pm_install_fails() {
  command_exists() { return 1; }
  createSpy -u -r "$SHUNIT_TRUE" check_supported_pm
  createSpy -u -o 'apt-get' get_supported_pm
  createSpy -u -r "$SHUNIT_FALSE" _install_from_pm

  output=$( (ensure_python3_installed) 2>&1 )

  assertFalse "Should not walk past a failed python3 install" $?
  assertContains "Should say what failed" "$output" "Couldn't install python3"
}

test_ensure_python3_dies_when_no_supported_package_manager() {
  command_exists() { return 1; }
  createSpy -u -r "$SHUNIT_FALSE" check_supported_pm
  createSpy -u install_from_pm

  output=$( (ensure_python3_installed) 2>&1 )

  assertFalse "Should fail when there is no way to install python3" $?
  assertContains "Should explain python3 is required" \
    "$output" "python3 is required by the claude configs."
  assertNeverCalled install_from_pm
}

#
# render_settings_template
#

test_render_settings_template_expands_dotfiles() {
  rendered=$(render_settings_template)

  # shellcheck disable=SC2016 # the placeholder is literal, not an expansion
  assertNotContains "The literal placeholder must not survive" \
    "$(cat "$rendered")" '$DOTFILES'
  assertContains "Should name this checkout's statusline" \
    "$(cat "$rendered")" "python3 '$DOTFILES/claude/statusline.py'"
  rm -f "$rendered"
}

test_render_settings_template_leaves_the_repo_template_alone() {
  before=$(cat "$DOTFILES/claude/settings.json")

  rendered=$(render_settings_template)
  rm -f "$rendered"

  assertEquals "The template is read-only input" \
    "$before" "$(cat "$DOTFILES/claude/settings.json")"
}

#
# report_settings_drift
#

test_report_settings_drift_says_nothing_when_there_is_none() {
  output=$(report_settings_drift '')

  assertTrue "No drift is not an error" $?
  assertEquals "Should print nothing at all" "" "$output"
}

test_report_settings_drift_lists_every_overwritten_key() {
  output=$(report_settings_drift 'theme: "light" -> "dark"
tui: "compact" -> "fullscreen"')

  assertContains "Should introduce the list" "$output" "overwrote settings changed on this machine"
  assertContains "Should name the first key" "$output" 'theme: "light" -> "dark"'
  assertContains "Should name the second key" "$output" 'tui: "compact" -> "fullscreen"'
}

#
# install_claude_settings
#
# test_install_claude.system.sh proves what the merge does to a settings file,
# against a real python3. `make unit-<image>` runs on the base stage, and that
# stage has no python3 on amazonlinux-2. These tests cover the shell around the
# merge: where it writes, when it makes a backup, and what it reports.
#

# merge_json.py exit 3: the target already agrees with the template.
test_install_settings_creates_the_config_dir() {
  createSpy -u -r 3 python3
  assertFalse "Config dir should not exist yet" "[ -d \"$CLAUDE_CONFIG_DIR\" ]"

  output=$(install_claude_settings)

  assertTrue "Should succeed" $?
  assertTrue "Should create the config dir" "[ -d \"$CLAUDE_CONFIG_DIR\" ]"
  assertContains "Should report nothing to do" "$output" "already up to date"
}

test_install_settings_hands_the_merger_the_rendered_template() {
  createSpy -u -r 3 python3

  quietly install_claude_settings

  # The rendered template is a temp file, so this can only match the merger and
  # the target. A test above covers the expansion of the template.
  assertCallCount python3 1
  args=$(getArgsForCall python3 1)
  assertContains "Should run the merger" "$args" "$DOTFILES/claude/merge_json.py"
  assertContains "Should merge into the machine's settings" \
    "$args" "$CLAUDE_CONFIG_DIR/settings.json"
}

test_install_settings_leaves_no_temp_file_when_there_is_nothing_to_do() {
  createSpy -u -r 3 python3

  quietly install_claude_settings

  leftovers=$(find "$CLAUDE_CONFIG_DIR" -name 'settings.json.??????' | wc -l)
  assertEquals "The merge temp file should be gone" "0" "$leftovers"
  assertFalse "Nothing to do means nothing to back up" \
    "[ -f \"$CLAUDE_CONFIG_DIR/settings.json.bkp\" ]"
}

# merge_json.py exit 2: the target is there but unreadable.
test_install_settings_backs_up_an_unreadable_file_before_replacing_it() {
  _given_settings 'not json at all {'
  createSpy -u -r 2 python3

  output=$(install_claude_settings 2>/dev/null)

  assertTrue "An unreadable file must not stop the deploy" $?
  assertContains "Should say it replaced the file" "$output" "Replaced unreadable"
  assertContains "Should name the backup" "$output" "Kept the old one as"
  assertEquals "The broken file is preserved verbatim" \
    "not json at all {" "$(cat "$CLAUDE_CONFIG_DIR/settings.json.bkp")"
}

# merge_json.py exit 0: merged, and the result differs from the target.
test_install_settings_backs_up_before_overwriting() {
  _given_settings '{"theme": "light"}'
  createSpy -u -r 0 python3

  output=$(install_claude_settings)

  assertContains "Should report where it wrote" "$output" "claude settings written to"
  assertContains "Should name the backup" "$output" "Backed up the old one as"
  assertContains "The backup holds the old content" \
    "$(cat "$CLAUDE_CONFIG_DIR/settings.json.bkp")" '"theme": "light"'
}

test_install_settings_does_not_back_up_a_file_that_was_not_there() {
  createSpy -u -r 0 python3

  quietly install_claude_settings

  assertFalse "Nothing existed to back up" \
    "[ -f \"$CLAUDE_CONFIG_DIR/settings.json.bkp\" ]"
}

test_install_settings_passes_the_drift_report_on() {
  _given_settings '{"theme": "light"}'
  createSpy -u -r 0 -o 'theme: "light" -> "dark"' python3

  output=$(install_claude_settings)

  assertContains "Should warn about the drift" \
    "$output" "overwrote settings changed on this machine"
  assertContains "Should name the key and both values" "$output" 'theme: "light" -> "dark"'
}

test_install_settings_dies_when_the_merge_fails() {
  createSpy -u -r "$SHUNIT_FALSE" python3

  output=$( (install_claude_settings) 2>&1 )

  assertFalse "Should not report success on a broken merge" $?
  assertContains "Should say what it could not do" "$output" "Could not merge the claude settings"
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
