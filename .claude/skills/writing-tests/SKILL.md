---
name: writing-tests
description: Write unit and system tests for this dotfiles repo. Covers shunit2 + shpy conventions, file boilerplate, mocking patterns for git/package-manager calls, feeding stdin to interactive prompts (confirm, prompt_line, choose), the @image annotation for Docker-based system tests, and the make targets used to run filtered tests. Use when adding tests under any module directory (zsh/, tmux/, git/, utils/, tests/) or writing test_*.sh / test_*.system.sh files.
---

# Writing Tests

Tests live next to the code they cover: `<module>/test_<name>.sh` (unit) and `<module>/test_<name>.system.sh` (system, Docker-only). Run via `make` — never invoke `tests/run_*.sh` directly.

## Quick start

```sh
make unit FILE=git/test_install_git.sh                       # one unit file
make unit FILE=git/test_install_git.sh TEST=test_foo         # one case
make system-ubuntu FILE=git/test_install_git.system.sh       # one system file
make unit-tests                                              # all unit on every image
DEBUG=1 make system-ubuntu ...                               # verbose docker output
```

After creating a new `test_*.sh`: `chmod +x` it, or `make unit` fails with `Permission denied`.

## Unit test boilerplate

```sh
#!/usr/bin/env sh

THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
  DOTFILES="$(get_abs_path "$THISDIR/..")"
}

setUp() {
  . "$THISDIR/install_<thing>.sh"
}

tearDown() {
  cleanupSpies
  cleanupTestDir
}

test_<description>() {
  createSpy -u -o "" git
  # Wrap with `quietly` (from utils_for_test.sh) instead of `>/dev/null`.
  # It silences stdout+stderr by default and re-enables them under DEBUG=1.
  printf 'input\n' | quietly some_function
  assertCalledWith git config --global ...
}

SHPY_PATH="$THISDIR/../tests/shpy"
export SHPY_PATH
. "$THISDIR/../tests/shpy"
. "$THISDIR/../tests/shpy-shunit2"
. "$THISDIR/../tests/shunit2"
```

## System test boilerplate

```sh
#!/usr/bin/env sh
THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR

oneTimeSetUp() {
  . "$THISDIR/../tests/utils_for_test.sh"
  . "$THISDIR/install_<thing>.sh"
}

# Runs in the plain image (no `@image` means default stage)
it_checks_<thing>_is_not_installed() { ... }

# @image: base
it_installs_<thing>_end_to_end() {
  quietly install_<thing>_wizard
  ...
}

# shellcheck source=../tests/shunit2
. shunit2
```

Each `it_*` function runs in a fresh container. The `# @image: <stage>` annotation picks a Dockerfile stage (see [tests/systems/](../../../tests/systems/)); omitting it uses the default. Wrap setup commands with `quietly` — it respects `DEBUG=1`.

## Mocking with shpy

`createSpy` replaces a command or shell function with a recorder. Always pass `-u` so an already-loaded function gets unset and the spy wins:

```sh
createSpy -u -r "$SHUNIT_TRUE"  is_zsh_installed     # spy a function, force return 0
createSpy -u -r "$SHUNIT_FALSE" command_exists       # force return 1
createSpy -u -o "some output"   install_from_pm      # capture stdout (and calls)
createSpy -u -o "v1" -o "v2"    git                  # sequence; last value sticks for further calls
```

Assertions (cursor-based — `assertCalledWith` advances internally; do **not** pass a call index):

```sh
assertCallCount      install_from_pm 1
assertCalledOnceWith install_from_pm zsh             # exactly 1 call + args
assertCalledWith     git config --global --get init.templateDir   # next call
assertCalledWith     git config --global init.templateDir "$DOTFILES/git/templates"
assertNeverCalled    install_from_pm
```

For commands that get called many times with different args (e.g. `git config` for read+write+read+write), spy on `git` once and use repeated `assertCalledWith` calls in order. The cursor advances each time.

If `assertCalledWith` reports `was:<...first-call args...>` but your function logically *did* reach the later call, the cursor hasn't advanced — add an earlier `assertCalledWith` for each prior call in order. The failure message looks like "the expected call never happened" but really means "the cursor is still parked on an earlier call."

## Feeding stdin to interactive prompts

`utils/utils.sh` provides three interactive primitives. Each consumes a different amount of stdin per call — important when chaining them:

| Helper | Reads | How to feed |
|---|---|---|
| `confirm "..."` | one byte (`dd bs=1 count=1`) | `echo y \|`, `echo n \|`, `printf '\n'` for default |
| `confirm -n "..."` | one byte, default N | `printf '\n'` returns 1; `echo y \|` returns 0 |
| `choose a b c` | one byte | `echo 1 \|`, `echo q \|` to cancel |
| `prompt_line "msg" var` | one line via `read -r` | `printf 'value\n' \|`; trims leading/trailing whitespace |

Chaining confirm + prompt_line in the same function: each `\n` is consumed by one helper. For one `confirm` + one `prompt_line`:

```sh
printf '\nMy Name\n' | configure_thing      # first \n = default-Y to confirm; "My Name\n" → prompt_line
echo 'n' | configure_thing                  # confirm sees 'n', skips the prompt
```

For the deploy wizard (many confirms in a row): `yes | deploy_wizard` blasts `y\n` repeatedly.

## Filesystem isolation

`SHUNIT_TMPDIR` is a per-test temp dir — use it for any file you create. Common pattern: relocate `$HOME`:

```sh
setUp() {
  . "$THISDIR/install_<thing>.sh"
  HOME=${SHUNIT_TMPDIR:?}/home
  mkdir -p "$HOME"
}
```

`cleanupTestDir` (called in `tearDown` via `utils_for_test.sh`) clears it between tests.

## Naming & structure conventions

- Unit functions: `test_<description>()`
- System functions: `it_<description>()`
- Group related tests with `# Section name` dividers matching the source file's sections
- Source the SUT in `setUp` (not `oneTimeSetUp`) so each test gets a fresh function namespace
- Both `cleanupSpies` and `cleanupTestDir` belong in `tearDown`

## Don't forget

- `chmod +x` every new test file
- `make unit FILE=...` from the repo root, not the module dir
- After editing a system Dockerfile, the make target rebuilds automatically — no manual `docker build`
- Shellcheck-clean: `docker run --rm -v "$PWD:/app:ro" koalaman/shellcheck:stable $(find . -name '*.sh' -not -path '*/old/*' -not -path '*/tmux-cmds*' | sed 's|^.|/app|')`
