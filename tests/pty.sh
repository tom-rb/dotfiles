#!/usr/bin/env sh

#
# Pseudo-terminal test driver
#
# Piping stdin into a prompt only exercises control flow: read_char's
# `stty -icanon -echo` is guarded by `[ -t 0 ]`, so a pipe skips raw mode
# entirely. These helpers run a command against a real pty instead, which is
# the only way to assert on keystroke handling, echo suppression, or Ctrl-D.
#

# Whole seconds to wait before sending each keystroke. A byte written before
# the command reaches its `stty -echo` sits in the input queue and gets echoed
# by the terminal, which is precisely what echo-suppression tests must not see.
# POSIX sleep takes an integer, so sub-second values are not portable here.
PTY_SETTLE_SECONDS="${PTY_SETTLE_SECONDS:-1}"

# Whole seconds a command may run before it is killed. Without this a subject
# that never returns blocks the entire suite.
PTY_TIMEOUT_SECONDS="${PTY_TIMEOUT_SECONDS:-30}"

# Strip what the terminal adds but assertions should not have to know about:
# the CR half of the pty's \r\n, and any escape sequences — unless
# PTY_KEEP_ESCAPES=1, which hands back the session untouched (SGR codes and
# every \r, including the mid-line ones a program writes on purpose) for
# tests asserting on color codes or in-place line rewrites.
_pty_normalize() {
  local esc
  esc=$(printf '\033')
  if [ "${PTY_KEEP_ESCAPES:-}" = 1 ]; then
    cat
  else
    tr -d '\r' | sed "s/$esc\[[0-9;]*[a-zA-Z]//g"
  fi
}

# Run a command under a pseudo-terminal, feeding it keystrokes one at a time.
# $1: keystrokes as printf %b escapes, one char per prompt ('' to send none,
#     which leaves the command facing exhausted input)
# $2+: the command, joined and re-parsed by sh, so quote it as one sh -c word
# Echoes the normalized session output; returns the command's own exit code.
pty_run() {
  local keys
  # The X sentinel survives the trailing-newline stripping of $(...), so a
  # newline keystroke ("take the default") can be sent like any other.
  keys=$(printf '%b' "${1?}"; printf X)
  keys=${keys%X}
  shift

  # The body runs in a subshell so its cleanup trap stays scoped to this call
  # and cannot displace shunit2's own traps.
  (
    dir=$(mktemp -d) || exit 1
    pid='' watchdog=''
    # shellcheck disable=SC2086 # both may be empty, and kill's moan is muted
    trap 'kill $pid $watchdog 2>/dev/null; rm -rf "$dir"' EXIT INT TERM
    mkfifo "$dir/fifo" || exit 1

    # The session is captured from script's stdout. `script` dispatches through
    # $SHELL, so pin it: these scripts are sh-only but a developer's login shell
    # is often not. -q keeps the "Script started/done" banner off stdout.
    # The reader has to start first: opening a fifo for writing blocks until a
    # reader is present, so a writer-first order deadlocks.
    SHELL=/bin/sh script -qec "$*" /dev/null <"$dir/fifo" >"$dir/capture" 2>&1 &
    pid=$!
    # The marker matters: script exits 0 when it is killed, so without it a
    # timed-out run is indistinguishable from a passing one.
    # Two details keep the watchdog from costing a full timeout on every call.
    # Its stdout must not be this function's: callers read pty_run through a
    # command substitution, which waits for every writer to close the pipe, so
    # a watchdog holding it open stalls the caller long after the command left.
    # And it polls for the command instead of sleeping through the timeout in
    # one go, so it retires with the run rather than outliving it and firing
    # `kill` at whatever inherited the pid by then.
    (
      waited=0
      while [ "$waited" -lt "$PTY_TIMEOUT_SECONDS" ] && kill -0 "$pid" 2>/dev/null; do
        sleep 1
        waited=$((waited + 1))
      done
      [ "$waited" -lt "$PTY_TIMEOUT_SECONDS" ] ||
        { kill "$pid" 2>/dev/null && : >"$dir/timeout"; }
    ) >/dev/null 2>&1 &
    watchdog=$!

    # PIPE is ignored while feeding so a command that exits early fails the
    # write instead of killing the test run.
    (
      trap '' PIPE
      exec 3>"$dir/fifo"
      while [ -n "$keys" ]; do
        sleep "$PTY_SETTLE_SECONDS"
        printf '%s' "${keys%"${keys#?}"}" >&3 2>/dev/null || break
        keys=${keys#?}
      done
      exec 3>&-
    )

    wait "$pid"
    status=$?
    if [ -e "$dir/timeout" ]; then
      echo "pty_run: killed after ${PTY_TIMEOUT_SECONDS}s: $*" >&2
      status=124
    fi
    _pty_normalize <"$dir/capture"
    exit $status
  )
}
