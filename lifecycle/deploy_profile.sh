#!/usr/bin/env sh

#
# The answer map
#
# $DOTFILES_ANSWERS is a space-separated `key=y|n` map. Each loop below splits
# it on spaces, so it disables globbing first and restores it after: a `*` in
# the map would otherwise expand against the working directory.

# Echo the answer recorded for key $1, `y` or `n`.
# Returns 1 when the key has no recorded answer, which is what makes a prompt
# nobody has answered yet fall through to stdin.
# $1: answer key
answer_for() {
  local key entry
  key=${1:?}
  # A subshell rather than the save-and-restore the others use: this loop
  # returns from inside itself, and a subshell drops `set -f` on its own.
  (
    set -f
    # shellcheck disable=SC2086
    for entry in $DOTFILES_ANSWERS; do
      case "$entry" in
        "$key"=*) printf '%s\n' "${entry#*=}"; exit 0 ;;
      esac
    done
    exit 1
  )
}

# Record answer $2 for key $1, replacing any answer already held for it.
# An empty key records nothing. Otherwise it would leave an entry no prompt
# can claim, which validate_answers would then reject on the next run.
# $1: answer key (may be empty)
# $2: y or n
record_answer() {
  local key value entry kept reglob
  key=${1?} value=${2:?}
  [ -n "$key" ] || return 0
  kept=''
  case $- in *f*) reglob='' ;; *) reglob=yes; set -f ;; esac
  # shellcheck disable=SC2086
  for entry in $DOTFILES_ANSWERS; do
    case "$entry" in
      "$key"=*) ;;
      *) kept="${kept}${kept:+ }$entry" ;;
    esac
  done
  DOTFILES_ANSWERS="${kept}${kept:+ }$key=$value"
  [ -z "$reglob" ] || set +f
}

# True when key $1 is one of the space-separated declared keys $2.
# Called only from a loop that has already disabled globbing, so this does not
# disable it again — a nested save-and-restore would restore the wrong state.
# The key may be empty. An empty one is simply undeclared, so an entry like
# `=y` reaches the caller's own reporting instead of aborting the shell here.
# $1: key  $2: declared keys
_is_declared_key() {
  local key declared candidate
  key=${1?} declared=${2:?}
  # shellcheck disable=SC2086
  for candidate in $declared; do
    [ "$candidate" = "$key" ] && return 0
  done
  return 1
}

# True when answer $1 reads as y or n.
# $1: one `key=value` entry
_is_readable_answer() {
  case "${1:?}" in
    *=y|*=n) return 0 ;;
  esac
  return 1
}

# Die unless every answer in the map names one of the declared keys $1 and
# reads y or n. Use this for a map a caller supplied: an unclaimed key there
# is a typo, and continuing anyway would run something other than what was
# asked for.
# $1: space-separated list of the keys this run can answer
validate_answers() {
  local declared entry reglob
  declared=${1:?}
  case $- in *f*) reglob='' ;; *) reglob=yes; set -f ;; esac
  # shellcheck disable=SC2086
  for entry in $DOTFILES_ANSWERS; do
    _is_declared_key "${entry%%=*}" "$declared" ||
      die "Unknown answer key \"${entry%%=*}\" (expected one of: $declared)"
    _is_readable_answer "$entry" || die "Answer \"$entry\" is neither y nor n"
  done
  [ -z "$reglob" ] || set +f
}

# Drop every answer the declared keys $1 do not claim, and name each one
# dropped. Use this for a map read from the profile: an unclaimed key there is
# drift from an upstream rename, not a typo, so it is discarded with a warning
# instead of blocking the run.
# $1: space-separated list of the keys this run can answer
drop_unknown_answers() {
  local declared entry kept reglob
  declared=${1:?} kept=''
  case $- in *f*) reglob='' ;; *) reglob=yes; set -f ;; esac
  # shellcheck disable=SC2086
  for entry in $DOTFILES_ANSWERS; do
    if _is_declared_key "${entry%%=*}" "$declared" && _is_readable_answer "$entry"; then
      kept="${kept}${kept:+ }$entry"
    else
      tui_warn "Ignoring \"$entry\" from $(tui_path "$(get_deploy_profile_path)")"
    fi
  done
  DOTFILES_ANSWERS=$kept
  [ -z "$reglob" ] || set +f
}

#
# Keyed prompts
#

# Ask a confirmation under the answer key $1. An answer the map already holds
# is replayed instead of asked, and one given at the prompt joins the map.
# Everything after the key reaches `confirm` untouched, so the key comes first.
# $1: answer key
# $2+: confirm's own flags and message
confirm_keyed() {
  local key recorded status
  key=${1:?}
  shift
  if recorded=$(answer_for "$key"); then
    confirm -a "$recorded" "$@"
    return
  fi
  confirm "$@"
  status=$?
  if [ "$status" -eq 0 ]; then
    record_answer "$key" y
  else
    record_answer "$key" n
  fi
  return "$status"
}

#
# The profile file
#

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
