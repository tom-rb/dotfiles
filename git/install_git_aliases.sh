#!/usr/bin/env sh

# shellcheck source=../utils/utils.sh
. "$DOTFILES/utils/utils.sh"

# Patch the init.zsh of zimfw git module to work on sh
# $1: path to init.zsh
patch_zimfw_git_init() {
  # shellcheck disable=SC2016 # don't expand vars indeed
  sed -i.bkp '
    # Remove anonymous function scoping and var declaration
    /^() {$/ d
    /^}$/ d
    /local gprefix/ d
    /zstyle/ d
    # Substitute ${gprefix} by g
    s/${gprefix}/g/
  ' "${1:?}"
}

install_git_aliases_bash() {
  local local_bin
  if [ -n "${ZSH_VERSION:-}" ]; then
    die "install_git_aliases is for non zsh shells, use zimfw instead."
  fi
  # TODO: local_bin="${DOTFILES:?}/.local/bin" -> needs writable /app in docker test
  local_bin="${HOME:?}/.local/bin"
  # Sub-shell for scoping set -e
  (
    set -e
    # Local git-ignored folder for machine specific files
    mkdir -p "$local_bin/zimfw"
    # Download zimfw-git scripts piping to tar and extracting directly in local_bin/zimfw
    wget -O - https://github.com/zimfw/git/tarball/79894ec1d7c2654d4d0048f9cf9fb00e905c6304 |
      tar -xzf - -C "$local_bin/zimfw" --strip-components=1
    # Get useful scripts for sh (not porting all functionality)
    ( cd "$local_bin/zimfw" && chmod -R u+x . &&
      mv functions/git-branch-current functions/git-root .. )
    patch_zimfw_git_init "$local_bin/zimfw/init.zsh"
    mv "$local_bin/zimfw/init.zsh" "$local_bin/git_aliases.sh"
    # Test patched script and delete unused files
    . "$local_bin/git_aliases.sh"
    rm -rf "$local_bin/zimfw"
  )
  # Install hook in bash
  # TODO: don't risk exporting path with local_bin twice
  { echo
    echo "# Source lots of 3-letter git aliases"
    echo "export PATH=\"$local_bin:\$PATH\""
    echo ". \"$local_bin/git_aliases.sh\""
  } >> "${HOME:?}/.bashrc"
  # TODO: report the appending to bashrc
  echo "Git aliases for bash installed!"
}
