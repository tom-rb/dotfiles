#!/usr/bin/env sh

# shellcheck source=../utils/utils.sh
. "$DOTFILES/utils/utils.sh"

is_tmux_installed() {
  command_exists tmux
}

# Get latest available tmux version from package manager
get_tmux_package_version() {
  get_version_in_pm tmux \
    | sed -E 's/([0-9]\.[0-9][abc]?).*/\1/'
}

# Get latest tmux version from github release
get_tmux_release_version() {
  wget --server-response --spider \
    https://github.com/tmux/tmux/releases/latest 2>&1 \
    | sed -nE '/^Location:/ s_.*tag/([0-9]\.[0-9][abc]?).*_\1_p'
}

install_tmux_build_dependencies() {
  install_from_pm wget tar gzip gcc make
  case $(get_supported_pm) in
    apt-get) install_from_pm libevent-dev libncurses-dev;;
    yum)     install_from_pm libevent-devel ncurses-devel;;
  esac
}

# Install version $1 from source, (optional) install at $2 location
install_tmux_from_source() {
  local version_tmux="$1" install_prefix="${2:-/usr/local}"
  local tmux_tar_gz="tmux-${version_tmux}.tar.gz"
  install_tmux_build_dependencies
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
}

install_tmux_wizard() {
  # Sub-shell for scoping set -e (and vars)
  (
    set -e
    # Dotfile configs are expecting version:
    TMUX_DESIRED_VERSION=3.1b

    if is_tmux_installed; then
      installed_version=$(tmux -V | cut -d' ' -f2)
      if [ "$installed_version" = $TMUX_DESIRED_VERSION ]; then
        echo "****************************"
        echo "tmux $TMUX_DESIRED_VERSION already installed."
        echo "****************************"
        return 0
      else
        echo "tmux installed version: $installed_version"
        echo "Dotfiles tmux version:  $TMUX_DESIRED_VERSION"
        echo "Versions are different, uninstall it yourself and try again. [press a key]"
        read_char silent
        return 1
      fi
    fi

    pm_version=$(get_tmux_package_version)

    if [ "$pm_version" = $TMUX_DESIRED_VERSION ]; then
      echo "tmux $pm_version is available from package manager"
      if confirm "Do you want to install from it?"; then
        install_from_pm tmux
        echo "****************************"
        echo "tmux $TMUX_DESIRED_VERSION installed."
        echo "****************************"
        return 0
      fi
    fi

    echo "tmux $TMUX_DESIRED_VERSION will be installed from source."

    local location

    # TODO: extract "custom path selection" to utils and test separately
    if confirm -n "Do you want to install it in a custom location?"; then
      while true; do
        read -p "Give absolute path: " -r location
        # Expand given variables, like $HOME or ~, and remove trailing '/'
        eval location="${location%%/*}"

        [ -z "$location" ] && continue
        if [ -e "$location" ]; then
          echo "The $location already exists"
          continue
        fi
        if ! confirm "Install under $location/bin/tmux?"; then
          continue
        fi
        if ! mkdir -p "$location"; then
          echo "Cannot create $location folder"
          continue
        fi
        break;
      done
    fi

    install_tmux_from_source $TMUX_DESIRED_VERSION "$location"
    echo "****************************"
    echo "tmux $TMUX_DESIRED_VERSION installed."
    echo "****************************"
  )
}

# Run installation if called with --wizard
if [ "$1" = --wizard ]; then
  install_tmux_wizard
fi