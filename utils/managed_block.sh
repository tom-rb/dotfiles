#!/usr/bin/env sh

# Upsert a fenced "managed block" into a config file under a tag-derived
# marker pair (# >>> $tag >>> ... # <<< $tag <<<). Creates the file if missing.
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
  _require_intact_fences "$file" "$tag"
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

# Die if $1 holds tag $2's opening fence but not its closing one. Replacing a
# block that has no end fence would consume every line from the opening fence to
# EOF, taking user content and any later block with it.
# No-op when the file or the opening fence is absent.
# $1: target file
# $2: tag
_require_intact_fences() {
  local file tag
  file=${1:?} tag=${2:?}
  [ -f "$file" ] || return 0
  grep -qF "# >>> $tag >>>" "$file" || return 0
  grep -qF "# <<< $tag <<<" "$file" \
    || die "Block '$tag' in $file has no closing fence '# <<< $tag <<<'; refusing to rewrite it."
}

# Write a file containing only the managed block, replacing any prior content.
_write_block_only() {
  local file tag content
  file=${1:?} tag=${2:?} content=${3?}
  printf '%s\n%s\n%s\n' "# >>> $tag >>>" "$content" "# <<< $tag <<<" > "$file"
}

# Warn that $1 holds content of its own and show the tail of it, so the choice
# that follows is made against what is actually in the file.
# $1: file
_preview_file() {
  local file lines shown
  file=${1:?} shown=5
  tui_warn "$(tui_path "$file") already exists and has content of its own:"
  echo
  tail -n "$shown" "$file" | tui_indent
  lines=$(wc -l <"$file" | tr -d '[:space:]')
  [ "$lines" -gt "$shown" ] && tui_detail "… showing the last $shown of $lines lines"
  echo
}

# True if $1 contains only managed-block fences (any tag) + blank lines, i.e.
# no hand-rolled user content.
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

# Lets callers ask "does my block already have this snippet?".
# True if file $1's managed block for tag $2 contains a line matching the
# awk ERE $3. Returns 1 if the file is absent or the tag's block isn't present.
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

# Read back the content of $1's managed block for tag $2, without its fences.
# Empty when the block isn't there.
_read_managed_block() {
  local file tag
  file=${1:?} tag=${2:?}
  [ -f "$file" ] || return 0
  awk -v s="# >>> $tag >>>" -v e="# <<< $tag <<<" '
    $0==s {inside=1; next}
    inside && $0==e {exit}
    inside
  ' "$file"
}

# Report what a managed-block write did, for callers that asked with --as.
# Silent without a label, so tests and internal callers stay quiet.
# $1: label (empty to say nothing)
# $2: updated | unchanged
_report_managed_block() {
  [ -n "$1" ] || return 0
  case "$2" in
    updated)   tui_ok "$1 updated" ;;
    unchanged) tui_skip "$1 unchanged" ;;
  esac
}

# Interactive wrapper around write_managed_block. Handles "first-time placement":
# if the target file already exists with hand-rolled content but no block for
# this tag, prompt the user (backup / append / overwrite, default backup).
# Quiet otherwise: missing file or block already present → straight upsert.
# A re-run whose block content is byte-identical writes nothing at all.
# -p / --prepend: forwarded to write_managed_block on the quiet path
# --after <anchor>: on first-time placement of this block, insert immediately
#   after <anchor>'s closing fence. Mutually exclusive with --prepend.
# --as <label>: report the outcome as "<label> updated" / "<label> unchanged"
# $1: target file
# $2: tag
# $3: content
install_managed_block() {
  local file tag content start prepend=0 anchor='' label='' add_label
  while :; do
    case "$1" in
      -p|--prepend) prepend=1; shift ;;
      --after)      anchor=${2:?}; shift 2 ;;
      --as)         label=${2:?}; shift 2 ;;
      *)            break ;;
    esac
  done
  file=${1:?} tag=${2:?} content=${3?}
  start="# >>> $tag >>>"
  if [ -n "$anchor" ] \
     && { [ ! -f "$file" ] || ! grep -qF "$start" "$file"; } \
     && { [ ! -f "$file" ] || ! grep -qF "# <<< $anchor <<<" "$file"; }; then
    die "Cannot place block '$tag' in $file: anchor '$anchor' not found."
  fi
  _require_intact_fences "$file" "$tag"

  # Quiet path: nothing the user wrote is at stake.
  # - file missing/empty (no content yet)
  # - this tag's block already there (idempotent re-run)
  # - file contains only other managed blocks + whitespace
  if [ ! -s "$file" ] \
     || grep -qF "$start" "$file" \
     || only_managed_blocks "$file"; then
    if grep -qF "$start" "$file" 2>/dev/null \
       && [ "$(_read_managed_block "$file" "$tag")" = "$content" ]; then
      _report_managed_block "$label" unchanged
      return 0
    fi
    if [ -n "$anchor" ]; then
      write_managed_block --after "$anchor" "$file" "$tag" "$content"
    elif [ "$prepend" = 1 ]; then
      write_managed_block --prepend "$file" "$tag" "$content"
    else
      write_managed_block "$file" "$tag" "$content"
    fi
    _report_managed_block "$label" updated
    return
  fi
  _preview_file "$file"

  local choice=0 backup
  if [ "$prepend" = 1 ]
    then add_label="prepend the managed block, keep the rest"
    else add_label="append the managed block, keep the rest"
  fi
  if choose -d 1 -q "stop, I'll check it myself" "What should I do with it?" \
                 "back it up, then write the managed block" \
                 "$add_label" \
                 "replace it with the managed block"
    then choice=$?
    else choice=$?
  fi
  case "$choice" in
    0) tui_warn "$(tui_path "$file") setup interrupted"; return 1 ;;
    1) backup=$(backup_file "$file") || die "Could not back up $(tui_path "$file")"
       tui_detail "Backed up the old one as $(tui_path "$backup")"
       _write_block_only "$file" "$tag" "$content" ;;
    2) if [ "$prepend" = 1 ]
         then write_managed_block --prepend "$file" "$tag" "$content"
         else write_managed_block "$file" "$tag" "$content"
       fi ;;
    3) _write_block_only "$file" "$tag" "$content" ;;
  esac
  _report_managed_block "$label" updated
}
