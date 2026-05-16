#!/usr/bin/env sh

# Upsert a fenced "managed block" into a config file under a tag-derived
# marker pair (# >>> $tag >>> ... # <<< $tag <<<). The function owns the
# markers; callers pass only the content that goes between them.
# Creates the file if missing.
# $1: target file
# $2: tag (e.g. dotfiles:zsh)
# $3: content (between the markers, without trailing newline)
write_managed_block() {
  local file tag content start end
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
  elif [ -s "$file" ]; then
    printf '\n%s\n%s\n%s\n' "$start" "$content" "$end" >> "$file"
  else
    printf '%s\n%s\n%s\n' "$start" "$content" "$end" > "$file"
  fi
}
