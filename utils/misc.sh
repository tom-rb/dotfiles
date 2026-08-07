#!/usr/bin/env sh

# Check if command $1 exists
command_exists() {
  command -v "${1:?}" >/dev/null
}

# Run $@ suppressing all output, unless DEBUG=1
quietly() {
  if [ "${DEBUG:-}" = "1" ]; then
    "$@"
  else
    "$@" >/dev/null 2>&1
  fi
}

# Run $@ suppressing only its stdout, unless DEBUG=1.
quietly_stdout() {
  if [ "${DEBUG:-}" = "1" ]; then
    "$@"
  else
    "$@" >/dev/null
  fi
}

#
# File utils
#

# Copy $1 file in the same location adding .bkp
# Use bkp1, bkp2, etc if backup exists.
# Echoes the path of the copy it made.
backup_file() {
  local file n
  file=${1:?} n=
  while [ -e "$file.bkp$n" ]; do
    n=$((n + 1))
  done
  cp "$file" "${file}.bkp$n" && printf '%s\n' "${file}.bkp$n"
}

# True if file $1 hashes to the expected SHA-256 $2.
# Fails on a missing argument rather than exiting, so a caller checking the
# result still gets to run its own cleanup. A host with no SHA-256 tool dies
# instead: it can't verify anything, and reporting that as a mismatch would
# blame the download for a missing coreutils.
verify_sha256() {
  local actual
  [ -n "${1:-}" ] && [ -n "${2:-}" ] || return 1
  if command_exists sha256sum; then
    actual=$(sha256sum "$1") || return 1
  elif command_exists shasum; then
    actual=$(shasum -a 256 "$1") || return 1
  else
    die "No SHA-256 tool found, install coreutils (sha256sum) or shasum"
  fi
  [ "${actual%% *}" = "$2" ]
}

#
# Version utilities
#

# True if version $1 is >= version $2 (uses `sort -V` for natural ordering).
# Handles dotted versions with optional suffix letters (e.g. 3.1 < 3.1a < 3.1b < 3.2).
version_ge() {
  [ "$(printf '%s\n%s\n' "${1:?}" "${2:?}" | sort -V | head -n1)" = "$2" ]
}

#
# Prose utilities
#

# Render a space-separated list as an English enumeration:
# "zsh", "zsh and tmux", "zsh, tmux and git".
# $1: space-separated words
english_list() {
  local out word count i
  out='' count=0 i=0
  for word in $1; do count=$((count + 1)); done
  for word in $1; do
    i=$((i + 1))
    if [ "$i" -eq 1 ]
      then out=$word
    elif [ "$i" -eq "$count" ]
      then out="$out and $word"
      else out="$out, $word"
    fi
  done
  printf '%s\n' "$out"
}
