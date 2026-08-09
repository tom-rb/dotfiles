#!/usr/bin/env sh

# Installing a JSON settings file the user also edits. A harness writes its own
# settings.json from inside the app, so the repo owns the keys its template
# names and leaves every other key alone. merge_json.py does the merging; the
# helpers here render the template, place the result, and report what changed.

# Make sure python3 is available. merge_json.py needs it on every deploy that
# installs a JSON settings file.
ensure_python3_installed() {
  if command_exists python3; then
    tui_skip "python3 already installed"
    return 0
  fi
  check_supported_pm || die "python3 is required to merge JSON settings."
  install_from_pm --as python3 --die "Couldn't install python3" -- python3
}

# Expand $DOTFILES in a settings template, so a value can name a file in this
# checkout. Echoes the path of a temp file, which the caller removes. Returns 1
# without echoing anything if it cannot write the file.
# $1: template path
render_settings_template() {
  local template out escaped
  template="${1:?}"
  out=$(mktemp) || return 1
  # A replacement carries its own syntax: '&' repeats the match and the
  # delimiter ends it. Escape both, and the backslash that escapes them.
  escaped=$(printf '%s' "${DOTFILES:?}" | sed 's,[\\&#],\\&,g')
  # '#' is the delimiter, because the replacement is a path full of slashes. The
  # pattern is single-quoted, so the shell keeps the literal $DOTFILES.
  if ! sed 's#[$]DOTFILES#'"$escaped"'#g' "$template" > "$out"; then
    rm -f "$out"
    return 1
  fi
  printf '%s\n' "$out"
}

# Name the keys the template just overwrote. A harness writes settings.json from
# inside the app. Without this report, the next deploy reverts a setting you
# changed there and says nothing.
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

# Merge a settings template into the machine's settings file. Keys the template
# does not name survive untouched. The template wins on every key it does name.
# $1: template path
# $2: target settings file
# $3: label for the messages, such as "claude"
install_json_settings() {
  local template target label config_dir rendered merged drift status backup
  template="${1:?}"
  target="${2:?}"
  label="${3:?}"
  config_dir=$(dirname "$target")

  mkdir -p "$config_dir" || die "Could not create $(tui_path "$config_dir")"

  rendered=$(render_settings_template "$template") \
    || die "Could not render the $label settings template"
  # Keep the temp file next to the target, not in /tmp. The mv below is then a
  # rename on one filesystem, and it never leaves a partial settings.json.
  merged=$(mktemp "$target.XXXXXX") || die "Could not create a temporary file"

  drift=$(python3 "${DOTFILES:?}/utils/merge_json.py" "$rendered" "$target" "$merged")
  status=$?
  rm -f "$rendered"

  case "$status" in
    3)
      rm -f "$merged"
      tui_skip "$label settings already up to date"
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
      tui_ok "$label settings written to $(tui_path "$target")"
      [ -n "$backup" ] && tui_detail "Backed up the old one as $(tui_path "$backup")"
      report_settings_drift "$drift"
      ;;
    *)
      rm -f "$merged"
      die "Could not merge the $label settings into $(tui_path "$target")"
      ;;
  esac
  return 0
}
