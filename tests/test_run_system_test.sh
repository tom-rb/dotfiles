#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/utils_for_test.sh"
  RUNNER="$THISDIR/run_system_test.sh"
}

setUp() {
  BIN_DIR="${SHUNIT_TMPDIR:?}/bin"
  # Two files, so a run covers both the case-after-case writes and the runner's
  # own "> file" header landing between them.
  FIXTURE_A="${SHUNIT_TMPDIR:?}/test_fixture_a.system.sh"
  FIXTURE_B="${SHUNIT_TMPDIR:?}/test_fixture_b.system.sh"
  LOG="${SHUNIT_TMPDIR:?}/run.log"
  ORIGINAL_PATH="$PATH"
  printf 'it_alpha() { :; }\nit_beta() { :; }\n' > "$FIXTURE_A"
  printf 'it_gamma() { :; }\n' > "$FIXTURE_B"
  # The runner refuses a test file it could not execute, so the fixtures need
  # the bit a real test file has.
  chmod +x "$FIXTURE_A" "$FIXTURE_B"
}

tearDown() {
  PATH="$ORIGINAL_PATH"
  cleanupTestDir
}

# Put a stub `docker` on PATH so the runner's pipeline can be exercised without
# starting a container.
# $1: (optional) extra line to print, e.g. FAILED
# $2: (optional) exit status for the stub, default 0
_given_a_fake_docker() {
  mkdir -p "$BIN_DIR"
  cat > "$BIN_DIR/docker" <<EOF
#!/usr/bin/env sh
# The runner hands the case name to the container as \`<file> -- <case>\`.
printf 'case %s ran\n' "\$(printf '%s\n' "\$*" | sed -nE 's/.*-- ([A-Za-z0-9_]+).*/\1/p')"
printf '%s\n' '${1-}'
# shunit2's closing summary, which the runner takes as proof a run happened.
printf 'Ran 1 test.\n'
exit ${2-0}
EOF
  chmod +x "$BIN_DIR/docker"
  PATH="$BIN_DIR:$PATH"
}

#
# Tests
#

# The echo half of the pipeline used to reopen /dev/stderr per test case, which
# against a redirected regular file starts every case back at offset 0: a whole
# suite's log kept only the last case, and a `> run.log` capture taken to read a
# red run afterwards had lost the failures that motivated it.
test_run_system_test_keeps_every_case_when_output_is_redirected() {
  _given_a_fake_docker

  "$RUNNER" ubuntu "$FIXTURE_A" "$FIXTURE_B" > "$LOG" 2>&1

  output=$(cat "$LOG")
  assertContains "First case's output must survive the ones after it" \
    "$output" "case it_alpha ran"
  assertContains "Second case's output must be there too" \
    "$output" "case it_beta ran"
  # The next file's header is written through the runner's own stdout, whose
  # offset an appending writer would leave behind — landing it on top of the
  # cases above.
  assertContains "A later file's cases must not overwrite an earlier file's" \
    "$output" "case it_gamma ran"
  assertContains "The runner's own headers must survive too" \
    "$output" "> $FIXTURE_A"
  assertContains "The runner's own headers must survive too" \
    "$output" "> $FIXTURE_B"
}

test_run_system_test_streams_every_case_through_a_pipe() {
  _given_a_fake_docker

  output=$("$RUNNER" ubuntu "$FIXTURE_A" "$FIXTURE_B" 2>&1)

  assertContains "First case's output expected" "$output" "case it_alpha ran"
  assertContains "Second case's output expected" "$output" "case it_beta ran"
  assertContains "Third case's output expected" "$output" "case it_gamma ran"
}

# sudo writes a bare `^@` to the terminal once per authentication when its
# stdin is a tty. It says nothing about the code under test, and it is two
# characters rather than the NUL it looks like.
test_run_system_test_drops_the_line_sudo_writes_to_the_terminal() {
  _given_a_fake_docker '^@'

  output=$("$RUNNER" ubuntu "$FIXTURE_A" 2>&1)

  assertNotContains "sudo's terminal noise must not reach the log" "$output" "^@"
  assertContains "The case's own output must survive the filter" \
    "$output" "case it_alpha ran"
}

test_run_system_test_keeps_a_line_that_merely_contains_the_same_characters() {
  _given_a_fake_docker 'bind-key ^@ copy-mode'

  output=$("$RUNNER" ubuntu "$FIXTURE_A" 2>&1)

  assertContains "Only a bare ^@ line is noise" "$output" "bind-key ^@ copy-mode"
}

test_run_system_test_succeeds_when_no_case_reports_a_failure() {
  _given_a_fake_docker

  "$RUNNER" ubuntu "$FIXTURE_A" >/dev/null 2>&1

  assertTrue "A quiet run is a passing run" $?
}

test_run_system_test_fails_when_a_case_reports_a_failure() {
  _given_a_fake_docker FAILED

  "$RUNNER" ubuntu "$FIXTURE_A" >/dev/null 2>&1

  assertFalse "A FAILED line must fail the run" $?
}

#
# A run that dies before shunit2 prints its summary leaves no FAILED to scan
# for. Scanning stdout was once the only signal, so every case below used to
# read as a pass: nothing ran, nothing was verified, and the suite was green.
#

test_run_system_test_fails_when_the_container_exits_non_zero_without_failed() {
  _given_a_fake_docker '' 1

  "$RUNNER" ubuntu "$FIXTURE_A" >/dev/null 2>&1

  assertFalse "A non-zero container must fail the run on its own" $?
}

test_run_system_test_lets_a_failing_case_speak_for_itself() {
  # shunit2 exits non-zero and prints FAILED; the runner adding "exited 1
  # without reporting a result" on top of that would be contradicting it.
  _given_a_fake_docker FAILED 1

  output=$("$RUNNER" ubuntu "$FIXTURE_A" 2>&1)

  assertContains "The case's own verdict must show" "$output" "FAILED"
  assertNotContains "No second, contradictory explanation" \
    "$output" "without reporting a result"
}

test_run_system_test_fails_when_the_command_cannot_be_executed() {
  # 126 is what a test file without its executable bit surfaces as.
  _given_a_fake_docker '' 126

  "$RUNNER" ubuntu "$FIXTURE_A" >/dev/null 2>&1

  assertFalse "An unexecutable command must fail the run" $?
}

test_run_system_test_names_the_image_when_the_run_never_started() {
  _given_a_fake_docker '' 125

  output=$("$RUNNER" ubuntu "$FIXTURE_A" 2>&1)

  assertContains "A refused run must name the file it was for" \
    "$output" "$FIXTURE_A"
  assertContains "A refused run must name the image it wanted" \
    "$output" "ubuntu-test:base"
  assertContains "A refused run must give docker's status" "$output" "125"
}

test_run_system_test_still_passes_a_clean_run() {
  _given_a_fake_docker '' 0

  "$RUNNER" ubuntu "$FIXTURE_A" >/dev/null 2>&1

  assertTrue "A zero exit with no FAILED is still a pass" $?
}

# Put a stub `docker` on PATH that exits cleanly having stopped partway, with
# no shunit2 summary to show for it — what amazonlinux-2's `script` does to
# some cases today.
_given_a_fake_docker_that_stops_halfway() {
  mkdir -p "$BIN_DIR"
  cat > "$BIN_DIR/docker" <<'EOF'
#!/usr/bin/env sh
printf 'case started\n'
exit 0
EOF
  chmod +x "$BIN_DIR/docker"
  PATH="$BIN_DIR:$PATH"
}

test_run_system_test_fails_when_the_run_never_reported_a_result() {
  _given_a_fake_docker_that_stops_halfway

  output=$("$RUNNER" ubuntu "$FIXTURE_A" 2>&1)
  status=$?

  assertFalse "A clean exit with no summary is not a pass" $status
  assertContains "The message must say no result was reported" \
    "$output" "stopped before shunit2 reported a result"
}

test_run_system_test_keeps_the_shunit2_summary_out_of_the_output() {
  _given_a_fake_docker

  output=$("$RUNNER" ubuntu "$FIXTURE_A" 2>&1)

  assertNotContains "The summary is a signal, not something to print" \
    "$output" "Ran 1 test."
  assertContains "The case's own output must survive" "$output" "case it_alpha ran"
}

test_run_system_test_refuses_a_test_file_without_its_executable_bit() {
  _given_a_fake_docker
  chmod -x "$FIXTURE_A"

  output=$("$RUNNER" ubuntu "$FIXTURE_A" 2>&1)
  status=$?

  assertFalse "A file that cannot run must fail the run" $status
  assertContains "The message must name the missing bit, not docker" \
    "$output" "not executable"
  assertContains "The message must name the file" "$output" "$FIXTURE_A"
}

#
# A run that plans nothing is the same silent pass by another route.
#

test_run_system_test_fails_when_the_filter_matches_no_case() {
  _given_a_fake_docker

  output=$("$RUNNER" -t it_no_such_case ubuntu "$FIXTURE_A" 2>&1)
  status=$?

  assertFalse "A filter that matched nothing is not a pass" $status
  assertContains "The message must name the case that was asked for" \
    "$output" "it_no_such_case"
}

test_run_system_test_fails_when_a_file_defines_no_cases() {
  _given_a_fake_docker
  printf '# nothing here\n' > "$FIXTURE_A"
  chmod +x "$FIXTURE_A"

  output=$("$RUNNER" ubuntu "$FIXTURE_A" 2>&1)
  status=$?

  assertFalse "A file with no cases is not a pass" $status
  assertContains "The message must say why" "$output" "No test cases found"
}

#
# JOBS decides how many cases are in flight; a pool of nought hands out no
# tokens, so every worker would wait on one forever.
#

test_run_system_test_refuses_a_job_count_of_zero() {
  _given_a_fake_docker

  output=$(JOBS=0 "$RUNNER" ubuntu "$FIXTURE_A" 2>&1)
  status=$?

  assertFalse "JOBS=0 must be refused, not hang" $status
  assertContains "The message must name the offending value" "$output" "JOBS"
}

test_run_system_test_refuses_a_job_count_that_is_not_a_number() {
  _given_a_fake_docker

  output=$(JOBS=abc "$RUNNER" ubuntu "$FIXTURE_A" 2>&1)
  status=$?

  assertFalse "A non-numeric JOBS must be refused" $status
  assertContains "The message must name the offending value" "$output" "abc"
}

test_run_system_test_keeps_case_output_on_stderr() {
  _given_a_fake_docker

  # Only the runner's own file headings belong on stdout; a caller separating
  # the streams to surface failures needs the cases themselves on stderr.
  output=$("$RUNNER" ubuntu "$FIXTURE_A" 2>&1 1>/dev/null)

  assertContains "Case output belongs on stderr" "$output" "case it_alpha ran"
}

test_run_system_test_refuses_a_test_file_that_does_not_exist() {
  _given_a_fake_docker

  output=$("$RUNNER" ubuntu "$SHUNIT_TMPDIR/test_absent.system.sh" 2>&1)
  status=$?

  assertFalse "A missing file must fail the run" $status
  assertContains "The message must say the file is missing" \
    "$output" "No such test file"
}

# Run tests
SHPY_PATH="$THISDIR/shpy"
export SHPY_PATH
. "$THISDIR/shpy"
. "$THISDIR/shpy-shunit2"
. "$THISDIR/shunit2"
