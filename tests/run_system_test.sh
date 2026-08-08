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

# Cases to keep in flight at once. Each runs in its own container and shares
# nothing but the host, and the tmux-from-source case already asks four cores of
# it. JOBS=1 runs the suite one case at a time.
: "${JOBS:=3}"
# A pool of nought hands out no tokens, so every worker would wait on one
# forever rather than the run failing.
case "${JOBS}" in
  *[!0-9]* | '' | 0) printf 'JOBS must be a positive integer, got: %s\n' "${JOBS}" >&2; exit 1 ;;
esac

# Field separator for plan records: ASCII FS, spelled `\034` in the printf
# formats that write them. Not whitespace, so `read` keeps a heading's empty
# fields instead of collapsing them away.
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

# $1: image  $2: test file  $3: test case
# $4: where docker records the container id, so an interrupt can reach a
#     container the worker shell cannot: killing the worker leaves the
#     `docker run` it was blocked on still running.
run_test_in_docker() {
  local image="${1:?}" file="${2:?}" case="${3:?}" cidfile="${4:?}"
  local command docker_status output_verdict
  command="${file} -- ${case}"
  # Give the test a pseudo-terminal, so anything guarded by [ -t 0 ] runs the
  # same path a human gets. docker's own -t cannot do this: the pipeline below
  # needs docker's stdout to stay a pipe, and -t refuses without a terminal on
  # the host side too.
  # The session goes through a file rather than straight out because util-linux
  # 2.30, which amazonlinux-2 ships, exits without draining the pty when its
  # stdout is a pipe, losing the tail of the session — shunit2's summary among
  # it. `tail` follows the file so the output still arrives live, which is all a
  # container killed partway through has to show for itself. -s trims the ~1s
  # --pid poll, which otherwise costs every case most of a second of idling.
  # Neither flag is POSIX, so an image added under tests/systems needs a tail
  # that implements them; the GNU and uutils ones in use both do.
  [ "${PTY}" = "0" ] || command=": >/tmp/pty_out
script -qec '${command}' /dev/null >/tmp/pty_out 2>&1 &
pty_pid=\$!
tail -f -s 0.05 -n +1 --pid=\"\$pty_pid\" /tmp/pty_out
wait \"\$pty_pid\""
  # Run test case. docker heads the pipeline, so $? afterwards belongs to awk;
  # its own status comes back out of fd 3, which the substitution captures.
  docker_status=$(
    {
      { docker run --rm --cidfile "${cidfile}" -v "${THISDIR}/..:/app:ro" -w /app \
          -e DOTFILES=/app ${DEBUG:+-e DEBUG=1} \
          ${PTY_SETTLE_SECONDS:+-e PTY_SETTLE_SECONDS="${PTY_SETTLE_SECONDS}"} \
          "${image}" sh -c "${command}"
        echo "$?" >&3
      } |
        # drop the CR half of a pty's \r\n, which the filter below would not match,
        tr -d '\r' |
        # filter verbose lines unless DEBUG is set, then echo output,
        # including the bare `^@` sudo writes to the terminal once per
        # authentication whenever its stdin is a tty — which is what the pty above
        # hands it. Two characters, not a NUL, so `tr -d` cannot take it, and
        # anchored so a line that merely contains `^@` survives.
        if [ "${DEBUG:-}" != "1" ]; then sed "/^$\|^\^@$/ d"; else cat; fi |
        # echo the output and judge it. shunit2's own summary is the receipt that
        # a run happened at all: a container can exit 0 having stopped halfway,
        # which leaves no FAILED to scan for and used to read as a pass. The
        # `.*` spans the colour codes shunit2 wraps the count in, and `tests?`
        # matches the plural run_unit_tests.sh's extract_ran_count allows for.
        # `>&2` duplicates the runner's own stderr, not reopens it.
        awk -v debug="${DEBUG:-}" '
          /^Ran .* tests?\.$/ { reported = 1; if (debug != "1") next }
          { print; fflush() }
          /FAILED/ { failed = 1 }
          END { exit failed ? 1 : (reported ? 0 : 2) }
        ' >&2
    } 3>&1
  )
  output_verdict=$?
  # An empty status means the stage never reached the echo, which is a failure
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
    0)
      [ "${output_verdict}" -eq 0 ] && return 0
      # Only worth saying when docker itself was happy; otherwise the statuses
      # below already explain the missing summary.
      [ "${output_verdict}" -eq 2 ] &&
        printf 'ERROR: %s in %s stopped before shunit2 reported a result\n' \
          "${case}" "${image}" >&2
      return 1 ;;
    # The statuses that mean the test never ran, rather than ran and failed:
    # 125 the daemon refused the run, 126/127 the container could not execute
    # the command — a missing image tag, or an `# @image:` naming a stage that
    # was never built.
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
  return 1
}

#
# Scheduling
#

# Take down everything the current run started. Killing a worker shell does not
# stop the `docker run` it is blocked on, so the containers are reached by the
# ids docker recorded for them rather than through the process tree.
# $1: the run's temp dir, holding the cidfiles and any unprinted output
# $2: the pids of the workers still outstanding, space separated
stop_plan() {
  local dir="${1:?}" pids="${2:-}" cidfile ids='' partial
  # shellcheck disable=SC2086 # the pids are a deliberate word-split list
  [ -z "${pids}" ] || kill ${pids} 2>/dev/null
  # `cat` rather than `read`, which reports EOF on the newline docker leaves off
  # the end of a cidfile and would take the id down with its status.
  for cidfile in "${dir}"/*.cid; do
    [ -s "${cidfile}" ] || continue
    ids="${ids} $(cat "${cidfile}")"
  done
  # shellcheck disable=SC2086 # one docker call for the lot, not one per id
  [ -z "${ids}" ] || docker rm -f ${ids} >/dev/null 2>&1
  # Whatever the interrupted cases had said for themselves. The replay loop
  # deletes each file as it prints it, so what is left is only the part of the
  # run nobody has seen — and a case killed midway is exactly the one whose
  # output is worth keeping.
  for partial in "${dir}"/*.out; do
    [ -s "${partial}" ] || continue
    printf '\n> interrupted, output so far:\n' >&2
    cat "${partial}" >&2
  done
  return 0
}

# Run the plan in $1/plan, keeping $JOBS cases in flight, and echo each case's
# output in plan order as it finishes. A plan is one record per line, five
# fields separated by ASCII FS: `H..file..` for a file heading, or
# `C.index.file.case.image` for a case.
# Returns the last non-zero verdict any case reported, or 0 if all passed.
run_plan() {
  local dir="${1:?}" plan slots_taken status workers
  local kind idx file case image pid rc
  plan="${dir}/plan"
  status=0
  # Named before the trap that reads it, so an interrupt landing between here
  # and the first container still finds something defined.
  workers=''
  trap 'stop_plan "${dir}" "${workers}"; exit 130' INT TERM
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
      run_test_in_docker "${image}" "${file}" "${case}" "${dir}/${idx}.cid" \
        >"${dir}/${idx}.out" 2>&1
    ) &
    workers="${workers}${workers:+ }$!"
  done <"${plan}"

  # Replay in plan order, so a parallel run reads exactly like a serial one.
  # Waiting on a worker that already finished returns at once, so the ordering
  # costs nothing beyond the slowest case still outstanding.
  while IFS="${PLAN_FS}" read -r kind idx file case image; do
    if [ "${kind}" = H ]; then
      printf '\n> %s\n' "${file}"
      continue
    fi
    # Both loops walk the plan in the same order, so the next case's worker is
    # the head of the list. Popping before the wait also keeps `workers` to what
    # an interrupt should still signal — never a pid the system has since
    # handed to somebody else.
    pid=${workers%% *}
    workers=${workers#"${pid}"}
    workers=${workers# }
    # A worker killed outright reports 128+signal here, which is a failure like
    # any other; nothing has to be inferred from a file it never wrote.
    wait "${pid}"
    rc=$?
    # Case output went to stderr before the pool existed, and downstream that
    # separates the streams to surface only failures still expects it there.
    cat "${dir}/${idx}.out" >&2
    # Printed, so an interrupt later has no reason to print it again.
    rm -f "${dir}/${idx}.out"
    [ "${rc}" -eq 0 ] || status="${rc}"
  done <"${plan}"

  trap - INT TERM
  exec 9>&-
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

# Refuse a test file the container could not execute, naming the missing bit
# rather than leaving it to surface as a docker 126 blaming the image. Costs no
# container to find out. Kept in step with the same check in run_unit_tests.sh.
for test_file in "$@"; do
  [ -f "$test_file" ] || { printf 'No such test file: %s\n' "$test_file" >&2; exit 1; }
  [ -x "$test_file" ] ||
    { printf 'Test file is not executable: %s\n' "$test_file" >&2; exit 1; }
done

# One directory for the plan and everything the run records against it.
run_dir=$(mktemp -d) || { echo 'Could not create temporary directory' >&2; exit 1; }
trap 'rm -rf "$run_dir"' EXIT INT TERM

# Write the plan out first, so the schedule and the output order are decided
# before any container starts.
case_index=0
{
  # Iterate through all test files in args
  while [ $# -gt 0 ]; do
    test_file=$1; shift
    printf 'H\034\034%s\n' "$test_file"
    # Iterate through all test cases
    for test_case in $(get_test_cases_from_file "$test_file"); do
      [ -n "$filter_case" ] && [ "$test_case" != "$filter_case" ] && continue
      tag=$(get_test_image_annotation "$test_file" "$test_case")
      image="${docker_image}-test:${tag:-base}"
      case_index=$((case_index + 1))
      printf 'C\034%s\034%s\034%s\034%s\n' \
        "$case_index" "$test_file" "$test_case" "$image"
    done
  done
} >"$run_dir/plan"

# A plan with nothing in it would sail through as a pass: a mistyped -t, or a
# file that defines no cases, must not read the same as a suite that ran.
if [ "${case_index}" -eq 0 ]; then
  if [ -n "${filter_case}" ]; then
    printf 'No test case named %s in the given files\n' "${filter_case}" >&2
  else
    echo 'No test cases found in the given files' >&2
  fi
  exit 1
fi

# Exits with 0 only if all tests passed
run_plan "$run_dir"
