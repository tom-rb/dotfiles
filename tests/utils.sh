#!/usr/bin/env sh

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