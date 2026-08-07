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

  out=$(_pm_packages_for libevent-headers ncurses-headers chsh)

  assertEquals "libevent-dev libncurses-dev passwd" "$out"
}

test_resolves_canonical_names_on_yum() {
  createSpy -u -o 'yum' get_supported_pm

  out=$(_pm_packages_for libevent-headers ncurses-headers chsh)

  assertEquals "libevent-devel ncurses-devel util-linux-user" "$out"
}

test_resolves_libatomic_per_pm() {
  createSpy -u -o 'apt-get' get_supported_pm
  assertEquals "libatomic1" "$(_pm_packages_for libatomic)"

  # On yum the package is already named libatomic, so it passes through.
  createSpy -u -o 'yum' get_supported_pm
  assertEquals "libatomic" "$(_pm_packages_for libatomic)"
}

test_unknown_names_pass_through() {
  createSpy -u -o 'apt-get' get_supported_pm

  out=$(_pm_packages_for wget tar gcc)

  assertEquals "wget tar gcc" "$out"
}

test_preserves_caller_order_for_mixed_names() {
  createSpy -u -o 'apt-get' get_supported_pm

  out=$(_pm_packages_for wget libevent-headers bison ncurses-headers)

  assertEquals "wget libevent-dev bison libncurses-dev" "$out"
}

test_unsupported_pm_passes_names_through() {
  createSpy -u -o '' get_supported_pm

  out=$(_pm_packages_for libevent-headers wget)

  # install_from_pm itself is responsible for the "no PM" error path,
  # so _pm_packages_for stays inert and just echoes the inputs.
  assertEquals "libevent-headers wget" "$out"
}

test_no_args_echoes_blank_line() {
  createSpy -u -o 'apt-get' get_supported_pm

  out=$(_pm_packages_for)

  assertEquals "" "$out"
}

#
# install_from_pm / get_version_in_pm — unsupported PM
#

test_get_version_in_package_manager_fails_for_unsupported_pm() {
  createSpy -u -r "$SHUNIT_FALSE" command_exists

  err_msg=$({ get_version_in_pm htop 1>/dev/null; } 2>&1)

  assertContains "Should get an error message" \
    "${err_msg}" "find package manager"
}

test_install_from_package_manager_fails_for_unsupported_pm() {
  createSpy -u -r "$SHUNIT_FALSE" command_exists

  err_msg=$({ install_from_pm --fail "Couldn't install htop" -- htop 1>/dev/null; } 2>&1)

  assertFalse "Nothing was installed, so the status must say so" $?
  assertContains "Should get an error message" \
    "${err_msg}" "find package manager"
}

#
# install_from_pm — reporting
#

# The ✓ wording a caller can only know once the packages have landed.
_installed_msg() {
  echo "git 2.51.0 installed"
}

test_install_from_pm_reports_the_task_and_the_outcome() {
  createSpy -u -o 'apt-get' get_supported_pm
  createSpy -u _install_from_pm

  output=$(install_from_pm --fail "Couldn't install git" -- git 2>&1)

  assertContains "Should name the packages and the PM while it runs" \
    "$output" "installing git (apt-get)"
  assertContains "Should close the task with the packages" \
    "$output" "✓ git installed"
  assertCalledOnceWith _install_from_pm git
}

# The Task speaks the caller's vocabulary, not the PM's: chsh installs passwd
# on apt, and a step announcing passwd is a step nobody asked for.
test_install_from_pm_names_the_task_before_the_pm_translation() {
  createSpy -u -o 'apt-get' get_supported_pm
  createSpy -u _install_from_pm

  output=$(install_from_pm --fail "Couldn't install chsh" -- chsh 2>&1)

  assertContains "Should name the canonical package" \
    "$output" "installing chsh (apt-get)"
  assertNotContains "Should not leak the apt name" "$output" "passwd"
}

# For the package lists that would not read as a name on their own.
test_install_from_pm_renames_the_task_with_as() {
  createSpy -u -o 'apt-get' get_supported_pm
  createSpy -u _install_from_pm

  output=$(install_from_pm --as 'build dependencies' \
    --die "Couldn't install them" -- wget tar 2>&1)

  assertContains "Should name the noun and the PM while it runs" \
    "$output" "installing build dependencies (apt-get)"
  assertContains "Should close the task with the noun" \
    "$output" "✓ build dependencies installed"
  assertCalledOnceWith _install_from_pm wget tar
}

# The separator is optional: a caller with flags to pass reads better with it,
# one without it should not have to type it.
test_install_from_pm_takes_packages_with_or_without_the_separator() {
  createSpy -u -o 'apt-get' get_supported_pm
  createSpy -u _install_from_pm

  quietly install_from_pm --fail "nope" git
  quietly install_from_pm --fail "nope" -- git

  assertCallCount _install_from_pm 2
  assertCalledWith _install_from_pm git
  assertCalledWith _install_from_pm git
}

test_install_from_pm_overrides_the_ok_wording_with_ok_cmd() {
  createSpy -u -o 'apt-get' get_supported_pm
  createSpy -u _install_from_pm

  output=$(install_from_pm --ok-cmd _installed_msg \
    --die "Couldn't install git" -- git 2>&1)

  assertContains "The helper should word the ✓, not the packages" \
    "$output" "✓ git 2.51.0 installed"
}

test_install_from_pm_does_not_claim_success_when_the_install_fails() {
  createSpy -u -o 'apt-get' get_supported_pm
  createSpy -u -r "$SHUNIT_FALSE" _install_from_pm

  output=$(install_from_pm --fail "Couldn't install git" -- git 2>&1)

  assertFalse "Should hand the PM's status back to the caller" $?
  assertNotContains "Nothing was installed, so nothing may say so" \
    "$output" "✓ git installed"
  assertContains "And the ✗ is the Task closing itself" \
    "$output" "✗ Couldn't install git"
}

test_install_from_pm_does_not_claim_success_without_a_package_manager() {
  createSpy -u -o '' get_supported_pm

  output=$({ install_from_pm --as 'build dependencies' \
    --fail "Couldn't install them" -- wget tar; } 2>&1)

  assertFalse "Should hand the failure back to the caller" $?
  assertNotContains "Nothing was installed, so nothing may say so" \
    "$output" "✓ build dependencies installed"
  # _install_from_pm's own complaint reaches stderr, and the Outcome replays it.
  assertContains "Should replay why under the ✗" \
    "$output" "find package manager"
}

test_install_from_pm_returns_the_pm_status_verbatim() {
  createSpy -u -o 'apt-get' get_supported_pm
  createSpy -u -r 42 _install_from_pm

  install_from_pm --fail "Couldn't install git" -- git >/dev/null 2>&1

  assertEquals "The caller decides what a given failure means" 42 $?
}

test_install_from_pm_dies_when_asked_to() {
  createSpy -u -o 'apt-get' get_supported_pm
  createSpy -u -r "$SHUNIT_FALSE" _install_from_pm

  output=$( (install_from_pm --die "Couldn't install git" -- git
             echo SHOULD-NOT-RUN) 2>&1)

  assertContains "$output" "✗ Couldn't install git"
  assertNotContains "die does not come back" "$output" "SHOULD-NOT-RUN"
}

test_install_from_pm_warns_without_dying() {
  createSpy -u -o 'apt-get' get_supported_pm
  createSpy -u -r "$SHUNIT_FALSE" _install_from_pm

  output=$( { install_from_pm --warn "Couldn't install chsh" -- chsh
              echo AFTER; } 2>&1)

  assertContains "$output" "! Couldn't install chsh"
  assertContains "A warning is not the end of the wizard" "$output" "AFTER"
}

# Without one, an install that failed would leave its arrow line open and the
# next line would glue onto it.
test_install_from_pm_requires_a_failure_flag() {
  createSpy -u -o 'apt-get' get_supported_pm
  createSpy -u _install_from_pm

  output=$( (install_from_pm -- git) 2>&1)

  assertContains "$output" "needs one of --die, --fail or --warn"
}


# Run tests
SHPY_PATH="$THISDIR/../tests/shpy"
export SHPY_PATH
. "$THISDIR/../tests/shpy"
. "$THISDIR/../tests/shpy-shunit2"
. "$THISDIR/../tests/shunit2"
