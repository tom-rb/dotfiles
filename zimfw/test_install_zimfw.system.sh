#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
  . "$THISDIR/../zsh/install_zsh.sh"
  . "$THISDIR/install_zimfw.sh"
}

# @image: with-basics
it_aborts_when_zsh_is_not_installed() {
  output=$(install_zimfw_wizard 2>&1)
  assertFalse "Wizard should fail without zsh installed" $?
  assertContains "Should hint to run install_zsh" \
    "$output" "install_zsh.sh"
}

# @image: with-zsh
it_installs_zimfw_end_to_end() {
  # Prerequisite: zsh + base dotfiles
  quietly install_zsh_wizard -y

  quietly install_zimfw_wizard -y

  assertTrue "zimfw.zsh should be on disk" "is_zimfw_installed"

  zshrc="$HOME/.config/zsh/.zshrc"
  assertContains "zshrc stub should have zimfw block" \
    "$(cat "$zshrc")" "# >>> dotfiles:zimfw >>>"
  # shellcheck disable=SC2016
  assertContains "zshrc stub should source zshrc-zim" \
    "$(cat "$zshrc")" 'source "$DOTFILES/zimfw/zshrc-zim"'

  # shellcheck disable=SC2016
  assertContains ".zimrc stub should source zimrc-base" \
    "$(cat "$HOME/.config/zsh/.zimrc")" 'source "$DOTFILES/zimfw/zimrc-base"'

  # Verify zsh -ic still loads without error after zimfw is wired in
  quietly zsh -ic 'echo ok'
  assertTrue "zsh -ic should succeed with zimfw configured" $?

  # zcompdump should land under XDG_CACHE_HOME (suffixed by zsh version),
  # not in $HOME. The zstyles in zimfw/zshrc-zim relocate it there.
  cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
  assertTrue "Expected zcompdump under $cache_dir" \
    "ls $cache_dir/zcompdump-* >/dev/null 2>&1"
  assertFalse "Should not leave a stray \$HOME/.zcompdump" \
    "test -e $HOME/.zcompdump"
}

# shellcheck source=../tests/shunit2
. shunit2
