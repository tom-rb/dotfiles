#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
  . "$THISDIR/install_asdf.sh"
}

it_checks_asdf_is_not_installed() {
  is_asdf_installed
  assertFalse "Expected asdf not installed" $?
}

# @image: with-zsh
it_installs_asdf_and_its_dotfiles() {
  # The asdf zshenv block references $XDG_DATA_HOME, defined by the zsh
  # installer's earlier block in the same file.
  quietly sh "$DOTFILES/zsh/install_zsh.sh" --wizard
  assertTrue "Expected zsh wizard to exit 0" $?
  quietly install_asdf_wizard -y
  assertTrue "Expected asdf wizard to exit 0" $?

  assertTrue "Expect asdf binary at \$HOME/.local/bin/asdf" \
    "test -x $HOME/.local/bin/asdf"

  contents=$(cat "$HOME/.zshenv")
  assertContains "Should write the dotfiles:asdf managed block" \
    "$contents" "dotfiles:asdf"
  # shellcheck disable=SC2016
  assertContains "Should export ASDF_DATA_DIR" \
    "$contents" 'export ASDF_DATA_DIR="${XDG_DATA_HOME'

  # Verify zsh resolves `asdf` via the PATH set up by our managed block
  output=$(zsh -c 'type -a asdf')
  assertContains "zsh should resolve asdf from .local/bin" \
    "$output" "$HOME/.local/bin/asdf"

  # And the binary actually runs
  output=$("$HOME/.local/bin/asdf" --version)
  assertContains "asdf --version should report the pinned version" \
    "$output" "0.16.7"
}

# @image: with-zsh
it_skips_zimrc_block_when_zimfw_is_not_installed() {
  quietly sh "$DOTFILES/zsh/install_zsh.sh" --wizard
  assertTrue "Expected zsh wizard to exit 0" $?
  output=$(install_asdf_wizard -y)

  assertContains "Should announce the skip" "$output" "zimfw not installed"

  zdotdir="$HOME/.config/zsh"
  assertFalse "Should not create a .zimrc out of thin air" \
    "test -e $zdotdir/.zimrc"
}

# @image: with-zsh
it_adds_zmodule_asdf_to_zimrc_when_zimfw_is_installed() {
  quietly sh "$DOTFILES/zsh/install_zsh.sh" --wizard
  assertTrue "Expected zsh wizard to exit 0" $?
  quietly sh "$DOTFILES/zimfw/install_zimfw.sh" --wizard
  assertTrue "Expected zimfw wizard to exit 0" $?
  quietly install_asdf_wizard -y
  assertTrue "Expected asdf wizard to exit 0" $?

  zdotdir="$HOME/.config/zsh"
  contents=$(cat "$zdotdir/.zimrc")
  assertContains "Should add the dotfiles:asdf managed block to .zimrc" \
    "$contents" "dotfiles:asdf"
  assertContains "Should declare zmodule asdf" \
    "$contents" "zmodule asdf"
  assertContains "Should keep the pre-existing dotfiles:zimfw block" \
    "$contents" "dotfiles:zimfw"

  # Next zsh startup should auto-reinit zim (since .zimrc is now newer than
  # init.zsh) and install the asdf module without error.
  quietly zsh -ic 'true'
  assertTrue "zsh should start cleanly with the new zmodule asdf line" $?
}

# shellcheck source=../tests/shunit2
. shunit2
