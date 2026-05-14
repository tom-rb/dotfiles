#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  # shellcheck source=../tests/utils_for_test.sh
  . "$THISDIR/../tests/utils_for_test.sh"
  # shellcheck source=install_git_aliases.sh
  . "$THISDIR/install_git_aliases.sh"
}

# @image: with-basics
it_installs_patched_git_aliases_in_bash() {
  quietly install_git_aliases_bash

  assertContains "Expected added source in .bashrc" \
    "$(cat ~/.bashrc)" "git_aliases.sh"

  # shellcheck disable=SC1090
  . ~/.bashrc

  assertContains "Expected installed alias" \
    "$(alias gb)" "git branch"
}

# shellcheck source=../tests/shunit2
. shunit2