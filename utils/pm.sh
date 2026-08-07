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
      quietly_stdout sudo yum makecache fast && sudo yum info "$pkg" \
      | sed -nE '/^Version\s*: (.*)/ { s//\1/p; q }';;
    *)
      >&2 echo "Couldn't find package manager";;
  esac
}

# Install the given canonical packages via the active PM, using a TUI task
# to communicate progress. Installer chatter is hidden behind quietly_stdout,
# which leaves stderr to report failures; DEBUG=1 brings the rest back.
# --as <noun>: name the Task after <noun> instead of the canonical package name.
# --ok-cmd FUNC: override the ✓ wording with FUNC's stdout, e.g. for a version
#   only readable once the packages have landed.
# --die/--fail/--warn REASON: how the Task closes when the PM says no. One of
#   them is required.
# $1+ (after an optional --): canonical package names
# Returns the PM's exit status — whether that is fatal is the caller's call.
install_from_pm() {
  local noun='' ok_cmd='' outcome='' reason='' message
  while [ $# -gt 0 ]; do
    case "$1" in
      --as)     noun=${2:?}; shift 2 ;;
      --ok-cmd) ok_cmd=${2:?}; shift 2 ;;
      --die|--fail|--warn)
        [ -n "$outcome" ] && die 'install_from_pm: --die, --fail and --warn are exclusive'
        outcome=$1 reason=${2:?}; shift 2 ;;
      --) shift; break ;;
      *)  break ;;
    esac
  done
  [ -n "$outcome" ] || die 'install_from_pm: needs one of --die, --fail or --warn'

  # The canonical names as the caller wrote them, not _pm_packages_for's translation.
  [ -n "$noun" ] || noun="$*"

  message="installing $noun ($(get_supported_pm))…"
  if [ -n "$ok_cmd" ]; then
    tui_task "$message" --ok-cmd "$ok_cmd" "$outcome" "$reason" -- _install_from_pm "$@"
  else
    tui_task "$message" --ok "$noun installed" "$outcome" "$reason" -- _install_from_pm "$@"
  fi
}

# The install itself, with no reporting around it.
_install_from_pm() {
  # shellcheck disable=SC2046 # splitting on purpose
  set -- $(_pm_packages_for "$@")
  case $(get_supported_pm) in
    apt-get)
      quietly_stdout sudo apt-get update &&
      quietly_stdout sudo apt-get install -y "$@";;
    yum)
      quietly_stdout sudo yum -y install "$@";;
    *)
      >&2 echo "Couldn't find package manager"
      return 1;;
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
      apt-get:libatomic)        resolved=libatomic1 ;;
      *)                        resolved=$name ;;
    esac
    out=${out:+$out }$resolved
  done
  echo "$out"
}
