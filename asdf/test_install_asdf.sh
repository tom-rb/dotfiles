#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
  DOTFILES="$(get_abs_path "$THISDIR/..")"
}

setUp() {
  . "$THISDIR/install_asdf.sh"
  HOME=${SHUNIT_TMPDIR:?}/home
  mkdir -p "$HOME"
  XDG_DATA_HOME=${SHUNIT_TMPDIR:?}/xdg-data
  mkdir -p "$XDG_DATA_HOME"
  XDG_CONFIG_HOME=${SHUNIT_TMPDIR:?}/xdg-config
  mkdir -p "$XDG_CONFIG_HOME"
  unset ZDOTDIR
}

tearDown() {
  cleanupSpies
  cleanupTestDir
}

#
# install_asdf_program
#

test_install_returns_true_if_asdf_is_already_installed() {
  createSpy -u -r "$SHUNIT_TRUE" is_asdf_installed
  createSpy -u wget
  createSpy -u tar

  output=$(install_asdf_program)

  assertTrue "asdf already installed should not be an error" $?
  assertContains "Should report already installed" \
    "$output" "asdf already installed"
  assertNeverCalled wget
  assertNeverCalled tar
}

test_install_downloads_and_extracts_asdf_when_not_installed() {
  createSpy -u -r "$SHUNIT_FALSE" is_asdf_installed
  createSpy -u -o "linux-amd64" detect_asdf_arch
  createSpy -u wget
  createSpy -u tar

  output=$(install_asdf_program)

  assertTrue "asdf install should not be an error" $?
  assertCalledOnceWith detect_asdf_arch
  # URL pattern: https://github.com/asdf-vm/asdf/releases/download/<ver>/asdf-<ver>-<os>-<arch>.tar.gz
  assertCalledWith wget -O "$HOME/.local/bin/asdf.tar.gz" \
    "https://github.com/asdf-vm/asdf/releases/download/v0.16.7/asdf-v0.16.7-linux-amd64.tar.gz"
  assertCalledWith tar -xzf "$HOME/.local/bin/asdf.tar.gz" -C "$HOME/.local/bin" asdf
  assertContains "Should report installed" "$output" "asdf installed"
}

#
# detect_asdf_arch
#

test_detect_arch_linux_amd64() {
  createSpy -u -o "Linux" -o "x86_64" uname
  assertEquals "linux-amd64" "$(detect_asdf_arch)"
}

test_detect_arch_darwin_arm64() {
  createSpy -u -o "Darwin" -o "arm64" uname
  assertEquals "darwin-arm64" "$(detect_asdf_arch)"
}

test_detect_arch_dies_on_unknown_os() {
  createSpy -u -o "Plan9" -o "x86_64" uname
  output=$( (detect_asdf_arch) 2>&1 )
  assertFalse "Should fail on unknown OS" $?
  assertContains "Should mention the unsupported OS" "$output" "Plan9"
}

#
# install_asdf_zshenv (block appended to $HOME/.zshenv)
#

test_zshenv_block_is_written() {
  quietly install_asdf_zshenv

  assertTrue "Should have created \$HOME/.zshenv" "test -f $HOME/.zshenv"

  contents=$(cat "$HOME/.zshenv")
  # shellcheck disable=SC2016
  assertContains "Should export ASDF_DATA_DIR off XDG_DATA_HOME" \
    "$contents" 'export ASDF_DATA_DIR=${XDG_DATA_HOME:?'
  # shellcheck disable=SC2016
  assertContains "Should prepend \$HOME/.local/bin so asdf itself is on PATH" \
    "$contents" 'export PATH=$HOME/.local/bin:$PATH'
  # shellcheck disable=SC2016
  assertContains "Should prepend the asdf shims dir to PATH" \
    "$contents" 'export PATH=$ASDF_DATA_DIR/shims:$PATH'
  assertContains "Should conditionally source the asdf java plugin loader" \
    "$contents" "set-java-home.zsh"
  assertContains "Should be wrapped in the dotfiles:asdf managed block" \
    "$contents" "dotfiles:asdf"
}

#
# install_asdf_zimrc
#

test_zimrc_block_is_written_when_zimrc_exists() {
  zdotdir="$XDG_CONFIG_HOME/zsh"
  mkdir -p "$zdotdir"
  # Mimic the .zimrc stub install_zimfw_zdotdir_stub leaves on disk: a
  # managed block sourcing the repo zimrc-base. Plain text would trip
  # install_managed_block's first-time placement prompt.
  cat >"$zdotdir/.zimrc" <<-'EOF'
		# >>> dotfiles:zimfw >>>
		source "$DOTFILES/zimfw/zimrc-base"
		# <<< dotfiles:zimfw <<<
EOF

  quietly install_asdf_zimrc

  contents=$(cat "$zdotdir/.zimrc")
  assertContains "Should wrap the line in the dotfiles:asdf managed block" \
    "$contents" "dotfiles:asdf"
  assertContains "Should declare the zim asdf module" \
    "$contents" "zmodule asdf"
  assertContains "Should preserve the pre-existing zimfw managed block" \
    "$contents" "dotfiles:zimfw"
  # The asdf module adds to fpath; its declaration must precede zmodule
  # completion (sourced via the dotfiles:zimfw block).
  asdf_pos=$(grep -n "dotfiles:asdf" "$zdotdir/.zimrc" | head -1 | cut -d: -f1)
  zimfw_pos=$(grep -n "dotfiles:zimfw" "$zdotdir/.zimrc" | head -1 | cut -d: -f1)
  assertTrue "asdf block should appear before the zimfw block" \
    "[ $asdf_pos -lt $zimfw_pos ]"
}

test_zimrc_block_is_skipped_when_zimrc_missing() {
  zdotdir="$XDG_CONFIG_HOME/zsh"

  output=$(install_asdf_zimrc)

  assertTrue "Should not error when .zimrc is absent" $?
  assertFalse "Should not create a .zimrc out of thin air" \
    "test -e $zdotdir/.zimrc"
  assertContains "Should note that zimfw isn't installed" \
    "$output" "zimfw not installed"
}

SHPY_PATH="$THISDIR/../tests/shpy"
export SHPY_PATH
. "$THISDIR/../tests/shpy"
. "$THISDIR/../tests/shpy-shunit2"
. "$THISDIR/../tests/shunit2"
