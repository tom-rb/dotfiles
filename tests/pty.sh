#!/usr/bin/env sh

#
# Pseudo-terminal test driver
#
# Piping stdin into a prompt only exercises control flow: read_char's
# `stty -icanon -echo` is guarded by `[ -t 0 ]`, so a pipe skips raw mode
# entirely. These helpers run a command against a real pty instead, which is
# the only way to assert on keystroke handling, echo suppression, or Ctrl-D.
#

# Seconds to wait before sending each keystroke. A byte written before the
# command reaches its `stty -echo` sits in the input queue and gets echoed by
# the terminal, which is precisely what echo-suppression tests must not see.
# Raise it if a slow machine makes those tests flaky.
PTY_SETTLE_SECONDS="${PTY_SETTLE_SECONDS:-0.3}"

# Strip what the terminal adds but assertions should not have to know about:
# the CR half of the pty's \r\n, and any escape sequences.
_pty_normalize() {
  tr -d '\r' | sed 's/\x1b\[[0-9;]*[A-Za-z]//g'
}

# Run a command under a pseudo-terminal, feeding it keystrokes one at a time.
# $1: keystrokes as printf %b escapes, one char per prompt ('' to send none,
#     which leaves the command facing exhausted input)
# $2+: the command, re-parsed by sh, so quote it as you would for sh -c
# Echoes the normalized session output; returns the command's own exit code.
pty_run() {
  local keys cap fifo pid status
  # The X sentinel survives the trailing-newline stripping of $(...), so a
  # newline keystroke ("take the default") can be sent like any other.
  keys=$(printf '%b' "${1?}"; printf X)
  keys=${keys%X}
  shift

  cap=$(mktemp) || return 1
  fifo=$(mktemp -u) || return 1
  mkfifo "$fifo" || return 1

  # The session is captured from script's stdout rather than a typescript file:
  # -q keeps the "Script started/done" banner off stdout, but always writes it
  # to the file, where it would also glue itself onto output lacking a trailing
  # newline. /dev/null is the typescript for that reason.
  # script dispatches through $SHELL, so pin it: these scripts are sh-only but
  # a developer's login shell is often not.
  # The reader has to start first: opening a fifo for writing blocks until a
  # reader is present, so a writer-first order deadlocks.
  SHELL=/bin/sh script -qec "$*" /dev/null <"$fifo" >"$cap" 2>&1 &
  pid=$!

  # PIPE is ignored while feeding so a command that exits early fails the write
  # instead of killing the test run.
  (
    trap '' PIPE
    exec 3>"$fifo"
    while : ; do
      sleep "$PTY_SETTLE_SECONDS"
      [ -z "$keys" ] && break
      printf '%s' "${keys%"${keys#?}"}" >&3 2>/dev/null || break
      keys=${keys#?}
    done
    exec 3>&-
  )

  wait "$pid"
  status=$?
  _pty_normalize <"$cap"
  rm -f "$cap" "$fifo"
  return $status
}
