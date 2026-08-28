#!/usr/bin/env python3
"""Build a 6H PicoROM image that restores the captured MAME grid scene."""

from pathlib import Path
import os


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BASE = 0xE000
SIZE = 0x2000
DATA_BASE = 0xE400
OUTPUT_NAME = os.environ.get("MZONE_GRID_NAME", "megazone_grid")
SCROLLY = int(os.environ.get("MZONE_GRID_SCROLLY", "0"), 0) & 0xFF
OUT = HERE / f"{OUTPUT_NAME}_6h.bin"
SIM_OUT = HERE / f"{OUTPUT_NAME}_6h_sim.rom"
SOURCE_ROM = ROOT / "rom" / "megazone.rom"
rom = bytearray([0xFF] * SIZE)


def put(addr, *values):
    offset = addr - BASE
    if offset < 0 or offset + len(values) > SIZE:
        raise ValueError(f"address outside 6H: ${addr:04X}")
    rom[offset:offset + len(values)] = bytes(value & 0xFF for value in values)


def konami_opcode(addr, plain):
    mask = (
        ((addr >> 1) & 1) << 7
        | ((~(addr >> 1)) & 1) << 5
        | ((addr >> 3) & 1) << 3
        | ((~(addr >> 3)) & 1) << 1
    )
    return plain ^ mask


def op(addr, plain):
    put(addr, konami_opcode(addr, plain))


def lda_imm(pc, value):
    op(pc, 0x86)
    put(pc + 1, value)
    return pc + 2


def ldb_imm(pc, value):
    op(pc, 0xC6)
    put(pc + 1, value)
    return pc + 2


def ldx_imm(pc, value):
    op(pc, 0x8E)
    put(pc + 1, value >> 8, value)
    return pc + 3


def ldy_imm(pc, value):
    op(pc, 0x10)
    op(pc + 1, 0x8E)
    put(pc + 2, value >> 8, value)
    return pc + 4


def sta_ext(pc, addr):
    op(pc, 0xB7)
    put(pc + 1, addr >> 8, addr)
    return pc + 3


def copy_1k(pc, source, destination):
    """Copy 1 KiB as four 256-byte loops using X=source and Y=destination."""
    pc = ldx_imm(pc, source)
    pc = ldy_imm(pc, destination)
    for _ in range(4):
        pc = ldb_imm(pc, 0)
        loop = pc
        op(pc, 0xA6)       # lda ,x+
        put(pc + 1, 0x80)
        pc += 2
        op(pc, 0xA7)       # sta ,y+
        put(pc + 1, 0xA0)
        pc += 2
        op(pc, 0x5A)       # decb
        pc += 1
        op(pc, 0x26)       # bne loop
        put(pc + 1, loop - (pc + 2))
        pc += 2
    return pc


def fill_1k(pc, destination, value):
    """Fill 1 KiB using four 256-byte loops."""
    pc = ldx_imm(pc, destination)
    pc = lda_imm(pc, value)
    for _ in range(4):
        pc = ldb_imm(pc, 0)
        loop = pc
        op(pc, 0xA7)       # sta ,x+
        put(pc + 1, 0x80)
        pc += 2
        op(pc, 0x5A)       # decb
        pc += 1
        op(pc, 0x26)       # bne loop
        put(pc + 1, loop - (pc + 2))
        pc += 2
    return pc


captures = (
    ("vram0.bin", 0x2000),
    ("vram1.bin", 0x2400),
    ("cram0.bin", 0x2800),
    ("cram1.bin", 0x2C00),
    ("obj.bin",   0x3000),
)

sources = []
data_pc = DATA_BASE
for filename, destination in captures:
    data = (HERE / filename).read_bytes()
    if len(data) != 0x400:
        raise ValueError(f"{filename}: expected 1024 bytes, got {len(data)}")
    put(data_pc, *data)
    sources.append((data_pc, destination))
    data_pc += len(data)

pc = BASE
op(pc, 0x10)               # lds #$3fff
op(pc + 1, 0xCE)
put(pc + 2, 0x3F, 0xFF)
pc += 4

# Keep both character layers opaque black while the captured VRAM/CRAM blocks
# are copied.
pc = fill_1k(pc, 0x2400, 0x10)
pc = fill_1k(pc, 0x2000, 0x10)

pc = lda_imm(pc, SCROLLY)
pc = sta_ext(pc, 0x1000)   # horizontal source offset
pc = lda_imm(pc, 0)
pc = sta_ext(pc, 0x1800)   # scrollx = 0
pc = sta_ext(pc, 0x0005)   # flip = 0

# Load each layer's attributes behind the opaque-black tile before replacing
# its VRAM. This prevents captured tiles appearing with reset attributes.
copy_order = (3, 1, 2, 0, 4)  # FIX CRAM/VRAM, SCROLL CRAM/VRAM, OBJ
for index in copy_order:
    source, destination = sources[index]
    pc = copy_1k(pc, source, destination)

watchdog_loop = pc
pc = sta_ext(pc, 0x0800)
op(pc, 0x20)               # bra watchdog_loop
put(pc + 1, watchdog_loop - (pc + 2))
pc += 2

if pc > DATA_BASE:
    raise ValueError(f"program overlaps captured data at ${pc:04X}")

put(0xFFF8, 0xE0, 0x00)    # IRQ (unused)
put(0xFFFC, 0xE0, 0x00)    # NMI (unused)
put(0xFFFE, 0xE0, 0x00)    # reset -> $E000

OUT.write_bytes(rom)
print(f"Wrote {OUT} ({len(rom)} bytes), program end ${pc:04X}")
print(f"SCROLLY=${SCROLLY:02X} (visible SCROLL shift {-SCROLLY:d} px modulo 256)")

sim_rom = bytearray(SOURCE_ROM.read_bytes())
if len(sim_rom) < BASE + SIZE:
    raise ValueError(f"assembled ROM is too small: {SOURCE_ROM}")
sim_rom[BASE:BASE + SIZE] = rom
SIM_OUT.write_bytes(sim_rom)
print(f"Wrote {SIM_OUT} ({len(sim_rom)} bytes) using {SOURCE_ROM}")
