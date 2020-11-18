#!/usr/bin/env sh

readonly THISDIR=$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)

oneTimeSetUp() {
  # shellcheck source=../utils_for_test.sh
  . "$THISDIR/../utils_for_test.sh"
}

setUp() {
  # shellcheck source=../../git/install_git_aliases.sh
  . "$THISDIR/../../git/install_git_aliases.sh"
}

#
# Tests
#

test_patch_zimfw_git_init() {
  mock_file="${SHUNIT_TMPDIR}/init.zsh"
  rm -f "$mock_file"

  cat <<-'EOF' > "$mock_file"
	() {
	  local gprefix
	  zstyle -s ':zim:git' aliases-prefix 'gprefix' || gprefix=G
	  echo "${gprefix}" # this would normally be alias commands
	}
	EOF

  patch_zimfw_git_init "$mock_file"
  patched=$(sh "$mock_file")

  assertEquals "Expect 'g' as git prefix" "g" "$patched"
  assertTrue "Expect backup created" "[ -f \"$mock_file.bkp\" ]"
}

# Run tests
# shellcheck source=../shunit2
. "$THISDIR/../shunit2"