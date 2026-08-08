#!/usr/bin/env sh

# Installs the agent skills and rules this repo ships into the directories the
# agents read. An "entry" is one item of a source directory: a skill directory,
# or a rule file. The install is the same for both — the harnesses tell them
# apart, this code does not.

#
# Ownership
#

# True when destination entry $1 is one this repo installed here: a symlink
# whose target lands inside one of the source directories $2+ that feed this
# destination.
# The test covers those sources only, not $DOTFILES as a whole. A link the user
# made into some *other* corner of the checkout is theirs — ~/.agents/skills
# pointed at a claude skill, say, which this repo deliberately does not install
# there.
# A copy looks the same as a file the user put there by hand, so copy mode
# cannot prune.
# $1: destination path to test
# $2+: the source directories that feed its destination
is_owned_entry() {
  local entry target root
  entry=${1:?}
  shift
  [ -L "$entry" ] || return 1
  target=$(readlink "$entry") || return 1
  # Only absolute targets are ours: install_entries writes nothing else, and a
  # relative link is by definition someone else's convention.
  for root in "$@"; do
    case "$target" in
      "$root"/*) return 0 ;;
    esac
  done
  return 1
}

# The names of every entry in the source directories given, space separated.
# A missing directory contributes nothing, so a module can name a source it does
# not always ship.
# $@: source directories
entry_names() {
  local dir entry names
  names=''
  for dir in "$@"; do
    [ -d "$dir" ] || continue
    for entry in "$dir"/*; do
      [ -e "$entry" ] || continue
      names="${names}${names:+ }${entry##*/}"
    done
  done
  printf '%s\n' "$names"
}

# Name any entry shipped by more than one of the source directories given.
# Two sources that feed one destination must not share a name. The installer
# scans for collisions before it installs anything, so the second source's entry
# looks free. Its install then quietly backs up the link the first one just
# made, on every deploy, forever.
# $@: source directories
duplicate_entry_names() {
  local name seen dupes
  seen='' dupes=''
  for name in $(entry_names "$@"); do
    case " $seen " in
      *" $name "*)
        case " $dupes " in
          *" $name "*) ;;
          *) dupes="${dupes}${dupes:+ }$name" ;;
        esac ;;
      *) seen="${seen}${seen:+ }$name" ;;
    esac
  done
  printf '%s\n' "$dupes"
}

#
# Questions
#

# Ask whether to link the entries to this checkout or copy them into place. A
# link is the default, so `-y` and a bare Enter both link.
# $1: what is being installed, for the question's wording
# $2: name of variable to set with "link" or "copy"
# Returns 1 when the user quits.
ask_install_mode() {
  local _subject _var _choice
  _subject=${1:?} _var=${2:?}
  if choose -d 1 -q "leave them alone" "How should the $_subject be installed?" \
                 "link them to this dotfiles checkout" \
                 "copy them into place"
    then _choice=$?
    else _choice=$?
  fi
  case "$_choice" in
    1) eval "$_var=link" ;;
    2) # Copy mode needs diff to tell an untouched copy from an edited one.
       # Without diff every copy looks edited, and the default policy would file
       # a fresh backup of the same directory on every deploy.
       command_exists diff \
         || die "Copy mode needs diff to tell an untouched copy from an edited one. Install diffutils, or link instead."
       eval "$_var=copy" ;;
    *) return 1 ;;
  esac
}

# Name the entries an install would destroy, then ask what to do with them.
# A backup is the default, so `-y` never deletes anything it cannot recover.
# $1: the colliding destination paths, one per line
# $2: name of variable to set with "backup", "delete" or "each"
# Returns 1 when the user quits.
ask_collision_policy() {
  local _paths _var _choice _path
  _paths=${1:?} _var=${2:?}
  tui_warn 'These already exist and are not what this repo would install:'
  printf '%s\n' "$_paths" | while IFS= read -r _path; do
    tui_detail "$(tui_path "$_path")"
  done
  if choose -d 1 -q "leave them alone" "What should I do with them?" \
                 "back all of them up" \
                 "delete all of them" \
                 "decide one by one"
    then _choice=$?
    else _choice=$?
  fi
  case "$_choice" in
    1) eval "$_var=backup" ;;
    2) eval "$_var=delete" ;;
    3) eval "$_var=each" ;;
    *) return 1 ;;
  esac
}

#
# Installing
#

# True when source $1 and destination $2 hold the same bytes.
# ask_install_mode refuses copy mode on a host without diff. Only a caller that
# passes "copy" directly reaches the fallback here. The fallback answers
# "different", which costs a question and never a silent overwrite.
_same_content() {
  command_exists diff || return 1
  diff -r -- "$1" "$2" >/dev/null 2>&1
}

# What it means to install source entry $1 as destination $2 in mode $3.
# Echoes one of:
#   missing   - nothing is there, just create it
#   correct   - already what we would install, leave it
#   collision - something else lives there, and the install destroys it
# In copy mode a destination with the same bytes as the source is the copy we
# made, so a re-run stays quiet. A destination with any other content is a
# collision. It may be an edit to our copy, or a skill that was there first.
# The two look the same, and both are worth a question.
# A symlink is always a collision in copy mode: there is no content to compare,
# and a change from a link to a copy is worth a report.
_entry_state() {
  local src dest mode
  src=${1:?} dest=${2:?} mode=${3:?}
  if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
    echo missing
  elif [ -L "$dest" ]; then
    if [ "$mode" = link ] && [ "$(readlink "$dest")" = "$src" ]
      then echo correct
      else echo collision
    fi
  elif [ "$mode" = link ]; then
    echo collision
  elif _same_content "$src" "$dest"; then
    echo correct
  else
    echo collision
  fi
}

# Name every destination entry that an install of source dir $1 into dir $2
# would destroy, one path per line. A caller scans every source it owns before
# it installs any of them, so the user answers for the whole picture once.
# $1: source directory
# $2: destination directory
# $3: mode, "link" or "copy"
list_collisions() {
  local src dest mode entry
  src=${1:?} dest=${2:?} mode=${3:?}
  [ -d "$src" ] || return 0
  for entry in "$src"/*; do
    [ -e "$entry" ] || continue
    [ "$(_entry_state "$entry" "$dest/${entry##*/}" "$mode")" = collision ] || continue
    printf '%s\n' "$dest/${entry##*/}"
  done
}

# Clear destination $1 out of the way under policy $2, and back it up into $3.
# $4: name of variable to set with a line that says what it did, so the caller
#     can report it after the summary line, not mixed into it
# The description is an out-parameter rather than stdout because the "each"
# policy asks a question here, and a captured prompt is an invisible one.
# Returns 1 when it could not clear the path.
_resolve_collision() {
  local _dest _policy _backup_dir _var _kept _msg
  _dest=${1:?} _policy=${2:?} _backup_dir=${3:?} _var=${4:?}
  if [ "$_policy" = each ]; then
    if confirm "Back up $(tui_path "$_dest")?"
      then _policy=backup
      else _policy=delete
    fi
  fi
  if [ "$_policy" = backup ]; then
    _kept=$(backup_path "$_dest" "$_backup_dir") || {
      tui_fail "Could not back up $(tui_path "$_dest")"
      return 1
    }
    _msg="backed $(tui_path "$_dest") up as $(tui_path "$_kept")"
  else
    rm -rf "$_dest" || {
      tui_fail "Could not remove $(tui_path "$_dest")"
      return 1
    }
    _msg="deleted $(tui_path "$_dest")"
  fi
  eval "$_var=\$_msg"
}

# Source directory $1 as a report names it: the path inside this checkout when
# it lives there. Two sources can feed one destination, and a summary that named
# the destination alone read as a contradiction — one source with nothing to do,
# the other linking, both talking about the same directory.
_src_label() {
  local src
  src=${1:?}
  if [ -n "${DOTFILES:-}" ]; then
    case "$src" in
      "$DOTFILES"/*) printf '%s\n' "${src#"$DOTFILES"/}"; return 0 ;;
    esac
  fi
  tui_path "$src"
}

# Install every entry of source directory $1 into destination directory $2.
# $3: mode, "link" or "copy"
# $4: collision policy, "backup", "delete" or "each"
# Nothing is ever overwritten in silence. The policy resolves a destination that
# is not already what we would install, and resolves it before anything is
# created. So `ln` and `cp` only ever meet a free path — the one place a file and
# a directory would behave differently.
# Backups land in a sibling of the destination, never inside it. Both harnesses
# discover skills recursively, and a backup inside the tree would come back as a
# skill of its own.
install_entries() {
  local src dest mode policy backup_dir entry target details changed note verb noun
  src=${1:?} dest=${2:?} mode=${3:?} policy=${4:?}
  [ -d "$src" ] || return 0
  backup_dir="$dest.bkp"
  details='' changed=0

  for entry in "$src"/*; do
    [ -e "$entry" ] || continue
    target="$dest/${entry##*/}"
    case "$(_entry_state "$entry" "$target" "$mode")" in
      correct)
        continue ;;
      collision)
        _resolve_collision "$target" "$policy" "$backup_dir" note || return 1
        details="${details}${details:+
}${note}" ;;
    esac
    if [ "$mode" = link ]
      then ln -s "$entry" "$target" || die "Could not link $(tui_path "$target")"
      else cp -R "$entry" "$target" || die "Could not copy $(tui_path "$target")"
    fi
    changed=$((changed + 1))
  done

  if [ "$changed" -eq 0 ]; then
    tui_skip "$(_src_label "$src") > $(tui_path "$dest"): nothing to do"
  else
    [ "$mode" = link ] && verb=linked || verb=copied
    [ "$changed" -eq 1 ] && noun=entry || noun=entries
    tui_ok "$(_src_label "$src") > $(tui_path "$dest"): $changed $noun $verb"
  fi
  if [ -n "$details" ]; then
    printf '%s\n' "$details" | while IFS= read -r note; do
      tui_detail "$note"
    done
  fi
  return 0
}

# Remove the entries this repo installed into destination $1 and no longer
# ships. Everything else stays, including the links the user made by hand.
# $1: destination directory
# $2: space-separated names the repo still ships
# $3+: the source directories that feed this destination
prune_owned_entries() {
  local dest keep entry name
  dest=${1:?} keep=${2-}
  shift 2
  [ -d "$dest" ] || return 0
  for entry in "$dest"/*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    is_owned_entry "$entry" "$@" || continue
    name=${entry##*/}
    case " $keep " in
      *" $name "*) continue ;;
    esac
    rm -rf "$entry" || die "Could not remove $(tui_path "$entry")"
    tui_detail "removed $(tui_path "$entry"), no longer in the repo"
  done
  return 0
}
