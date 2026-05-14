#!/usr/bin/env sh

# Run $@ suppressing all output, unless DEBUG=1
quietly() {
  if [ "${DEBUG:-}" = "1" ]; then
    "$@"
  else
    "$@" >/dev/null 2>&1
  fi
}

# Clean contents of temporary test dir SHUNIT_TMPDIR
cleanupTestDir() {
  # Only clean tmp dir if something is there
  if [ -n "$(command ls -qA -- "${SHUNIT_TMPDIR:?}")" ]; then (
      cd "${SHUNIT_TMPDIR:?}" &&
      # Clean all hidden and non-hidden files
      # https://unix.stackexchange.com/a/77313
      rm -rf -- ..?* .[!.]* *
  ) fi
}
