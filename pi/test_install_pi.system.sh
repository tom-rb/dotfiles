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
it_links_skills_into_the_agents_directory() {
  local skills_dest
  skills_dest="$HOME/.agents/skills"

  # Verify the destination does not exist before the install
  assertFalse "$HOME/.agents/skills should not exist yet" "[ -d \"$skills_dest\" ]"

  # Enter takes the default answer, which is to link
  printf '\n' | quietly install_pi_skills

  # Verify the install created ~/.agents/skills
  assertTrue "$HOME/.agents/skills should exist" "[ -d \"$skills_dest\" ]"

  # The link points at this checkout, so a change to the repo changes the skill
  assertEquals "ste-writing should link to the checkout" \
    "$DOTFILES/pi/skills/ste-writing" "$(readlink "$skills_dest/ste-writing")"
  assertTrue "ste-writing should resolve to its SKILL.md" \
    "[ -f \"$skills_dest/ste-writing/SKILL.md\" ]"
}

# The old step cleared ~/.agents/skills wholesale on every run. It took every
# skill installed from anywhere else with it.
# @image: base
it_leaves_skills_it_did_not_install_alone() {
  local skills_dest
  skills_dest="$HOME/.agents/skills"

  printf '\n' | quietly install_pi_skills
  mkdir -p "$skills_dest/handoff"
  echo "from somewhere else" > "$skills_dest/handoff/SKILL.md"

  # Second run: nothing to do, and nothing to take with it
  output=$(printf '\n' | install_pi_skills)

  assertContains "A second run should find nothing to do" "$output" "nothing to do"
  assertTrue "A skill from elsewhere should survive" \
    "[ -f \"$skills_dest/handoff/SKILL.md\" ]"
  assertEquals "And ours should be untouched" \
    "$DOTFILES/pi/skills/ste-writing" "$(readlink "$skills_dest/ste-writing")"
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

  # -y answers the mode question with its default, which is to link
  assertEquals "Skills should be linked into ~/.agents/skills" \
    "$DOTFILES/pi/skills/ste-writing" "$(readlink "$HOME/.agents/skills/ste-writing")"
  assertFalse "And nothing should reach Claude's own directory" \
    "[ -d \"$HOME/.claude/skills\" ]"

  # Idempotency: a second run detects the existing install and short-circuits
  # instead of reinstalling (verified here to avoid a second node bootstrap).
  output=$(install_pi_program)
  assertTrue "Re-running install_pi_program should succeed" $?
  assertContains "Should report already installed on re-run" \
    "$output" "pi ${PI_VERSION} already installed"
}

# shellcheck source=../tests/shunit2
. shunit2
