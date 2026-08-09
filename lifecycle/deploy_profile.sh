#!/usr/bin/env sh

#
# The deploy profile
#
# Where the answer map in utils/answers.sh is kept between runs, so a deploy
# can replay the last one. The map itself is a shared utility; only its
# persistence belongs to the deploy lifecycle.

# Replace $DOTFILES_ANSWERS with the answers recorded in the profile.
# A missing profile yields no answers, which is how a first deploy comes to ask
# everything — not a failure.
load_deploy_profile() {
  local path line answers
  path=$(get_deploy_profile_path)
  answers=''
  DOTFILES_ANSWERS=''
  [ -f "$path" ] || return 0
  # `|| [ -n "$line" ]` keeps a final line that has no newline after it: read
  # reports failure there, having already filled $line.
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*) continue ;;
    esac
    answers="${answers}${answers:+ }$line"
  done < "$path"
  DOTFILES_ANSWERS=$answers
}

# Write $DOTFILES_ANSWERS to the profile, one answer per line.
# Warns instead of dying if it cannot write. This runs at the end of a deploy,
# and an unwritable state directory should not turn a successful install into
# a failure.
save_deploy_profile() {
  local path entry reglob
  path=$(get_deploy_profile_path)
  if ! mkdir -p "${path%/*}" 2>/dev/null; then
    tui_warn "Couldn't save the deploy profile to $(tui_path "$path")"
    return 0
  fi
  # 2>/dev/null comes first on purpose: redirections are applied left to right,
  # so silencing stderr before opening $path is what keeps the shell's own
  # "cannot create" line out of a deploy that otherwise succeeded.
  case $- in *f*) reglob='' ;; *) reglob=yes; set -f ;; esac
  {
    # shellcheck disable=SC2086
    for entry in $DOTFILES_ANSWERS; do
      printf '%s\n' "$entry"
    done
  } 2>/dev/null > "$path" || tui_warn "Couldn't save the deploy profile to $(tui_path "$path")"
  [ -z "$reglob" ] || set +f
  return 0
}
