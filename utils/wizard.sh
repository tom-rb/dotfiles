#!/usr/bin/env sh

#
# Wizard runner
#

# Execute a step list as an &&-chain, short-circuiting on first failure.
# -y: pipe `yes ""` into the chain so interactive prompts accept defaults;
#     without -y, stdin is left untouched.
# Steps are passed after a literal -- separator to avoid collision with flags:
#   wizard_run "$@" -- step1 step2 step3
wizard_run() {
  local use_yes=0
  if [ "$1" = "-y" ]; then
    use_yes=1
    shift
  fi
  # Consume the -- separator
  shift

  # Build an &&-chain string from the step names
  local chain=""
  for step in "$@"; do
    if [ -z "$chain" ]; then
      chain="$step"
    else
      chain="$chain && $step"
    fi
  done

  if [ "$use_yes" = 1 ]; then
    yes "" | eval "$chain"
  else
    eval "$chain"
  fi
}

# Dispatch helper for the --wizard flag at the bottom of installer scripts.
# $1: name of the wizard function to invoke
# $2+: the script's "$@"; invokes $1 when $2 = --wizard, no-ops otherwise
wizard_main() {
  local func_name="$1"
  shift
  if [ "$1" = "--wizard" ]; then
    "$func_name"
  fi
}

# Thin wrapper around `sh --` for testability; forwards all arguments unchanged.
_sh() {
  sh "$@"
}

# Shell out to a module's installer with --wizard, returning its exit code.
# $1: module name (e.g. "zsh" → runs zsh/install_zsh.sh --wizard)
# The sh -- subshell ensures a die inside the module doesn't kill the caller.
start_module_wizard() {
  _sh -- "${DOTFILES:?}/${1:?}/install_${1}.sh" --wizard
}
