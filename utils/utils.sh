#!/usr/bin/env sh

# Echo $1 and exit 1, or optionally with specified $2 code
die() {
  echo "$1"
  exit ${2:+1}
}

# Check if command $1 exists
command_exists() {
  command -v "$1" >/dev/null
}