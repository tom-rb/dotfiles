#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  # shellcheck source=../tests/utils_for_test.sh
  . "$THISDIR/../tests/utils_for_test.sh"
  # shellcheck source=install_zsh.sh
  . "$THISDIR/install_zsh.sh"
}

it_checks_zsh_is_not_installed() {
  is_zsh_installed
  assertFalse "Expected zsh not installed" $?
}

# @image: with-basics
it_installs_zsh_and_its_dotfiles() {
  quietly install_zsh_wizard -y

  assertTrue "Expect zsh to be installed" "is_zsh_installed"

  assertTrue "Expect .zshenv to exist" "test -f $HOME/.zshenv"

  assertContains "Should export DOTFILES in .zshenv" \
    "$(cat "$HOME/.zshenv")" "export DOTFILES=$DOTFILES"

  # shellcheck disable=SC2016
  assertContains "Should source zshenv-base in .zshenv" \
    "$(cat "$HOME/.zshenv")" 'source "$DOTFILES/zsh/zshenv-base"'

  # Verify zsh can actually load the rendered env without errors
  output=$(zsh -c 'echo "ZDOTDIR=$ZDOTDIR DOTFILES=$DOTFILES"')
  assertContains "$output" "DOTFILES=$DOTFILES"
  assertContains "$output" "ZDOTDIR=$DOTFILES/zsh"

  # Verify zsh was set as the default login shell for the user
  current_shell=$(get_current_default_shell)
  assertContains "Default shell should be zsh" "$current_shell" "zsh"
}

# shellcheck source=../tests/shunit2
. shunit2
