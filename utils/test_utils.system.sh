#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
  . "$THISDIR/utils.sh"
}

it_checks_the_package_manager_is_supported() {
  check_supported_pm
  assertTrue "Package manager should be supported" $?
}

it_gets_available_version_of_package() {
  version=$(get_version_in_pm htop)
  echo "$version" | grep -qE '^[0-9]' # at least start with a number
  assertTrue "Some version should be returned, got <$version>" $?
}

it_installs_a_package_using_package_manager() {
  command_exists htop
  assertFalse "Htop was not expected to be already installed" $?

  quietly install_from_pm htop

  command_exists htop
  assertTrue "Htop should be installed" $?
}

# shellcheck source=../tests/shunit2
. shunit2