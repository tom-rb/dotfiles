#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
  . "$THISDIR/install_tmux.sh"
}

it_checks_tmux_is_not_installed() {
  is_tmux_installed
  assertFalse "Expected tmux not installed" $?
}

it_reads_available_tmux_package_version() {
  version=$(get_tmux_package_version)
  echo "$version" | grep -qE '^[0-9]\.[0-9][abc]?$'
  assertTrue "Expected a tmux version, got <$version>" $?
}

# @image: with-basics
it_reads_current_tmux_release_version() {
  version=$(get_tmux_release_version)
  echo "$version" | grep -qE '^[0-9]\.[0-9][abc]?$'
  assertTrue "Expected a tmux version, got <$version>" $?
}

# @image: with-basics
it_installs_tmux_from_source_to_specified_location() {
  version=$(get_tmux_release_version)
  prefix="$HOME/apps/tmux"

  quietly install_tmux_from_source "$version" "$prefix"
  assertTrue "Expected no error on installing tmux" $?

  command -v "$prefix/bin/tmux" >/dev/null
  assertTrue "Expected tmux to be installed" $?
}

# @image: with-zsh
it_installs_tmux_and_its_dotfiles() {
  quietly install_tmux_wizard -y
  assertTrue "Expected wizard to exit 0" $?

  assertTrue "Expect tmux to be installed" "is_tmux_installed"

  # Check wrapper-set user options are visible to tmux at startup
  output=$(tmux start \; show -g @user_conf \; show -g @theme_conf)
  assertContains "$output" "@user_conf"
  assertContains "$output" "@theme_conf"
  assertContains "$output" "/tmux/tmux.conf"
  assertContains "$output" "/tmux/theme.conf"
}

# Regression: tmux must resolve its plugin manager path even when the login
# shell does not export XDG_DATA_HOME (i.e. when install_zsh never ran).
# @image: with-tmux
it_resolves_tmux_plugin_manager_path_without_xdg_data_home_in_env() {
  unset XDG_DATA_HOME
  quietly install_tmux_wizard -y
  assertTrue "Expected wizard to exit 0" $?

  output=$(tmux start \; show-environment -g TMUX_PLUGIN_MANAGER_PATH)
  assertContains "Should bake absolute path under HOME default" \
    "$output" "$HOME/.local/share/tmux/plugins"
}

# @image: with-tmux
it_installs_tpm_and_materializes_declared_plugins() {
  quietly install_tmux_wizard -y
  assertTrue "Expected wizard to exit 0" $?

  plugins_dir="$HOME/.local/share/tmux/plugins"
  assertTrue "Expected TPM script at <plugins>/tpm/tpm" \
    "test -x $plugins_dir/tpm/tpm"
  # tmux-resurrect is declared in tmux/tmux.conf as a @plugin; install_plugins
  # should have materialized it into the plugins dir.
  assertTrue "Expected tmux-resurrect plugin dir to be populated" \
    "test -d $plugins_dir/tmux-resurrect"
}

# shellcheck source=../tests/shunit2
. shunit2