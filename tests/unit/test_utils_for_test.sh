#!/usr/bin/env sh

readonly THISDIR=$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)

# Source utils_for_test.sh script
utils() {
  # shellcheck source=../utils_for_test.sh
  . "$THISDIR/../utils_for_test.sh"
}

# Dummy function to test mock functionality
original_function() {
  echo 'original'
}

# Script level mock
setUp() {
  mock_original_function() {
    echo 'script'
  }
}

#
# Tests
#

test_script_level_mock_is_called() {
  message=$(utils ; eval "$(extract_mock_functions)" ; original_function)
  assertEquals "script" "$message"
}

test_a_test_level_mock_is_called() {
  mock_original_function() {
    echo 'mock1'
  }
  message=$(utils ; eval "$(extract_mock_functions)" ; original_function)
  assertEquals "mock1" "$message"
}

test_without_mocks_after_defining_one_test_level_mock_calls_script_level() {
  message=$(utils ; eval "$(extract_mock_functions)" ; original_function)
  assertEquals "script" "$message"
}

test_overwritting_a_test_level_mock_calls_the_new_mock() {
  mock_original_function() {
    echo 'mock2'
  }
  message=$(utils ; eval "$(extract_mock_functions)" ; original_function)
  assertEquals "mock2" "$message"
}

# Run tests
# shellcheck source=../shunit2
. "$THISDIR/../shunit2"