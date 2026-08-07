#!/usr/bin/env sh

# shellcheck source=../utils/utils.sh
. "${DOTFILES:?}/utils/utils.sh"

# Pinned release. Bump deliberately.
PI_VERSION="0.78.0"

# Check if the pi coding agent binary is installed.
is_pi_installed() {
  command_exists pi
}

# Version of the installed pi, which answers with a bare version string.
get_pi_version() {
  pi --version 2>/dev/null | head -n1
}

# asdf ships prebuilt node binaries that dynamically link libatomic.so.1, which
# isn't present by default on many distros. If the freshly installed node can't
# load its shared libraries, pull libatomic from the system PM so it can run.
ensure_node_runtime_libs() {
  node --version >/dev/null 2>&1 && return 0
  check_supported_pm || return 0
  install_from_pm --die "Couldn't install libatomic" -- libatomic
}

# Checks if node is available; if not, offers to install via asdf (preferred)
# or the system PM. Dies if the user declines or neither method is available.
ensure_node_installed() {
  local pm
  command_exists node && return 0
  tui_warn "node not found"
  if command_exists asdf; then
    confirm "Install node via asdf?" || die "node is required to install pi."
    asdf plugin add nodejs
    asdf install nodejs latest
    asdf set -u nodejs latest
    asdf reshim nodejs
  elif check_supported_pm; then
    pm=$(get_supported_pm)
    confirm "Install node via $pm?" || die "node is required to install pi."
    install_from_pm --as node --die "Couldn't install node from $pm" -- nodejs npm
  else
    die "Install node manually and re-run."
  fi
  ensure_node_runtime_libs
}

# Installs the pi coding agent npm package globally.
install_pi_program() {
  (
    set -e
    if is_pi_installed; then
      tui_skip "pi $(get_pi_version) already installed"
      return 0
    fi

    ensure_node_installed

    # The pinned version rather than `pi --version`: under an asdf-managed node
    # the binary sits outside PATH until the reshim below creates its shim, so
    # asking the binary here answers with nothing.
    tui_task "installing pi ${PI_VERSION} (npm)…" \
      --ok "pi ${PI_VERSION} installed" \
      --die "Failed to install the pi npm package." \
      -- npm install -g --loglevel=error --ignore-scripts "@earendil-works/pi-coding-agent@${PI_VERSION}"

    if command_exists asdf; then
      tui_task "reshimming asdf nodejs…" \
        --ok "asdf reshimmed" \
        --die "Couldn't reshim asdf nodejs" \
        -- asdf reshim nodejs
    fi
  )
}

# Copy all skill folders from pi/skills/ to ~/.agents/skills/, creating the
# destination directory if needed. Overwrites existing skills.
install_pi_skills() {
  local skills_src skills_dest
  (
    set -e
    skills_src="${DOTFILES:?}/pi/skills"
    skills_dest="$HOME/.agents/skills"

    if [ ! -d "$skills_src" ]; then
      tui_skip "No skills found in $(tui_path "$skills_src")"
      return 0
    fi

    mkdir -p "$HOME/.agents"
    rm -rf "$skills_dest"
    cp -r "$skills_src" "$skills_dest"

    tui_ok "Skills installed to $(tui_path "$skills_dest")"
  )
}

# Installs the pi coding agent and skills.
# -y: accepts default answer for all questions
install_pi_wizard() {
  wizard_run "$@" -- install_pi_program install_pi_skills
}

# Run installation if called with --wizard
wizard_main install_pi_wizard "$@"
