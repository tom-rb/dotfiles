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

# Make sure python3 is available. merge_json.py needs it now, and statusline.py
# needs it each time Claude Code draws the status line.
ensure_python3_installed() {
  if command_exists python3; then
    tui_skip "python3 already installed"
    return 0
  fi
  check_supported_pm || die "python3 is required by the claude configs."
  install_from_pm --as python3 --die "Couldn't install python3" -- python3
}

#
# Settings
#

# Expand $DOTFILES in the settings template. statusLine.command then names this
# checkout's statusline.py. Echoes the path of a temp file, which the caller
# removes. Returns 1 without echoing anything if it cannot write the file.
render_settings_template() {
  local out escaped
  out=$(mktemp) || return 1
  # A replacement carries its own syntax: '&' repeats the match and the
  # delimiter ends it. Escape both, and the backslash that escapes them.
  escaped=$(printf '%s' "${DOTFILES:?}" | sed 's,[\\&#],\\&,g')
  # '#' is the delimiter, because the replacement is a path full of slashes. The
  # pattern is single-quoted, so the shell keeps the literal $DOTFILES.
  if ! sed 's#[$]DOTFILES#'"$escaped"'#g' "${DOTFILES:?}/claude/settings.json" > "$out"; then
    rm -f "$out"
    return 1
  fi
  printf '%s\n' "$out"
}

# Name the keys the template just overwrote. Claude Code's own /config writes
# straight to settings.json. Without this report, the next deploy reverts a
# setting you changed in the app and says nothing.
# $1: merge_json.py's report, one "path: old -> new" line per key
report_settings_drift() {
  local line
  [ -n "${1:-}" ] || return 0
  tui_warn 'The template overwrote settings changed on this machine:'
  printf '%s\n' "$1" | while IFS= read -r line; do
    tui_detail "$line"
  done
  return 0
}

# Merge the settings template into the machine's settings.json. Keys the
# template does not name survive untouched: model, effortLevel, and anything
# else set inside Claude Code. The template wins on every key it does name.
install_claude_settings() {
  local config_dir target rendered merged drift status backup
  config_dir=$(get_claude_config_dir)
  target="$config_dir/settings.json"

  mkdir -p "$config_dir" || die "Could not create $(tui_path "$config_dir")"

  rendered=$(render_settings_template) \
    || die "Could not render the claude settings template"
  # Keep the temp file next to the target, not in /tmp. The mv below is then a
  # rename on one filesystem, and it never leaves a partial settings.json.
  merged=$(mktemp "$target.XXXXXX") || die "Could not create a temporary file"

  drift=$(python3 "${DOTFILES:?}/claude/merge_json.py" "$rendered" "$target" "$merged")
  status=$?
  rm -f "$rendered"

  case "$status" in
    3)
      rm -f "$merged"
      tui_skip "claude settings already up to date"
      ;;
    2)
      backup=$(backup_file "$target") || die "Could not back up $(tui_path "$target")"
      mv "$merged" "$target" || die "Could not write $(tui_path "$target")"
      tui_warn "Replaced unreadable $(tui_path "$target")"
      tui_detail "Kept the old one as $(tui_path "$backup")"
      ;;
    0)
      backup=''
      if [ -f "$target" ]; then
        backup=$(backup_file "$target") || die "Could not back up $(tui_path "$target")"
      fi
      mv "$merged" "$target" || die "Could not write $(tui_path "$target")"
      tui_ok "claude settings written to $(tui_path "$target")"
      [ -n "$backup" ] && tui_detail "Backed up the old one as $(tui_path "$backup")"
      report_settings_drift "$drift"
      ;;
    *)
      rm -f "$merged"
      die "Could not merge the claude settings into $(tui_path "$target")"
      ;;
  esac
  return 0
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

  ask_install_mode "skills and rules" mode || {
    tui_skip "skills and rules left alone"
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
      tui_skip "skills and rules left alone"
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
