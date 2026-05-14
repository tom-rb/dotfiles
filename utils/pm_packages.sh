#!/usr/bin/env sh

# Translate canonical package names into the names used by the active PM.
# Unknown names pass through unchanged (a typo surfaces as a PM install
# failure rather than here). Echoes space-separated, trailing newline.
pm_packages_for() {
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
