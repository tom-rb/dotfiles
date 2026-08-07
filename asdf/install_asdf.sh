#!/usr/bin/env sh

# shellcheck source=../utils/utils.sh
. "${DOTFILES:?}/utils/utils.sh"
# shellcheck source=activate.sh
. "${DOTFILES:?}/asdf/activate.sh"

ASDF_BLOCK_TAG="dotfiles:asdf"

# Pinned asdf release. Bump deliberately.
ASDF_VERSION="0.16.7"
# SHA-256 of each asdf-v${ASDF_VERSION}-<arch>.tar.gz upstream publishes for an
# arch detect_asdf_arch can return. Bump them all with the version.
ASDF_SHA256_LINUX_AMD64='6a5f56833da9e94068f3e70d5ca6ffe0a14a0887e1eac1b9b0c96f67d96242be'
ASDF_SHA256_LINUX_ARM64='a4904347dd1a468b4947fe1e22458742c89da27df589a324172bb8154229dea7'
ASDF_SHA256_DARWIN_AMD64='0d989891f40d2dbea8de41f3166603df530f1dfe97cb460a3044ded0e9756001'
ASDF_SHA256_DARWIN_ARM64='8a54d4426da75a49c57f670ccafafcc4cd0709d31e033b357bd01d19101b3e64'

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

# Pinned SHA-256 of the release tarball for the os-arch slug $1.
# Dies when the slug has no pinned digest — an arch added to detect_asdf_arch
# without one would otherwise install unverified.
asdf_sha256_for() {
  case "${1:?}" in
    linux-amd64)  echo "$ASDF_SHA256_LINUX_AMD64" ;;
    linux-arm64)  echo "$ASDF_SHA256_LINUX_ARM64" ;;
    darwin-amd64) echo "$ASDF_SHA256_DARWIN_AMD64" ;;
    darwin-arm64) echo "$ASDF_SHA256_DARWIN_ARM64" ;;
    *) die "No pinned checksum for asdf ${ASDF_VERSION} on $1" ;;
  esac
}

# Check if asdf is installed
is_asdf_installed() {
  command_exists asdf || [ -x "$(asdf_bin_dir)/asdf" ]
}

# Version of the installed asdf (`asdf version v0.16.7` -> 0.16.7).
get_asdf_version() {
  local bin
  bin=$(command -v asdf) || bin="$(asdf_bin_dir)/asdf"
  [ -x "$bin" ] || return 0
  "$bin" --version 2>/dev/null | awk '{print $NF}' | sed 's/^v//'
}

# Installs asdf by downloading the official release tarball into
# $HOME/.local/bin. PM install is intentionally skipped — see
# docs/adr/0002-install-asdf-from-tarball.md.
install_asdf_program() {
  local arch url bin_dir tarball version sha256
  (
    set -e
    if is_asdf_installed; then
      version=$(get_asdf_version)
      tui_skip "asdf${version:+ $version} already installed"
      return 0
    fi

    arch=$(detect_asdf_arch)
    # Resolved before the download so an unpinned arch fails without one.
    sha256=$(asdf_sha256_for "$arch")
    url="https://github.com/asdf-vm/asdf/releases/download/v${ASDF_VERSION}/asdf-v${ASDF_VERSION}-${arch}.tar.gz"
    bin_dir="$(asdf_bin_dir)"
    tarball="$bin_dir/asdf.tar.gz"

    tui_step "downloading asdf ${ASDF_VERSION}…"
    mkdir -p "$bin_dir"
    # -q hides wget's own diagnostics too, so say why the download failed here.
    wget -q -O "$tarball" "$url" || die "Couldn't download asdf ${ASDF_VERSION} from $url"
    if ! verify_sha256 "$tarball" "$sha256"; then
      rm -f "$tarball"
      die "Checksum mismatch for asdf ${ASDF_VERSION} (${arch}), refusing to install it"
    fi
    tar -xzf "$tarball" -C "$bin_dir" asdf || die "Couldn't unpack asdf ${ASDF_VERSION}"
    rm -f "$tarball"

    version=$(get_asdf_version)
    tui_ok "asdf${version:+ $version} installed"
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
    # Unquoted heredoc: the path *segments* are interpolated now from the shared
    # constants in activate.sh, while zsh-runtime vars stay escaped (\$) so zsh
    # expands them at login.
    content=$(cat <<-EOF
			# Managed by asdf/install_asdf.sh — edits inside this block will be overwritten.
			export ASDF_DATA_DIR="\${XDG_DATA_HOME:?'XDG_DATA_HOME is not set, have you run the zsh setup?'}/$ASDF_DATA_SUBPATH"
			export PATH="\$HOME/$ASDF_BIN_SUBPATH:\$PATH"
			export PATH="\$ASDF_DATA_DIR/$ASDF_SHIMS_SUBPATH:\$PATH"
			[[ -r "\$ASDF_DATA_DIR/plugins/java/set-java-home.zsh" ]] && source "\$ASDF_DATA_DIR/plugins/java/set-java-home.zsh"
EOF
    )
    install_managed_block --as "$(tui_path "$zshenv") (asdf block)" \
      "$zshenv" "$ASDF_BLOCK_TAG" "$content"
  )
}

# Write the zim `asdf` module declaration into $ZDOTDIR/.zimrc, so zimfw
# initializes asdf completions after compinit. Skipped when .zimrc is absent
# (zimfw not installed) — the asdf binary + .zshenv block work standalone.
install_asdf_zimrc() {
  local zdotdir zimrc content
  (
    set -e
    zdotdir=$(get_zdotdir)
    zimrc="$zdotdir/.zimrc"
    if [ ! -f "$zimrc" ]; then
      tui_skip "zimfw not installed; skipping asdf completions"
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
    install_managed_block --prepend --as "$(tui_path "$zimrc") (asdf zmodule)" \
      "$zimrc" "$ASDF_BLOCK_TAG" "$content"
  )
}

# Render the asdf dotfile block(s): the .zshenv exports, plus an optional
# .zimrc block when zimfw is present.
install_asdf_dotfiles() {
  (
    set -e
    install_asdf_zshenv
    install_asdf_zimrc
  )
}

# Installs asdf and its dotfile block.
# -y: accepts default answer for all questions
install_asdf_wizard() {
  wizard_run "$@" -- install_asdf_program install_asdf_dotfiles
}

# Run installation if called with --wizard
wizard_main install_asdf_wizard "$@"
