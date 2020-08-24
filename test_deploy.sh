#!/usr/bin/env sh

#
# Mocks
#

mock_read_char() {
  head -c 1 # just forward given char
}

# Extract list of mock functions and generate the declarations.
# Each mock_*() function is returned as *() { mock_*; };
# Args:
#   $0: this test script name
# Returns:
#   string: of mock function declarations
extract_mock_functions() {
  grep -E "^[ 	]*mock_[A-Za-z0-9_]* *\(\)" "$0" \
  | sed 's/mock_\([A-Za-z0-9_]*\).*/\1(){ mock_\1; };/g' \
  | xargs # to join lines into one
}

# Source and mock deploy.sh script
deploy() {
  . ./deploy.sh

  if ! eval "$(extract_mock_functions)"; then
    echo "Error while installing mocks, aborting" && exit 2
  fi
}

#
# Tests
#

test_confirm_has_default_message() {
  message=$(deploy ; echo 'y' | confirm)
  assertEquals "Continue?" "${message%% *}"
}

test_confirm_trims_given_message() {
  message=$(deploy ; echo 'y' | confirm 'Sure?  ')
  assertEquals "Sure? (Y/n) y" "${message}"
}

test_confirm_returns_ok_on_y() {
  (deploy ; echo 'y' | confirm) > /dev/null
  assertTrue "y should return ok" $?

  (deploy ; echo 'Y' | confirm) > /dev/null
  assertTrue "Y should return ok" $?
}

test_confirm_returns_error_on_n() {
  (deploy ; echo 'n' | confirm) > /dev/null
  assertFalse "n should return error" $?

  (deploy ; echo 'N' | confirm) > /dev/null
  assertFalse "N should return error" $?
}

test_confirm_asks_for_correct_input() {
  output=$(deploy ; echo 'xy' | confirm)
  assertTrue "y should return ok" $?

  echo "$output" | grep -q 'Choose y or n'
  assertTrue "Confirmation output expected" $?
}

test_confirm_returns_yes_on_enter() {
  (deploy ; echo '' | confirm) > /dev/null
  assertTrue "Enter should return ok" $?
}

test_confirm_echoes_right_inputs() {
  message=$(deploy ; echo 'y' | confirm)
  # message ends with y
  assertEquals "y" "${message##*[!y]}"

  message=$(deploy ; echo 'N' | confirm)
  # message ends with N
  assertEquals "N" "${message##*[!N]}"
}

test_confirm_write_y_for_enter() {
  message=$(deploy ; echo '' | confirm)
  assertEquals "y" "${message##*[!y]}"
}

test_supported_pm() {
  (deploy ; check_supported_pm)
  assertTrue "PM should be supported" $?
}

test_package_manager_wizard() {
  mock_update_package_manager() {
    echo 'update called'
  }
  mock_upgrade_packages() {
    echo 'upgrade called'
  }
  # [N]o for update, [y]es for upgrade
  output=$(deploy ; echo 'Ny' | package_manager_wizard)

  echo "$output" | grep -q 'update called'
  assertFalse "Update shouldn't be called" $?

  echo "$output" | grep -q 'upgrade called'
  assertTrue "Upgrade should've been called" $?
}

# Run tests
# shellcheck source=/usr/bin/shunit2
. shunit2