#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
  DOTFILES="$(get_abs_path "$THISDIR/..")"
}

setUp() {
  . "$THISDIR/utils.sh"
}

tearDown() {
  cleanupSpies
  cleanupTestDir
}


#
# Tests
#

test_resolves_canonical_names_on_apt() {
  createSpy -u -o 'apt-get' get_supported_pm

  out=$(pm_packages_for libevent-headers ncurses-headers chsh)

  assertEquals "libevent-dev libncurses-dev passwd" "$out"
}

test_resolves_canonical_names_on_yum() {
  createSpy -u -o 'yum' get_supported_pm

  out=$(pm_packages_for libevent-headers ncurses-headers chsh)

  assertEquals "libevent-devel ncurses-devel util-linux-user" "$out"
}

test_unknown_names_pass_through() {
  createSpy -u -o 'apt-get' get_supported_pm

  out=$(pm_packages_for wget tar gcc)

  assertEquals "wget tar gcc" "$out"
}

test_preserves_caller_order_for_mixed_names() {
  createSpy -u -o 'apt-get' get_supported_pm

  out=$(pm_packages_for wget libevent-headers bison ncurses-headers)

  assertEquals "wget libevent-dev bison libncurses-dev" "$out"
}

test_unsupported_pm_passes_names_through() {
  createSpy -u -o '' get_supported_pm

  out=$(pm_packages_for libevent-headers wget)

  # install_from_pm itself is responsible for the "no PM" error path,
  # so pm_packages_for stays inert and just echoes the inputs.
  assertEquals "libevent-headers wget" "$out"
}

test_no_args_echoes_blank_line() {
  createSpy -u -o 'apt-get' get_supported_pm

  out=$(pm_packages_for)

  assertEquals "" "$out"
}


# Run tests
SHPY_PATH="$THISDIR/../tests/shpy"
export SHPY_PATH
. "$THISDIR/../tests/shpy"
. "$THISDIR/../tests/shpy-shunit2"
. "$THISDIR/../tests/shunit2"
