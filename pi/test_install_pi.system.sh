#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
  . "$THISDIR/install_pi.sh"
}

# @image: base
it_copies_skills_to_agents_directory() {
  local skills_dest
  skills_dest="$HOME/.agents/skills"

  # Verify destination doesn't exist before install
  assertFalse "~/.agents/skills should not exist yet" "[ -d \"$skills_dest\" ]"

  # Run the install step
  quietly install_pi_skills

  # Verify ~/.agents/skills was created
  assertTrue "~/.agents/skills should exist" "[ -d \"$skills_dest\" ]"

  # Verify grill-me skill was copied
  assertTrue "grill-me skill should be copied" "[ -d \"$skills_dest/grill-me\" ]"
  assertTrue "grill-me should have SKILL.md" "[ -f \"$skills_dest/grill-me/SKILL.md\" ]"
}

# @image: base
it_overwrites_existing_skills() {
  local skills_dest grill_me_marker
  skills_dest="$HOME/.agents/skills"
  grill_me_marker="$skills_dest/grill-me/TEST_MARKER"

  # First install
  quietly install_pi_skills
  assertTrue "grill-me should exist after first install" "[ -d \"$skills_dest/grill-me\" ]"

  # Add a marker file to detect if it gets overwritten
  mkdir -p "$(dirname "$grill_me_marker")"
  echo "test marker" > "$grill_me_marker"
  assertTrue "Marker file should exist" "[ -f \"$grill_me_marker\" ]"

  # Second install should overwrite
  quietly install_pi_skills

  # Marker should be gone (directory was overwritten)
  assertFalse "Marker file should be overwritten" "[ -f \"$grill_me_marker\" ]"
  assertTrue "grill-me should still exist" "[ -d \"$skills_dest/grill-me\" ]"
}

# shellcheck source=../tests/shunit2
. shunit2
