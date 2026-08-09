#!/usr/bin/env sh
#
# Fast-forwards the dotfiles clone, then reruns deploy.sh against the answers
# from the last deploy.
#
# This is an entry point, a peer to deploy.sh. The `dotfiles update` shell
# function runs it as a fresh `sh`, so the pull cannot rewrite the file
# mid-read.
#

# Try locate project's root folder
if [ -z "$DOTFILES" ]; then
  DOTFILES=$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null 2>&1 && pwd -P)
fi

if [ ! -f "$DOTFILES/utils/utils.sh" ]; then
  echo "Cannot find installation files. Please, run this script from dotfiles root folder." >&2
  exit 1
fi

export DOTFILES

. "$DOTFILES/utils/utils.sh"

#
# Preconditions
#

# True when $1 is the root of its git clone, not merely somewhere inside one.
# A copy of the dotfiles unpacked under an unrelated repository would match
# too, and aim every git call below at the wrong repository. Both paths are
# resolved to their real form, so a $DOTFILES reached through a symlink still
# matches.
is_clone_root() {
  local dir root
  dir=$(CDPATH='' cd -- "${1:?}" >/dev/null 2>&1 && pwd -P) || return 1
  root=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 1
  [ "$root" = "$dir" ]
}

# Echo the branch HEAD points at.
# Returns 1 on a detached HEAD, which has no branch to fast-forward.
current_branch() {
  git -C "$DOTFILES" symbolic-ref --quiet --short HEAD
}

# Echo the upstream of branch $1 as remote/branch, e.g. origin/main.
# Returns 1 when the branch tracks nothing, leaving the pull no source.
upstream_of() {
  git -C "$DOTFILES" rev-parse --abbrev-ref --symbolic-full-name "${1:?}@{upstream}" 2>/dev/null
}

# True unless the branch and its upstream ref $1 have both moved since they
# parted. Commits on this side alone are not a divergence: there is nothing to
# fast-forward over, and `git pull --ff-only` reports such a branch as already
# up to date.
# This checks the tracking ref before any fetch, so a genuinely diverged clone
# gets a clear message here. The --ff-only pull still has the final say on
# whatever the fetch brings in.
can_fast_forward_to() {
  local upstream counts
  upstream=${1:?}
  counts=$(git -C "$DOTFILES" rev-list --left-right --count "HEAD...$upstream") || return 1
  # shellcheck disable=SC2086 # "<ahead>\t<behind>", split on IFS
  set -- $counts
  [ "${1:-0}" -eq 0 ] || [ "${2:-0}" -eq 0 ]
}

# Echo the default branch of remote $1 as remote/branch, e.g. origin/main.
# Returns 1 when the clone holds no record of it. refs/remotes/<remote>/HEAD is
# written at clone time, and a clone made without it never got one.
default_branch_of() {
  git -C "$DOTFILES" symbolic-ref --quiet --short "refs/remotes/${1:?}/HEAD"
}

# Ask before fast-forwarding a branch the remote does not treat as its default.
# A fast-forward on a tracking feature branch is well defined, so this names
# the branch and lets the user decide, instead of refusing outright. It says
# nothing when the remote's default is unknown.
# This calls `confirm`, not `confirm_keyed`. Which branch a checkout sits on is
# not a deploy choice, so nothing here is recorded in the deploy profile.
# $1: current branch  $2: its upstream
confirm_branch() {
  local remote default
  # A remote name cannot hold a slash, so this is the whole of it.
  remote=${2%%/*}
  default=$(default_branch_of "$remote") || return 0
  [ "$2" = "$default" ] && return 0
  tui_warn "$1 tracks $2, not the default $default"
  tui_detail "If that default is stale, refresh it with: dotfiles && git remote set-head $remote --auto"
  confirm "Update from $2 anyway?"
}

#
# The pull
#

# Where HEAD sat before the pull, so the ✓ can say how far it moved.
_UPDATE_HEAD_BEFORE=''

# The ✓ wording for the pull, counted off what it actually brought in.
_pulled_msg() {
  local count
  count=$(git -C "$DOTFILES" rev-list --count "$_UPDATE_HEAD_BEFORE..HEAD") || count=0
  case "$count" in
    0) echo 'already up to date' ;;
    1) echo '1 commit pulled' ;;
    *) echo "$count commits pulled" ;;
  esac
}

# Fast-forward the clone, and return git's status.
# Nothing pre-flights the working tree here. `--ff-only` already refuses when
# the merge would touch a dirty or untracked file, and names those files in
# its refusal. tui_task shows that stderr as-is.
pull_clone() {
  _UPDATE_HEAD_BEFORE=$(git -C "$DOTFILES" rev-parse HEAD)
  tui_task "Pulling $(tui_path "$DOTFILES")" \
    --ok-cmd _pulled_msg \
    --fail "Couldn't fast-forward $(tui_path "$DOTFILES")" \
    -- git -C "$DOTFILES" pull --ff-only
}

#
# The deploy
#

# Hand the terminal to a fresh deploy.sh, and return its status.
# A child process, not a sourced function, so it rereads deploy.sh from disk
# after the pull (see the exit at the bottom of this file). It keeps the
# terminal because a newly added module may ask a question, and chsh or a
# package install may need sudo.
# $DOTFILES_ANSWERS is left alone on purpose. Unset is how deploy.sh knows to
# replay the saved profile.
run_deploy() {
  sh -- "${DOTFILES:?}/deploy.sh"
}

# Check the clone can be fast-forwarded, pull it, and redeploy from it.
# Returns the deploy's status, so a module that did not complete makes the
# whole update non-zero.
run_update() {
  local branch upstream

  tui_section 'update'
  is_clone_root "$DOTFILES" ||
    die "$(tui_path "$DOTFILES") is not a git clone. Run deploy.sh from the clone to point \$DOTFILES at it."
  branch=$(current_branch) ||
    die "$(tui_path "$DOTFILES") has a detached HEAD. Check out a branch to update it."
  upstream=$(upstream_of "$branch") ||
    die "Branch $branch has no upstream. Set one with: git -C $DOTFILES branch -u <remote>/$branch"
  can_fast_forward_to "$upstream" ||
    die "Branch $branch has diverged from $upstream. Reconcile them yourself, this only fast-forwards."
  if ! confirm_branch "$branch" "$upstream"; then
    tui_skip "Nothing pulled"
    return 1
  fi

  pull_clone || return $?

  run_deploy
}

# Run the update if not called with dotfiles_dont_run.
# The exit is what makes this script safe to pull over: `sh` reads a script by
# byte offset, so anything left unread when run_update returns would be read
# back out of the file the pull has already replaced. Exiting here means there
# is nothing left to read.
# shellcheck disable=SC2154
if [ -z "$dotfiles_dont_run" ]; then
  run_update
  exit $?
fi
