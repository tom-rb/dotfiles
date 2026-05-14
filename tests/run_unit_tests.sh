#!/usr/bin/env sh

# Run a list of unit test files, streaming their output, then print the
# total number of tests executed (summed from each file's "Ran N tests"
# line). Exits non-zero on the first failing file.

#
# Parse arguments
#

# -t TEST: run only the named test case (skips files that don't define it)
filter_case=""
while [ $# -gt 0 ]; do
  case $1 in
    -t) filter_case="${2:?'-t requires a test case name'}"; shift 2 ;;
    --) shift; break ;;
    -*) printf 'Unknown flag: %s\n' "$1" >&2; exit 1 ;;
    *)  break ;;
  esac
done

if [ $# -lt 1 ]; then
  echo "Usage: $0 [-t test_case] test_file [test_file...]"
  echo "  -t test_case  Run only the named test case"
  echo "  test_file     Unit test script(s) to run"
  exit 1
fi

#
# Run tests
#

# Strip ANSI color escapes from $1 and echo the count from "Ran N tests."
extract_ran_count() {
  local esc
  esc=$(printf '\033')
  sed "s/$esc\[[0-9;]*[a-zA-Z]//g" "$1" \
    | sed -nE 's/^Ran +([0-9]+) tests?\..*/\1/p' \
    | tail -1
}

total=0
out=$(mktemp)
ec=$(mktemp)
trap 'rm -f "$out" "$ec"' EXIT INT TERM

for test_file in "$@"; do
  # Skip files that don't define the requested case
  if [ -n "$filter_case" ] && ! grep -qE "^${filter_case}\(\)" "$test_file"; then
    continue
  fi
  echo "> $test_file"
  : > "$ec"
  # Capture exit code via $ec since `| tee` masks it
  { "$test_file" ${filter_case:+-- "$filter_case"} || echo $? > "$ec"; } | tee "$out"
  rc=$(cat "$ec")
  [ -z "$rc" ] || exit "$rc"
  n=$(extract_ran_count "$out")
  total=$(( total + ${n:-0} ))
done

echo ">>>>>>  TOTAL: $total tests"
