#!/usr/bin/env sh

# Echo $1 and exit 1, or optionally with specified $2 code
die() {
  echo "${1:-Aborted.}"
  exit "${2:-1}"
}

# Check if command $1 exists
command_exists() {
  command -v "${1:?}" >/dev/null
}

#
# File utils
#

# Copy $1 file in the same location adding .bkp
# Use bkp1, bkp2, etc if backup exists.
backup_file() {
  local file n
  file=${1:?} n=
  while [ -e "$file.bkp$n" ]; do
    n=$((n + 1))
  done
  cp "$file" "${file}.bkp$n"
}

#
# Version utilities
#

# True if version $1 is >= version $2 (uses `sort -V` for natural ordering).
# Handles dotted versions with optional suffix letters (e.g. 3.1 < 3.1a < 3.1b < 3.2).
version_ge() {
  [ "$(printf '%s\n%s\n' "${1:?}" "${2:?}" | sort -V | head -n1)" = "$2" ]
}
