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

# Cases to keep in flight at once. Each runs in its own container and shares no
# state with the others; what they do share is the host, and the case that
# builds tmux from source already asks four cores of it. JOBS=1 runs the suite
# one case at a time.
: "${JOBS:=3}"
# A pool of nought hands out no tokens and every worker waits on one forever,
# so refuse anything that is not a positive whole number rather than hang.
case "${JOBS}" in
  *[!0-9]* | '' | 0) printf 'JOBS must be a positive integer, got: %s\n' "${JOBS}" >&2; exit 1 ;;
esac

# Field separator for plan records. ASCII FS is not whitespace, so `read` keeps
# the empty fields instead of collapsing them away.
PLAN_FS="$(printf '\034')"
readonly PLAN_FS

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

# $1: image  $2: test file  $3: test case  $4: name to give the container
# $5: where to stash docker's exit status. It belongs to the caller's temp dir
#     rather than a mktemp of its own, so a case killed before it can tidy up
#     is swept away with the rest of the run.
run_test_in_docker() {
  local image="${1:?}" file="${2:?}" case="${3:?}" name="${4:?}"
  local status_file="${5:?}" command docker_status output_verdict
  command="${file} -- ${case}"
  # Give the test a pseudo-terminal, so anything guarded by [ -t 0 ] runs the
  # same path a human gets. docker's own -t cannot do this: the pipeline below
  # needs docker's stdout to stay a pipe, and -t refuses without a terminal on
  # the host side too.
  # The session goes to a file that `tail` follows out to stdout, rather than
  # straight out: util-linux 2.30, which amazonlinux-2 ships, exits without
  # draining the pty when its stdout is a pipe, and the tail of the session —
  # shunit2's summary among it — dies with the container. Writing to a file
  # removes that race outright, where a settling delay would only narrow it.
  # Following the file rather than echoing it at the end keeps the output live,
  # which is what a container that gets killed has to show for itself: a case
  # stopped partway through otherwise reports not one line.
  [ "${PTY}" = "0" ] || command=": >/tmp/pty_out
script -qec '${command}' /dev/null >/tmp/pty_out 2>&1 &
pty_pid=\$!
tail -f -n +1 --pid=\"\$pty_pid\" /tmp/pty_out
wait \"\$pty_pid\""
  # Run test case. docker heads the pipeline, so $? afterwards belongs to awk;
  # stash its own status in a file, the way tui_task does. The brace group is a
  # pipeline stage, so the redirection stays confined to that subshell.
  {
    docker run --rm --name "${name}" -v "${THISDIR}/..:/app:ro" -w /app \
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
      # A case that failed its assertions exits non-zero and has already said
      # so in its own words; anything else owes an explanation.
      [ "${output_verdict}" -eq 1 ] ||
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
# Scheduling
#

# Take down everything the current run started. Killing a worker shell does not
# stop the `docker run` it is blocked on, so the containers are reached by the
# name they were given rather than through the process tree.
# $1: the container name prefix for this run
# $2: the pids of the workers still outstanding, space separated
# $3: (optional) the run's temp dir, removed when given
stop_plan() {
  local prefix="${1:?}" pids="${2:-}" dir="${3:-}" container partial
  # shellcheck disable=SC2086 # the pids are a deliberate word-split list
  [ -z "${pids}" ] || kill ${pids} 2>/dev/null
  for container in $(docker ps -q --filter "name=^${prefix}-" 2>/dev/null); do
    docker rm -f "${container}" >/dev/null 2>&1
  done
  [ -z "${dir}" ] && return 0
  # Whatever the interrupted cases had said for themselves. The replay loop
  # deletes each file as it prints it, so what is left is only the part of the
  # run nobody has seen — and a case killed midway is exactly the one whose
  # output is worth keeping.
  for partial in "${dir}"/*.out; do
    [ -s "${partial}" ] || continue
    printf '\n> interrupted, output so far:\n' >&2
    cat "${partial}" >&2
  done
  rm -rf "${dir}"
  return 0
}

# Run the plan file $1, keeping $JOBS cases in flight, and echo each case's
# output in plan order as it finishes. A plan is one record per line, five
# fields separated by ASCII FS: `H..file..` for a file heading, or
# `C.index.file.case.image` for a case. FS rather than a tab because the
# whitespace in IFS collapses runs of itself, which would eat the empty
# fields a heading is mostly made of.
# Returns the last non-zero verdict any case reported, or 0 if all passed.
run_plan() {
  local plan="${1:?}" dir slots_taken status prefix workers remaining worker
  local kind idx file case image pid rc
  status=0
  # Both are named before the trap that reads them, so an interrupt landing
  # between here and the first container still finds something defined.
  workers='' dir=''
  # Names the containers of this run and no other, so an interrupt can find
  # them without disturbing a suite running alongside it.
  prefix="dotfiles-test-$$"
  trap 'stop_plan "${prefix}" "${workers}" "${dir}"; exit 130' INT TERM
  dir=$(mktemp -d) || { echo 'Could not create temporary directory' >&2; exit 1; }
  # One token per slot on a fifo: a worker takes one before it starts and puts
  # it back when it is done, which caps what is in flight without the parent
  # polling anything.
  mkfifo "${dir}/slots" || { echo 'Could not create the slot fifo' >&2; exit 1; }
  exec 9<>"${dir}/slots"
  slots_taken=0
  while [ "${slots_taken}" -lt "${JOBS}" ]; do
    printf '\n' >&9
    slots_taken=$((slots_taken + 1))
  done

  # Every case is launched up front and blocks on a token, so a slot freed by a
  # quick case is taken immediately rather than at the end of a batch.
  while IFS="${PLAN_FS}" read -r kind idx file case image; do
    [ "${kind}" = C ] || continue
    (
      read -r _ <&9
      # Give the token back however this subshell ends, or a case that dies
      # early would shrink the pool for the rest of the run.
      trap 'printf "\n" >&9' EXIT
      run_test_in_docker "${image}" "${file}" "${case}" "${prefix}-${idx}" \
        "${dir}/${idx}.status" >"${dir}/${idx}.out" 2>&1
      echo $? >"${dir}/${idx}.rc"
    ) &
    echo $! >"${dir}/${idx}.pid"
    workers="${workers} $!"
  done <"${plan}"

  # Replay in plan order, so a parallel run reads exactly like a serial one.
  # Waiting on a worker that already finished returns at once, so the ordering
  # costs nothing beyond the slowest case still outstanding.
  while IFS="${PLAN_FS}" read -r kind idx file case image; do
    if [ "${kind}" = H ]; then
      printf '\n> %s\n' "${file}"
      continue
    fi
    read -r pid <"${dir}/${idx}.pid"
    wait "${pid}"
    # Case output went to stderr before the pool existed, and downstream that
    # separates the streams to surface only failures still expects it there.
    cat "${dir}/${idx}.out" >&2
    # Printed, so an interrupt later has no reason to print it again.
    rm -f "${dir}/${idx}.out"
    # Drop the reaped worker: an interrupt arriving later must not signal a pid
    # the system has since handed to somebody else.
    remaining=''
    for worker in ${workers}; do
      [ "${worker}" = "${pid}" ] || remaining="${remaining} ${worker}"
    done
    workers="${remaining}"
    # A missing file means the worker died before it could record a verdict,
    # which is a failure like any other.
    rc=$(cat "${dir}/${idx}.rc" 2>/dev/null)
    [ "${rc:-1}" -eq 0 ] || status="${rc:-1}"
  done <"${plan}"

  trap - INT TERM
  exec 9>&-
  rm -rf "${dir}"
  return "${status}"
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
  echo "  JOBS=N           Run N cases at once (default 3)"
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

# Write the plan out first, so the schedule and the output order are decided
# before any container starts.
plan=$(mktemp) || { echo 'Could not create temporary file' >&2; exit 1; }
trap 'rm -f "$plan"' EXIT INT TERM

case_index=0
# Iterate through all test files in args
while [ $# -gt 0 ]; do
  test_file=$1; shift
  printf 'H%s%s%s%s%s%s\n' \
    "${PLAN_FS}" "${PLAN_FS}" "${test_file}" "${PLAN_FS}" "${PLAN_FS}" '' >>"$plan"
  # Iterate through all test cases
  for test_case in $(get_test_cases_from_file "$test_file"); do
    [ -n "$filter_case" ] && [ "$test_case" != "$filter_case" ] && continue
    tag=$(get_test_image_annotation "$test_file" "$test_case")
    image="${docker_image}-test:${tag:-base}"
    case_index=$((case_index + 1))
    printf 'C%s%s%s%s%s%s%s%s\n' \
      "${PLAN_FS}" "${case_index}" "${PLAN_FS}" "${test_file}" \
      "${PLAN_FS}" "${test_case}" "${PLAN_FS}" "${image}" >>"$plan"
  done
done

# A plan with nothing in it would sail through as a pass, which is the failure
# this runner exists to refuse: a mistyped -t, or a file that defines no cases,
# should not read the same as a suite that ran and was happy.
if [ "${case_index}" -eq 0 ]; then
  if [ -n "${filter_case}" ]; then
    printf 'No test case named %s in the given files\n' "${filter_case}" >&2
  else
    echo 'No test cases found in the given files' >&2
  fi
  exit 1
fi

# Exits with 0 only if all tests passed
run_plan "$plan"
