#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
  . "$THISDIR/install_git.sh"
}

it_checks_git_is_not_installed() {
  is_git_installed
  assertFalse "Expected git not installed" $?
}

# @image: base
it_installs_git_configures_templates_and_hook_takes_effect() {
  quietly install_git_program
  assertTrue "Expect git to be installed" "is_git_installed"

  quietly install_git_templates
  assertEquals "init.templateDir should point to dotfiles templates" \
    "$DOTFILES/git/templates" \
    "$(git config --global --get init.templateDir)"

  quietly install_git_excludesfile
  assertEquals "core.excludesfile should point to dotfiles gitignore.global" \
    "$DOTFILES/git/.gitignore.global" \
    "$(git config --global --get core.excludesfile)"

  # Identity required for `git commit`; not exercising configure_git_user here
  # since its UX is covered by unit tests.
  git config --global user.name "Test User"
  git config --global user.email "test@example.com"

  quietly install_git_default_branch

  # A freshly-init'd repo should inherit the prepare-commit-msg hook,
  # which prefixes the commit message with the issue id parsed from the branch.
  repo="${SHUNIT_TMPDIR:?}/sample-repo"
  mkdir -p "$repo"
  (
    cd "$repo"
    quietly git init
  )
  assertEquals "Fresh repo should be on 'main' after install_git_default_branch" \
    "refs/heads/main" \
    "$(cd "$repo" && git symbolic-ref HEAD)"
  (
    cd "$repo"
    quietly git checkout -b ABC-123-test-feature
    echo hello > file.txt
    quietly git add file.txt
    quietly git commit -m "my message"
  )

  assertContains "Hook should have prefixed commit with issue id" \
    "$(cd "$repo" && git log -1 --pretty=%B)" \
    "[ABC-123] my message"

  # core.excludesfile should make patterns in .gitignore.global apply repo-wide
  (
    cd "$repo"
    echo "ruby 3.3.0" > .tool-versions
    echo tracked > tracked.txt
  )
  status_output=$(cd "$repo" && git status --porcelain)
  assertContains "untracked non-ignored file should appear in status" \
    "$status_output" "tracked.txt"
  assertNotContains "globally-ignored .tool-versions should be hidden" \
    "$status_output" ".tool-versions"
}

# shellcheck source=../tests/shunit2
. shunit2
