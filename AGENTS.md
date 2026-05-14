## Architecture

This repo is a portable dotfiles setup organized as self-contained, per-tool modules (`git/`, `tmux/`, `zsh/`, etc.). Each module owns its configuration files, install scripts, and tests. A top-level `deploy.sh` acts as the bootstrap entry point, delegating to per-module installers.

Shared utilities live in `utils/utils.sh` and are sourced by other scripts. Test infrastructure (shunit2, shpy mocks, Dockerfiles) lives in `tests/`.

Scripts are written in POSIX `sh`, not bash. They respect XDG directories.

## Testing

Tests use [shunit2](https://github.com/kward/shunit2) (vendored in `tests/`) with [shpy](https://github.com/codehearts/shpy) for spy/mock support.

**Two test tiers:**

- **Unit tests** (`test_*.sh`) — run locally or in Docker; test individual functions in isolation
- **System tests** (`test_*.system.sh`) — run in Docker only; test full install flows against real environments

System tests run per-function inside Docker containers (not per-file). A `# @image: <stage>` annotation on a test function selects which Dockerfile stage to use. The `Makefile` drives all test execution (`make unit-test`, `make system-tests`).

**Test file conventions:**
- Unit test functions are named `test_<description>()`
- System test functions are named `it_<description>()`
- Setup and teardown use `setUp()`, `tearDown()`, `oneTimeSetUp()` shunit2 hooks
- Spies are cleaned up in `tearDown()` via `cleanupSpies`; temp files via `cleanupTestDir`

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
readonly THISDIR=$(p="/$0"; p=${p%/*}; p=${p#/}; p=${p:-.}; CDPATH='' cd -- "$p" >/dev/null && pwd -P)
```

**Comments:** Each function gets a short comment directly above it describing what it does. If it takes arguments or flags, document them on subsequent lines: `-n: make default answer NO` / `$1: confirmation message`. If the return value is non-obvious, note it too: `Returns 0 on cancel or >=1 for the choice`. No block comments, no `@param`/`@returns` tags.

Related functions are grouped with a `#\n# Section name\n#` divider. Inline comments inside a function explain non-obvious logic only — a workaround, a hidden constraint, a subtle invariant — never what the code does.
