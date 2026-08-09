#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
  REAL_DOTFILES="$(get_abs_path "$THISDIR/..")"
}

# The helper is told which template and which target to use, so these tests give
# it a template of their own rather than a module's. The label they pass is
# "harness", a name no module uses: it can only reach the output through the
# argument.
setUp() {
  DOTFILES="$REAL_DOTFILES"
  . "$THISDIR/utils.sh"
  HOME=${SHUNIT_TMPDIR:?}/home
  CONFIG_DIR="$HOME/.harness"
  TARGET="$CONFIG_DIR/settings.json"
  TEMPLATE="${SHUNIT_TMPDIR:?}/template.json"
  mkdir -p "$HOME"
  # shellcheck disable=SC2016 # the placeholder is literal, not an expansion
  printf '%s\n' '{"theme": "dark", "hook": "python3 $DOTFILES/hook.py"}' > "$TEMPLATE"
}

tearDown() {
  cleanupSpies
  cleanupTestDir
}

# Write $1 as the machine's settings.json.
_given_settings() {
  mkdir -p "$CONFIG_DIR"
  printf '%s\n' "$1" > "$TARGET"
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
    "$output" "python3 is required to merge JSON settings."
  assertNeverCalled install_from_pm
}

#
# render_settings_template
#

test_render_settings_template_expands_dotfiles() {
  rendered=$(render_settings_template "$TEMPLATE")

  # shellcheck disable=SC2016 # the placeholder is literal, not an expansion
  assertNotContains "The literal placeholder must not survive" \
    "$(cat "$rendered")" '$DOTFILES'
  assertContains "Should name this checkout" \
    "$(cat "$rendered")" "python3 $DOTFILES/hook.py"
  rm -f "$rendered"
}

test_render_settings_template_leaves_the_template_alone() {
  before=$(cat "$TEMPLATE")

  rendered=$(render_settings_template "$TEMPLATE")
  rm -f "$rendered"

  assertEquals "The template is read-only input" "$before" "$(cat "$TEMPLATE")"
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
# install_json_settings
#
# The module system tests prove what the merge does to a settings file, against
# a real python3. `make unit-<image>` runs on the base stage, and that stage has
# no python3 on amazonlinux-2. These tests cover the shell around the merge:
# where it writes, when it makes a backup, and what it reports.
#

# merge_json.py exit 3: the target already agrees with the template.
test_install_settings_creates_the_config_dir() {
  createSpy -u -r 3 python3
  assertFalse "Config dir should not exist yet" "[ -d \"$CONFIG_DIR\" ]"

  output=$(install_json_settings "$TEMPLATE" "$TARGET" harness)

  assertTrue "Should succeed" $?
  assertTrue "Should create the config dir" "[ -d \"$CONFIG_DIR\" ]"
  assertContains "Should report nothing to do under its label" \
    "$output" "harness settings already up to date"
}

test_install_settings_hands_the_merger_the_rendered_template() {
  createSpy -u -r 3 python3

  quietly install_json_settings "$TEMPLATE" "$TARGET" harness

  # The rendered template is a temp file, so this can only match the merger and
  # the target. A test above covers the expansion of the template.
  assertCallCount python3 1
  args=$(getArgsForCall python3 1)
  assertContains "Should run the merger from utils" "$args" "$DOTFILES/utils/merge_json.py"
  assertContains "Should merge into the target it was given" "$args" "$TARGET"
}

test_install_settings_leaves_no_temp_file_when_there_is_nothing_to_do() {
  createSpy -u -r 3 python3

  quietly install_json_settings "$TEMPLATE" "$TARGET" harness

  leftovers=$(find "$CONFIG_DIR" -name 'settings.json.??????' | wc -l)
  assertEquals "The merge temp file should be gone" "0" "$leftovers"
  assertFalse "Nothing to do means nothing to back up" "[ -f \"$TARGET.bkp\" ]"
}

# merge_json.py exit 2: the target is there but unreadable.
test_install_settings_backs_up_an_unreadable_file_before_replacing_it() {
  _given_settings 'not json at all {'
  createSpy -u -r 2 python3

  output=$(install_json_settings "$TEMPLATE" "$TARGET" harness 2>/dev/null)

  assertTrue "An unreadable file must not stop the deploy" $?
  assertContains "Should say it replaced the file" "$output" "Replaced unreadable"
  assertContains "Should name the backup" "$output" "Kept the old one as"
  assertEquals "The broken file is preserved verbatim" \
    "not json at all {" "$(cat "$TARGET.bkp")"
}

# merge_json.py exit 0: merged, and the result differs from the target.
test_install_settings_backs_up_before_overwriting() {
  _given_settings '{"theme": "light"}'
  createSpy -u -r 0 python3

  output=$(install_json_settings "$TEMPLATE" "$TARGET" harness)

  assertContains "Should report where it wrote, under its label" \
    "$output" "harness settings written to"
  assertContains "Should name the backup" "$output" "Backed up the old one as"
  assertContains "The backup holds the old content" \
    "$(cat "$TARGET.bkp")" '"theme": "light"'
}

test_install_settings_does_not_back_up_a_file_that_was_not_there() {
  createSpy -u -r 0 python3

  quietly install_json_settings "$TEMPLATE" "$TARGET" harness

  assertFalse "Nothing existed to back up" "[ -f \"$TARGET.bkp\" ]"
}

test_install_settings_passes_the_drift_report_on() {
  _given_settings '{"theme": "light"}'
  createSpy -u -r 0 -o 'theme: "light" -> "dark"' python3

  output=$(install_json_settings "$TEMPLATE" "$TARGET" harness)

  assertContains "Should warn about the drift" \
    "$output" "overwrote settings changed on this machine"
  assertContains "Should name the key and both values" "$output" 'theme: "light" -> "dark"'
}

test_install_settings_dies_when_the_merge_fails() {
  createSpy -u -r "$SHUNIT_FALSE" python3

  output=$( (install_json_settings "$TEMPLATE" "$TARGET" harness) 2>&1 )

  assertFalse "Should not report success on a broken merge" $?
  assertContains "Should say what it could not do, under its label" \
    "$output" "Could not merge the harness settings"
}

# Run tests
SHPY_PATH="$THISDIR/../tests/shpy"
export SHPY_PATH
. "$THISDIR/../tests/shpy"
. "$THISDIR/../tests/shpy-shunit2"
. "$THISDIR/../tests/shunit2"
