#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
  # shellcheck disable=SC2034
  DOTFILES="$(get_abs_path "$THISDIR/..")"
}

setUp() {
  . "$THISDIR/utils.sh"
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

test_prepends_with_blank_line_separator_when_file_has_content_without_markers() {
  printf '%s\n' "existing line 1" "existing line 2" > "$TARGET"

  write_managed_block --prepend "$TARGET" "dotfiles:zsh" "source base"

  expected='# >>> dotfiles:zsh >>>
source base
# <<< dotfiles:zsh <<<

existing line 1
existing line 2'
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

#
# write_managed_block --after <anchor>
#

test_after_inserts_block_immediately_after_anchor_closing_fence() {
  cat > "$TARGET" <<-EOF
		# >>> dotfiles:zsh:base >>>
		source base
		# <<< dotfiles:zsh:base <<<

		# >>> dotfiles:zsh:overrides >>>
		source overrides
		# <<< dotfiles:zsh:overrides <<<
EOF

  write_managed_block --after "dotfiles:zsh:base" "$TARGET" "dotfiles:zimfw" "source zim"

  expected='# >>> dotfiles:zsh:base >>>
source base
# <<< dotfiles:zsh:base <<<

# >>> dotfiles:zimfw >>>
source zim
# <<< dotfiles:zimfw <<<

# >>> dotfiles:zsh:overrides >>>
source overrides
# <<< dotfiles:zsh:overrides <<<'
  assertEquals "$expected" "$(cat "$TARGET")"
}

test_after_is_ignored_on_reinstall_block_position_preserved() {
  # Block sits BEFORE the anchor — a misordered state. Re-running with
  # --after must not relocate it; the rule is position-preserving.
  cat > "$TARGET" <<-EOF
		# >>> dotfiles:zimfw >>>
		old zim
		# <<< dotfiles:zimfw <<<

		# >>> dotfiles:zsh:base >>>
		source base
		# <<< dotfiles:zsh:base <<<
EOF

  write_managed_block --after "dotfiles:zsh:base" "$TARGET" "dotfiles:zimfw" "new zim"

  expected='# >>> dotfiles:zimfw >>>
new zim
# <<< dotfiles:zimfw <<<

# >>> dotfiles:zsh:base >>>
source base
# <<< dotfiles:zsh:base <<<'
  assertEquals "$expected" "$(cat "$TARGET")"
}

test_after_dies_when_anchor_absent_from_file() {
  cat > "$TARGET" <<-EOF
		# >>> dotfiles:something-else >>>
		stuff
		# <<< dotfiles:something-else <<<
EOF
  original=$(cat "$TARGET")

  ( write_managed_block --after "dotfiles:zsh:base" "$TARGET" "dotfiles:zimfw" "source zim" ) >/dev/null 2>&1
  rc=$?

  assertNotEquals 0 "$rc"
  assertEquals "$original" "$(cat "$TARGET")"
}

#
# install_managed_block
#

test_install_managed_block_is_quiet_when_file_absent() {
  createSpy -u choose

  install_managed_block "$TARGET" "dotfiles:zsh" "source base" >/dev/null

  assertNeverCalled choose
  expected='# >>> dotfiles:zsh >>>
source base
# <<< dotfiles:zsh <<<'
  assertEquals "$expected" "$(cat "$TARGET")"
}

test_install_managed_block_is_quiet_when_block_already_present() {
  cat > "$TARGET" <<-EOF
	above
	# >>> dotfiles:zsh >>>
	old
	# <<< dotfiles:zsh <<<
	below
EOF
  createSpy -u choose

  install_managed_block "$TARGET" "dotfiles:zsh" "new" >/dev/null

  assertNeverCalled choose
  expected='above
# >>> dotfiles:zsh >>>
new
# <<< dotfiles:zsh <<<
below'
  assertEquals "$expected" "$(cat "$TARGET")"
}

test_install_managed_block_is_quiet_when_file_only_has_other_managed_blocks() {
  cat > "$TARGET" <<-EOF
	# >>> dotfiles:zsh >>>
	source zshrc
	# <<< dotfiles:zsh <<<
EOF
  createSpy -u choose

  install_managed_block "$TARGET" "dotfiles:zimfw" "zimfw block" >/dev/null

  assertNeverCalled choose
  expected='# >>> dotfiles:zsh >>>
source zshrc
# <<< dotfiles:zsh <<<

# >>> dotfiles:zimfw >>>
zimfw block
# <<< dotfiles:zimfw <<<'
  assertEquals "$expected" "$(cat "$TARGET")"
  assertFalse "No backup should be created" "[ -f \"$TARGET.bkp\" ]"
}

test_install_managed_block_after_lands_block_after_anchor_on_quiet_path() {
  cat > "$TARGET" <<-EOF
		# >>> dotfiles:zsh:base >>>
		source base
		# <<< dotfiles:zsh:base <<<

		# >>> dotfiles:zsh:overrides >>>
		source overrides
		# <<< dotfiles:zsh:overrides <<<
EOF
  createSpy -u choose

  install_managed_block --after "dotfiles:zsh:base" "$TARGET" "dotfiles:zimfw" "source zim" >/dev/null

  assertNeverCalled choose
  expected='# >>> dotfiles:zsh:base >>>
source base
# <<< dotfiles:zsh:base <<<

# >>> dotfiles:zimfw >>>
source zim
# <<< dotfiles:zimfw <<<

# >>> dotfiles:zsh:overrides >>>
source overrides
# <<< dotfiles:zsh:overrides <<<'
  assertEquals "$expected" "$(cat "$TARGET")"
}

test_install_managed_block_prepend_lands_block_above_existing_managed_block() {
  cat > "$TARGET" <<-EOF
		# >>> dotfiles:zimfw >>>
		source zimrc-base
		# <<< dotfiles:zimfw <<<
EOF
  createSpy -u choose

  install_managed_block --prepend "$TARGET" "dotfiles:asdf" "zmodule asdf" >/dev/null

  assertNeverCalled choose
  expected='# >>> dotfiles:asdf >>>
zmodule asdf
# <<< dotfiles:asdf <<<

# >>> dotfiles:zimfw >>>
source zimrc-base
# <<< dotfiles:zimfw <<<'
  assertEquals "$expected" "$(cat "$TARGET")"
}

test_install_managed_block_prompts_when_user_content_sits_alongside_managed_block() {
  cat > "$TARGET" <<-EOF
	hand-rolled line
	# >>> dotfiles:zsh >>>
	source zshrc
	# <<< dotfiles:zsh <<<
EOF

  printf '\n' | install_managed_block "$TARGET" "dotfiles:zimfw" "zimfw block" >/dev/null

  assertTrue "Backup should exist (prompt took the default)" "[ -f \"$TARGET.bkp\" ]"
}

test_install_managed_block_first_time_default_backs_up() {
  printf 'user line\n' > "$TARGET"

  printf '\n' | install_managed_block "$TARGET" "dotfiles:zsh" "block" >/dev/null

  assertTrue "Backup file should exist" "[ -f \"$TARGET.bkp\" ]"
  assertEquals "user line" "$(cat "$TARGET.bkp")"
  expected='# >>> dotfiles:zsh >>>
block
# <<< dotfiles:zsh <<<'
  assertEquals "$expected" "$(cat "$TARGET")"
}

test_install_managed_block_first_time_append_keeps_user_content() {
  printf 'user line\n' > "$TARGET"

  echo 2 | install_managed_block "$TARGET" "dotfiles:zsh" "block" >/dev/null

  assertFalse "No backup should be created" "[ -f \"$TARGET.bkp\" ]"
  expected='user line

# >>> dotfiles:zsh >>>
block
# <<< dotfiles:zsh <<<'
  assertEquals "$expected" "$(cat "$TARGET")"
}

test_install_managed_block_first_time_append_with_prepend_lands_block_at_top() {
  printf 'user line\n' > "$TARGET"

  echo 2 | install_managed_block --prepend "$TARGET" "dotfiles:zsh" "block" >/dev/null

  assertFalse "No backup should be created" "[ -f \"$TARGET.bkp\" ]"
  expected='# >>> dotfiles:zsh >>>
block
# <<< dotfiles:zsh <<<

user line'
  assertEquals "$expected" "$(cat "$TARGET")"
}

test_install_managed_block_first_time_overwrite_drops_user_content() {
  printf 'user line\n' > "$TARGET"

  echo 3 | install_managed_block "$TARGET" "dotfiles:zsh" "block" >/dev/null

  assertFalse "No backup should be created" "[ -f \"$TARGET.bkp\" ]"
  expected='# >>> dotfiles:zsh >>>
block
# <<< dotfiles:zsh <<<'
  assertEquals "$expected" "$(cat "$TARGET")"
}

test_install_managed_block_first_time_cancel_leaves_file_alone() {
  printf 'user line\n' > "$TARGET"

  echo q | install_managed_block "$TARGET" "dotfiles:zsh" "block" >/dev/null
  rc=$?

  assertEquals 1 "$rc"
  assertEquals "user line" "$(cat "$TARGET")"
  assertFalse "No backup should be created" "[ -f \"$TARGET.bkp\" ]"
}


#
# managed_block_contains
#

test_managed_block_contains_true_when_pattern_inside_block() {
  cat > "$TARGET" <<-EOF
	# >>> dotfiles:tmux >>>
	source tmux-cmds.sh
	tmux-enter
	# <<< dotfiles:tmux <<<
EOF

  managed_block_contains "$TARGET" "dotfiles:tmux" "tmux-enter"
  assertTrue "Should match line inside the block" $?
}

test_managed_block_contains_false_when_pattern_outside_block() {
  cat > "$TARGET" <<-EOF
	tmux-enter
	# >>> dotfiles:tmux >>>
	source tmux-cmds.sh
	# <<< dotfiles:tmux <<<
	tmux-enter
EOF

  managed_block_contains "$TARGET" "dotfiles:tmux" "tmux-enter"
  assertFalse "Should ignore matches outside the fence" $?
}

test_managed_block_contains_false_when_pattern_in_other_tags_block() {
  cat > "$TARGET" <<-EOF
	# >>> dotfiles:zsh >>>
	tmux-enter
	# <<< dotfiles:zsh <<<
	# >>> dotfiles:tmux >>>
	source tmux-cmds.sh
	# <<< dotfiles:tmux <<<
EOF

  managed_block_contains "$TARGET" "dotfiles:tmux" "tmux-enter"
  assertFalse "Should only inspect the requested tag's block" $?
}

test_managed_block_contains_false_when_tag_has_no_block() {
  cat > "$TARGET" <<-EOF
	# >>> dotfiles:zsh >>>
	tmux-enter
	# <<< dotfiles:zsh <<<
EOF

  managed_block_contains "$TARGET" "dotfiles:tmux" "tmux-enter"
  assertFalse "Should return false when the tag isn't present" $?
}

test_managed_block_contains_false_when_file_missing() {
  managed_block_contains "$SHUNIT_TMPDIR/does-not-exist" "dotfiles:tmux" "tmux-enter"
  assertFalse "Should return false when the file doesn't exist" $?
}


# Run tests
SHPY_PATH="$THISDIR/../tests/shpy"
export SHPY_PATH
. "$THISDIR/../tests/shpy"
. "$THISDIR/../tests/shpy-shunit2"
. "$THISDIR/../tests/shunit2"
