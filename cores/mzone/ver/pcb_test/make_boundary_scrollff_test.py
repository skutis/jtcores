#!/usr/bin/env python3
from pathlib import Path

pcb = Path(__file__).resolve().parent
src_bin = pcb / "megazone_grid_scrollp1px_6h.bin"
src_sim = pcb / "megazone_grid_scrollp1px_6h_sim.rom"
out_bin = pcb / "tboundary_scrollff_6h.bin"
out_sim = pcb / "tboundary_scrollff_6h_sim.rom"

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
# Clear it and add one stock balloon crossing the normal FIX boundary.
rom[0x1400:0x1800] = bytes(0x400)
rom[0x1400:0x1404] = bytes((0x4E, 0xC5, 0xAA, 0x00))
out_bin.write_bytes(rom)

sim = bytearray(src_sim.read_bytes())
sim[0xE000:0x10000] = rom
out_sim.write_bytes(sim)

print(f"Wrote {out_bin} ({len(rom)} bytes)")
print(f"Wrote {out_sim} ({len(sim)} bytes)")
