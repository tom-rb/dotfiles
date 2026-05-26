#!/usr/bin/env sh

# Upsert a fenced "managed block" into a config file under a tag-derived
# marker pair (# >>> $tag >>> ... # <<< $tag <<<). The function owns the
# markers; callers pass only the content that goes between them.
# Creates the file if missing.
# -p / --prepend: place at the top of an existing non-empty file (default: append)
# --after <anchor>: on first-time placement of this block, insert immediately
#   after <anchor>'s closing fence. Dies if <anchor> is absent from the file.
#   Mutually exclusive with --prepend.
# $1: target file
# $2: tag (e.g. dotfiles:zsh)
# $3: content (between the markers, without trailing newline)
write_managed_block() {
  local file tag content start end prepend=0 anchor=''
  while :; do
    case "$1" in
      -p|--prepend) prepend=1; shift ;;
      --after)      anchor=${2:?}; shift 2 ;;
      *)            break ;;
    esac
  done
  file=${1:?} tag=${2:?} content=${3?}
  start="# >>> $tag >>>"
  end="# <<< $tag <<<"
  if [ -f "$file" ] && grep -qF "$start" "$file"; then
    # Replace existing block in place; surrounding content untouched.
    awk -v s="$start" -v e="$end" -v c="$content" '
      $0==s {print s; print c; print e; skip=1; next}
      skip && $0==e {skip=0; next}
      !skip
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  elif [ -n "$anchor" ]; then
    local anchor_end="# <<< $anchor <<<"
    if [ ! -f "$file" ] || ! grep -qF "$anchor_end" "$file"; then
      die "Cannot place block '$tag' in $file: anchor '$anchor' not found."
    fi
    awk -v ae="$anchor_end" -v s="$start" -v e="$end" -v c="$content" '
      {print}
      $0==ae && !placed {print ""; print s; print c; print e; placed=1}
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  elif [ -s "$file" ] && [ "$prepend" = 1 ]; then
    { printf '%s\n%s\n%s\n\n' "$start" "$content" "$end"; cat "$file"; } > "$file.tmp" \
      && mv "$file.tmp" "$file"
  elif [ -s "$file" ]; then
    printf '\n%s\n%s\n%s\n' "$start" "$content" "$end" >> "$file"
  else
    _write_block_only "$file" "$tag" "$content"
  fi
}

# Write a file containing only the managed block, replacing any prior content.
# Used by write_managed_block's empty-file branch and by install_managed_block's
# backup/overwrite choices, where preserved user content is either saved or dropped.
_write_block_only() {
  local file tag content
  file=${1:?} tag=${2:?} content=${3?}
  printf '%s\n%s\n%s\n' "# >>> $tag >>>" "$content" "# <<< $tag <<<" > "$file"
}

# True if $1 contains only managed-block fences (any tag) + blank lines, i.e.
# no hand-rolled user content. Used by install_managed_block to skip the
# first-time prompt when the only existing content is another module's block.
only_managed_blocks() {
  awk '
    /^# >>> .+ >>>$/ { inb=1; next }
    inb && /^# <<< .+ <<<$/ { inb=0; next }
    inb { next }
    /^[[:space:]]*$/ { next }
    { user=1; exit }
    END { exit user ? 1 : 0 }
  ' "${1:?}"
}

# True if file $1's managed block for tag $2 contains a line matching the
# awk ERE $3. Returns 1 if the file is absent or the tag's block isn't present.
# Lets callers ask "does my block already have this snippet?" without
# re-deriving the fence format.
# $1: target file
# $2: tag
# $3: awk regex matched against each line between the markers
managed_block_contains() {
  local file tag pattern start end
  file=${1:?} tag=${2:?} pattern=${3:?}
  start="# >>> $tag >>>"
  end="# <<< $tag <<<"
  [ -f "$file" ] || return 1
  awk -v s="$start" -v e="$end" -v p="$pattern" '
    $0==s {inb=1; next}
    inb && $0==e {inb=0; next}
    inb && $0 ~ p {found=1}
    END {exit !found}
  ' "$file"
}

# Interactive wrapper around write_managed_block. Handles "first-time placement":
# if the target file already exists with hand-rolled content but no block for
# this tag, prompt the user (backup / append / overwrite, default backup).
# Quiet otherwise: missing file or block already present → straight upsert.
# -p / --prepend: forwarded to write_managed_block on the quiet path
# --after <anchor>: on first-time placement of this block, insert immediately
#   after <anchor>'s closing fence. Mutually exclusive with --prepend.
# $1: target file
# $2: tag
# $3: content
install_managed_block() {
  local file tag content start prepend=0 anchor='' add_label
  while :; do
    case "$1" in
      -p|--prepend) prepend=1; shift ;;
      --after)      anchor=${2:?}; shift 2 ;;
      *)            break ;;
    esac
  done
  file=${1:?} tag=${2:?} content=${3?}
  start="# >>> $tag >>>"
  # Anchor is a hard precondition. Check before any user-facing prompt so a
  # missing anchor never collapses into the backup/overwrite branches (which
  # would silently land the block without honoring the ordering constraint).
  # Exception: if this tag's block already lives in the file, we're on a
  # position-preserving re-install and the anchor isn't consulted.
  if [ -n "$anchor" ] \
     && { [ ! -f "$file" ] || ! grep -qF "$start" "$file"; } \
     && { [ ! -f "$file" ] || ! grep -qF "# <<< $anchor <<<" "$file"; }; then
    die "Cannot place block '$tag' in $file: anchor '$anchor' not found."
  fi
  # Quiet path: nothing the user wrote is at stake.
  # - file missing/empty (no content yet)
  # - this tag's block already there (idempotent re-run)
  # - file contains only other managed blocks + whitespace (e.g. zimfw
  #   landing on a .zshenv freshly written by install_zsh)
  if [ ! -s "$file" ] \
     || grep -qF "$start" "$file" \
     || only_managed_blocks "$file"; then
    if [ -n "$anchor" ]; then
      write_managed_block --after "$anchor" "$file" "$tag" "$content"
    elif [ "$prepend" = 1 ]; then
      write_managed_block --prepend "$file" "$tag" "$content"
    else
      write_managed_block "$file" "$tag" "$content"
    fi
    return
  fi
  echo "Found existing $file: (tail of it)"
  echo ">>>"
  tail "$file"
  echo "<<<"
  # `if`-wrap so a caller running under `set -e` doesn't abort on choose's
  # non-zero exit (which is how the chosen option is returned).
  local choice=0
  if [ "$prepend" = 1 ]
    then add_label="Prepend block to existing $file"
    else add_label="Append block to existing $file"
  fi
  if choose -d 1 "Backup existing $file and write block" \
                 "$add_label" \
                 "Overwrite existing $file with block only"
    then choice=$?
    else choice=$?
  fi
  case "$choice" in
    0) echo "$file not configured!"; return 1 ;;
    1) backup_file "$file"
       _write_block_only "$file" "$tag" "$content" ;;
    2) if [ "$prepend" = 1 ]
         then write_managed_block --prepend "$file" "$tag" "$content"
         else write_managed_block "$file" "$tag" "$content"
       fi ;;
    3) _write_block_only "$file" "$tag" "$content" ;;
  esac
}
