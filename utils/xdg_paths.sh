#!/usr/bin/env sh

# XDG Base Directory + tool-path resolvers.
#
# Path segments are exposed as variables so both the sh-side helpers below
# AND the zsh code that install_zsh_zshenv inlines into $HOME/.zshenv pull
# from the same constants.

XDG_CONFIG_DEFAULT_SUBPATH=.config
XDG_DATA_DEFAULT_SUBPATH=.local/share
XDG_CACHE_DEFAULT_SUBPATH=.cache
ZDOTDIR_SUBPATH=zsh
ZIM_HOME_SUBPATH=zim
TMUX_PLUGINS_SUBPATH=tmux/plugins
AGENTS_SKILLS_SUBPATH=.agents/skills

xdg_config_home() { echo "${XDG_CONFIG_HOME:-$HOME/$XDG_CONFIG_DEFAULT_SUBPATH}"; }
xdg_data_home()   { echo "${XDG_DATA_HOME:-$HOME/$XDG_DATA_DEFAULT_SUBPATH}"; }
xdg_cache_home()  { echo "${XDG_CACHE_HOME:-$HOME/$XDG_CACHE_DEFAULT_SUBPATH}"; }

# $ZDOTDIR (where zsh reads .zshrc, .zlogin, etc.)
get_zdotdir() { echo "${ZDOTDIR:-$(xdg_config_home)/$ZDOTDIR_SUBPATH}"; }

# $ZIM_HOME (where the zimfw framework lives)
get_zim_home() { echo "${ZIM_HOME:-$(xdg_config_home)/$ZIM_HOME_SUBPATH}"; }

# Tmux plugin manager directory (TPM + each @plugin clone)
get_tmux_plugins_dir() { echo "$(xdg_data_home)/$TMUX_PLUGINS_SUBPATH"; }

# Claude Code's config directory. Claude Code ignores XDG and reads
# $HOME/.claude, unless CLAUDE_CONFIG_DIR gives another path.
get_claude_config_dir() { echo "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; }

# Claude Code's user-level skills directory. Claude Code finds every
# subdirectory that holds a SKILL.md, and its name is the command it answers to.
get_claude_skills_dir() { echo "$(get_claude_config_dir)/skills"; }

# Claude Code's user-level rules directory. Claude Code loads it ahead of a
# project's own.
get_claude_rules_dir() { echo "$(get_claude_config_dir)/rules"; }

# The cross-harness skills directory pi reads. Claude Code does not look here,
# so the installer puts a skill meant for both agents in each harness's own
# directory.
get_agents_skills_dir() { echo "$HOME/$AGENTS_SKILLS_SUBPATH"; }
