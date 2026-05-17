#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
  # shellcheck disable=SC2034
  DOTFILES="$(get_abs_path "$THISDIR/..")"
}

setUp() {
  . "$THISDIR/xdg_paths.sh"
  HOME=${SHUNIT_TMPDIR:?}/home
  mkdir -p "$HOME"
  unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME ZDOTDIR ZIM_HOME
}

tearDown() {
  cleanupSpies
  cleanupTestDir
}

#
# XDG primitives
#

test_xdg_config_home_defaults_to_dot_config() {
  assertEquals "$HOME/.config" "$(xdg_config_home)"
}

test_xdg_config_home_honors_env_override() {
  XDG_CONFIG_HOME=/custom/cfg
  assertEquals "/custom/cfg" "$(xdg_config_home)"
}

test_xdg_data_home_defaults_to_local_share() {
  assertEquals "$HOME/.local/share" "$(xdg_data_home)"
}

test_xdg_data_home_honors_env_override() {
  XDG_DATA_HOME=/custom/data
  assertEquals "/custom/data" "$(xdg_data_home)"
}

test_xdg_cache_home_defaults_to_dot_cache() {
  assertEquals "$HOME/.cache" "$(xdg_cache_home)"
}

test_xdg_cache_home_honors_env_override() {
  XDG_CACHE_HOME=/custom/cache
  assertEquals "/custom/cache" "$(xdg_cache_home)"
}

#
# Tool-path helpers
#

test_get_zdotdir_defaults_to_xdg_config_zsh() {
  assertEquals "$HOME/.config/zsh" "$(get_zdotdir)"
}

test_get_zdotdir_honors_zdotdir_env() {
  ZDOTDIR=/custom/zdot
  assertEquals "/custom/zdot" "$(get_zdotdir)"
}

test_get_zdotdir_follows_xdg_config_home_override() {
  XDG_CONFIG_HOME=/custom/cfg
  assertEquals "/custom/cfg/zsh" "$(get_zdotdir)"
}

test_get_zim_home_defaults_to_xdg_config_zim() {
  assertEquals "$HOME/.config/zim" "$(get_zim_home)"
}

test_get_zim_home_honors_zim_home_env() {
  ZIM_HOME=/custom/zim
  assertEquals "/custom/zim" "$(get_zim_home)"
}

test_get_tmux_plugins_dir_defaults_to_xdg_data_tmux_plugins() {
  assertEquals "$HOME/.local/share/tmux/plugins" "$(get_tmux_plugins_dir)"
}

test_get_tmux_plugins_dir_follows_xdg_data_home_override() {
  XDG_DATA_HOME=/custom/data
  assertEquals "/custom/data/tmux/plugins" "$(get_tmux_plugins_dir)"
}


# Run tests
SHPY_PATH="$THISDIR/../tests/shpy"
export SHPY_PATH
. "$THISDIR/../tests/shpy"
. "$THISDIR/../tests/shpy-shunit2"
. "$THISDIR/../tests/shunit2"
