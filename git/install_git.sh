#!/usr/bin/env sh

# shellcheck source=../utils/utils.sh
. "${DOTFILES:?}/utils/utils.sh"

# Idempotently set a global git config key. If the key already equals $target,
# do nothing. If it's set to a different value, ask before overwriting.
# $1: config key (e.g. init.templateDir)
# $2: target value
# $3: (optional) user-facing label for messages; defaults to $1
set_git_global_config() {
  local key target label current
  key=${1:?} target=${2:?} label=${3:-$1}
  current=$(git config --global --get "$key" || true)
  if [ "$current" = "$target" ]; then
    echo "$label already configured."
    return 0
  fi
  if [ -n "$current" ]; then
    echo "$key is already set to: $current"
    if ! confirm -n "Overwrite with $target?"; then
      echo "$label not configured."
      return 0
    fi
  fi
  git config --global "$key" "$target"
  echo "****************************"
  echo "$label configured."
  echo "****************************"
}

# Check if git is installed
is_git_installed() {
  command_exists git
}

# Installs git from the system package manager
install_git_program() {
  # Sub-shell for scoping set -e
  (
    set -e
    if is_git_installed; then
      echo "****************************"
      echo "git already installed."
      echo "****************************"
      return 0
    fi

    install_from_pm git
    echo "****************************"
    echo "git installed."
    echo "****************************"
  )
}

# Point git's init.templateDir at $DOTFILES/git/templates so new repos pick up
# the hooks and info/exclude shipped here.
install_git_templates() {
  set_git_global_config init.templateDir "${DOTFILES:?}/git/templates" "git templates"
}

# Point git's core.excludesfile at $DOTFILES/git/.gitignore.global so the
# globally-ignored patterns shipped here apply to every repo.
install_git_excludesfile() {
  set_git_global_config core.excludesfile "${DOTFILES:?}/git/.gitignore.global" "git excludesfile"
}

# Set init.defaultBranch=main so `git init` no longer creates `master`.
install_git_default_branch() {
  set_git_global_config init.defaultBranch "main" "git init.defaultBranch"
}

# Offer to set git user.name and user.email globally.
# Shows existing value in brackets; default answer is N when set, Y when empty.
configure_git_user() {
  local key current new
  for key in user.name user.email; do
    current=$(git config --global --get "$key" || true)
    if [ -n "$current" ]; then
      confirm -n "Change git $key now? [$current]" || continue
    else
      confirm "Set git $key now?" || continue
    fi
    prompt_line "  $key: " new
    if [ -n "$new" ]; then
      git config --global "$key" "$new"
    fi
  done
}

# Installs git, configures templates and global excludes, then offers to set user identity.
# -y: accepts default answer for all questions
install_git_wizard() {
  wizard_run "$@" -- install_git_program install_git_templates install_git_excludesfile install_git_default_branch configure_git_user
}

# Run installation if called with --wizard
wizard_main install_git_wizard "$@"
