#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import time
import unicodedata

RESET = "\033[0m"
DIM = "\033[2m"
CYAN = "\033[36m"
BLUE = "\033[34m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
RED = "\033[31m"
BG_GRAY = "\033[48;5;235m"
BG_RESET = "\033[49m"

# Small safety margin: some terminals reserve a column or two for borders or
# scrollbars, and COLUMNS does not include them.
SAFETY_MARGIN = 3


# The columns one character takes on screen. Wide and full-width glyphs take 2.
def char_width(ch):
    return 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1


# The columns a string takes on screen. Skips the SGR escape sequences, which
# the terminal does not draw.
def visible_len(s):
    out = 0
    i = 0
    while i < len(s):
        if s[i] == "\033":
            j = s.find("m", i)
            i = j + 1 if j != -1 else len(s)
            continue
        out += char_width(s[i])
        i += 1
    return out


# The name of the checked-out git head in $1, and whether the head is detached.
# Returns an empty name if $1 is not a git repository.
def git_head(cwd):
    # Without this guard, git -C "" runs against the process working directory
    # and reports an unrelated repository.
    if not cwd:
        return "", False
    try:
        branch = subprocess.check_output(
            ["git", "-C", cwd, "branch", "--show-current"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
        if branch:
            return branch, False
        sha = subprocess.check_output(
            ["git", "-C", cwd, "rev-parse", "--short", "HEAD"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
        return sha, True
    # No git on PATH raises OSError. A directory outside a repository makes git
    # exit non-zero, which raises CalledProcessError. A branch name that is not
    # valid UTF-8 raises UnicodeDecodeError, because text=True decodes it.
    except (OSError, subprocess.SubprocessError, UnicodeDecodeError):
        return "", False


# The color for a usage percentage: green, then yellow from 70%, then red
# from 90%.
def bar_color(pct):
    if pct >= 90:
        return RED
    if pct >= 70:
        return YELLOW
    return GREEN


EIGHTHS = "▏▎▍▌▋▊▉█"


# Draws a bar of $2 cells filled to $1 percent, with the percentage as a label
# inside it. Partial cells use the eighth-block glyphs.
# suffix: the text after the number in the label. Pass "" to drop the "%".
def render_bar(pct, width, color, suffix="%"):
    total_eighths = round(width * 8 * pct / 100)
    total_eighths = max(0, min(total_eighths, width * 8))
    full, remainder = divmod(total_eighths, 8)
    chars = ["█"] * full
    if remainder:
        chars.append(EIGHTHS[remainder - 1])
        full += 1
    # Plain space, not "░": the unfilled part of the partial-eighth glyph is
    # blank, so a dotted empty cell next to it would clash.
    chars += [" "] * (width - full)

    # Overlay the percentage as a label. Center the label in the empty region
    # (under 50%) or in the filled region (from 50% up), not in a fixed half.
    # The label then moves toward the true center as the usage nears 0%, and
    # does not hold a fixed position in the middle of the right half.
    # In compact mode, suffix="" removes the "%" so the bare digits still fit.
    label = f"{pct}{suffix}"
    boundary = max(0, min(width, -(-pct * width // 100)))  # ceil(pct/100*width)
    if pct < 50:
        region_start, region_width = boundary, width - boundary
    else:
        region_start, region_width = 0, boundary
    label = label[:region_width] if region_width else ""
    start = region_start + max(0, (region_width - len(label)) // 2)
    for i, ch in enumerate(label):
        pos = start + i
        if region_start <= pos < region_start + region_width:
            chars[pos] = ch

    bar_str = f"{color}{''.join(chars)}{RESET}"

    # Give the whole track a low-luminance gray background, independent of the
    # foreground colors and glyphs above. Each internal RESET clears all SGR
    # state, the background too. Set the background again after every RESET.
    bar_str = bar_str.replace(RESET, RESET + BG_GRAY)
    return f"{BG_GRAY}{bar_str}{BG_RESET}"


# The time left until the epoch second $1, as "1h05".
def format_remaining(resets_at):
    remaining = max(0, int(resets_at - time.time()))
    hours, rem = divmod(remaining, 3600)
    minutes = rem // 60
    return f"{hours}h{minutes:02d}"


SHORT_EFFORT = {
    "low": "lo",
    "medium": "med",
    "high": "hi",
    "xhigh": "xhi",
    "max": "max",
}


# A token count as a short string: 84000 becomes "84K", 1500000 becomes "1.5M".
def format_tokens(n):
    if n >= 1_000_000:
        value = n / 1_000_000
        return f"{int(value)}M" if value == int(value) else f"{value:.1f}M"
    if n >= 1_000:
        return f"{round(n / 1_000)}K"
    return str(n)


# Builds the "[model effort] bar tokens 💰[5h w]" right section.
# compact: shrinks the context bar to 5 cells with no label inside, and
# shortens the effort level. The caller uses this as a fallback when the full
# section does not fit the terminal width.
def build_right(model, effort, thinking_enabled, pct, used_tokens, window_size,
                 five_hour_pct, five_hour_resets_at, weekly_pct, compact):
    model_part = f"{CYAN}{model}{RESET}"
    if effort:
        effort_label = SHORT_EFFORT.get(effort, effort) if compact else effort
        model_part += f" {YELLOW}{effort_label}{RESET}"
    elif thinking_enabled is not None:
        model_part += f" {'🧠' if thinking_enabled else '💤'}"

    bar_width = 5 if compact else 10
    color = bar_color(pct)
    bar = render_bar(pct, bar_width, color, suffix="" if compact else "%")
    right = f"{DIM}[{RESET}{model_part}{DIM}]{RESET} {bar}"
    if used_tokens is not None and window_size:
        right += f"{DIM}▏{RESET}{color}{format_tokens(used_tokens)}{RESET}{DIM}/{RESET}{format_tokens(window_size)}"
    else:
        right += f"{DIM}▏{RESET}{pct:02d}%"

    sub_part = ""
    if five_hour_pct is not None:
        rate_color = bar_color(five_hour_pct)
        label = format_remaining(five_hour_resets_at) if five_hour_resets_at else "5h"
        sub_part += f"{rate_color}{int(five_hour_pct):02d}%{RESET}{DIM}{label}{RESET}"

    if weekly_pct is not None:
        week_color = bar_color(weekly_pct)
        sep = " " if sub_part else ""
        sub_part += f"{sep}{week_color}{int(weekly_pct):02d}%{RESET}{DIM}w{RESET}"

    if sub_part:
        if compact:
            right += f" {DIM}💰{RESET}{sub_part}"
        else:
            right += f" {DIM}💰{RESET}{DIM}[{RESET}{sub_part}{DIM}]{RESET}"

    return right


# Reads the payload Claude Code sends on stdin, and prints the status line.
def main():
    data = json.load(sys.stdin)

    cwd = (data.get("workspace") or {}).get("current_dir") or data.get("cwd") or ""
    dirname = os.path.basename(cwd.rstrip("/")) or cwd

    model = (data.get("model") or {}).get("display_name") or "?"
    effort = (data.get("effort") or {}).get("level")
    thinking_enabled = (data.get("thinking") or {}).get("enabled")

    ctx = data.get("context_window") or {}
    pct = ctx.get("used_percentage")
    pct = int(pct) if pct is not None else 0
    used_tokens = ctx.get("total_input_tokens")
    window_size = ctx.get("context_window_size")

    rate_limits = data.get("rate_limits") or {}
    five_hour = rate_limits.get("five_hour") or {}
    five_hour_pct = five_hour.get("used_percentage")
    five_hour_resets_at = five_hour.get("resets_at")
    weekly_pct = (rate_limits.get("seven_day") or {}).get("used_percentage")

    branch, detached = git_head(cwd)

    # Left section: folder + cwd, git branch
    left = f"{BLUE}📁 {dirname}{RESET}"
    if branch:
        if detached:
            left += f"{DIM} | {RESET}{YELLOW}🚧 {branch}{RESET}"
        else:
            left += f"{DIM} | {RESET}{GREEN}🌿 {branch}{RESET}"

    try:
        columns = int(os.environ.get("COLUMNS", "80"))
    except ValueError:
        columns = 80
    budget = columns - SAFETY_MARGIN

    right = build_right(model, effort, thinking_enabled, pct, used_tokens, window_size,
                         five_hour_pct, five_hour_resets_at, weekly_pct, compact=False)
    if visible_len(left) + visible_len(right) > budget:
        right = build_right(model, effort, thinking_enabled, pct, used_tokens, window_size,
                             five_hour_pct, five_hour_resets_at, weekly_pct, compact=True)

    pad = budget - visible_len(left) - visible_len(right)
    pad = max(pad, 1)

    line = f"{left}{' ' * pad}{right}"

    print(line)


if __name__ == "__main__":
    main()
