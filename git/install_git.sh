#!/usr/bin/env sh

# shellcheck source=../utils/utils.sh
. "${DOTFILES:?}/utils/utils.sh"

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
  local current target
  target="${DOTFILES:?}/git/templates"
  current=$(git config --global --get init.templateDir || true)

  if [ "$current" = "$target" ]; then
    echo "git templates already configured."
    return 0
  fi

  if [ -n "$current" ]; then
    echo "init.templateDir is already set to: $current"
    if ! confirm -n "Overwrite with $target?"; then
      echo "git templates not configured."
      return 0
    fi
  fi

  git config --global init.templateDir "$target"
  echo "****************************"
  echo "git templates configured."
  echo "****************************"
}

# Point git's core.excludesfile at $DOTFILES/git/.gitignore.global so the
# globally-ignored patterns shipped here apply to every repo.
install_git_excludesfile() {
  local current target
  target="${DOTFILES:?}/git/.gitignore.global"
  current=$(git config --global --get core.excludesfile || true)

  if [ "$current" = "$target" ]; then
    echo "git excludesfile already configured."
    return 0
  fi

  if [ -n "$current" ]; then
    echo "core.excludesfile is already set to: $current"
    if ! confirm -n "Overwrite with $target?"; then
      echo "git excludesfile not configured."
      return 0
    fi
  fi

  git config --global core.excludesfile "$target"
  echo "****************************"
  echo "git excludesfile configured."
  echo "****************************"
}

# Set init.defaultBranch=main so `git init` no longer creates `master`.
install_git_default_branch() {
  local current target
  target="main"
  current=$(git config --global --get init.defaultBranch || true)

  if [ "$current" = "$target" ]; then
    echo "git init.defaultBranch already configured."
    return 0
  fi

  if [ -n "$current" ]; then
    echo "init.defaultBranch is already set to: $current"
    if ! confirm -n "Overwrite with $target?"; then
      echo "git init.defaultBranch not configured."
      return 0
    fi
  fi

  git config --global init.defaultBranch "$target"
  echo "****************************"
  echo "git init.defaultBranch configured."
  echo "****************************"
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

# Installs git, configures templates and global excludes, then offers to set
# user identity
install_git_wizard() {
  install_git_program \
    && install_git_templates \
    && install_git_excludesfile \
    && install_git_default_branch \
    && configure_git_user
}

# Run installation if called with --wizard
if [ "$1" = --wizard ]; then
  install_git_wizard
fi
