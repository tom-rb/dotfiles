#!/usr/bin/env sh

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

# Return version of canonical package $1 available in the active PM.
get_version_in_pm() {
  local pkg
  pkg=$(_pm_packages_for "$1")
  case $(get_supported_pm) in
    apt-get)
      apt-cache policy "$pkg" \
      | sed -nE '/.*Candidate: (.*)/ { s//\1/p; q }';;
    yum)
      sudo yum makecache fast && sudo yum info "$pkg" \
      | sed -nE '/^Version\s*: (.*)/ { s//\1/p; q }';;
    *)
      >&2 echo "Couldn't find package manager";;
  esac
}

# Install the given canonical packages via the active PM.
# Names are translated through _pm_packages_for; unknown names pass through
# (so callers can mix curated and plain names: install_from_pm chsh git wget).
install_from_pm() {
  # shellcheck disable=SC2046 # splitting on purpose
  set -- $(_pm_packages_for "$@")
  case $(get_supported_pm) in
    apt-get)
      run_quiet sudo apt-get update &&
      run_quiet sudo apt-get install -y "$@";;
    yum)
      run_quiet sudo yum -y install "$@";;
    *)
      >&2 echo "Couldn't find package manager";;
  esac
}

# Translate canonical package names into the names used by the active PM.
# Unknown names pass through unchanged (a typo surfaces as a PM install
# failure rather than here). Echoes space-separated, trailing newline.
_pm_packages_for() {
  local name pm resolved out=
  pm=$(get_supported_pm)
  for name in "$@"; do
    case "$pm:$name" in
      apt-get:libevent-headers) resolved=libevent-dev ;;
      yum:libevent-headers)     resolved=libevent-devel ;;
      apt-get:ncurses-headers)  resolved=libncurses-dev ;;
      yum:ncurses-headers)      resolved=ncurses-devel ;;
      apt-get:chsh)             resolved=passwd ;;
      yum:chsh)                 resolved=util-linux-user ;;
      *)                        resolved=$name ;;
    esac
    out=${out:+$out }$resolved
  done
  echo "$out"
}
