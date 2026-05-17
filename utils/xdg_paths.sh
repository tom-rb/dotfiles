#!/usr/bin/env sh

# XDG Base Directory + tool-path resolvers.
#
# Path segments are exposed as variables so both the sh-side helpers below
# AND the zsh code that install_zsh_zshenv inlines into $HOME/.zshenv pull
# from the same constants — no "keep these in sync" lockstep.

XDG_CONFIG_DEFAULT_SUBPATH=.config
XDG_DATA_DEFAULT_SUBPATH=.local/share
XDG_CACHE_DEFAULT_SUBPATH=.cache
ZDOTDIR_SUBPATH=zsh
ZIM_HOME_SUBPATH=zim
TMUX_PLUGINS_SUBPATH=tmux/plugins

xdg_config_home() { echo "${XDG_CONFIG_HOME:-$HOME/$XDG_CONFIG_DEFAULT_SUBPATH}"; }
xdg_data_home()   { echo "${XDG_DATA_HOME:-$HOME/$XDG_DATA_DEFAULT_SUBPATH}"; }
xdg_cache_home()  { echo "${XDG_CACHE_HOME:-$HOME/$XDG_CACHE_DEFAULT_SUBPATH}"; }

# $ZDOTDIR (where zsh reads .zshrc, .zlogin, etc.)
get_zdotdir() { echo "${ZDOTDIR:-$(xdg_config_home)/$ZDOTDIR_SUBPATH}"; }

# $ZIM_HOME (where the zimfw framework lives)
get_zim_home() { echo "${ZIM_HOME:-$(xdg_config_home)/$ZIM_HOME_SUBPATH}"; }

# Tmux plugin manager directory (TPM + each @plugin clone)
get_tmux_plugins_dir() { echo "$(xdg_data_home)/$TMUX_PLUGINS_SUBPATH"; }
