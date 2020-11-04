#!/usr/bin/env sh

# Clean contents of temporary test dir SHUNIT_TMPDIR
cleanupTestDir() {
  # Only clean tmp dir if something is there
  if [ -n "$(command ls -qA -- "${SHUNIT_TMPDIR:?}")" ]; then (
      cd "${SHUNIT_TMPDIR:?}" &&
      # Clean all hidden and non-hidden files
      # https://unix.stackexchange.com/a/77313
      rm -rf -- ..?* .[!.]* *
  ) fi
}

# Extract list of mock functions and generate the declarations.
# Usage: eval "$(extract_mock_functions)"
# NOTE: implementation is tied to shunit2 lib internals
extract_mock_functions() {
  local script_file=${0:?}
  # Use internal shunit2 variable to determine current running test
  local test_name=${_shunit_test_:?}
  # Sed patterns summary:
  # 1. Skip lines inside test functions that are not $test_name
  # 2. When $test_name is found, append a flag to hold space
  # 3. Append to hold space the stubbed calls to mock functions
  # 4. Print the hold space and quit if $test_name was closed '}'
  sed -nE \
    -e "/^test_/{ /$test_name/! { :skip_test /^}$/! {n;b skip_test} } }" \
    -e "/$test_name/{ s/.*/TEST_FOUND/; H }" \
    -e '/^[ 	]*mock_([A-Za-z0-9_]+) *\(\).*/ { s//\1(){ mock_\1; };/ ; H }' \
    -e "/^}$/{ g; /TEST_FOUND/{ s///;p;q }; h }" "$script_file" \
  | xargs # to join lines into one
}