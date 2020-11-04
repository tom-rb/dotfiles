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
  # TODO: extract and test reading github release
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

# Installs tmux using given version $1
install_tmux_program() {
  local tmux_desired_version installed_version pm_version location
  tmux_desired_version=${1:?}
  # Sub-shell for scoping set -e
  (
    set -e
    if is_tmux_installed; then
      installed_version=$(tmux -V | cut -d' ' -f2)
      if [ "$installed_version" = "$tmux_desired_version" ]; then
        echo "****************************"
        echo "tmux $tmux_desired_version already installed."
        echo "****************************"
        return 0
      else
        echo "tmux installed version: $installed_version"
        echo "Dotfiles tmux version:  $tmux_desired_version"
        echo "Versions are different, uninstall it yourself and try again. [press a key]"
        read_char silent
        return 1
      fi
    fi

    pm_version=$(get_tmux_package_version)

    if [ "$pm_version" = "$tmux_desired_version" ]; then
      echo "tmux $pm_version is available from package manager"
      if confirm "Do you want to install from it?"; then
        install_from_pm tmux
        echo "****************************"
        echo "tmux $tmux_desired_version installed."
        echo "****************************"
        return 0
      fi
    fi

    echo "tmux $tmux_desired_version will be installed from source."

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

    install_tmux_from_source "$tmux_desired_version" "$location"
    echo "****************************"
    echo "tmux $tmux_desired_version installed."
    echo "****************************"
  )
}

install_tmux_dotfiles() {
  local config_dir tmux_conf contents
  # Sub-shell for scoping set -e
  (
    set -e
    config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/tmux"     # tmux.conf and scripts
    mkdir -v -p "${XDG_DATA_HOME:-$HOME/.local/share}/tmux" # tmux plugins
    mkdir -v -p "$config_dir"
    tmux_conf="$config_dir/tmux.conf"

    # Use tmux source-file command to include versioned tmux.conf
    contents="source-file ${DOTFILES:?}/tmux/tmux.conf"

    # Ask user what to do if file already exist
    if [ -e "$tmux_conf" ]; then
      echo "Found existing $tmux_conf file: (tail of it)"
      echo ">>>"
      tail "$tmux_conf"
      echo "<<<"
      if choose "Backup existing tmux.conf" \
                "Append to existing tmux.conf" \
                "Overwrite existing tmux.conf"
      then # this is the cancel handling
        echo "tmux.conf not configured!"
        return 1
      else # this is choice handling
        case "$?" in
          1) backup_file "$tmux_conf" &&
              echo "$contents" > "$tmux_conf" ;;
          2) echo "$contents" >> "$tmux_conf" ;;
          3) rm -v -f "$tmux_conf" &&
              echo "$contents" > "$tmux_conf" ;;
        esac
      fi
    else
      echo "$contents" > "$tmux_conf"
    fi

    echo "****************************"
    echo "$tmux_conf configured."
    echo "****************************"
  )
  # TODO: copy theme.conf
  # TODO: install tmux-cmds.sh somehow (bash and zsh only?)
}

install_tmux_wizard() {
  # Install specific version that dotfile configs are expecting
  install_tmux_program 3.1b && install_tmux_dotfiles
}

# Run installation if called with --wizard
if [ "$1" = --wizard ]; then
  install_tmux_wizard
fi
