#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
  . "$THISDIR/install_pi.sh"
  # activate_asdf wires an installed-but-off-PATH asdf into the environment
  # before the pi step; the cross-module test below drives it.
  # shellcheck source=../asdf/activate.sh
  . "$DOTFILES/asdf/activate.sh"
}

it_checks_pi_is_not_installed() {
  is_pi_installed
  assertFalse "Expected pi not installed on clean image" $?
}

# @image: base
it_copies_skills_to_agents_directory() {
  local skills_dest
  skills_dest="$HOME/.agents/skills"

  # Verify destination doesn't exist before install
  assertFalse "$HOME/.agents/skills should not exist yet" "[ -d \"$skills_dest\" ]"

  # Run the install step
  quietly install_pi_skills

  # Verify ~/.agents/skills was created
  assertTrue "$HOME/.agents/skills should exist" "[ -d \"$skills_dest\" ]"

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

# @image: with-asdf
it_installs_pi_via_asdf_managed_node() {
  # pi's node binaries need a modern glibc; amazonlinux:2 ships 2.26, too old to
  # run them. Skip there rather than fail on a platform limitation.
  glibc=$(getconf GNU_LIBC_VERSION 2>/dev/null)
  case "$glibc" in
    "glibc "*)
      if ! version_ge "${glibc#glibc }" 2.27; then
        echo "Skipping: pi's node needs glibc >= 2.27 (found ${glibc#glibc })"
        startSkipping
        return 0
      fi
      ;;
  esac

  # asdf-nodejs verifies downloads against GPG keys fetched from public
  # keyservers; skip that to keep the test off flaky keyserver infrastructure.
  export NODEJS_CHECK_SIGNATURES=no

  # asdf is installed at ~/.local/bin but off PATH (see the with-asdf stage).
  # This is the deploy-time situation: without activation pi can't see asdf and
  # falls back to the package manager. Drive the real fix.
  assertFalse "asdf must not be on PATH before activation" "command_exists asdf"
  activate_asdf
  assertTrue "activate_asdf should put asdf on PATH" "command_exists asdf"

  assertFalse "pi should not be installed yet" "is_pi_installed"

  # Full wizard: bootstraps node via asdf, installs pi, then copies skills.
  quietly install_pi_wizard -y
  assertTrue "Expected pi wizard to exit 0" $?

  assertTrue "pi should be on PATH after install" "is_pi_installed"

  output=$(pi --version 2>&1)
  assertContains "pi --version should report the pinned version" \
    "$output" "$PI_VERSION"

  assertTrue "Skills should be copied to ~/.agents/skills" \
    "[ -d \"$HOME/.agents/skills/grill-me\" ]"

  # Idempotency: a second run detects the existing install and short-circuits
  # instead of reinstalling (verified here to avoid a second node bootstrap).
  output=$(install_pi_program)
  assertTrue "Re-running install_pi_program should succeed" $?
  assertContains "Should report already installed on re-run" \
    "$output" "pi already installed"
}

# shellcheck source=../tests/shunit2
. shunit2
