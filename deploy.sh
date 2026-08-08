#!/usr/bin/env sh
#
# Installs programs and configures them to use the respective dotfiles.
#
# Many configurations come from several repos out there.
#
# Honorable inspirations:
# https://github.com/Parth/dotfiles
# https://github.com/codehearts/dotfiles
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
# shellcheck source=lifecycle/deploy_profile.sh
. "$DOTFILES/lifecycle/deploy_profile.sh"
. "$DOTFILES/asdf/activate.sh"

# Packages required for basic operations
basic_packages="wget tar gzip"

# Modules the wizard offers, in the order they are asked. A module's position
# here is the counter in its section header.
deploy_modules="zsh zimfw asdf tmux git pi claude"

# Modules that ran but did not finish — a failed step, or one the user
# cancelled. Names collect here so the epilogue can name them and the run can
# exit non-zero. Reset at the top of every deploy_wizard.
_DEPLOY_INCOMPLETE=''

check_basic_packages() {
  for cmd in $basic_packages; do
    command_exists "$cmd" || return 1
  done
}

install_basic_packages() {
  # shellcheck disable=SC2086 # word splitting on purpose
  install_from_pm --as 'basic packages' \
    --die "Couldn't install basic packages" \
    -- $basic_packages
}

# Announce module $1 with its position in deploy_modules, run its wizard, and
# record it when it does not finish.
# $1: module name
# Returns the module wizard's exit status.
run_module() {
  local name index total m status
  name=${1:?} index=0 total=0
  for m in $deploy_modules; do
    total=$((total + 1))
    [ "$m" = "$name" ] && index=$total
  done
  tui_section "$name" "$index" "$total"
  start_module_wizard "$name"
  status=$?
  if [ "$status" -ne 0 ]; then
    _DEPLOY_INCOMPLETE="${_DEPLOY_INCOMPLETE}${_DEPLOY_INCOMPLETE:+ }$name"
    # The module has already said what went wrong; this line names the module
    # it went wrong in, and is the only marker when a step failed silently.
    tui_fail "$name did not complete"
  fi
  return "$status"
}

# Closing line for a run that reached the end.
# Returns 1 when anything was left incomplete.
deploy_epilogue() {
  local restart
  if command_exists zsh; then
    # shellcheck disable=SC2016 # the backticks are literal, quoting a command
    restart='Restart your shell with `exec zsh` to pick up the changes.'
  else
    restart='Restart your shell to pick up the changes.'
  fi

  echo
  if [ -z "$_DEPLOY_INCOMPLETE" ]; then
    tui_ok "Done. $restart"
    return 0
  fi
  tui_warn "Done, but $(english_list "$_DEPLOY_INCOMPLETE") did not complete."
  tui_detail 'Re-run with DEBUG=1 for full output.'
  tui_detail "$restart"
  return 1
}

# Say that the questions below are answering themselves, and how to answer them
# by hand again. Nothing to say on a first run, which has no profile to replay.
announce_replayed_profile() {
  [ -n "$DOTFILES_ANSWERS" ] || return 0
  tui_detail "Replaying the answers in $(get_deploy_profile_path)"
  # shellcheck disable=SC2016 # names the invocation, does not run it
  tui_detail 'Run with DOTFILES_ANSWERS='"''"' to answer them again.'
}

deploy_wizard() {
  _DEPLOY_INCOMPLETE=''

  # An unset map replays the last deploy's answers; a caller-supplied map
  # (even empty, for a fresh interview) wins instead.
  if [ -n "${DOTFILES_ANSWERS+set}" ]; then
    validate_answers "$deploy_modules"
  else
    load_deploy_profile
    drop_unknown_answers "$deploy_modules"
    announce_replayed_profile
  fi

  check_supported_pm || die "Sorry, this OS is not supported."

  if ! check_basic_packages; then
    press_any_key "Basic packages needed: $basic_packages"
    install_basic_packages
  fi

  # Put an already-installed-but-off-PATH asdf on PATH for the whole run, so
  # is_asdf_installed (and later modules like pi) see it regardless of which
  # questions get answered below.
  activate_asdf

  # zimfw and asdf both depend on zsh dotfiles.
  if confirm -k zsh "Install zsh?" && run_module zsh; then
    if confirm -k zimfw "Install zimfw (zsh framework)?"; then
      run_module zimfw
    fi
    if confirm -k asdf "Install asdf?"; then
      run_module asdf
      activate_asdf
    fi
  fi

  if confirm -k tmux "Install tmux?"; then
    run_module tmux
  fi

  if confirm -k git "Install git (and default configs)?"; then
    run_module git
  fi

  if confirm -k pi "Install pi?"; then
    run_module pi
  fi

  if confirm -k claude "Configure claude code?"; then
    run_module claude
  fi

  # Answers, not outcomes: a module accepted but failed still stays in the
  # profile, so the next run retries it. A run that dies before here writes
  # nothing and leaves the previous profile alone.
  save_deploy_profile

  deploy_epilogue
}

# Run installation if not called with dotfiles_dont_run
# shellcheck disable=SC2154
if [ -z "$dotfiles_dont_run" ]; then
  deploy_wizard
fi
