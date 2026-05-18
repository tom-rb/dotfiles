#!/usr/bin/env sh

# shellcheck source=../utils/utils.sh
. "${DOTFILES:?}/utils/utils.sh"

# Pinned TPM release. Bump deliberately.
TPM_VERSION='3.1.0'
TPM_REPO='https://github.com/tmux-plugins/tpm'

is_tmux_installed() {
  command_exists tmux
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
  install_from_pm \
    wget tar gzip gcc make libevent-headers ncurses-headers bison
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

# No-arg step adapter for install_tmux_program so the wizard runner can call it
# from the step list without arguments. The version constant lives here.
install_tmux_program_step() {
  install_tmux_program 3.1b
}

install_tmux_dotfiles() {
  local config_dir tmux_conf contents plugins_dir
  # Sub-shell for scoping set -e
  (
    set -e
    config_dir="$(xdg_config_home)/tmux"
    plugins_dir="$(get_tmux_plugins_dir)"
    mkdir -v -p "$config_dir"
    mkdir -v -p "$plugins_dir"
    tmux_conf="$config_dir/tmux.conf"

    # Use tmux source-file command to include dotfiles repo tmux.conf
    # With this, user can still use machine's options in its tmux.conf
    # TMUX_PLUGIN_MANAGER_PATH is baked here as an absolute path so the repo
    # conf does not depend on XDG_DATA_HOME being exported by the login shell.
    contents=$(cat <<-EOF
		# Managed by tmux/install_tmux.sh — edits inside this block will be overwritten.
		set -g @user_conf "${tmux_conf}"
		set -g @theme_conf "${DOTFILES:?}/tmux/theme.conf"
		set-environment -g TMUX_PLUGIN_MANAGER_PATH "${plugins_dir}"
		source-file ${DOTFILES:?}/tmux/tmux.conf
EOF
    )

    install_managed_block "$tmux_conf" "dotfiles:tmux" "$contents"

    echo "****************************"
    echo "$tmux_conf configured."
    echo "****************************"
  )
}

# True if TPM is present at the expected location.
is_tpm_installed() {
  test -x "$(get_tmux_plugins_dir)/tpm/tpm"
}

# Clone pinned TPM into <plugins>/tpm/ as a git repo. Idempotent: skips if present.
# A git-backed install lets tpm/bin/install_plugins recognize tpm itself as already
# managed and skip re-cloning it.
install_tpm() {
  local plugins_dir
  (
    set -e
    if is_tpm_installed; then
      echo "****************************"
      echo "TPM ${TPM_VERSION} already installed."
      echo "****************************"
      return 0
    fi
    install_from_pm git
    plugins_dir=$(get_tmux_plugins_dir)
    mkdir -p "$plugins_dir"
    git clone --depth=1 --branch "v${TPM_VERSION}" -c advice.detachedHead=false "$TPM_REPO" "$plugins_dir/tpm"
    echo "****************************"
    echo "TPM ${TPM_VERSION} installed."
    echo "****************************"
  )
}

# Materialize @plugin entries declared in tmux.conf via TPM's headless installer.
# Requires git (each plugin is a git clone).
install_tpm_plugins() {
  (
    set -e
    "$(get_tmux_plugins_dir)/tpm/bin/install_plugins"
  )
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

# Install tmux bridge managed block into $ZDOTDIR/.zshrc, if present.
# The block always sources tmux-cmds.sh. When the user opts in, the rich
# auto-enter snippet (with terminal-emulator detection) is also injected.
# Re-running preserves the previous auto-enter choice as the prompt default.
install_tmux_shell_bridge() {
  local zdotdir zshrc content auto_enter want_auto_enter
  (
    set -e
    zdotdir=$(get_zdotdir)
    zshrc="$zdotdir/.zshrc"

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

    content=$(cat <<-EOF
		# Managed by tmux/install_tmux.sh — edits inside this block will be overwritten.
		[ -f "\$DOTFILES/tmux/tmux-cmds.sh" ] && source "\$DOTFILES/tmux/tmux-cmds.sh"
		${auto_enter}
EOF
    )
    install_managed_block "$zshrc" "dotfiles:tmux" "$content"

    echo "$zshrc updated with tmux bridge block."
  )
}

# Installs tmux and its dotfiles with an expected version
# -y: accepts default answer for all questions
install_tmux_wizard() {
  wizard_run "$@" -- install_tmux_program_step install_tmux_dotfiles install_tpm install_tpm_plugins install_tmux_shell_bridge
}

# Run installation if called with --wizard
wizard_main install_tmux_wizard "$@"
