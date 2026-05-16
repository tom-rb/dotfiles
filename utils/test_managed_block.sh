#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
  # shellcheck disable=SC2034
  DOTFILES="$(get_abs_path "$THISDIR/..")"
}

setUp() {
  . "$THISDIR/managed_block.sh"
  TARGET="${SHUNIT_TMPDIR:?}/file"
}

tearDown() {
  cleanupSpies
  cleanupTestDir
}


test_creates_file_with_markers_and_content_when_missing() {
  write_managed_block "$TARGET" "dotfiles:zsh" "source base"

  assertTrue "File should be created" "[ -f \"$TARGET\" ]"
  expected='# >>> dotfiles:zsh >>>
source base
# <<< dotfiles:zsh <<<'
  assertEquals "$expected" "$(cat "$TARGET")"
}

test_replacing_one_tag_leaves_other_tags_blocks_intact() {
  cat > "$TARGET" <<-EOF
	# >>> dotfiles:zsh >>>
	zsh old
	# <<< dotfiles:zsh <<<

	# >>> dotfiles:zimfw >>>
	zimfw stays
	# <<< dotfiles:zimfw <<<
EOF

  write_managed_block "$TARGET" "dotfiles:zsh" "zsh new"

  expected='# >>> dotfiles:zsh >>>
zsh new
# <<< dotfiles:zsh <<<

# >>> dotfiles:zimfw >>>
zimfw stays
# <<< dotfiles:zimfw <<<'
  assertEquals "$expected" "$(cat "$TARGET")"
}

test_replaces_block_in_place_preserving_surrounding_content() {
  cat > "$TARGET" <<-EOF
	above 1
	above 2
	# >>> dotfiles:zsh >>>
	old content
	more old content
	# <<< dotfiles:zsh <<<
	below 1
	below 2
EOF

  write_managed_block "$TARGET" "dotfiles:zsh" "new content"

  expected='above 1
above 2
# >>> dotfiles:zsh >>>
new content
# <<< dotfiles:zsh <<<
below 1
below 2'
  assertEquals "$expected" "$(cat "$TARGET")"
}

test_no_leading_separator_when_existing_file_is_empty() {
  : > "$TARGET"

  write_managed_block "$TARGET" "dotfiles:zsh" "source base"

  expected='# >>> dotfiles:zsh >>>
source base
# <<< dotfiles:zsh <<<'
  assertEquals "$expected" "$(cat "$TARGET")"
}

test_appends_with_blank_line_separator_when_file_has_content_without_markers() {
  printf '%s\n' "existing line 1" "existing line 2" > "$TARGET"

  write_managed_block "$TARGET" "dotfiles:zsh" "source base"

  expected='existing line 1
existing line 2

# >>> dotfiles:zsh >>>
source base
# <<< dotfiles:zsh <<<'
  assertEquals "$expected" "$(cat "$TARGET")"
}


# Run tests
SHPY_PATH="$THISDIR/../tests/shpy"
export SHPY_PATH
. "$THISDIR/../tests/shpy"
. "$THISDIR/../tests/shpy-shunit2"
. "$THISDIR/../tests/shunit2"
