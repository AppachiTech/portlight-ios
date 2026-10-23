#!/usr/bin/env python3
"""Regenerates Sources/PortlightKit/Keys/BlowfishConstants.swift.

Blowfish's initial P-array and S-boxes are the fractional hexadecimal digits
of pi. Computing them here (Machin's formula, integer arithmetic) instead of
pasting a table keeps the constants reviewable: anyone can rerun this and
diff the output.
"""
import pathlib

WORDS = 18 + 4 * 256
HEX = WORDS * 8
GUARD = 20
SCALE = 16 ** (HEX + GUARD)


def arctan_inv(x: int) -> int:
    total = term = SCALE // x
    x2, n, sign = x * x, 1, -1
    while term:
        term //= x2
        total += sign * (term // (2 * n + 1))
        sign, n = -sign, n + 1
    return total


def main() -> None:
    pi = 16 * arctan_inv(5) - 4 * arctan_inv(239)
    digits = format(pi - 3 * SCALE, "x").rjust(HEX + GUARD, "0")[:HEX]
    words = [int(digits[i * 8:(i + 1) * 8], 16) for i in range(WORDS)]
    boxes = [words[18 + 256 * b:18 + 256 * (b + 1)] for b in range(4)]
    # Spot checks against the published tables.
    assert words[0] == 0x243F6A88 and words[17] == 0x8979FB1B
    assert boxes[0][0] == 0xD1310BA6 and boxes[3][0] == 0x3A39CE37 and boxes[3][255] == 0x3AC372E6

    def table(name, ws):
        rows = ["        " + ", ".join(f"0x{w:08X}" for w in ws[i:i + 6]) + "," for i in range(0, len(ws), 6)]
        return f"    static let {name}: [UInt32] = [\n" + "\n".join(rows) + "\n    ]\n"

    out = [
        "// Generated from the hexadecimal digits of pi (the Blowfish constants).",
        "// Do not edit by hand: regenerate with scripts/gen_blowfish_constants.py.",
        "",
        "enum BlowfishConstants {",
        table("p", words[:18]),
        *[table(f"s{b}", boxes[b]) for b in range(4)],
        "}",
        "",
    ]
    path = pathlib.Path(__file__).resolve().parent.parent / "Sources/PortlightKit/Keys/BlowfishConstants.swift"
    path.write_text("\n".join(out))
    print(f"wrote {path}")


if __name__ == "__main__":
    main()
