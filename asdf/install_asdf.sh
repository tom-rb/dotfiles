#!/usr/bin/env sh

# shellcheck source=../utils/utils.sh
. "${DOTFILES:?}/utils/utils.sh"

BLOCK_TAG="dotfiles:asdf"

ASDF_VERSION="v0.16.7"

# Map the current host's `uname -s`/`uname -m` to the os-arch slug used in
# asdf release tarball names (e.g. linux-amd64, darwin-arm64).
# Dies if the combination isn't published upstream.
detect_asdf_arch() {
  local os arch
  os=$(uname -s)
  arch=$(uname -m)
  case "$os" in
    Linux)  os=linux ;;
    Darwin) os=darwin ;;
    *) die "Unsupported OS for asdf: $os" ;;
  esac
  case "$arch" in
    x86_64|amd64)  arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) die "Unsupported arch for asdf: $arch" ;;
  esac
  echo "${os}-${arch}"
}

# Check if asdf is installed
is_asdf_installed() {
  command_exists asdf
}

# Installs asdf by downloading the official release tarball into
# $HOME/.local/bin. PM install is intentionally skipped — see
# docs/adr/0002-install-asdf-from-tarball.md.
install_asdf_program() {
  local arch url bin_dir tarball
  (
    set -e
    if is_asdf_installed; then
      echo "****************************"
      echo "asdf already installed."
      echo "****************************"
      return 0
    fi

    arch=$(detect_asdf_arch)
    url="https://github.com/asdf-vm/asdf/releases/download/${ASDF_VERSION}/asdf-${ASDF_VERSION}-${arch}.tar.gz"
    bin_dir="$HOME/.local/bin"
    tarball="$bin_dir/asdf.tar.gz"

    mkdir -p "$bin_dir"
    wget -O "$tarball" "$url"
    tar -xzf "$tarball" -C "$bin_dir" asdf
    rm -f "$tarball"

    echo "****************************"
    echo "asdf installed."
    echo "****************************"
  )
}

# Render $HOME/.zshenv with an inlined managed block that exports
# ASDF_DATA_DIR, prepends $HOME/.local/bin and the asdf shims dir to PATH,
# and conditionally sources the asdf-java plugin's set-java-home script.
# Must run after install_zsh_zshenv since this block references $XDG_DATA_HOME
# from the dotfiles:zsh block above it.
install_asdf_zshenv() {
  local zshenv content
  (
    set -e
    zshenv="$HOME/.zshenv"
    content=$(cat <<-'EOF'
			# Managed by asdf/install_asdf.sh — edits inside this block will be overwritten.
			export ASDF_DATA_DIR="${XDG_DATA_HOME:?'XDG_DATA_HOME is not set, have you run the zsh setup?'}/asdf"
			export PATH="$HOME/.local/bin:$PATH"
			export PATH="$ASDF_DATA_DIR/shims:$PATH"
			[[ -r "$ASDF_DATA_DIR/plugins/java/set-java-home.zsh" ]] && source "$ASDF_DATA_DIR/plugins/java/set-java-home.zsh"
EOF
    )
    install_managed_block "$zshenv" "$BLOCK_TAG" "$content"

    echo "****************************"
    echo "$zshenv configured for asdf."
    echo "****************************"
  )
}

# Write the zim `asdf` module declaration into $ZDOTDIR/.zimrc, so zimfw
# initializes asdf completions after compinit. Skipped when .zimrc is absent
# (zimfw not installed) — the asdf binary + .zshenv block work standalone.
install_asdf_zimrc() {
  local zdotdir zimrc content
  zdotdir=$(get_zdotdir)
  zimrc="$zdotdir/.zimrc"
  if [ ! -f "$zimrc" ]; then
    echo "zimfw not installed; skipping asdf completions."
    return 0
  fi
  content=$(cat <<-'EOF'
		# Managed by asdf/install_asdf.sh — edits inside this block will be overwritten.
		# Completions for asdf-managed runtimes (must follow the completion module).
		zmodule asdf
EOF
  )
  # Prepend: zim modules that add to fpath (e.g. `asdf`) must be declared
  # before `zmodule completion` runs compinit. zimrc-base is sourced from
  # the dotfiles:zimfw block, so this block must precede it.
  install_managed_block --prepend "$zimrc" "$BLOCK_TAG" "$content"
  echo "$zimrc updated with asdf zmodule."
}

# Render the asdf dotfile block(s): the .zshenv exports, plus an optional
# .zimrc block when zimfw is present.
install_asdf_dotfiles() {
  install_asdf_zshenv && install_asdf_zimrc
}

# Installs asdf and its dotfile block.
# -y: accept default answers for all questions
install_asdf_wizard() {
  wizard_run "$@" -- install_asdf_program install_asdf_dotfiles
}

# Run installation if called with --wizard
wizard_main install_asdf_wizard "$@"
