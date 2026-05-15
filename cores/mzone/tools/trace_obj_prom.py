#!/usr/bin/env python3
from pathlib import Path
import argparse


ROOT = Path(__file__).resolve().parents[3]
OBJ_START = 0x13000
PROM_START = 0x1F000

PLANE_OFFS = [0x4000 * 8 + 4, 0x4000 * 8 + 0, 4, 0]
X_OFFS = [
    0, 1, 2, 3,
    8 * 8 + 0, 8 * 8 + 1, 8 * 8 + 2, 8 * 8 + 3,
    16 * 8 + 0, 16 * 8 + 1, 16 * 8 + 2, 16 * 8 + 3,
    24 * 8 + 0, 24 * 8 + 1, 24 * 8 + 2, 24 * 8 + 3,
]
Y_OFFS = [
    0 * 8, 1 * 8, 2 * 8, 3 * 8, 4 * 8, 5 * 8, 6 * 8, 7 * 8,
    32 * 8, 33 * 8, 34 * 8, 35 * 8, 36 * 8, 37 * 8, 38 * 8, 39 * 8,
]


def bit_lsb(buf, bit_index):
    return (buf[bit_index // 8] >> (bit_index % 8)) & 1


def sprite_pen(gfx, code, x, y):
    base = code * 64 * 8
    pen = 0
    for plane in PLANE_OFFS:
        pen = (pen << 1) | bit_lsb(gfx, base + plane + X_OFFS[x] + Y_OFFS[y])
    return pen


def dac_rg(bits):
    return [0, 2, 4, 6, 9, 11, 13, 15][bits]


def dac_b(bits):
    return [0, 5, 10, 15][bits]


def rgb4(a16, idx):
    prom = a16[idx & 0x1F]
    return dac_rg(prom & 7), dac_rg((prom >> 3) & 7), dac_b((prom >> 6) & 3), prom


def main():
    parser = argparse.ArgumentParser(description="Trace Mega Zone OBJ pens through MAME C6/A16 PROMs.")
    parser.add_argument("--rom", default=str(ROOT / "rom" / "megazone.rom"))
    parser.add_argument("--code", type=lambda s: int(s, 0), default=0xAA)
    parser.add_argument("--color", type=lambda s: int(s, 0), default=None)
    args = parser.parse_args()

    rom = Path(args.rom).read_bytes()
    gfx = rom[OBJ_START:OBJ_START + 0x8000]
    prom = rom[PROM_START:PROM_START + 0x260]
    a16 = prom[:0x20]
    c6 = prom[0x20:0x120]

    colors = range(16) if args.color is None else [args.color & 0xF]
    for color in colors:
        seen = {}
        for y in range(16):
            for x in range(16):
                pen = sprite_pen(gfx, args.code, x, y)
                if pen and pen not in seen:
                    c6_addr = (color << 4) | pen
                    c6_val = c6[c6_addr] & 0xF
                    r, g, b, a16_prom = rgb4(a16, c6_val)
                    seen[pen] = (c6_addr, c6_val, a16_prom, r, g, b, x, y)

        print(f"color {color:x}")
        for pen in sorted(seen):
            c6_addr, c6_val, a16_prom, r, g, b, x, y = seen[pen]
            print(
                f"  pen={pen:x} c6_addr={c6_addr:02x} c6={c6_val:x} "
                f"a16_addr={c6_val:02x} a16={a16_prom:02x} rgb={r:x}{g:x}{b:x} "
                f"sample={x},{y}"
            )


if __name__ == "__main__":
    main()
