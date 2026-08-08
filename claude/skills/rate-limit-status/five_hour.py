#!/usr/bin/env python3
"""Report the state of the Claude subscription 5-hour rate-limit window.

Emits a single JSON object on stdout. Reports only — no thresholds, no
actions. The caller decides what to do with the reported numbers.

Exit 0 with the reading, or exit 1 with {"error": ...} and no reading.
"""
import datetime
import json
import os
import sys
import urllib.error
import urllib.request
from typing import NoReturn

ENDPOINT = "https://api.anthropic.com/api/oauth/usage"
# Claude Code reads ~/.claude unless CLAUDE_CONFIG_DIR names another directory,
# and the dotfiles installer honors that too. This script follows it as well,
# which keeps the credentials next to the config that produced them.
CONFIG_DIR = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
CREDENTIALS = os.environ.get(
    "CLAUDE_CREDENTIALS", os.path.join(CONFIG_DIR, ".credentials.json")
)
TIMEOUT_SECONDS = 15


def fail(kind, detail) -> NoReturn:
    json.dump({"error": kind, "detail": detail}, sys.stdout, indent=2)
    print()
    sys.exit(1)


def read_token():
    try:
        with open(CREDENTIALS) as fh:
            oauth = json.load(fh).get("claudeAiOauth") or {}
    except FileNotFoundError:
        fail("no_credentials", f"{CREDENTIALS} not found; this skill needs a "
                               "subscription OAuth login, not an API key")
    except (OSError, ValueError) as exc:
        fail("unreadable_credentials", f"{CREDENTIALS}: {exc}")

    token = oauth.get("accessToken")
    if not token:
        fail("no_token", "credentials file has no claudeAiOauth.accessToken")
    # Milliseconds since epoch. Used only to explain a 401 after the fact.
    # Claude Code refreshes this file in place, so a token that looks stale may
    # still work, and one that looks fresh may still be revoked.
    return token, oauth.get("expiresAt")


def fetch(token):
    request = urllib.request.Request(
        ENDPOINT,
        headers={
            "Authorization": f"Bearer {token}",
            "anthropic-beta": "oauth-2025-04-20",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        return exc.code
    except (urllib.error.URLError, TimeoutError, ValueError) as exc:
        fail("unreachable", f"could not reach the usage endpoint: {exc}")


def main():
    now = datetime.datetime.now(datetime.timezone.utc)
    token, expires_at_ms = read_token()
    payload = fetch(token)

    if isinstance(payload, int):
        if payload == 401:
            stale = (
                expires_at_ms is not None
                and expires_at_ms / 1000 < now.timestamp()
            )
            fail("unauthorized", "the stored access token was rejected"
                 + (" and is past its recorded expiry; an active Claude Code "
                    "session refreshes it" if stale else ""))
        fail("http_error", f"usage endpoint returned HTTP {payload}")

    window = payload.get("five_hour")
    if not isinstance(window, dict):
        fail("no_window", "response contained no five_hour window")

    raw_reset = window.get("resets_at")
    used = window.get("utilization")
    # A reading is the whole point. A null here would read as "0% used" to
    # anything that summarizes it, and this script promised an error instead.
    if not isinstance(used, (int, float)) or isinstance(used, bool):
        fail("no_reading", "the five_hour window reported no utilization")

    reading = {
        "window": "five_hour",
        "used_percentage": used,
        "checked_at": now.replace(microsecond=0).isoformat(),
    }

    if raw_reset:
        # The endpoint returns a +00:00 offset today. Tolerate a "Z" suffix too,
        # because fromisoformat only learned to parse it in 3.11.
        resets_at = datetime.datetime.fromisoformat(raw_reset.replace("Z", "+00:00"))
        # An aware timestamp cannot subtract an offset-naive one, and an
        # endpoint that sends no offset is not worth a traceback. Read it as
        # UTC, which is what it has always been.
        if resets_at.tzinfo is None:
            resets_at = resets_at.replace(tzinfo=datetime.timezone.utc)
        remaining = max(0, int((resets_at - now).total_seconds()))
        reading["resets_at"] = raw_reset
        reading["resets_at_epoch"] = int(resets_at.timestamp())
        reading["seconds_remaining"] = remaining
        reading["summary"] = (
            f"{used}% of the 5h window used, resets in "
            f"{remaining // 3600}h{remaining % 3600 // 60:02d}m"
        )
    else:
        reading["resets_at"] = None
        reading["seconds_remaining"] = None
        reading["summary"] = f"{used}% of the 5h window used, reset time unreported"

    json.dump(reading, sys.stdout, indent=2)
    print()


if __name__ == "__main__":
    main()
