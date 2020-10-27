#!/usr/bin/env sh

# Disallow unset variables in tests
set -o nounset

# Determine the location of this script, and subsequently the system test directory
readonly system_dir=$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)

#
# Test case discovery function
#

readonly test_case_regex="^\s*(it_[A-Za-z0-9_-]*)\s*\(\)"

# Outputs a list of all test cases found in $1 to stdout
get_test_cases_from_file() {
  sed -nE "s/${test_case_regex}.*/\1/p" "$1"
}

# Outputs annotated image name for the given test (or empty)
# Tests can choose an image suffix with @image: name
get_test_image_annotation() {
  local file=${1:?} case=${2:?}
  # /^# @image: (.+)$/  When the image name annotation is found,
  #   s//\1/;h;n;       get the name; send it to [h]old space; read [n]ext line;
  #   /^$case/{g;p;q}   if its the case, [g]et and [p]rint name then [q]uit.
  sed -nE "/^# @image: (.+)$/ { s//\1/;h;n; /^$case/{g;p;q} }" "$file"
}

#
# Test helpers
#



#
# Run tests
#

run_test_in_docker() {
  local image=${1:?} file=${2:?} case=${3:?}
  # Run test case (negation used in last pipeline command),
  ! (
    docker run --rm -v "${system_dir}/../..:/app:ro" -w /app -e DOTFILES=/app \
    "${image}" sh -c "${file} -- ${case}"
  ) |
  # filter verbose lines and echo output,
  sed "/^$\|^Ran .* test.$/ d" |
  tee /dev/tty |
  # and return 1 if test failed (by negating successful grep search)
  grep -q FAILED
}

# Print usage information if the wrong number of arguments are passed
if [ $# -lt 2 ]; then
  echo "Usage: $0 image_base_name test_file [test_file...]"
  echo "  image_base_name Docker base image to run test into"
  echo "  test_file  Test script(s) to run"
  exit 1
fi

docker_image=$1
shift

# Track tests status
status=0

# Iterate through all test files in args
while [ $# -gt 0 ]; do
  test_file=$1; shift
  printf '\n> %s\n' "${test_file}"
  # Iterate through all test cases
  for test_case in $(get_test_cases_from_file "$test_file"); do
    suffix=$(get_test_image_annotation "$test_file" "$test_case")
    image="$docker_image${suffix:+"-"}$suffix-test"
    run_test_in_docker "$image" "$test_file" "$test_case" || status=$?
  done
done

# Exits with 0 only if all tests passed
exit $status