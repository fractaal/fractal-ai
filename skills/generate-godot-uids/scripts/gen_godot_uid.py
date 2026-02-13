#!/usr/bin/env python3
"""Generate Godot-style ResourceUID strings (uid://...)."""

import argparse
import secrets
import string

ALPHABET = string.digits + string.ascii_lowercase
PREFIX = "uid://"


def _to_base36(value: int) -> str:
    if value == 0:
        return "0"
    chars = []
    while value > 0:
        value, rem = divmod(value, 36)
        chars.append(ALPHABET[rem])
    return "".join(reversed(chars))


def _generate_uid() -> str:
    # ResourceUID 0 is invalid; ensure non-zero 64-bit value.
    value = 0
    while value == 0:
        value = secrets.randbits(64)
    return f"{PREFIX}{_to_base36(value)}"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate Godot ResourceUID strings (uid://...)."
    )
    parser.add_argument(
        "-n",
        "--count",
        type=int,
        default=1,
        help="Number of UIDs to generate (default: 1).",
    )
    parser.add_argument(
        "--bare",
        action="store_true",
        help="Output without the uid:// prefix.",
    )
    args = parser.parse_args()

    if args.count < 1:
        parser.error("--count must be >= 1")

    for _ in range(args.count):
        uid = _generate_uid()
        if args.bare:
            uid = uid[len(PREFIX) :]
        print(uid)


if __name__ == "__main__":
    main()
