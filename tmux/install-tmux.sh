#!/usr/bin/env sh

is_tmux_installed() {
  command -v tmux >/dev/null
}

get_tmux_package_version() {
  if command -v apt-cache >/dev/null; then
    apt-cache policy tmux \
    | sed -nE 's/.*Candidate: ([0-9]\.[0-9][abc]?).*/\1/p'
  else
    >&2 echo "Couldn't find package manager"
  fi
}

install_tmux_from_pm() {
  if command -v apt-cache >/dev/null; then
    sudo apt-get install -y tmux
  else
    >&2 echo "Couldn't find package manager"
  fi
}