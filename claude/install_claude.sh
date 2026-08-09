#!/usr/bin/env sh

# shellcheck source=../utils/utils.sh
. "${DOTFILES:?}/utils/utils.sh"

# Check if the Claude Code CLI is installed.
is_claude_installed() {
  command_exists claude
}

# Report whether Claude Code is installed. A missing Claude Code is not an
# error, because the settings are valid before the install.
report_claude_install() {
  if is_claude_installed; then
    tui_ok "claude $(claude --version 2>/dev/null | head -n1) found"
  else
    tui_warn "claude is not on PATH"
    tui_detail 'Configuring anyway, ready for whenever you install it.'
  fi
  return 0
}

#
# Settings
#

# Merge the settings template into the machine's settings.json. Keys the
# template does not name survive untouched: model, effortLevel, and anything
# else set inside Claude Code. The template wins on every key it does name.
install_claude_settings() {
  install_json_settings "${DOTFILES:?}/claude/settings.json" \
    "$(get_claude_config_dir)/settings.json" claude
}

#
# Skills and rules
#

# Install the skills and rules this repo ships into Claude Code's user-level
# directories. pi's skills land here too, because Claude Code does not read
# ~/.agents/skills. This module owns ~/.claude/skills outright. If two modules
# pruned one directory, each would remove the other's links on every deploy.
install_claude_skills_and_rules() {
  local mode policy collisions duplicates
  local skills_src pi_skills_src rules_src skills_dest rules_dest
  skills_src="${DOTFILES:?}/claude/skills"
  pi_skills_src="${DOTFILES:?}/pi/skills"
  rules_src="${DOTFILES:?}/claude/rules"
  skills_dest=$(get_claude_skills_dir)
  rules_dest=$(get_claude_rules_dir)

  # Two sources share this destination. A name shipped by both would make each
  # install undo the other. That is a packaging mistake, not a machine state, so
  # the deploy stops here. The installer does not choose a winner.
  duplicates=$(duplicate_entry_names "$skills_src" "$pi_skills_src")
  [ -z "$duplicates" ] \
    || die "claude/skills and pi/skills both ship: $duplicates"

  # The prune comes first when there is nothing left to install. A repo that
  # dropped its last skill must still remove the links it made.
  if [ -z "$(entry_names "$skills_src" "$pi_skills_src" "$rules_src")" ]; then
    prune_owned_entries "$skills_dest" '' "$skills_src" "$pi_skills_src"
    prune_owned_entries "$rules_dest" '' "$rules_src"
    tui_skip "No skills or rules to install"
    return 0
  fi

  ask_install_mode claude_skills "skills and rules" mode || {
    tui_warn "skills and rules installation interrupted"
    return 1
  }

  # The installer scans every source before it installs anything. The user sees
  # the whole picture once, and answers once.
  collisions=$(
    list_collisions "$skills_src" "$skills_dest" "$mode"
    list_collisions "$pi_skills_src" "$skills_dest" "$mode"
    list_collisions "$rules_src" "$rules_dest" "$mode"
  )
  policy=backup
  if [ -n "$collisions" ]; then
    ask_collision_policy "$collisions" policy || {
      tui_warn "skills and rules left in place, installation interrupted"
      return 1
    }
  fi

  mkdir -p "$skills_dest" "$rules_dest" \
    || die "Could not create $(tui_path "$(get_claude_config_dir)")"

  install_entries "$skills_src" "$skills_dest" "$mode" "$policy" || return 1
  install_entries "$pi_skills_src" "$skills_dest" "$mode" "$policy" || return 1
  install_entries "$rules_src" "$rules_dest" "$mode" "$policy" || return 1

  prune_owned_entries "$skills_dest" "$(entry_names "$skills_src" "$pi_skills_src")" \
    "$skills_src" "$pi_skills_src"
  prune_owned_entries "$rules_dest" "$(entry_names "$rules_src")" "$rules_src"
}

# Configures Claude Code with the dotfiles' settings, status line, skills and
# rules.
# -y: accepts default answer for all questions
install_claude_wizard() {
  wizard_run "$@" -- report_claude_install ensure_python3_installed \
    install_claude_settings install_claude_skills_and_rules
}

# Run installation if called with --wizard
wizard_main install_claude_wizard "$@"
