#!/usr/bin/env python3
"""Build the focused FIX/SCROLL boundary and OBJ-position comparison test."""

from pathlib import Path
import os


HERE = Path(__file__).resolve().parent
SOURCE_NAME = os.environ.get("MZONE_FIX_SOURCE", "tboundary_scrollff")
OUTPUT_NAME = os.environ.get("MZONE_FIX_NAME", "tfix_boundary")
SOURCE_BIN = HERE / f"{SOURCE_NAME}_6h.bin"
SOURCE_SIM = HERE / f"{SOURCE_NAME}_6h_sim.rom"
OUT = HERE / f"{OUTPUT_NAME}_6h.bin"
SIM_OUT = HERE / f"{OUTPUT_NAME}_6h_sim.rom"

rom = bytearray(SOURCE_BIN.read_bytes())

# Captured data starts at 6H file offset $0400 in this order:
# SCROLL VRAM, FIX VRAM, SCROLL CRAM, FIX CRAM, OBJ.
fix_vram = 0x0800
fix_cram = 0x1000

# First visible FIX row: glyph 7 at both ends, CPU cells $2440 and $2445.
for col in (0, 5):
    cell = 2 * 32 + col
    rom[fix_vram + cell] = 0x07
    rom[fix_cram + cell] = 0x0F

# Next FIX row, vdump 24..31: six solid blue/yellow references.
# PCB-confirmed stock combinations are blue $31/$0D and yellow $34/$0E.
pattern = ((0x31, 0x0D), (0x34, 0x0E), (0x31, 0x0D)) * 2
for col, (tile, attr) in enumerate(pattern):
    cell = 3 * 32 + col
    rom[fix_vram + cell] = tile
    rom[fix_cram + cell] = attr

OUT.write_bytes(rom)

sim = bytearray(SOURCE_SIM.read_bytes())
sim[0xE000:0x10000] = rom
SIM_OUT.write_bytes(sim)

print(f"Wrote {OUT} ({len(rom)} bytes)")
print(f"Wrote {SIM_OUT} ({len(sim)} bytes)")
