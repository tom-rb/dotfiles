#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
  # For `quietly`. The update itself runs as a child process, not sourced.
  # shellcheck source=../utils/utils.sh
  . "$THISDIR/../utils/utils.sh"
}

#
# Helpers
#

# Publish a copy of this repo to a bare remote at $1, leaving the working clone
# it was pushed from at $2 for later commits.
# A scratch repo rather than the mounted /app. When the suite runs from a
# linked worktree, /app/.git is a file that points at a path inside the host's
# main clone, and git in the container cannot follow it.
seed_scratch_remote() {
  local remote work
  remote=${1:?} work=${2:?}

  quietly git init --bare "$remote"
  # The remote's HEAD is what a clone copies into refs/remotes/origin/HEAD, and
  # so what the update reads back as the remote's default branch. `git init`
  # still points it at master.
  quietly git -C "$remote" symbolic-ref HEAD refs/heads/main
  mkdir -p "$work"
  cp -R "${DOTFILES:?}/." "$work"
  rm -rf "$work/.git"
  (
    cd "$work" || return 1
    quietly git init
    # `git init -b main` would be clearer but wants git 2.28.
    quietly git symbolic-ref HEAD refs/heads/main
    quietly git config user.name 'Test User'
    quietly git config user.email 'test@example.com'
    quietly git add -A
    quietly git commit -m 'the dotfiles as they were deployed'
    quietly git remote add origin "$remote"
    quietly git push -u origin main
  )
}

# Commit file $2 in the working clone $1 and push it.
push_upstream_change() {
  local work name
  work=${1:?} name=${2:?}
  (
    cd "$work" || return 1
    echo 'pulled' > "$name"
    quietly git add "$name"
    quietly git commit -m "an upstream change"
    quietly git push
  )
}

# Write a deploy profile at $1 that declines every module, so the deploy the
# update runs replays it instead of asking, and installs nothing.
write_declining_profile() {
  local path
  path=${1:?}
  mkdir -p "${path%/*}"
  cat > "$path" <<-'EOF'
	zsh=n
	zimfw=n
	asdf=n
	tmux=n
	git=n
	pi=n
	claude=n
EOF
}

#
# Tests
#

# @image: with-git
it_pulls_an_upstream_commit_and_redeploys() {
  local remote work clone state output status
  remote=${SHUNIT_TMPDIR:?}/remote.git
  work=${SHUNIT_TMPDIR:?}/upstream
  clone=${SHUNIT_TMPDIR:?}/clone
  state=${SHUNIT_TMPDIR:?}/state

  seed_scratch_remote "$remote" "$work"
  quietly git clone "$remote" "$clone"
  push_upstream_change "$work" 'upstream-marker'
  write_declining_profile "$state/dotfiles/profile"

  output=$(DOTFILES="$clone" XDG_STATE_HOME="$state" sh -- "$clone/update.sh" 2>&1)
  status=$?

  assertTrue "Expected the update to exit clean, got: $output" "$status"
  assertTrue "Expected the upstream commit in the clone" "[ -f '$clone/upstream-marker' ]"
  assertContains "Expected the pull to be reported" "$output" "1 commit pulled"
  assertContains "Expected the deploy to replay the profile" \
    "$output" "Replaying the answers"
  assertContains "Expected the deploy to reach its epilogue" "$output" "Done."
}

# shellcheck source=../tests/shunit2
. shunit2
