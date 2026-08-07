#!/usr/bin/env sh

# shellcheck source=../utils/utils.sh
. "${DOTFILES:?}/utils/utils.sh"

TMUX_BLOCK_TAG="dotfiles:tmux"

# Pinned Tmux and TPM release. Bump deliberately.
TMUX_DESIRED_VERSION='3.5a'
# SHA-256 of tmux-${TMUX_DESIRED_VERSION}.tar.gz. Bump it with the version.
TMUX_SHA256='16216bd0877170dfcc64157085ba9013610b12b082548c7c9542cc0103198951'
TPM_VERSION='3.1.0'
TPM_REPO='https://github.com/tmux-plugins/tpm'

# Check if tmux is installed
is_tmux_installed() {
  command_exists tmux
}

# Version of the tmux on PATH (`tmux 3.6a` -> 3.6a).
get_tmux_version() {
  tmux -V | cut -d' ' -f2
}

# The ✓ wording for a package-manager install.
_tmux_installed_msg() {
  echo "tmux $(get_tmux_version) installed"
}

# Get latest available tmux version from package manager
get_tmux_package_version() {
  get_version_in_pm tmux \
    | sed -E 's/([0-9]\.[0-9][abc]?).*/\1/'
}

# Install the toolchain and headers a from-source tmux build needs.
install_tmux_build_dependencies() {
  install_from_pm --as 'build dependencies' \
    --die "Couldn't install the tmux build dependencies" \
    -- wget tar gzip gcc make libevent-headers ncurses-headers bison
}

# Install version $1 from source, (optional) install at $2 location
install_tmux_from_source() {
  local version_tmux="$1" install_prefix="${2:-/usr/local}"
  local tmux_tar_gz="tmux-${version_tmux}.tar.gz"
  # Only the pinned release has a known digest, so any other one is unverifiable.
  test "$version_tmux" = "$TMUX_DESIRED_VERSION" \
    || die "No pinned checksum for tmux ${version_tmux}"
  install_tmux_build_dependencies
  # Download sources inside $HOME to be in a non read-only path.
  (
    set -e
    cd "$HOME"
    # -q hides wget's own diagnostics too, so say why the step failed here.
    # -O pins the output name: a leftover tarball from a failed run would
    # otherwise send this download to tmux-*.tar.gz.1 and leave the checksum
    # verifying the stale file.
    wget -q -O "${tmux_tar_gz}" "https://github.com/tmux/tmux/releases/download/${version_tmux}/${tmux_tar_gz}" \
      || die "Couldn't download tmux ${version_tmux}"
    if ! verify_sha256 "${tmux_tar_gz}" "$TMUX_SHA256"; then
      rm -f "${tmux_tar_gz}"
      die "Checksum mismatch for ${tmux_tar_gz}, refusing to build it"
    fi
    tar xf "${tmux_tar_gz}" && rm -f "${tmux_tar_gz}"
    tui_task "building tmux ${version_tmux} from source (a few minutes)…" \
      --ok "tmux ${version_tmux} installed" \
      --die "Couldn't build tmux ${version_tmux} from source" \
      -- _build_tmux_from_source "${version_tmux}" "${install_prefix}"
    rm -rf "tmux-${version_tmux}"
  )
}

# Configure, compile and install tmux from its extracted source directory.
# $1: version being built  $2: install prefix
_build_tmux_from_source() {
  (
    cd "tmux-$1"
    ./configure --prefix="$2" && make -j4
    sudo make install
  )
}

# Installs tmux, ensuring at least minimum version $1
install_tmux_program() {
  local min_version installed_version pm_version pm location
  min_version=${1:?}
  (
    set -e
    if is_tmux_installed; then
      installed_version=$(get_tmux_version)
      if version_ge "$installed_version" "$min_version"; then
        tui_skip "tmux $installed_version already installed (≥ required $min_version)"
        return 0
      fi
      tui_warn "Some features may not work with the older tmux."
      tui_detail "tmux installed version:    $installed_version"
      tui_detail "Dotfiles minimum version:  $min_version"
      if confirm -n "Install dotfiles anyway?"; then
        return 0
      fi
      tui_skip "tmux dotfiles not installed"
      return 1
    fi

    pm_version=$(get_tmux_package_version)
    pm=$(get_supported_pm)

    if [ -n "$pm_version" ] && version_ge "$pm_version" "$min_version"; then
      tui_skip "tmux $pm_version available from $pm (≥ required $min_version)"
      if confirm "Install tmux from $pm?"; then
        install_from_pm --ok-cmd _tmux_installed_msg \
          --die "Couldn't install tmux $pm_version" \
          -- tmux
        return 0
      fi
    fi

    # The pinned release is the only one with a checksum, so it is what gets
    # built — which is fine as long as it clears the minimum asked for.
    version_ge "$TMUX_DESIRED_VERSION" "$min_version" \
      || die "Can't install tmux ≥ $min_version: only $TMUX_DESIRED_VERSION is pinned"

    tui_skip "tmux $TMUX_DESIRED_VERSION will be installed from source"

    if confirm -n "Install tmux in a custom location?"; then
      prompt_new_path "Install under %s/bin/tmux?" location
    fi

    # Reports its own step and result — the build is where the version is known.
    install_tmux_from_source "$TMUX_DESIRED_VERSION" "$location"
  )
}

# No-arg step adapter for install_tmux_program so the wizard runner can call it
# from the step list without arguments.
install_tmux_program_step() {
  install_tmux_program $TMUX_DESIRED_VERSION
}

install_tmux_dotfiles() {
  local config_dir tmux_conf contents plugins_dir
  (
    set -e
    config_dir="$(xdg_config_home)/tmux"
    plugins_dir="$(get_tmux_plugins_dir)"
    mkdir -p "$config_dir"
    mkdir -p "$plugins_dir"
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

    install_managed_block --as "$(tui_path "$tmux_conf")" \
      "$tmux_conf" "$TMUX_BLOCK_TAG" "$contents"
  )
}

# Check if TPM is installed
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
      tui_skip "TPM ${TPM_VERSION} already installed"
      return 0
    fi
    install_from_pm --die "Couldn't install git" -- git
    plugins_dir=$(get_tmux_plugins_dir)
    mkdir -p "$plugins_dir"
    tui_task "cloning TPM ${TPM_VERSION}…" \
      --ok "TPM ${TPM_VERSION} installed" \
      --die "Couldn't clone TPM ${TPM_VERSION} from $TPM_REPO" \
      -- git clone --quiet --depth=1 --branch "v${TPM_VERSION}" -c advice.detachedHead=false "$TPM_REPO" "$plugins_dir/tpm"
  )
}

# Materialize @plugin entries declared in tmux.conf via TPM's headless installer.
# Requires git (each plugin is a git clone).
install_tpm_plugins() {
  (
    set -e
    tui_task "installing tmux plugins…" \
      --ok "tmux plugins installed" \
      --die "Couldn't install the tmux plugins" \
      -- "$(get_tmux_plugins_dir)/tpm/bin/install_plugins"
  )
}

# Installs tmux and its dotfiles with an expected version
# -y: accepts default answer for all questions
install_tmux_wizard() {
  wizard_run "$@" -- install_tmux_program_step install_tmux_dotfiles install_tpm install_tpm_plugins
}

# Run installation if called with --wizard
wizard_main install_tmux_wizard "$@"
