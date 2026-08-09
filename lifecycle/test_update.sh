#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
}

setUp() {
  # Source update.sh with a defined DOTFILES path
  DOTFILES="$(CDPATH='' cd -- "$THISDIR/.." >/dev/null && pwd -P)" \
    dotfiles_dont_run=1 . "$THISDIR/../update.sh"
}

tearDown() {
  cleanupSpies
  cleanupTestDir
}

#
# Helpers
#

# Spy on git with the answers a healthy clone gives: on branch main, tracking
# origin/main, with origin/main as the remote's default branch. The queries are
# answered in the order run_update asks them. That order is asserted by
# test_update_queries_the_clone_then_fast_forwards below.
# -f N: make query N, and every query after it, fail
# -b NAME: put the checkout on branch NAME, tracking origin/NAME
# -d "AHEAD BEHIND": how far the branch and its upstream have each moved
# -c COUNT: how many commits the pull moves HEAD over
spyOnGit() {
  local fail branch distance count statuses index
  fail='' branch='main' distance='0 3' count='3'
  while [ $# -gt 0 ]; do
    case "$1" in
      -f) fail=${2:?}; shift 2 ;;
      -b) branch=${2:?}; shift 2 ;;
      -d) distance=${2:?}; shift 2 ;;
      -c) count=${2?}; shift 2 ;;
      *)  break ;;
    esac
  done

  statuses=''
  index=1
  while [ "$index" -lt "${fail:-1}" ]; do
    statuses="$statuses -r $SHUNIT_TRUE"
    index=$((index + 1))
  done
  if [ -n "$fail" ]; then
    statuses="$statuses -r $SHUNIT_FALSE"
  else
    statuses="-r $SHUNIT_TRUE"
  fi

  # shellcheck disable=SC2086 # the status flags are built to be word-split
  createSpy -u $statuses \
    -o "$DOTFILES" \
    -o "$branch" \
    -o "origin/$branch" \
    -o "$distance" \
    -o 'origin/main' \
    -o 'abc1234' \
    -o '' \
    -o "$count" \
    git
}

#
# Preconditions
#

test_update_dies_when_dotfiles_is_not_a_git_clone() {
  spyOnGit -f 1
  createSpy -u run_deploy

  message=$(run_update 2>&1)

  assertFalse "Error code expected" $?
  assertContains "Expected the moved-clone message" "$message" "not a git clone"
  assertNeverCalled run_deploy
}

test_update_dies_when_dotfiles_is_not_the_root_of_its_clone() {
  createSpy -u -r "$SHUNIT_TRUE" -o '/some/enclosing/repo' git
  createSpy -u run_deploy

  message=$(run_update 2>&1)

  assertFalse "Error code expected" $?
  assertContains "Expected the moved-clone message" "$message" "not a git clone"
  assertNeverCalled run_deploy
}

test_update_dies_on_a_detached_head() {
  spyOnGit -f 2
  createSpy -u run_deploy

  message=$(run_update 2>&1)

  assertFalse "Error code expected" $?
  assertContains "Expected the detached-HEAD message" "$message" "detached HEAD"
  assertNeverCalled run_deploy
}

test_update_dies_when_the_branch_has_no_upstream() {
  spyOnGit -f 3
  createSpy -u run_deploy

  message=$(run_update 2>&1)

  assertFalse "Error code expected" $?
  assertContains "Expected the missing-upstream message" "$message" "no upstream"
  assertContains "Expected the branch to be named" "$message" "main"
  assertNeverCalled run_deploy
}

test_update_dies_when_the_branch_has_diverged_from_its_upstream() {
  # Commits on both sides: the pull cannot fast-forward over them.
  spyOnGit -d '2 3'
  createSpy -u run_deploy

  message=$(run_update 2>&1)

  assertFalse "Error code expected" $?
  assertContains "Expected the divergence message" "$message" "diverged from origin/main"
  assertNeverCalled run_deploy
}

# The normal state of anyone developing this repo: commits on this side only.
test_update_deploys_when_the_branch_is_only_ahead_of_its_upstream() {
  spyOnGit -d '2 0' -c 0
  createSpy -u run_deploy

  message=$(run_update </dev/null 2>&1)

  assertTrue "Being ahead should not stop the update" $?
  assertNotContains "Being ahead is not a divergence" "$message" "diverged"
  assertCalledOnceWith run_deploy
}

#
# The non-default branch prompt
#

test_update_asks_before_updating_a_non_default_branch() {
  spyOnGit -b feat/x
  createSpy -u run_deploy

  message=$(echo y | run_update 2>&1)

  assertTrue "Expected the accepted branch to go ahead" $?
  assertContains "Expected the branch and the default to be named" \
    "$message" "feat/x tracks origin/feat/x, not the default origin/main"
  assertCalledOnceWith run_deploy
}

# The warning fires on any clone whose record of the default predates a branch
# rename, so it points at the command that refreshes that record.
test_update_names_the_command_that_refreshes_a_stale_default() {
  spyOnGit -b feat/x
  createSpy -u run_deploy

  message=$(echo y | run_update 2>&1)

  assertContains "Expected the set-head hint" \
    "$message" "git remote set-head origin --auto"
}

test_update_stops_when_a_non_default_branch_is_declined() {
  spyOnGit -b feat/x
  createSpy -u run_deploy

  echo n | quietly run_update

  assertFalse "Error code expected" $?
  assertNeverCalled run_deploy
}

test_update_does_not_ask_about_the_default_branch() {
  spyOnGit
  createSpy -u run_deploy

  # No stdin: a prompt here would abort the run rather than hang.
  message=$(run_update 2>&1 </dev/null)

  assertTrue "Expected no prompt on the default branch" $?
  assertNotContains "Expected no branch warning" "$message" "not the default"
}

#
# The pull
#

test_update_queries_the_clone_then_fast_forwards() {
  spyOnGit
  createSpy -u run_deploy

  quietly run_update </dev/null

  assertCalledWith git -C "$DOTFILES" rev-parse --show-toplevel
  assertCalledWith git -C "$DOTFILES" symbolic-ref --quiet --short HEAD
  assertCalledWith git -C "$DOTFILES" rev-parse --abbrev-ref --symbolic-full-name "main@{upstream}"
  assertCalledWith git -C "$DOTFILES" rev-list --left-right --count "HEAD...origin/main"
  assertCalledWith git -C "$DOTFILES" symbolic-ref --quiet --short refs/remotes/origin/HEAD
  assertCalledWith git -C "$DOTFILES" rev-parse HEAD
  assertCalledWith git -C "$DOTFILES" pull --ff-only
}

test_update_reports_how_many_commits_the_pull_brought_in() {
  spyOnGit -c 3
  createSpy -u run_deploy

  message=$(run_update </dev/null 2>&1)

  assertContains "Expected the commit count" "$message" "3 commits pulled"
}

test_update_reports_a_pull_that_brought_nothing_in() {
  spyOnGit -c 0
  createSpy -u run_deploy

  message=$(run_update </dev/null 2>&1)

  assertContains "Expected the up-to-date wording" "$message" "already up to date"
}

test_update_does_not_deploy_when_the_pull_fails() {
  spyOnGit -f 7
  createSpy -u run_deploy

  quietly run_update </dev/null

  assertFalse "Error code expected" $?
  assertNeverCalled run_deploy
}

#
# The deploy
#

test_update_deploys_after_a_successful_pull() {
  spyOnGit
  createSpy -u run_deploy

  quietly run_update </dev/null

  assertTrue "Expected a clean run" $?
  assertCalledOnceWith run_deploy
}

test_update_propagates_the_status_of_the_deploy() {
  spyOnGit
  createSpy -u -r "$SHUNIT_FALSE" run_deploy

  quietly run_update </dev/null

  assertFalse "Error code expected" $?
}

# Run tests
SHPY_PATH="$THISDIR/../tests/shpy"
export SHPY_PATH
. "$THISDIR/../tests/shpy"
. "$THISDIR/../tests/shpy-shunit2"
. "$THISDIR/../tests/shunit2"
