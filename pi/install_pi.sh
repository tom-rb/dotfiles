#!/usr/bin/env sh

# shellcheck source=../utils/utils.sh
. "${DOTFILES:?}/utils/utils.sh"

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

# Installs Claude Code skills from pi/skills/.
# -y: accepts default answer for all questions
install_pi_wizard() {
  wizard_run "$@" -- install_pi_skills
}

# Run installation if called with --wizard
wizard_main install_pi_wizard "$@"
