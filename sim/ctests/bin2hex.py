#!/usr/bin/env python3
"""Convert a raw flat binary (ldblip -b output) to a $readmemh hex file: one byte per line,
two lowercase hex digits. mem[i] gets image byte i, so a base-0 image lands at address 0."""
import sys


def main() -> int:
    if len(sys.argv) != 3:
        sys.stderr.write("usage: bin2hex.py <in.bin> <out.hex>\n")
        return 2
    data = open(sys.argv[1], "rb").read()
    with open(sys.argv[2], "w") as f:
        f.write("".join(f"{b:02x}\n" for b in data))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
