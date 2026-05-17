## Architecture

This repo is a portable dotfiles setup organized as self-contained, per-tool modules (`git/`, `tmux/`, `zsh/`, etc.). Each module owns its configuration files, install scripts, and tests. A top-level `deploy.sh` acts as the bootstrap entry point, delegating to per-module installers.

Shared utilities live in `utils/utils.sh` and are sourced by other scripts. Test infrastructure (shunit2, shpy mocks, Dockerfiles) lives in `tests/`.

Scripts are written in POSIX `sh`, not bash. They respect XDG directories.

## Testing

Tests use [shunit2](https://github.com/kward/shunit2) (vendored in `tests/`) with [shpy](https://github.com/codehearts/shpy) for spy/mock support.

**Two test tiers:**

- **Unit tests** (`test_*.sh`) — run locally or in Docker; test individual functions in isolation
- **System tests** (`test_*.system.sh`) — run in Docker only; test full install flows against real environments

System tests run per-function inside Docker containers (not per-file). A `# @image: <stage>` annotation on a test function selects which Dockerfile stage to use. The `Makefile` is the canonical entry point — it rebuilds images automatically when their Dockerfile changes, so prefer it over invoking `tests/run_system_test.sh` directly.

**Running tests via `make`:**
```sh
make unit                                # all unit tests, locally
make unit-ubuntu                         # all unit tests, inside ubuntu image
make system-ubuntu                       # all system tests, inside ubuntu image
make unit-tests                          # all unit tests, on every image
make system-tests                        # all system tests, on every image
```

**Filters** (work with any target, combinable):
```sh
make unit FILE=zsh/test_install_zsh.sh                       # one file only
make system-ubuntu TEST=it_installs_zsh_and_its_dotfiles     # one case only
make system-ubuntu FILE=zsh/test_install_zsh.system.sh TEST=it_checks_zsh_is_not_installed
```

`DEBUG=1` enables verbose docker output. Run `make help` for the full target list.

**Test file conventions:**
- Unit test functions are named `test_<description>()`
- System test functions are named `it_<description>()`
- Setup and teardown use `setUp()`, `tearDown()`, `oneTimeSetUp()` shunit2 hooks
- Spies are cleaned up in `tearDown()` via `cleanupSpies`; temp files via `cleanupTestDir`
- Wrap noisy commands with `quietly` instead of `>/dev/null 2>&1` — it respects `DEBUG=1`:
  ```sh
  # in oneTimeSetUp: . "$THISDIR/../tests/utils_for_test.sh"
  quietly install_tmux_from_source "$version" "$prefix"
  ```

## Linting

```sh
make lint
```
Runs shellcheck in Docker over every `*.sh` in the repo. Config in `.shellcheckrc`. `old/` folder is excluded.

## Code Style

**Shell:**
- Shebang: `#!/usr/bin/env sh`
- 2-space indentation
- POSIX-compatible constructs only; no `[[ ]]`, no bash arrays
- Variables quoted consistently: `"$var"`, `"${var}"`, `"${var:-default}"`, `"${1:?}"`
- Command substitution via `$(...)`, not backticks

**Naming:**
- Functions and scripts: `snake_case`
- Global/exported variables: `UPPER_CASE`
- Local variables: `lower_case`

**Functions:**
- Complex install flows wrap their body in a subshell with `set -e` for implicit error propagation
- Simple utilities are flat functions
- Error exit via a shared `die "message" [code]` function

**Self-location pattern** (used in every script to find its own directory):
```sh
THISDIR="$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)"
readonly THISDIR
```

**Comments:** Each function gets a short comment directly above it describing what it does. If it takes arguments or flags, document them on subsequent lines: `-n: make default answer NO` / `$1: confirmation message`. If the return value is non-obvious, note it too: `Returns 0 on cancel or >=1 for the choice`. No block comments, no `@param`/`@returns` tags.

Related functions are grouped with a `#\n# Section name\n#` divider. Inline comments inside a function explain non-obvious logic only — a workaround, a hidden constraint, a subtle invariant — never what the code does.
