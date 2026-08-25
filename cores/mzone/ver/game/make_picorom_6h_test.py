#!/usr/bin/env python3
"""Build a standalone 8 KiB Mega Zone main-CPU test ROM for socket 6H."""

from pathlib import Path


BASE = 0xE000
SIZE = 0x2000
OUT = Path(__file__).with_name("megazone_6h_test.bin")
SIM_OUT = Path(__file__).with_name("megazone_6h_test_sim.rom")
SOURCE_ROM = Path(__file__).resolve().parents[4] / "rom" / "megazone.rom"
rom = bytearray([0xFF] * SIZE)


def put(addr, *values):
    offset = addr - BASE
    if offset < 0 or offset + len(values) > SIZE:
        raise ValueError(f"address outside 6H: {addr:04x}")
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


def sta_ext(pc, addr):
    op(pc, 0xB7)
    put(pc + 1, addr >> 8, addr)
    return pc + 3


def fill_1k(pc, addr, initial, increment):
    """Fill four 256-byte pages using B's zero-to-FF wraparound."""
    pc = ldx_imm(pc, addr)
    pc = lda_imm(pc, initial)
    for _ in range(4):
        pc = ldb_imm(pc, 0)
        loop = pc
        op(pc, 0xA7)       # sta ,x+
        put(pc + 1, 0x80)
        pc += 2
        if increment:
            op(pc, 0x4C)   # inca
            pc += 1
        op(pc, 0x5A)       # decb
        pc += 1
        op(pc, 0x26)       # bne loop
        put(pc + 1, loop - (pc + 2))
        pc += 2
    return pc


pc = BASE
op(pc, 0x10)               # lds #$3fff
op(pc + 1, 0xCE)
put(pc + 2, 0x3F, 0xFF)
pc += 4

pc = lda_imm(pc, 0)
pc = sta_ext(pc, 0x1000)   # horizontal scroll = 0
pc = sta_ext(pc, 0x1800)   # vertical scroll = 0
pc = fill_1k(pc, 0x3000, 0x00, False)  # clear object RAM
pc = fill_1k(pc, 0x2000, 0x00, True)   # SCROLL: repeating tile codes
pc = fill_1k(pc, 0x2800, 0x0F, False)  # SCROLL: palette 15
pc = fill_1k(pc, 0x2400, 0x00, True)   # FIX: repeating tile codes
pc = fill_1k(pc, 0x2C00, 0x0E, False)  # FIX: palette 14

watchdog_loop = pc
pc = sta_ext(pc, 0x0800)   # service hardware watchdog forever
op(pc, 0x20)               # bra watchdog_loop
put(pc + 1, watchdog_loop - (pc + 2))
pc += 2

# Hardware vectors are data, so they are not Konami-1 encoded.
put(0xFFF8, 0xE0, 0x00)    # IRQ (unused)
put(0xFFFC, 0xE0, 0x00)    # NMI (unused)
put(0xFFFE, 0xE0, 0x00)    # reset -> $E000

OUT.write_bytes(rom)
print(f"Wrote {OUT} ({len(rom)} bytes), program end ${pc:04X}")

# The assembled simulation ROM places the main CPU's 64 KiB region first, so
# CPU $E000-$FFFF is the same byte range as the standalone 6H image.
sim_rom = bytearray(SOURCE_ROM.read_bytes())
if len(sim_rom) < BASE + SIZE:
    raise ValueError(f"assembled ROM is too small: {SOURCE_ROM}")
sim_rom[BASE:BASE + SIZE] = rom
SIM_OUT.write_bytes(sim_rom)
print(f"Wrote {SIM_OUT} ({len(sim_rom)} bytes) using {SOURCE_ROM}")
