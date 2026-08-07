#!/usr/bin/env sh

#
# Output
#

# Resolve the palette once. Colors and cursor control collapse to empty strings
# when stdout is not a terminal or NO_COLOR is set.
tui_init() {
  local esc
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    esc=$(printf '\033')
    _TUI_BOLD="${esc}[1m" _TUI_DIM="${esc}[2m" _TUI_GREEN="${esc}[32m"
    _TUI_YELLOW="${esc}[33m" _TUI_RED="${esc}[31m" _TUI_RESET="${esc}[0m"
    _TUI_CURSOR_HIDE="${esc}[?25l" _TUI_CURSOR_SHOW="${esc}[?25h"
  else
    _TUI_BOLD='' _TUI_DIM='' _TUI_GREEN='' _TUI_YELLOW='' _TUI_RED='' _TUI_RESET=''
    _TUI_CURSOR_HIDE='' _TUI_CURSOR_SHOW=''
  fi
}
tui_init

#
# Cursor
#

# Whether the cursor is currently hidden.
_TUI_CURSOR_HIDDEN=''

# Whether the restore trap is installed.
_TUI_CURSOR_TRAP=''

# Park the cursor out of sight for the length of a step.
_tui_hide_cursor() {
  [ -n "$_TUI_CURSOR_HIDE" ] || return 0
  if [ -z "$_TUI_CURSOR_TRAP" ]; then
    # The hide sequence outlives the process that wrote it, so a Ctrl-C
    # mid-step would hand the terminal back without a cursor. The signals are
    # re-raised with the default handler, so the caller still reads the exit
    # status as a signal rather than a clean stop.
    trap '_tui_cursor_restore' EXIT
    trap '_tui_cursor_restore; trap - INT; kill -INT $$' INT
    trap '_tui_cursor_restore; trap - TERM; kill -TERM $$' TERM
    _TUI_CURSOR_TRAP=1
  fi
  printf '%s' "$_TUI_CURSOR_HIDE"
  _TUI_CURSOR_HIDDEN=1
}

# Give the cursor back. A no-op unless _tui_hide_cursor took it away.
_tui_show_cursor() {
  [ -n "$_TUI_CURSOR_HIDDEN" ] || return 0
  printf '%s' "$_TUI_CURSOR_SHOW"
  _TUI_CURSOR_HIDDEN=''
}

# Leave the terminal usable when the script ends mid-step: close the open line
# and give the cursor back.
_tui_cursor_restore() {
  _tui_close_step
  _tui_show_cursor
}

#
# Steps
#

# The in-flight task's message, rewritten in place by the next Outcome.
_TUI_TASK_MSG=''

# The tail of the running tui_task command's stderr, and whether that command
# exited non-zero; the Outcome replays and clears both.
_TUI_TASK_STDERR=''
_TUI_TASK_FAILED=''

# End an open task line with a newline. A no-op when no task is open.
_tui_close_step() {
  [ -z "$_TUI_TASK_MSG" ] && return 0
  _tui_show_cursor
  printf '\n'
  _TUI_TASK_MSG=''
}

# Blank line, then a bold section header with an optional progress counter.
# $1: title  $2: (optional) index  $3: (optional) total
tui_section() {
  local title index total
  title=${1:?} index=$2 total=$3
  # A header landing mid-step would otherwise glue onto the open line.
  _tui_close_step
  echo
  if [ -n "$index" ] && [ -n "$total" ]; then
    printf '%s▸ %s  (%s/%s)%s\n' "$_TUI_BOLD" "$title" "$index" "$total" "$_TUI_RESET"
  else
    printf '%s▸ %s%s\n' "$_TUI_BOLD" "$title" "$_TUI_RESET"
  fi
}

# Announce work about to start. On a terminal the line is left open (no
# trailing newline) so the next tui_ok/tui_skip/tui_warn/tui_fail rewrites it
# via \r, with the cursor hidden until then; off a terminal it is printed as a
# complete line, like the terminators below.
# $1: message
tui_step() {
  local message
  message=${1:?}
  if [ -t 1 ]; then
    _TUI_TASK_MSG=$message
    _tui_hide_cursor
    printf '  → %s' "$message"
  else
    printf '  → %s\n' "$message"
  fi
}

# Replay the stderr that tui_task stashed away under the Outcome line just
# printed, then empty the stash.
# $1: 'fail' to replay plainly on stderr and add the DEBUG hint; anything else
#     replays dimmed on stdout
_tui_flush_run_output() {
  if [ "${1:-}" = 'fail' ]; then
    [ -n "$_TUI_TASK_STDERR" ] && printf '%s\n' "$_TUI_TASK_STDERR" | tui_indent >&2
    [ -n "$_TUI_TASK_FAILED" ] && tui_detail 'Re-run with DEBUG=1 for full output.' >&2
  elif [ -n "$_TUI_TASK_STDERR" ]; then
    printf '%s\n' "$_TUI_TASK_STDERR" | tui_indent -d
  fi
  _TUI_TASK_STDERR='' _TUI_TASK_FAILED=''
  return 0
}

# Shared by tui_ok/tui_skip/tui_warn: rewrite an open task line in place via
# \r, padded with spaces to clear whichever of the two messages is longer;
# print a standalone line when no task is open. tui_fail cannot reuse this —
# see its own comment.
# $1: glyph  $2: color  $3: message
_tui_terminate() {
  local glyph color message pad
  glyph=$1 color=$2 message=$3
  if [ -n "$_TUI_TASK_MSG" ]; then
    pad=$(( ${#_TUI_TASK_MSG} - ${#message} ))
    printf '\r  %s%s%s %s' "$color" "$glyph" "$_TUI_RESET" "$message"
    [ "$pad" -gt 0 ] && printf "%${pad}s" ''
    _tui_show_cursor
    printf '\n'
    _TUI_TASK_MSG=''
  else
    printf '  %s%s%s %s\n' "$color" "$glyph" "$_TUI_RESET" "$message"
  fi
  _tui_flush_run_output
}

# Step succeeded.
# $1: message
tui_ok() {
  _tui_terminate '✓' "$_TUI_GREEN" "${1:?}"
}

# Already done, or declined.
# $1: message
tui_skip() {
  _tui_terminate '•' "$_TUI_DIM" "${1:?}"
}

# Needs attention, but not fatal.
# $1: message
tui_warn() {
  _tui_terminate '!' "$_TUI_YELLOW" "${1:?}"
}

# Failed. Written to stderr so it survives a stdout pipe. Cannot use
# _tui_terminate's \r rewrite: that trick relies on both halves landing on the
# same fd in program order, which stdout and stderr do not guarantee, so an
# open task is instead closed with a plain newline on stdout before anything
# reaches stderr — the arrow line stays as history and the ✗ lands below it.
# $1: message
tui_fail() {
  _tui_close_step
  printf '  %s✗%s %s\n' "$_TUI_RED" "$_TUI_RESET" "${1:?}" >&2
  _tui_flush_run_output fail
}

# Print $1 via tui_fail (stderr) and exit 1, or optionally with specified $2
# code.
die() {
  tui_fail "${1:-Aborted.}"
  exit "${2:-1}"
}

# Indent every line of stdin 4 spaces.
# -d: dim each line, so a replayed tail reads like the tui_detail lines
tui_indent() {
  local line dim='' reset=''
  [ "${1:-}" = '-d' ] && dim=$_TUI_DIM reset=$_TUI_RESET
  # A read loop rather than sed: sed block-buffers when its stdout is a pipe, so
  # a long DEBUG=1 build would dump its whole log at the end, after the stderr
  # lines it is meant to explain.
  while IFS= read -r line; do
    printf '    %s%s%s\n' "$dim" "$line" "$reset"
  done
  # A last line with no trailing newline leaves read failing but $line set.
  [ -n "$line" ] && printf '    %s%s%s\n' "$dim" "$line" "$reset"
  return 0
}

# Run a command as one Task: open the line, run it, and close it with an
# Outcome. Its stdout is discarded and the tail of its stderr stashed for the
# Outcome to replay indented. Under DEBUG=1 both streams go through tui_indent
# instead.
# The command reports nothing and exits nothing: it returns a status, and this
# function decides what that status means on screen.
# $1: task message
# --ok MSG: wording of the ✓
# --ok-cmd FUNC: wording of the ✓, taken from FUNC's stdout — for a value only
#     knowable once the command has succeeded, like a version read back off disk
# --die REASON: close with ✗ and exit
# --fail REASON: close with ✗ and return the command's status
# --warn MSG: close with ! and return the command's status
# Exactly one success flag and exactly one failure flag are required.
# $@ after --: the command and its arguments
# Returns 0, or the command's exit status.
tui_task() {
  local message ok_msg ok_cmd outcome reason
  local status_file err_file status errexit
  # Locals, so the stash lives and dies with the task that made it.
  local _TUI_TASK_STDERR='' _TUI_TASK_FAILED=''
  message=${1:?}
  shift
  ok_msg='' ok_cmd='' outcome='' reason=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --ok)
        [ -n "$ok_msg$ok_cmd" ] && die 'tui_task: --ok and --ok-cmd are exclusive'
        ok_msg=${2:?}; shift 2 ;;
      --ok-cmd)
        [ -n "$ok_msg$ok_cmd" ] && die 'tui_task: --ok and --ok-cmd are exclusive'
        ok_cmd=${2:?}; shift 2 ;;
      --die|--fail|--warn)
        [ -n "$outcome" ] && die 'tui_task: --die, --fail and --warn are exclusive'
        outcome=${1#--} reason=${2:?}; shift 2 ;;
      --) shift; break ;;
      *)  die "tui_task: unexpected argument \"$1\"" ;;
    esac
  done
  [ -n "$ok_msg$ok_cmd" ] || die 'tui_task: --ok or --ok-cmd is required'
  [ -n "$outcome" ]       || die 'tui_task: --die, --fail or --warn is required'
  [ $# -gt 0 ]            || die 'tui_task: no command to run'

  tui_step "$message"
  # Both branches run the command inside a subshell that restores the caller's
  # errexit, so a multi-statement function still stops at its first failing
  # line, while the bookkeeping around it runs with errexit off.
  case "$-" in
    *e*) errexit=1;;
    *)   errexit='';;
  esac
  if [ "${DEBUG:-}" = "1" ]; then
    # Make sure the command's own output won't glue with an opened task.
    _tui_close_step
    status_file=$(mktemp) || die "Could not create temporary file"
    # The command sits on the left of a pipe, so $? after the pipe would be
    # tui_indent's status, not its own; stash it in a file instead. The brace
    # group is a pipeline stage, so its `set +e` is confined to that subshell.
    { set +e; ( [ -n "$errexit" ] && set -e; "$@" ) 2>&1; echo "$?" >"$status_file"; } | tui_indent
    read -r status <"$status_file"
    rm -f "$status_file"
  else
    # A file rather than a pipe into tui_indent: nothing may be printed until
    # the task line is closed, and a pipe would also cost the command's own $?.
    err_file=$(mktemp) || die "Could not create temporary file"
    # No pipeline here to contain it, so errexit is turned off and put back by
    # hand around the bookkeeping.
    set +e
    ( [ -n "$errexit" ] && set -e; quietly_stdout "$@" ) 2>"$err_file"
    status=$?
    # tail before tr, so only the five lines that survive are scanned for the
    # NUL bytes that make some shells warn at column 0.
    [ -s "$err_file" ] && _TUI_TASK_STDERR=$(tail -n 5 "$err_file" | tr -d '\000')
    rm -f "$err_file"
    [ "$status" -ne 0 ] && _TUI_TASK_FAILED=1
    [ -n "$errexit" ] && set -e
  fi

  if [ "$status" -eq 0 ]; then
    if [ -n "$ok_cmd" ]; then
      # A wording helper that stumbles does not un-succeed the task.
      ok_msg=$("$ok_cmd") || :
    fi
    tui_ok "$ok_msg"
    return 0
  fi

  case "$outcome" in
    die)  die "$reason" ;;
    fail) tui_fail "$reason" ;;
    warn) tui_warn "$reason" ;;
  esac
  return "$status"
}

# Indented, dimmed continuation line under the step above (paths, versions, reasons).
# $1: message
tui_detail() {
  printf '    %s%s%s\n' "$_TUI_DIM" "${1:?}" "$_TUI_RESET"
}

# $HOME → ~, for display only — never for paths that get written to a file.
# $1: path
tui_path() {
  local path
  path=${1:?}
  case "$path" in
    "$HOME") printf '%s\n' '~';;
    "$HOME"/*) printf '~%s\n' "${path#"$HOME"}";;
    *) printf '%s\n' "$path";;
  esac
}

#
# Input
#

# Ctrl-D as a literal byte. A terminal in raw mode (-icanon) hands it over as
# ordinary input instead of closing the stream, so read_char has to recognise
# it to spot exhausted input the way a pipe's EOF does.
EOT_CHAR=$(printf '\004')

# Read one char from terminal input (or piped stdin)
# If $1 is not empty, echoing the char is turned off
# Returns 1 and echoes nothing when input is exhausted (EOF)
# https://stackoverflow.com/a/30022297/4783169
# shellcheck disable=SC2120
read_char() {
  local c
  # TODO: block -isig chars too; restore only what was enabled before
  # Only apply stty changes if FD 0 is open (stdin is from tty)
  [ -t 0 ] && stty -icanon -echo
  # The X sentinel outlives the trailing-newline stripping of $(...), which is
  # what makes a newline keypress distinguishable from a dried-up stdin.
  c=$(dd bs=1 count=1 2>/dev/null; printf X)
  [ -t 0 ] && stty icanon echo
  c=${c%X}
  # Empty means a closed pipe, EOT means a raw-mode terminal: both are the end
  # of the input, as opposed to a newline, which is a keypress meaning "default"
  if [ -z "$c" ] || [ "$c" = "$EOT_CHAR" ]; then
    return 1
  fi
  # With $1 set, only wait for the keypress (for a "waiting for input" effect)
  [ -z "$1" ] && printf '%s' "$c"
  return 0
}

# Print $1 as a warning, wait for any keypress, then close the line.
# Dies when input is exhausted.
# $1: message
press_any_key() {
  printf '  %s!%s %s (press any key)' "$_TUI_YELLOW" "$_TUI_RESET" "${1:?}"
  read_char silent || die "Aborted: input ended while asking \"$1\""
  echo
}

# Ask for user confirmation with a keystroke
# -n: Make default answer be NO
# $1: (optional) Confirmation message
confirm() {
  local c message out_code
  if [ "$1" != '-n' ]
    then message=$1 out_code=0
    else message=$2 out_code=1
  fi
  # Remove trailing whitespace characters
  message="${message%"${message##*[![:space:]]}"}"
  message="${message:-Continue?}"
  if [ $out_code -eq 0 ]
    then message="$message  [Y/n] "
    else message="$message  [y/N] "
  fi
  printf '  %s?%s %s' "$_TUI_BOLD" "$_TUI_RESET" "$message"
  while : ; do
    if ! c=$(read_char); then
      echo
      die "Aborted: input ended while asking \"$message\""
    fi
    case "$c" in
      [nN]) echo "$c"; return 1;;
      [yY]) echo "$c"; return 0;;
      "")   [ $out_code -eq 0 ] && echo 'y' || echo 'n'
            return $out_code;;
      *)    echo ' Choose y or n.';;
    esac
  done
}

# Ask a question and show a numbered list of options, then return the choice.
# -d N: return choice N when the user just presses enter, and mark it "(default)"
# -q LABEL: wording of the quit option, so it can speak the caller's voice
# $1: the question
# $2-9: messages to choose from
# Returns 0 on cancel or >=1 for the choice
choose() {
  local opt_i c question quit_label default=
  quit_label='quit'
  while : ; do
    case "$1" in
      -d) default=${2:?}; shift 2 ;;
      -q) quit_label=${2:?}; shift 2 ;;
      *)  break ;;
    esac
  done
  question=${1:?}
  shift
  # While a valid option isn't chosen
  while : ; do
    printf '  %s?%s %s\n' "$_TUI_BOLD" "$_TUI_RESET" "$question"
    opt_i=0
    # Print options
    for opt in "$@"; do
      opt_i=$((opt_i + 1))
      if [ "$opt_i" = "$default" ]
        then printf '      %d) %s  %s(default)%s\n' "$opt_i" "$opt" "$_TUI_DIM" "$_TUI_RESET"
        else printf '      %d) %s\n' "$opt_i" "$opt"
      fi
    done
    printf '      q) %s\n' "$quit_label"
    printf '    › '
    # Get answer TODO: ctrl+c should cancel, not return 2
    while : ; do
      if ! c=$(read_char); then
        echo
        die "Aborted: input ended while choosing an option"
      fi
      case "$c" in
        [1-$opt_i]) echo "$c"; return "$c" ;;
        q)   echo "$c"; return 0 ;;
        "")  [ -n "$default" ] && { echo "$default"; return "$default"; } ;;
      esac
    done
  done
}

# Prompt the user for a single line of input, behind a `›` input cursor.
# Leading and trailing whitespace are stripped.
# $1: prompt message; usually empty, since the question above already named
#     what is being asked for
# $2: name of variable to set with the response
prompt_line() {
  printf '    › %s' "${1-}"
  # A failed read means the input dried up, which is not the same as someone
  # entering nothing.
  read -r "${2:?}" || die "Aborted: input ended while asking \"${1:-for input}\""
}

# Prompt repeatedly for an absolute path that does not yet exist, then create it.
# Shell variables and ~ in the input are expanded (eval) and a trailing slash is
# stripped. Re-prompts on empty input, an already-existing path, a declined
# confirmation, or a failed mkdir; returns only once the directory exists.
# Dies when input is exhausted.
# $1: confirm message; a single %s is replaced with the entered path (printf)
# $2: name of variable to set with the created path
prompt_new_path() {
  local _msg _var _path
  _msg=${1:?} _var=${2:?}
  while : ; do
    printf '    › absolute path: '
    # At EOF read leaves _path empty, otherwise the loop spins on the CPU forever.
    read -r _path || die "Aborted: input ended while asking for a path"
    # Expand $HOME, ~, etc. and drop any trailing slash.
    eval _path="${_path%/}"
    [ -z "$_path" ] && continue
    if [ -e "$_path" ]; then
      echo "The $_path already exists"
      continue
    fi
    # shellcheck disable=SC2059 # $_msg is a caller-supplied printf template
    if ! confirm "$(printf "$_msg" "$_path")"; then
      continue
    fi
    if ! mkdir -p "$_path"; then
      echo "Cannot create $_path folder"
      continue
    fi
    break
  done
  eval "$_var=\$_path"
}
