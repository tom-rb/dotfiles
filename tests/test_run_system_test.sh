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
}

tearDown() {
  PATH="$ORIGINAL_PATH"
  cleanupTestDir
}

# Put a stub `docker` on PATH so the runner's pipeline can be exercised without
# starting a container.
# $1: (optional) extra line to print, e.g. FAILED
_given_a_fake_docker() {
  mkdir -p "$BIN_DIR"
  cat > "$BIN_DIR/docker" <<EOF
#!/usr/bin/env sh
# The runner hands the case name to the container as \`<file> -- <case>\`.
printf 'case %s ran\n' "\$(printf '%s\n' "\$*" | sed -nE 's/.*-- ([A-Za-z0-9_]+).*/\1/p')"
printf '%s\n' '${1-}'
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

# Run tests
SHPY_PATH="$THISDIR/shpy"
export SHPY_PATH
. "$THISDIR/shpy"
. "$THISDIR/shpy-shunit2"
. "$THISDIR/shunit2"
