#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
  REAL_DOTFILES="$(get_abs_path "$THISDIR/..")"
}

# Every test works against a fake checkout: ownership means "the link points
# inside the source directory that feeds this destination", so the tests need
# sources they can add to and take from.
setUp() {
  DOTFILES="$REAL_DOTFILES"
  . "$THISDIR/utils.sh"
  DOTFILES="${SHUNIT_TMPDIR:?}/dotfiles"
  SRC="$DOTFILES/skills"
  OTHER_SRC="$DOTFILES/other-skills"
  DEST="${SHUNIT_TMPDIR:?}/home/.claude/skills"
  mkdir -p "$SRC" "$OTHER_SRC" "$DEST"
  DOTFILES_ANSWERS=''
}

tearDown() {
  cleanupSpies
  cleanupTestDir
}

# A skill directory named $1 in the fake checkout, which holds a SKILL.md
# with $2.
_given_a_source_skill() {
  mkdir -p "$SRC/${1:?}"
  printf '%s\n' "${2:-body}" > "$SRC/$1/SKILL.md"
}

# Stage $1 as the answers to come, for `... < "$KEYS"`. printf interprets
# backslash escapes, so '\n' is the Enter that means "take the default".
# A file rather than a pipe: a piped function runs in a subshell, where the
# variable an out-parameter sets dies with it.
_given_keystrokes() {
  KEYS="${SHUNIT_TMPDIR:?}/keystrokes"
  printf '%b' "${1:?}" > "$KEYS"
}

#
# is_owned_entry
#

test_owned_entry_recognizes_a_link_into_the_source() {
  _given_a_source_skill alpha
  ln -s "$SRC/alpha" "$DEST/alpha"

  is_owned_entry "$DEST/alpha" "$SRC"

  assertTrue "A link into the source we install from is ours" $?
}

test_owned_entry_rejects_a_link_somewhere_else() {
  ln -s "${SHUNIT_TMPDIR:?}/elsewhere" "$DEST/handoff"

  is_owned_entry "$DEST/handoff" "$SRC"

  assertFalse "A link outside the checkout is not ours" $?
}

# The user is free to wire a corner of the checkout into a destination this repo
# never installs it to — a claude skill linked into pi's directory, say. That
# link is theirs, and a later prune must not take it.
test_owned_entry_rejects_a_link_into_a_source_that_does_not_feed_it() {
  mkdir -p "$OTHER_SRC/gamma"
  ln -s "$OTHER_SRC/gamma" "$DEST/gamma"

  is_owned_entry "$DEST/gamma" "$SRC"

  assertFalse "Only the sources feeding this destination count" $?
}

test_owned_entry_accepts_any_of_the_sources_it_is_given() {
  mkdir -p "$OTHER_SRC/gamma"
  ln -s "$OTHER_SRC/gamma" "$DEST/gamma"

  is_owned_entry "$DEST/gamma" "$SRC" "$OTHER_SRC"

  assertTrue "A destination fed by two sources owns both" $?
}

# The links a user makes by hand are typically relative. Only the absolute form
# install_entries writes counts as ours.
test_owned_entry_rejects_a_relative_link() {
  ln -s ../../.agents/skills/handoff "$DEST/handoff"

  is_owned_entry "$DEST/handoff" "$SRC"

  assertFalse "A relative link is someone else's convention" $?
}

test_owned_entry_rejects_a_real_directory() {
  mkdir -p "$DEST/alpha"

  is_owned_entry "$DEST/alpha" "$SRC"

  assertFalse "A copy cannot be proven ours" $?
}

#
# entry_names
#

test_entry_names_lists_every_source_directory() {
  _given_a_source_skill alpha
  _given_a_source_skill beta
  mkdir -p "$DOTFILES/rules"
  : > "$DOTFILES/rules/md.md"

  assertEquals "alpha beta md.md" "$(entry_names "$SRC" "$DOTFILES/rules")"
}

test_entry_names_ignores_a_missing_directory() {
  _given_a_source_skill alpha

  assertEquals "alpha" "$(entry_names "$SRC" "$DOTFILES/nowhere")"
}

test_entry_names_is_empty_for_an_empty_directory() {
  assertEquals "" "$(entry_names "$SRC")"
}

#
# duplicate_entry_names
#

test_duplicate_entry_names_finds_a_name_two_sources_share() {
  _given_a_source_skill alpha
  _given_a_source_skill beta
  mkdir -p "$OTHER_SRC/beta"

  assertEquals "beta" "$(duplicate_entry_names "$SRC" "$OTHER_SRC")"
}

test_duplicate_entry_names_is_empty_when_sources_are_disjoint() {
  _given_a_source_skill alpha
  mkdir -p "$OTHER_SRC/gamma"

  assertEquals "" "$(duplicate_entry_names "$SRC" "$OTHER_SRC")"
}

test_duplicate_entry_names_reports_a_shared_name_once() {
  _given_a_source_skill alpha
  mkdir -p "$OTHER_SRC/alpha" "$DOTFILES/third"
  mkdir -p "$DOTFILES/third/alpha"

  assertEquals "alpha" "$(duplicate_entry_names "$SRC" "$OTHER_SRC" "$DOTFILES/third")"
}

#
# ask_install_mode
#

test_ask_install_mode_defaults_to_link() {
  _given_keystrokes '\n'

  quietly_stdout ask_install_mode claude_skills "skills" mode < "$KEYS"

  assertTrue "Enter should be an answer, not an abort" $?
  assertEquals "link" "$mode"
}

test_ask_install_mode_returns_copy_on_the_second_option() {
  _given_keystrokes '2'

  quietly_stdout ask_install_mode claude_skills "skills" mode < "$KEYS"

  assertEquals "copy" "$mode"
}

test_ask_install_mode_records_the_mode_it_was_given() {
  _given_keystrokes '2'

  quietly_stdout ask_install_mode claude_skills "skills" mode < "$KEYS"

  assertEquals 'claude_skills=copy' "$DOTFILES_ANSWERS"
}

# Each module asks this about its own entries. One key between them would let
# whichever ran first answer for the other, silently.
test_ask_install_mode_keeps_each_callers_answer_apart() {
  DOTFILES_ANSWERS='pi_skills=copy'
  _given_keystrokes '1'

  quietly_stdout ask_install_mode claude_skills "skills and rules" mode < "$KEYS"

  assertEquals "pi's answer should not answer for claude" "link" "$mode"
  assertEquals 'pi_skills=copy claude_skills=link' "$DOTFILES_ANSWERS"
}

test_ask_install_mode_replays_a_recorded_mode() {
  DOTFILES_ANSWERS='claude_skills=copy'
  # stdin says option 1. The recorded copy has to win.
  _given_keystrokes '1'

  quietly_stdout ask_install_mode claude_skills "skills" mode < "$KEYS"

  assertEquals "copy" "$mode"
}

test_ask_install_mode_reports_a_quit() {
  _given_keystrokes 'q'

  quietly_stdout ask_install_mode claude_skills "skills" mode < "$KEYS"

  assertFalse "Quitting is not a mode" $?
}

# Without diff every copy looks edited, and the default policy would file a
# fresh backup of the same directory on every deploy. The option is withheld
# rather than refused after the fact: a refusal comes too late to stop the
# answer being recorded, and a recorded answer is replayed instead of asked.
test_ask_install_mode_does_not_offer_copy_without_diff() {
  command_exists() { [ "$1" != diff ]; }
  _given_keystrokes '1'

  output=$( (ask_install_mode claude_skills "skills" mode < "$KEYS") 2>&1 )

  assertContains "Should say what is missing" "$output" "diff"
  assertNotContains "Should not offer a mode it cannot honor" \
    "$output" "2) copy them into place"
}

test_ask_install_mode_still_links_without_diff() {
  command_exists() { [ "$1" != diff ]; }
  _given_keystrokes '\n'

  quietly_stdout ask_install_mode claude_skills "skills" mode < "$KEYS"

  assertTrue "Linking should still be available" $?
  assertEquals "link" "$mode"
  assertEquals 'claude_skills=link' "$DOTFILES_ANSWERS"
}

test_ask_install_mode_asks_again_when_a_recorded_copy_cannot_be_honored() {
  command_exists() { [ "$1" != diff ]; }
  DOTFILES_ANSWERS='claude_skills=copy'
  _given_keystrokes '1'

  quietly_stdout ask_install_mode claude_skills "skills" mode < "$KEYS"

  assertEquals "the stale copy should not be replayed" "link" "$mode"
  assertEquals 'claude_skills=link' "$DOTFILES_ANSWERS"
}

#
# list_collisions
#

test_list_collisions_names_a_real_directory_in_link_mode() {
  _given_a_source_skill alpha
  mkdir -p "$DEST/alpha"

  assertEquals "$DEST/alpha" "$(list_collisions "$SRC" "$DEST" link)"
}

test_list_collisions_ignores_a_link_already_pointing_at_the_source() {
  _given_a_source_skill alpha
  ln -s "$SRC/alpha" "$DEST/alpha"

  assertEquals "" "$(list_collisions "$SRC" "$DEST" link)"
}

test_list_collisions_names_a_link_pointing_elsewhere() {
  _given_a_source_skill alpha
  ln -s "${SHUNIT_TMPDIR:?}/elsewhere" "$DEST/alpha"

  assertEquals "$DEST/alpha" "$(list_collisions "$SRC" "$DEST" link)"
}

# A dangling link is invisible to -e. A silent replacement of one would be the
# same surprise as a silent replacement of a real link.
test_list_collisions_names_a_dangling_link() {
  _given_a_source_skill alpha
  ln -s "${SHUNIT_TMPDIR:?}/gone" "$DEST/alpha"

  assertEquals "$DEST/alpha" "$(list_collisions "$SRC" "$DEST" link)"
}

# An untouched copy is the one we made, so a re-run asks nothing.
test_list_collisions_ignores_an_identical_copy_in_copy_mode() {
  _given_a_source_skill alpha body
  mkdir -p "$DEST/alpha"
  printf 'body\n' > "$DEST/alpha/SKILL.md"

  assertEquals "" "$(list_collisions "$SRC" "$DEST" copy)"
}

# An edited copy and a skill that was there first look the same. Both are worth
# a question before the installer replaces them.
test_list_collisions_names_a_differing_copy_in_copy_mode() {
  _given_a_source_skill alpha body
  mkdir -p "$DEST/alpha"
  printf 'edited\n' > "$DEST/alpha/SKILL.md"

  assertEquals "$DEST/alpha" "$(list_collisions "$SRC" "$DEST" copy)"
}

test_list_collisions_names_a_link_in_copy_mode() {
  _given_a_source_skill alpha
  ln -s "$SRC/alpha" "$DEST/alpha"

  assertEquals "$DEST/alpha" "$(list_collisions "$SRC" "$DEST" copy)"
}

#
# install_entries
#

test_install_entries_links_every_entry() {
  _given_a_source_skill alpha
  _given_a_source_skill beta

  quietly install_entries "$SRC" "$DEST" link backup

  assertEquals "$SRC/alpha" "$(readlink "$DEST/alpha")"
  assertEquals "$SRC/beta" "$(readlink "$DEST/beta")"
}

test_install_entries_copies_every_entry() {
  _given_a_source_skill alpha body

  quietly install_entries "$SRC" "$DEST" copy backup

  assertFalse "A copy is not a link" "[ -L \"$DEST/alpha\" ]"
  assertEquals "body" "$(cat "$DEST/alpha/SKILL.md")"
}

test_install_entries_reports_nothing_to_do_on_a_second_run() {
  _given_a_source_skill alpha
  quietly install_entries "$SRC" "$DEST" link backup

  output=$(install_entries "$SRC" "$DEST" link backup)

  assertContains "Should report it is already done" "$output" "nothing to do"
}

test_install_entries_backs_a_collision_up_outside_the_skills_root() {
  _given_a_source_skill alpha
  mkdir -p "$DEST/alpha"
  printf 'mine\n' > "$DEST/alpha/SKILL.md"

  quietly install_entries "$SRC" "$DEST" link backup

  assertEquals "The link should be installed" "$SRC/alpha" "$(readlink "$DEST/alpha")"
  assertEquals "The old one should be kept verbatim" \
    "mine" "$(cat "$DEST.bkp/alpha/SKILL.md")"
  # Both harnesses discover skills recursively: a backup inside the root would
  # come back as a skill of its own.
  assertFalse "The backup must not sit inside the skills root" \
    "[ -e \"$DEST/alpha.bkp\" ]"
}

test_install_entries_names_the_backup_it_made() {
  _given_a_source_skill alpha
  mkdir -p "$DEST/alpha"

  output=$(install_entries "$SRC" "$DEST" link backup)

  assertContains "Should say where the old one went" "$output" "backed"
  assertContains "Should name the backup path" "$output" "skills.bkp/alpha"
}

test_install_entries_deletes_a_collision_under_the_delete_policy() {
  _given_a_source_skill alpha
  mkdir -p "$DEST/alpha"

  quietly install_entries "$SRC" "$DEST" link delete

  assertEquals "$SRC/alpha" "$(readlink "$DEST/alpha")"
  assertFalse "Nothing should be kept" "[ -d \"$DEST.bkp/alpha\" ]"
}

test_install_entries_asks_per_entry_under_the_each_policy() {
  _given_a_source_skill alpha
  _given_a_source_skill beta
  mkdir -p "$DEST/alpha" "$DEST/beta"

  # confirm reads a single byte: 'y' backs alpha up, 'n' deletes beta.
  _given_keystrokes 'yn'

  quietly install_entries "$SRC" "$DEST" link each < "$KEYS"

  assertTrue "alpha should be kept" "[ -d \"$DEST.bkp/alpha\" ]"
  assertFalse "beta should not be" "[ -d \"$DEST.bkp/beta\" ]"
}

test_install_entries_keeps_a_second_backup_of_the_same_name() {
  _given_a_source_skill alpha
  mkdir -p "$DEST.bkp/alpha"
  mkdir -p "$DEST/alpha"

  quietly install_entries "$SRC" "$DEST" link backup

  assertTrue "The earlier backup should survive" "[ -d \"$DEST.bkp/alpha\" ]"
  assertTrue "The new one should sit beside it" "[ -d \"$DEST.bkp/alpha-1\" ]"
}

test_install_entries_backs_an_edited_copy_up_before_replacing_it() {
  _given_a_source_skill alpha body
  quietly install_entries "$SRC" "$DEST" copy backup
  printf 'edited\n' >> "$DEST/alpha/SKILL.md"

  output=$(install_entries "$SRC" "$DEST" copy backup)

  assertEquals "The source should win" "body" "$(cat "$DEST/alpha/SKILL.md")"
  assertContains "A local change is never reverted in silence" "$output" "backed"
  assertContains "The edit should be kept verbatim" \
    "edited" "$(cat "$DEST.bkp/alpha/SKILL.md")"
}

test_install_entries_is_quiet_when_a_copy_is_untouched() {
  _given_a_source_skill alpha body
  quietly install_entries "$SRC" "$DEST" copy backup

  output=$(install_entries "$SRC" "$DEST" copy backup)

  assertContains "An untouched copy needs no question" \
    "$output" "nothing to do"
  assertFalse "And nothing worth backing up" "[ -d \"$DEST.bkp\" ]"
}

test_install_entries_replaces_a_copy_with_a_link_when_the_mode_changes() {
  _given_a_source_skill alpha
  quietly install_entries "$SRC" "$DEST" copy backup

  quietly install_entries "$SRC" "$DEST" link backup

  assertEquals "$SRC/alpha" "$(readlink "$DEST/alpha")"
  assertTrue "The copy should be kept" "[ -d \"$DEST.bkp/alpha\" ]"
}

test_install_entries_does_nothing_for_a_missing_source() {
  install_entries "$DOTFILES/nowhere" "$DEST" link backup

  assertTrue "A source the repo does not ship is not an error" $?
  assertEquals "" "$(ls "$DEST")"
}

#
# prune_owned_entries
#

test_prune_removes_an_entry_the_repo_dropped() {
  _given_a_source_skill alpha
  _given_a_source_skill beta
  quietly install_entries "$SRC" "$DEST" link backup

  quietly prune_owned_entries "$DEST" "alpha" "$SRC"

  assertTrue "The shipped one stays" "[ -L \"$DEST/alpha\" ]"
  assertFalse "The dropped one goes" "[ -L \"$DEST/beta\" ]"
}

# The regression this whole rewrite exists for: the previous installer cleared
# the destination wholesale, and took 19 skills that came from somewhere else.
test_prune_never_removes_what_this_repo_did_not_install() {
  _given_a_source_skill alpha
  quietly install_entries "$SRC" "$DEST" link backup
  mkdir -p "$DEST/handmade"
  ln -s ../../.agents/skills/handoff "$DEST/handoff"

  quietly prune_owned_entries "$DEST" "alpha" "$SRC"

  assertTrue "A directory we did not create stays" "[ -d \"$DEST/handmade\" ]"
  assertTrue "A link we did not create stays" "[ -L \"$DEST/handoff\" ]"
}

test_prune_removes_a_dangling_link_of_ours() {
  _given_a_source_skill alpha
  quietly install_entries "$SRC" "$DEST" link backup
  rm -rf "$SRC/alpha"

  quietly prune_owned_entries "$DEST" "" "$SRC"

  assertFalse "A link to a skill the repo dropped goes" "[ -L \"$DEST/alpha\" ]"
}

# A copy carries no proof of origin, so the prune leaves it where it is.
test_prune_leaves_copies_alone() {
  _given_a_source_skill alpha
  quietly install_entries "$SRC" "$DEST" copy backup

  quietly prune_owned_entries "$DEST" "" "$SRC"

  assertTrue "A copy is never pruned" "[ -d \"$DEST/alpha\" ]"
}

test_prune_names_what_it_removed() {
  _given_a_source_skill alpha
  quietly install_entries "$SRC" "$DEST" link backup

  output=$(prune_owned_entries "$DEST" "" "$SRC")

  assertContains "Should name the entry" "$output" "alpha"
  assertContains "Should say why" "$output" "no longer in the repo"
}

# The reviewer's case: a link the user made from this destination into a corner
# of the checkout that does not feed it. Ours by the old $DOTFILES-wide test,
# theirs by the scoped one.
test_prune_leaves_a_link_into_another_source_alone() {
  _given_a_source_skill alpha
  quietly install_entries "$SRC" "$DEST" link backup
  mkdir -p "$OTHER_SRC/gamma"
  ln -s "$OTHER_SRC/gamma" "$DEST/gamma"

  quietly prune_owned_entries "$DEST" "alpha" "$SRC"

  assertTrue "A link into a source we do not install from stays" \
    "[ -L \"$DEST/gamma\" ]"
}

test_prune_does_nothing_for_a_missing_destination() {
  prune_owned_entries "${SHUNIT_TMPDIR:?}/nowhere" "alpha" "$SRC"

  assertTrue "A destination that was never created is not an error" $?
}

# Run tests
SHPY_PATH="$THISDIR/../tests/shpy"
export SHPY_PATH
. "$THISDIR/../tests/shpy"
. "$THISDIR/../tests/shpy-shunit2"
. "$THISDIR/../tests/shunit2"
