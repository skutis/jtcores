#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
SRC = ROOT / "rom" / "megazone.rom"
OUT = ROOT / "rom" / "megazone_scrolltest.rom"
SCR_START = 0x1B000
OBJ_START = 0x13000
PROM_START = 0x1F000


def konami_opcode(addr, plain):
    mask = (
        ((addr >> 1) & 1) << 7
        | ((~(addr >> 1)) & 1) << 5
        | ((addr >> 3) & 1) << 3
        | ((~(addr >> 3)) & 1) << 1
    )
    return plain ^ mask


def put(buf, addr, *data):
    for i, value in enumerate(data):
        buf[addr + i] = value & 0xFF


def encode_row(pens):
    bits = [0] * 32
    packed_pens = pens[3::-1] + pens[7:3:-1]
    bit_groups = (
        (4, 5, 6, 7), (0, 1, 2, 3), (12, 13, 14, 15), (8, 9, 10, 11),
        (20, 21, 22, 23), (16, 17, 18, 19), (28, 29, 30, 31), (24, 25, 26, 27),
    )
    for pen, group in zip(packed_pens, bit_groups):
        for i, bit in enumerate(group):
            bits[bit] = (pen >> (3 - i)) & 1
    value = 0
    for bit, state in enumerate(bits):
        value |= state << bit
    data = value.to_bytes(4, "big")
    # The local sim downloader uses SWAB=1, so graphics bytes are swapped in
    # 16-bit lanes before the 32-bit fix/scroll ROM port sees them.
    return bytes((data[1], data[0], data[3], data[2]))


def op(buf, addr, value):
    put(buf, addr, konami_opcode(addr, value))


def lda_imm(buf, pc, value):
    op(buf, pc, 0x86)
    put(buf, pc + 1, value)
    return pc + 2


def lda_ext(buf, pc, addr):
    op(buf, pc, 0xB6)
    put(buf, pc + 1, addr >> 8, addr)
    return pc + 3


def sta_ext(buf, pc, addr):
    op(buf, pc, 0xB7)
    put(buf, pc + 1, addr >> 8, addr)
    return pc + 3


def adda_imm(buf, pc, value):
    op(buf, pc, 0x8B)
    put(buf, pc + 1, value)
    return pc + 2


def nega(buf, pc):
    op(buf, pc, 0x40)
    return pc + 1


def write_vram_cram(buf, pc, vram_base, cram_base, offs, tile, color):
    pc = lda_imm(buf, pc, tile)
    pc = sta_ext(buf, pc, vram_base + offs)
    pc = lda_imm(buf, pc, color)
    pc = sta_ext(buf, pc, cram_base + offs)
    return pc


def write_sprite(buf, pc, index, attr, ypos, code, xpos):
    base = 0x3000 + index * 4
    pc = lda_imm(buf, pc, attr)
    pc = sta_ext(buf, pc, base + 0)
    pc = lda_imm(buf, pc, ypos)
    pc = sta_ext(buf, pc, base + 1)
    pc = lda_imm(buf, pc, code)
    pc = sta_ext(buf, pc, base + 2)
    pc = lda_imm(buf, pc, xpos)
    pc = sta_ext(buf, pc, base + 3)
    return pc


def main():
    rom = bytearray(SRC.read_bytes())

    # Give only the start-position diagnostic markers their own CRAM color.
    marker_color = 0x0B
    put(rom, PROM_START + 0x120 + 0xB7, 0x3E)
    put(rom, PROM_START + 0x120 + 0xBF, 0x3E)
    put(rom, PROM_START + 0x01E, 0x3F)

    border_rows = []
    for row in range(8):
        pens = [0x0] * 8
        if row == 0 or row == 7:
            pens = [0xF] * 8
        else:
            pens[0] = 0xF
            pens[7] = 0xF
        if row == 0:
            pens[7] = 0xE
        border_rows.append(encode_row(pens))

    # Make tile $08 a solid diagnostic tile in the scroll/fix graphics region.
    # jtmzone_scroll addresses graphics as 32-bit words:
    # {code_msb, tile_code, row}. Four $ff bytes decode to pen $f for all pixels.
    for row in range(8):
        word_addr = (0x08 << 3) | row
        put(rom, SCR_START + word_addr * 4, 0xFF, 0xFF, 0xFF, 0xFF)

    # Tile $09 is an extra copy of the outside-border marker.
    for row, data in enumerate(border_rows):
        word_addr = (0x09 << 3) | row
        put(rom, SCR_START + word_addr * 4, *data)

    obj_code = 0xAA

    # Main CPU IRQ test program at $8000. Opcode bytes are Konami-1 encoded;
    # operands are stored plain because jtframe only decodes opcode fetches.
    # The IRQ handler increments both scroll registers once per vblank IRQ.
    pc = 0x8000
    op(rom, pc, 0x10)              # lds #$3fff, stack in shared RAM
    op(rom, pc + 1, 0xCE)
    put(rom, pc + 2, 0x3F, 0xFF)
    pc += 4

    for offs in range(240):
        pc = lda_imm(rom, pc, 0x00)
        pc = sta_ext(rom, pc, 0x3000 + offs)

    # Put the reference sprite in object RAM before the longer tilemap setup, so
    # the first vblank DMA used by the video dump already has stable data.
    pc = write_sprite(rom, pc, 0, 0x4F, 0xC5, obj_code, 0x17)

    for offs in range(0x400):
        op(rom, pc, 0x86)          # lda #visible SCROLL zero tile
        put(rom, pc + 1, 0x00)
        pc += 2
        op(rom, pc, 0xB7)          # sta SCROLL VRAM
        put(rom, pc + 1, 0x20 | (offs >> 8), offs & 0xFF)
        pc += 3

    for offs in range(0x400):
        op(rom, pc, 0x86)          # lda #default SCROLL zero color
        put(rom, pc + 1, 0x00)
        pc += 2
        op(rom, pc, 0xB7)          # sta SCROLL CRAM
        put(rom, pc + 1, 0x28 | (offs >> 8), offs & 0xFF)
        pc += 3

    for offs in range(0x400):
        col = offs & 0x1F
        op(rom, pc, 0x86)          # lda #visible repeating FIX zero tile
        put(rom, pc + 1, 0x00)
        pc += 2
        op(rom, pc, 0xB7)          # sta FIX VRAM
        put(rom, pc + 1, 0x24 | (offs >> 8), offs & 0xFF)
        pc += 3

    for offs in range(0x400):
        col = offs & 0x1F
        op(rom, pc, 0x86)          # lda #default FIX zero color
        put(rom, pc + 1, 0x00)
        pc += 2
        op(rom, pc, 0xB7)          # sta FIX CRAM
        put(rom, pc + 1, 0x2C | (offs >> 8), offs & 0xFF)
        pc += 3

    for digit, offs in (
        (0x01, 0x043),             # SCROLL (0,0)
        (0x02, 0x040),             # SCROLL top-right
        (0x03, 0x3A3),             # SCROLL (27,0)
        (0x04, 0x3F8),             # SCROLL bottom-right
    ):
        pc = write_vram_cram(rom, pc, 0x2000, 0x2800, offs, digit, 0x0F)
    pc = write_vram_cram(rom, pc, 0x2000, 0x2800, 0x000, 0x09, 0x0F)
    pc = write_vram_cram(rom, pc, 0x2000, 0x2800, 0x042, 0x09, marker_color)

    fix_markers = [
        (0x01, 0x041, 0x0F),        # FIX (0,0), green on current palette
        (0x02, 0x046, 0x0E),        # FIX top-right
        (0x03, 0x3E1, 0x0D),        # FIX bottom-left
        (0x04, 0x3E6, 0x0C),        # FIX bottom-right
    ]
    for digit, row, col in (
        (0x01, 0, 30),
        (0x02, 0, 31),
        (0x03, 0,  0),
        (0x04, 0,  1),
        (0x05, 1, 30),
        (0x06, 1, 31),
    ):
        fix_markers.append((digit, (row << 5) | col, 0x0F))

    for digit, offs, color in fix_markers:
        pc = write_vram_cram(rom, pc, 0x2400, 0x2C00, offs, digit, color)

    # Number the first visible FIX row so the left/right FIX ownership can be
    # identified directly from VRAM column order. MAME shows the first visible
    # FIX row at $2440, i.e. FIX VRAM offset $040.
    for col in range(32):
        tile = 0x09 if col == 0 else col
        color = marker_color if col == 0 else 0x0F
        pc = write_vram_cram(rom, pc, 0x2400, 0x2C00, 0x040 + col, tile, color)

    op(rom, pc, 0x4F)              # clra
    pc += 1
    pc = sta_ext(rom, pc, 0x3FF0)  # IRQ scroll/object counter
    pc = sta_ext(rom, pc, 0x1000)  # horizontal scroll
    pc = sta_ext(rom, pc, 0x1800)  # vertical scroll

    sprite_codes = (obj_code,) * 8
    sprite_attrs = (
        0x4F, 0x4F, 0x4F, 0x4F,
        0x4F, 0x0F, 0xCF, 0x8F,
    )
    sprite_xpos = (0x17, 0x06, 0x05, 0x06, 0x20, 0x48, 0x70, 0x98)
    sprite_ypos = (0xC5, 0x30, 0x30, 0x30, 0x70, 0x70, 0x70, 0x70)
    for i, code in enumerate(sprite_codes):
        attr = sprite_attrs[i]
        ypos = sprite_ypos[i]
        xpos = sprite_xpos[i]
        pc = write_sprite(rom, pc, i, attr, ypos, code, xpos)

    pc = lda_imm(rom, pc, 0x01)
    pc = sta_ext(rom, pc, 0x0007)  # enable main IRQ latch
    op(rom, pc, 0x1C)              # andcc #$ef, enable CPU IRQ
    put(rom, pc + 1, 0xEF)
    pc += 2
    op(rom, pc, 0x20)              # bra self
    put(rom, pc + 1, 0xFE)

    pc = 0xF000
    pc = lda_ext(rom, pc, 0x3FF0)  # irq: lda counter
    op(rom, pc, 0x4C)              # inca
    pc += 1
    pc = sta_ext(rom, pc, 0x3FF0)
    pc = sta_ext(rom, pc, 0x1000)  # horizontal scroll
    pc = sta_ext(rom, pc, 0x1800)  # vertical scroll

    pc = write_sprite(rom, pc, 0, 0x4F, 0xC5, obj_code, 0x17)

    pc = lda_ext(rom, pc, 0x3FF0)  # sprite 1 x offset
    pc = adda_imm(rom, pc, 0x57)
    pc = sta_ext(rom, pc, 0x3007)
    pc = lda_ext(rom, pc, 0x3FF0)  # sprite 1 y moves forward
    pc = adda_imm(rom, pc, 0x70)
    pc = sta_ext(rom, pc, 0x3005)

    pc = lda_ext(rom, pc, 0x3FF0)  # sprite 2 x opposite
    pc = nega(rom, pc)
    pc = adda_imm(rom, pc, 0xC7)
    pc = sta_ext(rom, pc, 0x300B)
    pc = lda_ext(rom, pc, 0x3FF0)  # sprite 2 y offset
    pc = adda_imm(rom, pc, 0x40)
    pc = sta_ext(rom, pc, 0x3009)

    pc = lda_ext(rom, pc, 0x3FF0)  # sprite 3 x slower-looking diagonal
    pc = adda_imm(rom, pc, 0x27)
    pc = sta_ext(rom, pc, 0x300F)
    pc = lda_ext(rom, pc, 0x3FF0)
    pc = nega(rom, pc)
    pc = adda_imm(rom, pc, 0x90)
    pc = sta_ext(rom, pc, 0x300D)

    op(rom, pc, 0x3B)              # rti

    # Patch both possible vector locations used by local/JTFRAME layouts.
    put(rom, 0x7FF8, 0xF0, 0x00)
    put(rom, 0x7FFE, 0x80, 0x00)
    put(rom, 0xFFF8, 0xF0, 0x00)
    put(rom, 0xFFFE, 0x80, 0x00)

    OUT.write_bytes(rom)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
