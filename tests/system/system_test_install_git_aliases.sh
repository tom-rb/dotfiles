#!/usr/bin/env sh

readonly THISDIR=$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)

oneTimeSetUp() {
  # shellcheck source=../../git/install_git_aliases.sh
  . "$THISDIR/../../git/install_git_aliases.sh"
}

# @image: basics
it_installs_patched_git_aliases_in_bash() {
  install_git_aliases_bash >/dev/null 2>&1

  assertContains "Expected added source in .bashrc" \
    "$(cat ~/.bashrc)" "git_aliases.sh"

  # shellcheck disable=SC1090
  . ~/.bashrc

  assertContains "Expected installed alias" \
    "$(alias gb)" "git branch"
}

# shellcheck source=../shunit2
. shunit2