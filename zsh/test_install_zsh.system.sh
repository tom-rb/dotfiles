#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
  . "$THISDIR/install_zsh.sh"
}

it_checks_zsh_is_not_installed() {
  is_zsh_installed
  assertFalse "Expected zsh not installed" $?
}

# @image: with-basics
it_installs_zsh_and_its_dotfiles() {
  quietly install_zsh_wizard -y
  assertTrue "Expected wizard to exit 0" $?

  assertTrue "Expect zsh to be installed" "is_zsh_installed"

  assertTrue "Expect .zshenv to exist" "test -f $HOME/.zshenv"

  assertContains "Should export DOTFILES in .zshenv" \
    "$(cat "$HOME/.zshenv")" "export DOTFILES=$DOTFILES"

  # shellcheck disable=SC2016
  assertContains "Should inline ZDOTDIR export in .zshenv" \
    "$(cat "$HOME/.zshenv")" 'export ZDOTDIR=${XDG_CONFIG_HOME}/zsh'

  # Verify zsh can actually load the rendered env without errors
  output=$(zsh -c 'echo "ZDOTDIR=$ZDOTDIR DOTFILES=$DOTFILES"')
  assertContains "$output" "DOTFILES=$DOTFILES"
  assertContains "ZDOTDIR should resolve via XDG" \
    "$output" "ZDOTDIR=$HOME/.config/zsh"

  # The $ZDOTDIR/.zshrc stub should exist and source the repo base
  zshrc="$HOME/.config/zsh/.zshrc"
  assertTrue "Expect \$ZDOTDIR/.zshrc to exist" "test -f $zshrc"
  # shellcheck disable=SC2016
  assertContains "Stub should source repo .zshrc" \
    "$(cat "$zshrc")" 'source "$DOTFILES/zsh/zshrc-base"'

  # Verify zsh can load an interactive-ish shell without errors
  quietly zsh -ic 'echo ok'
  assertTrue "zsh -ic should succeed with base stub" $?

  # Verify zsh was set as the default login shell for the user
  current_shell=$(get_current_default_shell)
  assertContains "Default shell should be zsh" "$current_shell" "zsh"
}

# shellcheck source=../tests/shunit2
. shunit2
