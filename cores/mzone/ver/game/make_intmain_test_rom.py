#!/usr/bin/env python3

from pathlib import Path


SRC = Path("rom.bin").resolve()
OUT = Path("megazone_intmain_test.rom")
SOUND_OFFSET = 0x10000
SOUND_SIZE = 0x2000

# Z80 program:
#   di
#   ld   sp,$e7ff
#   ld   bc,$0800
# delay:
#   dec  bc
#   ld   a,b
#   or   c
#   jr   nz,delay
#   xor  a
#   ld   ($a000),a       ; pulse /INTMAIN once
# stop:
#   jp   stop
PROGRAM = bytes.fromhex(
    "f3 "
    "31 ff e7 "
    "01 00 08 "
    "0b 78 b1 20 fb "
    "af "
    "32 00 a0 "
    "c3 10 00"
)

rom = bytearray(SRC.read_bytes())
rom[SOUND_OFFSET:SOUND_OFFSET + SOUND_SIZE] = bytes([0xFF]) * SOUND_SIZE
rom[SOUND_OFFSET:SOUND_OFFSET + len(PROGRAM)] = PROGRAM
OUT.write_bytes(rom)
print(f"Wrote {OUT} ({len(rom)} bytes)")
