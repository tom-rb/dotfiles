#!/usr/bin/env python3
"""Deep-merge a JSON template over a JSON target. The template wins.

Usage: merge_json.py <template> <target> <out>

This script merges objects key by key. Arrays and scalars in the template
replace the values in the target. The script keeps every key that the target
holds and the template does not name. This preserves machine-local settings.

The script writes the merged document to <out>, not over <target>. The caller
decides when to make a backup, and can put the result in place with a rename.
The script prints each key that the template overwrites to stdout, one
"dotted.path: old -> new" line for each key.

Exit codes:
  0  merged, and the result differs from the target
  1  the template is missing or is not a JSON object
  2  the target exists but does not read as a JSON object. <out> holds
     the template alone
  3  the target already agrees with the template. The script skips <out>
  4  the script merged the documents but could not write <out>
"""
import json
import sys

EXIT_MERGED = 0
EXIT_TEMPLATE_ERROR = 1
EXIT_TARGET_UNREADABLE = 2
EXIT_UNCHANGED = 3
EXIT_WRITE_ERROR = 4


def load_object(path):
    with open(path) as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise TypeError("not a JSON object")
    return data


def merge(template, target, prefix, overwritten):
    merged = dict(target)
    for key, new in template.items():
        path = prefix + key
        if key in target:
            old = target[key]
            if isinstance(new, dict) and isinstance(old, dict):
                merged[key] = merge(new, old, path + ".", overwritten)
                continue
            if old != new:
                overwritten.append((path, old, new))
        merged[key] = new
    return merged


def main(argv):
    if len(argv) != 3:
        # python -OO strips the docstring, which leaves __doc__ as None.
        print((__doc__ or "").strip(), file=sys.stderr)
        return EXIT_TEMPLATE_ERROR
    template_path, target_path, out_path = argv

    try:
        template = load_object(template_path)
    # json.load raises JSONDecodeError, a ValueError, when the text is not JSON.
    # load_object raises TypeError when the JSON is not an object.
    except (OSError, ValueError, TypeError) as err:
        print(f"{template_path}: {err}", file=sys.stderr)
        return EXIT_TEMPLATE_ERROR

    status = EXIT_MERGED
    loaded = False
    try:
        target = load_object(target_path)
        loaded = True
    except FileNotFoundError:
        target = {}
    except (OSError, ValueError, TypeError) as err:
        print(f"{target_path}: {err}", file=sys.stderr)
        target = {}
        status = EXIT_TARGET_UNREADABLE

    overwritten = []
    merged = merge(template, target, "", overwritten)

    # Compare as data, not as text. Claude Code rewrites this file with its own
    # format, and a new indentation is not a change worth a backup.
    if loaded and merged == target:
        return EXIT_UNCHANGED

    try:
        with open(out_path, "w") as handle:
            json.dump(merged, handle, indent=2)
            handle.write("\n")
    except OSError as err:
        print(f"{out_path}: {err}", file=sys.stderr)
        return EXIT_WRITE_ERROR

    for path, old, new in overwritten:
        print(f"{path}: {json.dumps(old)} -> {json.dumps(new)}")
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
