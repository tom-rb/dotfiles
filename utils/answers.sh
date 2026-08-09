#!/usr/bin/env sh

#
# The answer map
#
# $DOTFILES_ANSWERS is a space-separated `key=value` map holding what the user
# answered, so a prompt already answered can be replayed instead of asked. Each
# loop below splits it on spaces, so it disables globbing first and restores it
# after: a `*` in the map would otherwise expand against the working directory.
#
# Keeping the answers here rather than in the profile file is what lets a module
# wizard ask a keyed question while running standalone, with no deploy around it.

# Echo the answer recorded for key $1 — `y`, `n`, or an option word.
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
# $2: the answer word — `y` or `n` from a confirmation, or an option word from
#     a choice. It cannot hold a space: spaces separate entries in the map.
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
  # An answer recorded in a module wizard is recorded in another process, where
  # the variable above dies with it. $DOTFILES_ANSWERS_OUT is the way home that
  # with_answers opened; appending is enough, since it replays the file in order
  # and a later answer for a key overwrites an earlier one.
  [ -z "${DOTFILES_ANSWERS_OUT:-}" ] ||
    printf '%s\n' "$key=$value" >> "$DOTFILES_ANSWERS_OUT"
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

# True when answer $1 carries a value at all.
# This is a structural check, not a check of what the value means: a choice
# records an option word, and this module cannot know one prompt's words from
# another's. Each keyed prompt vets its own recorded value instead, and asks
# again when it does not recognise it.
# $1: one `key=value` entry
_is_readable_answer() {
  case "${1:?}" in
    *=?*) return 0 ;;
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
    _is_readable_answer "$entry" || die "Answer \"$entry\" carries no value"
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
  # Anything but y or n is a hand-edit or a leftover from a prompt that has
  # since become a choice. Replaying it would render a line reading "yes" that
  # the run then treats as a no, so it is asked again instead. The warning is
  # what names the entry: without it a non-interactive run reaches the prompt
  # and dies on exhausted input, naming neither the answer nor where it came
  # from.
  if recorded=$(answer_for "$key"); then
    if [ "$recorded" = y ] || [ "$recorded" = n ]; then
      confirm -a "$recorded" "$@"
      return
    fi
    tui_warn "Ignoring \"$key=$recorded\": not a \"y\" or \"n\""
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

# Echo the word at 1-based position $1 of the space-separated list $2.
# Returns 1 when the list is shorter than that.
# $1: position  $2: the words
_word_at() {
  local position words index word
  position=${1:?} words=${2:?}
  # A subshell rather than the save-and-restore the loops above use: this one
  # returns from inside itself, and a subshell drops `set -f` on its own.
  (
    set -f
    index=0
    # shellcheck disable=SC2086
    for word in $words; do
      index=$((index + 1))
      [ "$index" -eq "$position" ] && { printf '%s\n' "$word"; exit 0; }
    done
    exit 1
  )
}

# Echo the 1-based position of word $1 in the space-separated list $2.
# Returns 1 when the list does not hold the word, which is how an answer
# recorded before an option was renamed or dropped falls through to the prompt.
# $1: word  $2: the words
_index_of_word() {
  local needle words index word
  needle=${1:?} words=${2:?}
  (
    set -f
    index=0
    # shellcheck disable=SC2086
    for word in $words; do
      index=$((index + 1))
      [ "$word" = "$needle" ] && { printf '%s\n' "$index"; exit 0; }
    done
    exit 1
  )
}

# Ask a choice under the answer key $1. An answer the map already holds is
# replayed instead of asked, and one made at the prompt joins the map.
# The map holds the option's word, not its number: the profile is a file people
# read, and a number would silently come to mean a different option the day the
# options are reordered.
# A quit records nothing. Unlike a declined confirmation, which is a settled
# "not this module", quitting a choice leaves the module unfinished and the
# deploy non-zero — recording it would make that permanent, with no prompt left
# to take it back.
# $1: answer key
# $2: the option words, space-separated, in the order the options are passed
# $3+: choose's own flags, question and options
# Returns choose's status: 0 on quit, or the number of the chosen option.
choose_keyed() {
  local key words recorded index status word
  key=${1:?} words=${2:?}
  shift 2
  if recorded=$(answer_for "$key") && index=$(_index_of_word "$recorded" "$words"); then
    # `choose` still vets the index against the options it was actually given,
    # and asks when it does not fit. So this cannot return here: what the user
    # answers to that fallthrough is a real answer, and has to be recorded like
    # any other.
    choose -a "$index" "$@"
  else
    choose "$@"
  fi
  status=$?
  [ "$status" -eq 0 ] && return "$status"
  # A word list shorter than the option list names nothing for this choice.
  # Recording an empty value would abort the run on record_answer's own
  # argument check, which is a worse answer than leaving the map alone.
  word=$(_word_at "$status" "$words") || return "$status"
  record_answer "$key" "$word"
  return "$status"
}

#
# Crossing a process boundary
#

# Run "$@" with the answer map visible to it, and take back what it recorded.
# A module wizard runs as its own `sh`, so a keyed prompt inside one cannot see
# the map through a plain variable, and what it records dies with the process.
# The map travels out through the environment and the answers come home through
# a file, which is what makes a keyed prompt work anywhere, not only in the
# process that owns the map.
# Returns the command's own status, so a module that did not finish still reads
# as one that did not finish.
# $@: the command and its arguments
with_answers() {
  local out status line
  export DOTFILES_ANSWERS
  # mktemp, not a $$-derived name: a predictable path in a shared /tmp is a
  # symlink someone else can plant, and this one gets truncated and then read
  # straight back into the answer map.
  # Nowhere to collect answers is not a reason to skip the step: it still runs,
  # and only what it would have recorded is lost.
  if ! out=$(mktemp 2>/dev/null); then
    tui_warn "Couldn't open a file to collect answers"
    "$@"
    return $?
  fi
  export DOTFILES_ANSWERS_OUT
  DOTFILES_ANSWERS_OUT=$out
  "$@"
  status=$?
  # Unset before the replay, so recording an answer here does not append it to
  # the file being read.
  unset DOTFILES_ANSWERS_OUT
  # `|| [ -n "$line" ]` keeps a final line with no newline after it, the way
  # load_deploy_profile does.
  while IFS= read -r line || [ -n "$line" ]; do
    # Only lines that carry both a key and a value. This loop runs in the
    # deploy's own process, where record_answer's argument check would abort
    # the whole run rather than the one answer, and a line with no `=` at all
    # would otherwise be recorded as its own key and value.
    case "$line" in
      ?*=?*) record_answer "${line%%=*}" "${line#*=}" ;;
    esac
  done < "$out"
  rm -f "$out"
  return "$status"
}
