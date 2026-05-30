#!/usr/bin/env sh

# asdf path resolvers and runtime activation, shared by the asdf installer
# (install_asdf.sh) and by any same-run consumer (e.g. deploy → pi) that needs
# asdf before a new login shell has sourced the .zshenv block.

# shellcheck source=../utils/utils.sh
. "${DOTFILES:?}/utils/utils.sh"

# Path segments used by both activate_asdf (runtime) and the rendered .zshenv
# block, so the two never drift.
ASDF_BIN_SUBPATH=".local/bin"
ASDF_DATA_SUBPATH="asdf"
ASDF_SHIMS_SUBPATH="shims"

# asdf binary directory (PM install is skipped; see docs/adr/0002-install-asdf-from-tarball.md).
asdf_bin_dir() { echo "$HOME/$ASDF_BIN_SUBPATH"; }

# asdf data directory (runtimes, plugins, shims).
asdf_data_dir() { echo "$(xdg_data_home)/$ASDF_DATA_SUBPATH"; }

# asdf shims directory (runtime executables exposed on PATH).
asdf_shims_dir() { echo "$(asdf_data_dir)/$ASDF_SHIMS_SUBPATH"; }

# Apply asdf's PATH wiring to the current (non-zsh) environment so same-run
# consumers can see the asdf binary and its runtime shims; the .zshenv block
# does the same for future zsh logins. No-op when asdf is absent; idempotent.
activate_asdf() {
  local bin_dir shims_dir
  bin_dir="$(asdf_bin_dir)"
  command_exists asdf || [ -x "$bin_dir/asdf" ] || return 0
  ASDF_DATA_DIR="$(asdf_data_dir)"
  shims_dir="$(asdf_shims_dir)"
  export ASDF_DATA_DIR
  case ":$PATH:" in *":$bin_dir:"*) ;; *) PATH="$bin_dir:$PATH" ;; esac
  case ":$PATH:" in *":$shims_dir:"*) ;; *) PATH="$shims_dir:$PATH" ;; esac
  export PATH
}
