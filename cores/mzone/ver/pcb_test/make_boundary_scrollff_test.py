#!/usr/bin/env python3
from pathlib import Path
import os

pcb = Path(__file__).resolve().parent
source_name = os.environ.get("MZONE_BOUNDARY_SOURCE", "megazone_grid_scrollp1px")
output_name = os.environ.get("MZONE_BOUNDARY_NAME", "tboundary_scrollff")
screen_flip = os.environ.get("MZONE_SCREEN_FLIP") == "1"
src_bin = pcb / f"{source_name}_6h.bin"
src_sim = pcb / f"{source_name}_6h_sim.rom"
out_bin = pcb / f"{output_name}_6h.bin"
out_sim = pcb / f"{output_name}_6h_sim.rom"


def sprite_x(value):
    return (251 - value) & 0xFF if screen_flip else value


def sprite_y(value):
    return (241 - value) & 0xFF if screen_flip else value

# Captured data starts at CPU $E400, file offset $0400. SCROLL VRAM is
# first and SCROLL CRAM follows FIX VRAM at offset $0C00.
rom = bytearray(src_bin.read_bytes())
for row in range(32):
    # Keep column 31 as the original captured grid character so the final
    # SCROLL tile-map column provides a matching edge reference.
    for col in range(2, 31):  # SCROLL cells beginning immediately after FIX
        cell = row * 32 + col
        rom[0x0400 + cell] = (row * 30 + col - 2) % 36  # 0-9, A-Z
        rom[0x0C00 + cell] = 0x0F

# OBJ capture follows the four 1 KiB tile/color captures at file offset $1400.
# Clear it, keep the original stock balloon, and add two white reference
# sprites on a separate row at the requested raw X coordinates. Code $44 with
# attribute $4E is the stock white diagnostic sprite used by the other M-Zone
# PCB tests.
rom[0x1400:0x1800] = bytes(0x400)
rom[0x1400:0x1404] = bytes((0x4E, sprite_y(0xC5), 0xAA, sprite_x(0x00)))
rom[0x1404:0x1408] = bytes((0x4E, sprite_y(0xA5), 0x44, sprite_x(0x0A)))
rom[0x1408:0x140C] = bytes((0x4E, sprite_y(0xA5), 0x44, sprite_x(0xF8)))
rom[0x140C:0x1410] = bytes((0x4E, sprite_y(0xD5), 0x44, sprite_x(0xFB)))
out_bin.write_bytes(rom)

sim = bytearray(src_sim.read_bytes())
sim[0xE000:0x10000] = rom
out_sim.write_bytes(sim)

print(f"Wrote {out_bin} ({len(rom)} bytes)")
print(f"Wrote {out_sim} ({len(sim)} bytes)")
