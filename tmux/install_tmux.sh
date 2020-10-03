#!/usr/bin/env sh
set -u

# shellcheck source=../utils/utils.sh
. "$DOTFILES/utils/utils.sh"

is_tmux_installed() {
  command_exists tmux
}

# Get latest available tmux version from package manager
get_tmux_package_version() {
  if command_exists apt-cache; then
    apt-cache policy tmux \
    | sed -nE 's/.*Candidate: ([0-9]\.[0-9][abc]?).*/\1/p'
  else
    >&2 echo "Couldn't find package manager"
  fi
}

# Get latest tmux version from github release
get_tmux_release_version() {
  wget --server-response --spider \
    https://github.com/tmux/tmux/releases/latest 2>&1 \
    | sed -nE '/^Location:/ s_.*tag/([0-9]\.[0-9][abc]?).*_\1_p'
}

install_tmux_from_pm() {
  if command_exists apt-get; then
    sudo apt-get install -y tmux
  else
    >&2 echo "Couldn't find package manager"
  fi
}

install_tmux_from_source() {
  local version_tmux="$1" install_prefix="${2:-/usr/local}"
  local tmux_tar_gz="tmux-${version_tmux}.tar.gz"

  if command_exists apt-get; then
    { sudo apt-get update \
      && sudo apt-get -y install wget tar build-essential libevent-dev libncurses-dev
    } || die "ERROR while installing tmux compilation dependencies."
  else
    >&2 echo "Couldn't find package manager"
    exit 2
  fi

  # Download sources inside $HOME to be in a non read-only path.
  (
    set -e
    cd "$HOME"

    # TODO: checksum
    wget "https://github.com/tmux/tmux/releases/download/${version_tmux}/${tmux_tar_gz}"
    tar xf "${tmux_tar_gz}" && rm -f "${tmux_tar_gz}"
    (
      cd "tmux-${version_tmux}"
      ./configure --prefix="${install_prefix}" && make -j4
      sudo make install
    )
    rm -rf "tmux-${version_tmux}"
  )

  echo "******************"
  echo "TMUX is installed."
  echo "******************"
}