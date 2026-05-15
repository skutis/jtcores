#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
SRC = ROOT / "rom" / "megazone.rom"
OUT = ROOT / "rom" / "megazone_scrolltest.rom"
SCR_START = 0x1B000
OBJ_START = 0x13000


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


def main():
    rom = bytearray(SRC.read_bytes())

    # Make tile $08 a solid diagnostic tile in the scroll/fix graphics region.
    # jtmzone_scroll addresses graphics as 32-bit words:
    # {code_msb, tile_code, row}. Four $ff bytes decode to pen $f for all pixels.
    for row in range(8):
        word_addr = (0x08 << 3) | row
        put(rom, SCR_START + word_addr * 4, 0xFF, 0xFF, 0xFF, 0xFF)

    # Main CPU IRQ test program at $8000. Opcode bytes are Konami-1 encoded;
    # operands are stored plain because jtframe only decodes opcode fetches.
    # The IRQ handler increments both scroll registers once per vblank IRQ.
    pc = 0x8000
    op(rom, pc, 0x10)              # lds #$3fff, stack in shared RAM
    op(rom, pc + 1, 0xCE)
    put(rom, pc + 2, 0x3F, 0xFF)
    pc += 4

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

    for digit, offs, color in (
        (0x01, 0x041, 0x0F),        # FIX (0,0), green on current palette
        (0x02, 0x046, 0x0E),        # FIX top-right
        (0x03, 0x3E1, 0x0D),        # FIX bottom-left
        (0x04, 0x3E6, 0x0C),        # FIX bottom-right
    ):
        pc = write_vram_cram(rom, pc, 0x2400, 0x2C00, offs, digit, color)

    op(rom, pc, 0x4F)              # clra
    pc += 1
    pc = sta_ext(rom, pc, 0x3FF0)  # IRQ scroll/object counter
    pc = sta_ext(rom, pc, 0x1000)  # horizontal scroll
    pc = sta_ext(rom, pc, 0x1800)  # vertical scroll

    # A grid of varied real sprite codes. Entry format is attr, ypos, code, xpos.
    # Keep the palette fixed for most entries so OBJ decode/order can be compared
    # without also changing the C6 palette row.
    sprite_codes = (0xAA,) * 16
    sprite_colors = tuple(range(16))
    for i, code in enumerate(sprite_codes):
        base = 0x33FC - i * 4
        color = sprite_colors[i]
        ypos = 0x38 + (i // 4) * 0x28
        xpos = 0x18 + (i % 4) * 0x38
        pc = lda_imm(rom, pc, color)
        pc = sta_ext(rom, pc, base + 0)
        pc = lda_imm(rom, pc, ypos)
        pc = sta_ext(rom, pc, base + 1)
        pc = lda_imm(rom, pc, code)
        pc = sta_ext(rom, pc, base + 2)
        pc = lda_imm(rom, pc, xpos)
        pc = sta_ext(rom, pc, base + 3)

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

    pc = lda_ext(rom, pc, 0x3FF0)  # sprite 0 x moves forward
    pc = sta_ext(rom, pc, 0x33FF)
    pc = lda_ext(rom, pc, 0x3FF0)  # sprite 0 y moves opposite
    pc = nega(rom, pc)
    pc = adda_imm(rom, pc, 0xD0)
    pc = sta_ext(rom, pc, 0x33FD)

    pc = lda_ext(rom, pc, 0x3FF0)  # sprite 1 x offset
    pc = adda_imm(rom, pc, 0x50)
    pc = sta_ext(rom, pc, 0x33FB)
    pc = lda_ext(rom, pc, 0x3FF0)  # sprite 1 y moves forward
    pc = adda_imm(rom, pc, 0x70)
    pc = sta_ext(rom, pc, 0x33F9)

    pc = lda_ext(rom, pc, 0x3FF0)  # sprite 2 x opposite
    pc = nega(rom, pc)
    pc = adda_imm(rom, pc, 0xC0)
    pc = sta_ext(rom, pc, 0x33F7)
    pc = lda_ext(rom, pc, 0x3FF0)  # sprite 2 y offset
    pc = adda_imm(rom, pc, 0x40)
    pc = sta_ext(rom, pc, 0x33F5)

    pc = lda_ext(rom, pc, 0x3FF0)  # sprite 3 x slower-looking diagonal
    pc = adda_imm(rom, pc, 0x20)
    pc = sta_ext(rom, pc, 0x33F3)
    pc = lda_ext(rom, pc, 0x3FF0)
    pc = nega(rom, pc)
    pc = adda_imm(rom, pc, 0x90)
    pc = sta_ext(rom, pc, 0x33F1)

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
