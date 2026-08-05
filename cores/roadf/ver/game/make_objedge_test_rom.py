#!/usr/bin/env python3
"""Build a Road Fighter ROM that displays isolated sprites at X=0 and X=8."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
SOURCE = ROOT / "rom" / "roadf.rom"
OUTPUT = ROOT / "rom" / "roadf_objedge_test.rom"

HEADER = 8
PROGRAM = 0x4000
OBJ_RAM = 0x1000
OBJ_X0 = 33
OBJ_X8 = 32


def rom_offset(cpu_address):
    # The assembled maincpu region retains the complete 64 KiB CPU address
    # space, including the blank 0000-3fff area. It is byte-addressed here;
    # SDRAM lane swapping happens later in the simulation/FPGA memory path.
    return HEADER + cpu_address


def konami_opcode(address, plain):
    mask = (
        ((address >> 1) & 1) << 7
        | ((~(address >> 1)) & 1) << 5
        | ((address >> 3) & 1) << 3
        | ((~(address >> 3)) & 1) << 1
    )
    return plain ^ mask


def put_cpu(rom, address, *values):
    for index, value in enumerate(values):
        rom[rom_offset(address + index)] = value & 0xFF


def opcode(rom, address, value):
    put_cpu(rom, address, konami_opcode(address, value))


def lda_imm(rom, pc, value):
    opcode(rom, pc, 0x86)
    put_cpu(rom, pc + 1, value)
    return pc + 2


def lda_ext(rom, pc, address):
    opcode(rom, pc, 0xB6)
    put_cpu(rom, pc + 1, address >> 8, address)
    return pc + 3


def sta_ext(rom, pc, address):
    opcode(rom, pc, 0xB7)
    put_cpu(rom, pc + 1, address >> 8, address)
    return pc + 3


def write_sprite(rom, pc, entry, attr, ypos, code, xpos):
    base = OBJ_RAM + entry * 4
    for address, value in (
        (base + 0, attr),
        (base + 1, ypos),
        (base + 2, code),
        (base + 3, xpos),
    ):
        pc = lda_imm(rom, pc, value)
        pc = sta_ext(rom, pc, address)
    return pc


def main():
    rom = bytearray(SOURCE.read_bytes())
    if len(rom) < rom_offset(0xFFFF) + 1:
        raise ValueError(f"{SOURCE} is too short for the Road Fighter CPU map")

    pc = PROGRAM

    # Clear the 34 scanned object entries in the CPU-visible inactive bank.
    # Keep this loop compact: full-ROM simulation starts the CPU only after the
    # download and an unrolled clear takes several additional video frames.
    pc = lda_imm(rom, pc, 0)
    opcode(rom, pc, 0x8E)  # LDX #OBJ_RAM
    put_cpu(rom, pc + 1, OBJ_RAM >> 8, OBJ_RAM)
    pc += 3
    opcode(rom, pc, 0xC6)  # LDB #34*4
    put_cpu(rom, pc + 1, 34 * 4)
    pc += 2
    clear_loop = pc
    opcode(rom, pc, 0xA7)  # STA ,X+
    put_cpu(rom, pc + 1, 0x80)
    pc += 2
    opcode(rom, pc, 0x5A)  # DECB
    pc += 1
    opcode(rom, pc, 0x26)  # BNE clear_loop
    put_cpu(rom, pc + 1, (clear_loop - (pc + 2)) & 0xFF)
    pc += 2

    # dr_y is the complement of stored Y. Keep the two edge tests vertically
    # isolated so their 16-pixel spans cannot overwrite each other.
    pc = write_sprite(rom, pc, OBJ_X0, 0x0F, (~96) & 0xFF, 0x00, 0x00)
    pc = write_sprite(rom, pc, OBJ_X8, 0x0F, (~128) & 0xFF, 0x00, 0x08)

    # Reading INTST toggles obj_frame, exposing the bank just written.
    pc = lda_ext(rom, pc, 0x1400)

    # Hold the test display indefinitely.
    loop = pc
    opcode(rom, pc, 0x20)  # BRA
    put_cpu(rom, pc + 1, (loop - (pc + 2)) & 0xFF)

    # Reset vector is data, not an opcode fetch.
    put_cpu(rom, 0xFFFE, PROGRAM >> 8, PROGRAM)

    OUTPUT.write_bytes(rom)
    print(f"wrote {OUTPUT}")


if __name__ == "__main__":
    main()
