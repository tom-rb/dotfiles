#!/usr/bin/env sh

# Read one char from terminal input (or piped stdin)
# If $1 is not empty, echoing the char is turned off
# https://stackoverflow.com/a/30022297/4783169
# shellcheck disable=SC2120
read_char() {
  # TODO: block -isig chars too; restore only what was enabled before
  # Only apply stty changes if FD 0 is open (stdin is from tty)
  [ -t 0 ] && stty -icanon -echo
  if [ -z "$1" ]; then
    dd bs=1 count=1 2>/dev/null
  else
    # Only read a char (for a "waiting for input" effect)
    dd bs=1 count=1 1>/dev/null 2>&1
  fi
  [ -t 0 ] && stty icanon echo
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
    then message="$message (Y/n) "
    else message="$message (y/N) "
  fi
  printf "%s" "$message"
  while : ; do
    c=$(read_char)
    case "$c" in
      [nN]) echo "$c"; return 1;;
      [yY]) echo "$c"; return 0;;
      "")   [ $out_code -eq 0 ] && echo 'y' || echo 'n'
            return $out_code;;
      *)    echo ' Choose y or n.';;
    esac
  done
}

# Show options to the user and return a choice
# -d N: return choice N when the user just presses enter
# $1-9: messages to choose from
# Returns 0 on cancel or >=1 for the choice
choose() {
  local opt_i c default=
  if [ "$1" = -d ]; then
    default=$2
    shift 2
  fi
  # While a valid option isn't chosen
  while : ; do
    opt_i=0
    # Print options
    for opt in "$@"; do
      opt_i=$((opt_i + 1))
      printf '%d) %s\n' $opt_i "$opt"
    done
    echo "q) Quit"
    # Get answer TODO: ctrl+c should cancel, not return 2
    while : ; do
      c=$(read_char)
      case "$c" in
        [1-$opt_i]) echo "$c"; return "$c" ;;
        q)   echo 'Cancelled'; return 0 ;;
        "")  [ -n "$default" ] && { echo "$default"; return "$default"; } ;;
      esac
    done
  done
}

# Prompt the user for a single line of input.
# Leading and trailing whitespace are stripped (default IFS read behavior).
# $1: prompt message
# $2: name of variable to set with the response
prompt_line() {
  printf "%s" "${1:?}"
  read -r "${2:?}"
  # Defensive trailing newline. Under pipes the terminal driver isn't echoing
  # the user's Enter, so without this the next caller's prompt collides on the
  # same line. In TTY mode it costs us one extra blank line — acceptable trade.
  echo
}

#
# Status reporting helpers
#
# Single glyph + short message replaces the previous asterisk-wall pattern.
# The visual vocabulary is intentionally tiny so users can scan by symbol:
#   section header    "name"          ↵ top-level module banner (blank line above)
#   say_ok            "✓ message"     ↵ a step completed
#   say_step          "→ message"     ↵ a step is starting / a download
#   say_warn          "! message"     ↵ non-fatal warning the user should notice
#   say_info          "  message"     ↵ extra, lower-noise context (indented two)
#

# Print a top-level section banner with a preceding blank line.
# $1: section name (e.g. "zsh", "tmux")
say_section() {
  printf '\n== %s ==\n' "${1:?}"
}

# Print a success line: "  ✓ <msg>"
say_ok() {
  printf '  ✓ %s\n' "${1:?}"
}

# Print an in-progress step: "  → <msg>"
say_step() {
  printf '  → %s\n' "${1:?}"
}

# Print a warning line to stderr: "  ! <msg>"
# Stderr so it stands out in piped logs and survives stdout muting.
say_warn() {
  printf '  ! %s\n' "${1:?}" >&2
}

# Print an indented context line: "    <msg>" (4-space indent so it nests under say_*)
say_info() {
  printf '    %s\n' "${1:?}"
}

# Echo singular form when count is 1, plural form otherwise.
# $1: count, $2: singular form, $3: plural form
pluralize() {
  if [ "${1:?}" = "1" ]; then echo "${2:?}"; else echo "${3:?}"; fi
}

# Run a command, suppressing stdout/stderr by default.
# On non-zero exit OR when DEBUG=1, the captured output is replayed to stderr
# so the user can diagnose. Idea: keep the happy path quiet, keep failures loud.
# $@: the command + args to run
run_quiet() {
  local _rq_log _rq_rc
  if [ "${DEBUG:-}" = "1" ]; then
    "$@"
    return $?
  fi
  _rq_log=$(mktemp 2>/dev/null || printf '/tmp/run_quiet.%d' $$)
  "$@" >"$_rq_log" 2>&1
  _rq_rc=$?
  if [ "$_rq_rc" -ne 0 ]; then
    # Replay everything we swallowed so the failure isn't a mystery
    cat "$_rq_log" >&2
  fi
  rm -f "$_rq_log"
  return $_rq_rc
}
