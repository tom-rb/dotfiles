#!/usr/bin/env sh

# shellcheck source=../utils/utils.sh
. "${DOTFILES:?}/utils/utils.sh"

# Pinned TPM release. Bump deliberately.
TPM_VERSION='3.1.0'
TPM_URL="https://github.com/tmux-plugins/tpm/archive/refs/tags/v${TPM_VERSION}.tar.gz"

is_tmux_installed() {
  command_exists tmux
}

# Absolute path of the tmux plugins dir (matches install_tmux_dotfiles default).
get_tmux_plugins_dir() {
  echo "${XDG_DATA_HOME:-$HOME/.local/share}/tmux/plugins"
}

# Get latest available tmux version from package manager
get_tmux_package_version() {
  get_version_in_pm tmux \
    | sed -E 's/([0-9]\.[0-9][abc]?).*/\1/'
}

# Fetch server response headers for the tmux latest release redirect
get_tmux_release_headers() {
  wget --server-response --spider \
    https://github.com/tmux/tmux/releases/latest 2>&1
}

# Get latest tmux version from github release
get_tmux_release_version() {
  get_tmux_release_headers \
    | sed -nE '/^[[:space:]]*Location:/ { s_.*tag/([0-9]\.[0-9][abc]?).*_\1_p; q }'
}

install_tmux_build_dependencies() {
  # shellcheck disable=SC2046  # intentional word-splitting of resolved names
  install_from_pm $(pm_packages_for \
    wget tar gzip gcc make libevent-headers ncurses-headers bison)
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
    # $tmux_desired_version is the minimum acceptable version. Anything >= it
    # (installed or available from the package manager) is accepted as-is.
    if is_tmux_installed; then
      installed_version=$(tmux -V | cut -d' ' -f2)
      if version_ge "$installed_version" "$tmux_desired_version"; then
        echo "****************************"
        echo "tmux $installed_version installed (>= required $tmux_desired_version)."
        echo "****************************"
        return 0
      fi
      echo "tmux installed version:    $installed_version"
      echo "Dotfiles minimum version:  $tmux_desired_version"
      echo "Some features may not work with the older tmux."
      if confirm -n "Install dotfiles anyway?"; then
        return 0
      fi
      return 1
    fi

    pm_version=$(get_tmux_package_version)

    if [ -n "$pm_version" ] && version_ge "$pm_version" "$tmux_desired_version"; then
      echo "tmux $pm_version is available from package manager (>= required $tmux_desired_version)"
      if confirm "Do you want to install from it?"; then
        install_from_pm tmux
        echo "****************************"
        echo "tmux $pm_version installed."
        echo "****************************"
        return 0
      fi
    fi

    echo "tmux $tmux_desired_version will be installed from source."

    # TODO: extract "custom path selection" to utils and test separately
    if confirm -n "Do you want to install it in a custom location?"; then
      while : ; do
        printf 'Give absolute path: '; read -r location
        # Expand given variables, like $HOME or ~, and remove trailing '/'
        eval location="${location%/}"

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
  local config_dir tmux_conf contents plugins_dir
  # Sub-shell for scoping set -e
  (
    set -e
    config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/tmux"     # tmux.conf
    plugins_dir="${XDG_DATA_HOME:-$HOME/.local/share}/tmux/plugins"
    mkdir -v -p "$config_dir"
    mkdir -v -p "$plugins_dir"
    tmux_conf="$config_dir/tmux.conf"

    # Use tmux source-file command to include dotfiles repo tmux.conf
    # With this, user can still use machine's options in its tmux.conf
    # TMUX_PLUGIN_MANAGER_PATH is baked here as an absolute path so the repo
    # conf does not depend on XDG_DATA_HOME being exported by the login shell.
    contents=$(cat <<-EOF
		# Path of this stub file — reload binding sources this back
		set -g @user_conf "${tmux_conf}"
		# Theme file shipped by the repo (absolute path)
		set -g @theme_conf "${DOTFILES:?}/tmux/theme.conf"
		# Resolve tmux plugin manager path
		set-environment -g TMUX_PLUGIN_MANAGER_PATH "${plugins_dir}"
		# Source tmux.conf from dotfiles repo
		source-file ${DOTFILES:?}/tmux/tmux.conf
		# Add machine custom config here
EOF
    )

    # Ask user what to do if tmux.conf already exist
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
              printf "%s\n" "$contents" > "$tmux_conf" ;;
          2) printf "%s\n" "$contents" >> "$tmux_conf" ;;
          3) rm -v -f "$tmux_conf" &&
              printf "%s\n" "$contents" > "$tmux_conf" ;;
        esac
      fi
    else
      printf "%s\n" "$contents" > "$tmux_conf"
    fi

    echo "****************************"
    echo "$tmux_conf configured."
    echo "****************************"
  )
}

# True if TPM is present at the expected location.
is_tpm_installed() {
  test -x "$(get_tmux_plugins_dir)/tpm/tpm"
}

# Download + extract pinned TPM into <plugins>/tpm/. Idempotent: skips if present.
install_tpm() {
  local plugins_dir tarball
  (
    set -e
    if is_tpm_installed; then
      echo "****************************"
      echo "TPM ${TPM_VERSION} already installed."
      echo "****************************"
      return 0
    fi
    plugins_dir=$(get_tmux_plugins_dir)
    mkdir -p "$plugins_dir"
    tarball="$plugins_dir/tpm-${TPM_VERSION}.tar.gz"
    wget -nv -O "$tarball" "$TPM_URL"
    # Tarball contains a single top-level dir tpm-<version>/; extract & rename.
    tar -xzf "$tarball" -C "$plugins_dir"
    rm -f "$tarball"
    rm -rf "$plugins_dir/tpm"
    mv "$plugins_dir/tpm-${TPM_VERSION}" "$plugins_dir/tpm"
    echo "****************************"
    echo "TPM ${TPM_VERSION} installed."
    echo "****************************"
  )
}

# Materialize @plugin entries declared in tmux.conf. Requires git (each plugin
# is a git clone). install_plugins shells out to a tmux server internally.
install_tpm_plugins() {
  local plugins_dir
  (
    set -e
    # shellcheck disable=SC2046  # intentional word-splitting of resolved names
    install_from_pm $(pm_packages_for git)
    plugins_dir=$(get_tmux_plugins_dir)
    "$plugins_dir/tpm/bin/install_plugins"
  )
}

# Resolve $ZDOTDIR (matches zshenv-base default)
get_zdotdir() {
  echo "${ZDOTDIR:-${XDG_CONFIG_HOME:-$HOME/.config}/zsh}"
}

# True if the existing tmux-managed block in $1 already contains the
# auto-enter snippet (used to pre-fill the wizard prompt default).
bridge_block_has_auto_enter() {
  local file="$1" start='# >>> dotfiles:tmux >>>' end='# <<< dotfiles:tmux <<<'
  [ -f "$file" ] || return 1
  awk -v s="$start" -v e="$end" '
    $0==s {inb=1; next}
    inb && $0==e {inb=0; next}
    inb && /tmux-enter/ {found=1}
    END {exit !found}
  ' "$file"
}

# Install tmux bridge marker block into $ZDOTDIR/.zshrc, if present.
# The block always sources tmux-cmds.sh. When the user opts in, the rich
# auto-enter snippet (with terminal-emulator detection) is also injected.
# Idempotent: re-running replaces the block in place, preserving the previous
# auto-enter choice as the wizard prompt default.
install_tmux_shell_bridge() {
  local zdotdir zshrc start end block auto_enter want_auto_enter
  (
    set -e
    zdotdir=$(get_zdotdir)
    zshrc="$zdotdir/.zshrc"
    start='# >>> dotfiles:tmux >>>'
    end='# <<< dotfiles:tmux <<<'

    if [ ! -f "$zshrc" ]; then
      echo "No $zshrc found — skipping tmux shell bridge."
      echo "Hint: run zsh/install_zsh.sh --wizard first to get a managed stub."
      return 0
    fi

    # Default the auto-enter prompt to the previous choice (YES if the block
    # already has the snippet, NO otherwise).
    if bridge_block_has_auto_enter "$zshrc"; then
      confirm    "Auto-launch tmux on new shells (with terminal-emulator detection)?" \
        && want_auto_enter=1 || want_auto_enter=0
    else
      confirm -n "Auto-launch tmux on new shells (with terminal-emulator detection)?" \
        && want_auto_enter=1 || want_auto_enter=0
    fi
    if [ "$want_auto_enter" = 1 ]; then
      auto_enter=$(cat <<-'EOF'
		# Auto-enter tmux when a new terminal opens (specific emulators only)
		if [ -z "$TMUX" ] && command -v tmux >/dev/null; then
		  if [ -n "$WT_SESSION" ]; then # Windows Terminal defines this
		    tmux-enter
		  elif pstree -s $$ | grep -Eq "(gnome-terminal|wslbridge2?-back)"; then
		    tmux-enter
		  fi
		fi
EOF
      )
    else
      auto_enter=
    fi

    block=$(cat <<-EOF
		$start
		# Managed by tmux/install_tmux.sh — edits inside this block will be overwritten.
		[ -f "\$DOTFILES/tmux/tmux-cmds.sh" ] && source "\$DOTFILES/tmux/tmux-cmds.sh"
		${auto_enter}
		$end
EOF
    )

    if grep -qF "$start" "$zshrc"; then
      awk -v s="$start" -v e="$end" -v b="$block" '
        $0==s {print b; skip=1; next}
        skip && $0==e {skip=0; next}
        !skip
      ' "$zshrc" > "$zshrc.tmp" && mv "$zshrc.tmp" "$zshrc"
    else
      printf '\n' >> "$zshrc"
      printf '%s\n' "$block" >> "$zshrc"
    fi

    echo "$zshrc updated with tmux bridge block."
  )
}

# Installs tmux and its dotfiles with an expected version
# -y: accepts default answer for all questions
install_tmux_wizard() {
  local desired_version=3.1b
  if [ "$1" = -y ]; then
  # Sends "enter" continuously
  yes "
" | { install_tmux_program "$desired_version" \
      && install_tmux_dotfiles \
      && install_tpm \
      && install_tpm_plugins \
      && install_tmux_shell_bridge; }
  else
    install_tmux_program "$desired_version" \
      && install_tmux_dotfiles \
      && install_tpm \
      && install_tpm_plugins \
      && install_tmux_shell_bridge
  fi
}

# Run installation if called with --wizard
if [ "$1" = --wizard ]; then
  install_tmux_wizard interactive
fi
