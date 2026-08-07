#!/usr/bin/env sh

# Disallow unset variables in tests
set -o nounset

# Determine the location of this script, and subsequently the test directory
THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

# Run tests against a pseudo-terminal by default, so raw-mode code is exercised
# rather than skipped. PTY=0 gives the test piped stdin instead, which is what a
# scripted, non-interactive run looks like.
: "${PTY:=1}"

#
# Test case discovery function
#

readonly test_case_regex="^\s*(it_[A-Za-z0-9_-]*)\s*\(\)"

# Print a list of all test cases found in $1
get_test_cases_from_file() {
  sed -nE "s/${test_case_regex}.*/\1/p" "$1"
}

# Print annotated image name for the given test, if it exists
# Note: tests can choose an image tag (i.e. stage) with # @image: name
get_test_image_annotation() {
  local file="${1:?}" case="${2:?}"
  # /^# @image: (.+)$/  When the image name annotation is found,
  #   s//\1/;h;n;       get the name; send it to [h]old space; read [n]ext line;
  #   /^$case/{g;p;q}   if its the case, [g]et and [p]rint name then [q]uit.
  sed -nE "/^# @image: (.+)$/ { s//\1/;h;n; /^$case/{g;p;q} }" "$file"
}

#
# Run tests
#

run_test_in_docker() {
  local image="${1:?}" file="${2:?}" case="${3:?}" command
  local status_file docker_status output_verdict
  command="${file} -- ${case}"
  # Give the test a pseudo-terminal, so anything guarded by [ -t 0 ] runs the
  # same path a human gets. docker's own -t cannot do this: the pipeline below
  # needs docker's stdout to stay a pipe, and -t refuses without a terminal on
  # the host side too.
  [ "${PTY}" = "0" ] || command="script -qec '${command}' /dev/null"
  status_file=$(mktemp) || { echo 'Could not create temporary file' >&2; exit 1; }
  # Run test case. docker heads the pipeline, so $? afterwards belongs to awk;
  # stash its own status in a file, the way tui_task does. The brace group is a
  # pipeline stage, so the redirection stays confined to that subshell.
  {
    docker run --rm -v "${THISDIR}/..:/app:ro" -w /app \
      -e DOTFILES=/app ${DEBUG:+-e DEBUG=1} \
      ${PTY_SETTLE_SECONDS:+-e PTY_SETTLE_SECONDS="${PTY_SETTLE_SECONDS}"} \
      "${image}" sh -c "${command}"
    echo "$?" >"${status_file}"
  } |
    # drop the CR half of a pty's \r\n, which the filter below would not match,
    tr -d '\r' |
    # filter verbose lines unless DEBUG is set, then echo output,
    # including the bare `^@` sudo writes to the terminal once per
    # authentication whenever its stdin is a tty — which is what the pty above
    # hands it. Two characters, not a NUL, so `tr -d` cannot take it, and
    # anchored so a line that merely contains `^@` survives.
    if [ "${DEBUG:-}" != "1" ]; then sed "/^$\|^\^@$/ d"; else cat; fi |
    # echo the output and judge it. shunit2's own summary is the receipt that a
    # run happened at all: a container can exit 0 having stopped halfway, which
    # leaves no FAILED to scan for and used to read as a pass. The summary is
    # swallowed rather than printed, as it was by the filter above, except
    # under DEBUG. `>&2` duplicates the runner's own stderr, not reopens it.
    awk -v debug="${DEBUG:-}" '
      /^Ran .* test.$/ { reported = 1; if (debug != "1") next }
      { print; fflush() }
      /FAILED/ { failed = 1 }
      END { exit failed ? 1 : (reported ? 0 : 2) }
    ' >&2
  output_verdict=$?
  docker_status=$(cat "${status_file}")
  rm -f "${status_file}"
  # An empty file means the stage never reached the echo, which is a failure
  # too — inferring "passed" from missing evidence is the bug being fixed here.
  report_run_status "${docker_status:-1}" "${output_verdict}" "${image}" "${file}" "${case}"
}

# Explain why a case did not pass, then return its verdict: 0 only when the
# container exited cleanly and its output showed a run that reached the end.
# $1: docker's exit status
# $2: the output verdict: 0 clean, 1 a FAILED line, 2 no shunit2 summary
# $3: image  $4: test file  $5: test case
report_run_status() {
  local status="${1:?}" output_verdict="${2:?}" image="${3:?}" file="${4:?}"
  local case="${5:?}"
  case "${status}" in
    0) ;;
    # The statuses that mean the test never ran, rather than ran and failed:
    # 125 the daemon refused the run, 126/127 the container could not execute
    # the command — a missing image tag, an `# @image:` naming a stage that was
    # never built, or a test file without its executable bit. A bare number
    # here would be unreadable, so name what was being attempted.
    125|126|127)
      printf 'ERROR: could not run %s in %s (docker exit %s)\n' \
        "${file}" "${image}" "${status}" >&2 ;;
    *)
      printf 'ERROR: %s in %s exited %s without reporting a result\n' \
        "${case}" "${image}" "${status}" >&2 ;;
  esac
  # Only worth saying when docker itself was happy; otherwise the status above
  # already explains the missing summary.
  [ "${status}" -eq 0 ] && [ "${output_verdict}" -eq 2 ] &&
    printf 'ERROR: %s in %s stopped before shunit2 reported a result\n' \
      "${case}" "${image}" >&2
  [ "${status}" -eq 0 ] && [ "${output_verdict}" -eq 0 ]
}

#
# Parse arguments
#

# -t TEST: run only the named test case
filter_case=""
while [ $# -gt 0 ]; do
  case $1 in
    -t) filter_case="${2:?'-t requires a test case name'}"; shift 2 ;;
    --) shift; break ;;
    -*) printf 'Unknown flag: %s\n' "$1" >&2; exit 1 ;;
    *)  break ;;
  esac
done

if [ $# -lt 2 ]; then
  echo "Usage: $0 [-t test_case] image_base_name test_file [test_file...]"
  echo "  -t test_case     Run only the named test case"
  echo "  image_base_name  Docker base image to run tests against"
  echo "  test_file        Test script(s) to run"
  echo "Env:"
  echo "  DEBUG=1          Show full docker output"
  exit 1
fi

docker_image=$1
shift

# Refuse a test file the container could not execute. The verdict above would
# catch it anyway, but as a docker 126 naming the image rather than the bit
# that is actually missing — and this costs no container to find out.
for test_file in "$@"; do
  [ -f "$test_file" ] || { printf 'No such test file: %s\n' "$test_file" >&2; exit 1; }
  [ -x "$test_file" ] ||
    { printf 'Test file is not executable: %s\n' "$test_file" >&2; exit 1; }
done

# Track tests status
status=0

# Iterate through all test files in args
while [ $# -gt 0 ]; do
  test_file=$1; shift
  printf '\n> %s\n' "${test_file}"
  # Iterate through all test cases
  for test_case in $(get_test_cases_from_file "$test_file"); do
    [ -n "$filter_case" ] && [ "$test_case" != "$filter_case" ] && continue
    tag=$(get_test_image_annotation "$test_file" "$test_case")
    image="${docker_image}-test:${tag:-base}"
    run_test_in_docker "$image" "$test_file" "$test_case" || status=$?
  done
done

# Exits with 0 only if all tests passed
exit $status
