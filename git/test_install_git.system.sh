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

  # Identity required for `git commit`; not exercising configure_git_user here
  # since its UX is covered by unit tests.
  git config --global user.name "Test User"
  git config --global user.email "test@example.com"
  git config --global init.defaultBranch main

  # A freshly-init'd repo should inherit the prepare-commit-msg hook,
  # which prefixes the commit message with the issue id parsed from the branch.
  repo="${SHUNIT_TMPDIR:?}/sample-repo"
  mkdir -p "$repo"
  (
    cd "$repo"
    quietly git init
    quietly git checkout -b ABC-123-test-feature
    echo hello > file.txt
    quietly git add file.txt
    quietly git commit -m "my message"
  )

  assertContains "Hook should have prefixed commit with issue id" \
    "$(cd "$repo" && git log -1 --pretty=%B)" \
    "[ABC-123] my message"
}

# shellcheck source=../tests/shunit2
. shunit2
