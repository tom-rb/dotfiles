---
name: rate-limit-status
description: Read how much of the Claude subscription 5-hour rate-limit window is used and when it resets. Use when deciding whether there is budget left before starting long or expensive work, when the limit may cut the work off mid-task, or when the user asks how much of their limit is left.
---

Run:

```bash
python3 "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/rate-limit-status/five_hour.py"
```

It queries the account's usage endpoint and prints one JSON object. It takes no arguments and changes nothing.

## What comes back

```json
{
  "window": "five_hour",
  "used_percentage": 28.0,
  "checked_at": "2026-08-03T21:31:32+00:00",
  "resets_at": "2026-08-03T23:10:00.473996+00:00",
  "resets_at_epoch": 1785798600,
  "seconds_remaining": 5907,
  "summary": "28.0% of the 5h window used, resets in 1h38m"
}
```

- `used_percentage` — how much of the window the account has used, 0–100. At 100 the account cannot send another request until the reset.
- `resets_at` / `resets_at_epoch` — when the current window rolls over and `used_percentage` returns to 0.
- `seconds_remaining` — `resets_at` minus now, floored at 0. Compute it again rather than reuse a stale reading. It decays in real time.

A failed read exits 1 and prints `{"error": ..., "detail": ...}` instead. The error is most often `unauthorized` or `unreachable`. `unauthorized` means the endpoint rejected the stored token, and an active session refreshes it. **A failed read is not a reading of zero.** Treat it as unknown budget.

## This skill only reports

It applies no threshold and takes no action. The caller decides what counts as "too close to the limit", whether to stop, shrink the work, or wait for the window to reset.

## How to wait, if the caller chooses to

`seconds_remaining` is the exact duration to wait for a clean window. To wait, run a **backgrounded** `sleep`. A background command runs detached, stays alive across turns, and re-invokes the agent when it exits. The end of the sleep is itself the wake signal.

Add a small buffer past `resets_at`. The two clocks are not the same clock.

After a wake, run this skill again before you resume the work. A wake is not evidence that the window reset. The sleep may have been cut short, or the clock may have drifted. The fresh reading is the evidence.
