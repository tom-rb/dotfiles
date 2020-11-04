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
# CLI utils
#

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
# $1-9: messages to choose from
# Returns 0 on cancel or >=1 for the choice
choose() {
  local opt_i c
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
      esac
    done
  done
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
# Package Manager utilities
#

# Returns supported package manager name, or nothing
get_supported_pm() {
  # Only supporting apt and yum for now
  if command_exists apt-get; then
    echo 'apt-get'
  elif command_exists yum; then
    echo 'yum'
  fi
}

# Check if system package manager is supported
check_supported_pm() {
  test -n "$(get_supported_pm)"
}

# Return version of package $1 available in package manager
get_version_in_pm() {
  case $(get_supported_pm) in
    apt-get)
      apt-cache policy "$1" \
      | sed -nE '/.*Candidate: (.*)/ { s//\1/p; q }';;
    yum)
      yum info "$1" \
      | sed -nE '/^Version\s*: (.*)/ { s//\1/p; q }';;
    *)
      >&2 echo "Couldn't find package manager";;
  esac
}

# Installs given packages from available package manager
install_from_pm() {
  case $(get_supported_pm) in
    apt-get)
      sudo apt-get update &&
      sudo apt-get install -y "$@";;
    yum)
      sudo yum -y install "$@";;
    *)
      >&2 echo "Couldn't find package manager";;
  esac
}