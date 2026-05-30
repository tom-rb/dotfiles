#!/usr/bin/env sh

# shellcheck source=../utils/utils.sh
. "${DOTFILES:?}/utils/utils.sh"

# Pinned release. Bump deliberately.
PI_VERSION="0.78.0"

# Check if the pi coding agent binary is installed.
is_pi_installed() {
  command_exists pi
}

# asdf ships prebuilt node binaries that dynamically link libatomic.so.1, which
# isn't present by default on many distros. If the freshly installed node can't
# load its shared libraries, pull libatomic from the system PM so it can run.
ensure_node_runtime_libs() {
  node --version >/dev/null 2>&1 && return 0
  check_supported_pm || return 0
  install_from_pm libatomic
}

# Checks if node is available; if not, offers to install via asdf (preferred)
# or the system PM. Dies if the user declines or neither method is available.
ensure_node_installed() {
  command_exists node && return 0
  if command_exists asdf; then
    confirm "node not found. Install via asdf?" || die "node is required to install pi."
    asdf plugin add nodejs
    asdf install nodejs latest
    asdf set -u nodejs latest
    asdf reshim nodejs
  elif check_supported_pm; then
    confirm "node not found. Install via $(get_supported_pm)?" || die "node is required to install pi."
    install_from_pm nodejs npm
  else
    die "node not found. Install node manually and re-run."
  fi
  ensure_node_runtime_libs
}

# Installs the pi coding agent npm package globally, then reshims if asdf
# manages node.
install_pi_program() {
  (
    set -e
    if is_pi_installed; then
      echo "****************************"
      echo "pi already installed."
      echo "****************************"
      return 0
    fi

    ensure_node_installed

    # wizard_run invokes each step as `step || ...`, which makes the shell
    # ignore `set -e` for the whole command (subshell included). Handle the
    # failure explicitly so a botched install can't masquerade as success.
    npm install -g --ignore-scripts "@earendil-works/pi-coding-agent@${PI_VERSION}" \
      || die "Failed to install the pi npm package."

    if command_exists asdf; then
      asdf reshim nodejs
    fi

    echo "****************************"
    echo "pi ${PI_VERSION} installed."
    echo "****************************"
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
      echo "No skills found in $skills_src; skipping."
      return 0
    fi

    mkdir -p "$HOME/.agents"
    rm -rf "$skills_dest"
    cp -r "$skills_src" "$skills_dest"

    echo "****************************"
    echo "Skills installed to $skills_dest"
    echo "****************************"
  )
}

# Installs the pi coding agent and its Claude Code skills.
# -y: accepts default answer for all questions
install_pi_wizard() {
  wizard_run "$@" -- install_pi_program install_pi_skills
}

# Run installation if called with --wizard
wizard_main install_pi_wizard "$@"
