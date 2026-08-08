#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
  . "$THISDIR/install_claude.sh"
  SETTINGS="$(get_claude_config_dir)/settings.json"
}

# The value at top-level key $1 of the installed settings.json.
_settings_value() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' \
    "$SETTINGS" "${1:?}"
}

# Runs on the bare image, so this test uses the real package manager. The ubuntu
# base stage already ships python3, and the amazonlinux-2 base stage does not.
# Only amazonlinux-2 proves the install here.
# @image: base
it_installs_python3_from_the_package_manager() {
  if command_exists python3; then
    echo "Skipping: this image already ships python3"
    startSkipping
    return 0
  fi

  quietly ensure_python3_installed
  assertTrue "Expected the python3 bootstrap to exit 0" $?

  assertTrue "python3 should be on PATH afterwards" "command_exists python3"

  # Idempotency: a second run finds it and stops early.
  output=$(ensure_python3_installed)
  assertContains "Should report it is already there" "$output" "python3 already installed"
}

# @image: with-python
it_installs_settings_on_a_clean_machine() {
  assertFalse "settings.json should not exist yet" "[ -f \"$SETTINGS\" ]"

  quietly install_claude_wizard -y
  assertTrue "Expected the claude wizard to exit 0" $?

  assertTrue "settings.json should exist" "[ -f \"$SETTINGS\" ]"
  assertEquals "Should apply the template" "dark" "$(_settings_value theme)"

  command=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["statusLine"]["command"])' "$SETTINGS")
  assertEquals "Should name this checkout's statusline" \
    "python3 '$DOTFILES/claude/statusline.py'" "$command"

  leftovers=$(find "$(get_claude_config_dir)" -name 'settings.json.??????' | wc -l)
  assertEquals "The merge temp file should be gone" "0" "$leftovers"

  # -y answers the mode question with its default, which is to link. pi's skills
  # are here too: Claude Code does not read ~/.agents/skills.
  assertEquals "Should link its own skill" \
    "$DOTFILES/claude/skills/rate-limit-status" \
    "$(readlink "$(get_claude_skills_dir)/rate-limit-status")"
  assertEquals "Should link pi's skills alongside them" \
    "$DOTFILES/pi/skills/ste-writing" \
    "$(readlink "$(get_claude_skills_dir)/ste-writing")"
  assertEquals "Should link its rules" \
    "$DOTFILES/claude/rules/md.md" \
    "$(readlink "$(get_claude_rules_dir)/md.md")"
  assertTrue "A linked skill should resolve to its SKILL.md" \
    "[ -f \"$(get_claude_skills_dir)/rate-limit-status/SKILL.md\" ]"
}

# @image: with-python
it_preserves_machine_local_keys_and_replaces_arrays() {
  mkdir -p "$(get_claude_config_dir)"
  cat > "$SETTINGS" <<-'EOF'
	{
	  "model": "opus",
	  "effortLevel": "high",
	  "theme": "light",
	  "permissions": { "deny": ["OnlyMine"], "allow": ["Bash(ls:*)"] }
	}
	EOF

  output=$(install_claude_settings)
  assertTrue "Expected the merge to exit 0" $?

  assertEquals "model is machine-local" "opus" "$(_settings_value model)"
  assertEquals "effortLevel is machine-local" "high" "$(_settings_value effortLevel)"
  assertEquals "the template wins on theme" "dark" "$(_settings_value theme)"

  permissions=$(python3 -c 'import json,sys; p=json.load(open(sys.argv[1]))["permissions"]; print(" ".join(p["deny"]), "|", " ".join(p["allow"]))' "$SETTINGS")
  assertContains "The template's deny list lands" "$permissions" "CronCreate"
  assertNotContains "The machine's deny entry is replaced" "$permissions" "OnlyMine"
  assertContains "A sibling key the template ignores survives" "$permissions" "Bash(ls:*)"

  assertContains "Should report the overwritten key" \
    "$output" 'theme: "light" -> "dark"'
  assertTrue "Should have backed the old file up" "[ -f \"$SETTINGS.bkp\" ]"

  # Idempotency: nothing left to do, and no second backup.
  output=$(install_claude_settings)
  assertContains "A re-run should find nothing to do" "$output" "already up to date"
  assertFalse "Should not pile up backups" "[ -f \"$SETTINGS.bkp1\" ]"
}

# Claude Code rewrites this file itself. A change of format alone must not count
# as a change worth a backup and a rewrite.
# @image: with-python
it_ignores_a_pure_reformat() {
  quietly install_claude_settings
  python3 -c 'import json,sys; p=sys.argv[1]; json.dump(json.load(open(p)), open(p,"w"), indent=4, sort_keys=True)' \
    "$SETTINGS"

  output=$(install_claude_settings)

  assertContains "Different formatting is not different settings" \
    "$output" "already up to date"
  assertFalse "And nothing worth backing up" "[ -f \"$SETTINGS.bkp\" ]"
}

# A JSON array parses, but there is nothing to merge keys into.
# @image: with-python
it_treats_a_non_object_settings_file_as_unreadable() {
  mkdir -p "$(get_claude_config_dir)"
  printf '["not", "an", "object"]' > "$SETTINGS"

  output=$(install_claude_settings 2>/dev/null)

  assertTrue "Should recover rather than fail" $?
  assertContains "Should say it replaced the file" "$output" "Replaced unreadable"
  assertEquals "And the template lands clean" "dark" "$(_settings_value theme)"
}

# @image: with-python
it_replaces_an_unreadable_settings_file() {
  mkdir -p "$(get_claude_config_dir)"
  printf 'truncated mid-write {' > "$SETTINGS"

  output=$(install_claude_settings 2>/dev/null)
  assertTrue "An unreadable file must not stop the deploy" $?

  assertContains "Should say it replaced the file" "$output" "Replaced unreadable"
  assertEquals "The broken file is kept verbatim" \
    "truncated mid-write {" "$(cat "$SETTINGS.bkp")"
  assertEquals "And the template lands clean" "dark" "$(_settings_value theme)"
}

# The point of the expanded path: the command that the settings file names must
# run and print a line. This test sends a payload like the one Claude Code
# sends.
# @image: with-python
it_installs_a_statusline_command_that_runs() {
  quietly install_claude_settings

  command=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["statusLine"]["command"])' "$SETTINGS")
  payload='{"workspace":{"current_dir":"/tmp"},"model":{"display_name":"Opus"},
            "effort":{"level":"high"},
            "context_window":{"used_percentage":42,"total_input_tokens":84000,
                              "context_window_size":200000}}'

  output=$(printf '%s' "$payload" | eval "$command" 2>&1)
  assertTrue "The statusline command should exit 0" $?

  assertContains "Should render the model" "$output" "Opus"
  assertContains "Should render the working directory" "$output" "tmp"
}

# shellcheck source=../tests/shunit2
. shunit2
