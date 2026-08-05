#!/usr/bin/env python3
from pathlib import Path
import os


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


def write_edge_test_sprite(buf, source_code, test_code):
    del source_code
    rows = ("8888888888888888",) * 16

    def inverse_post_word(word_addr):
        low = word_addr & 0x3F
        raw_low = (
            (low & 0x30)
            | ((low & 0x01) << 3)
            | ((low & 0x08) >> 1)
            | ((low & 0x04) >> 1)
            | ((low & 0x02) >> 1)
        )
        return (word_addr & ~0x3F) | raw_low

    def encode_obj_word(pens):
        raw = 0
        bit_map = (
            (11, 15, 3, 7), (10, 14, 2, 6),
            (9, 13, 1, 5), (8, 12, 0, 4),
            (27, 31, 19, 23), (26, 30, 18, 22),
            (25, 29, 17, 21), (24, 28, 16, 20),
        )
        for pen, bits in zip(pens, bit_map):
            for shift, bit in zip((3, 2, 1, 0), bits):
                raw |= ((pen >> shift) & 1) << bit
        return raw

    for row, pattern in enumerate(rows):
        pens = [int(pen, 16) for pen in pattern]
        pens[0] = 1
        pens[15] = 2
        for half in range(2):
            raw = encode_obj_word(pens[half * 8:half * 8 + 8])
            response = (
                (test_code << 5)
                | ((row >> 3) << 4)
                | (half << 3)
                | (row & 7)
            )
            for lane in range(2):
                source_word = inverse_post_word(response * 2 + lane)
                word = (raw >> (lane * 16)) & 0xFFFF
                put(buf, OBJ_START + source_word * 2,
                    word & 0xFF, word >> 8)


def write_tile_rows(buf, tile, rows):
    for row in range(8):
        pens = [
            0xF if rows[7 - x][7 - row] != "." else 0x0
            for x in range(8)
        ]
        word_addr = (tile << 3) | row
        put(buf, SCR_START + word_addr * 4, *encode_row(pens))


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


def ldb_imm(buf, pc, value):
    op(buf, pc, 0xC6)
    put(buf, pc + 1, value)
    return pc + 2


def ldx_imm(buf, pc, value):
    op(buf, pc, 0x8E)
    put(buf, pc + 1, value >> 8, value)
    return pc + 3


def stb_x_postinc(buf, pc):
    op(buf, pc, 0xE7)
    put(buf, pc + 1, 0x80)
    return pc + 2


def sta_ext(buf, pc, addr):
    op(buf, pc, 0xB7)
    put(buf, pc + 1, addr >> 8, addr)
    return pc + 3


def adda_imm(buf, pc, value):
    op(buf, pc, 0x8B)
    put(buf, pc + 1, value)
    return pc + 2


def cmpa_imm(buf, pc, value):
    op(buf, pc, 0x81)
    put(buf, pc + 1, value)
    return pc + 2


def lsla(buf, pc):
    op(buf, pc, 0x48)
    return pc + 1


def bcs(buf, pc, rel):
    op(buf, pc, 0x25)
    put(buf, pc + 1, rel)
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


def write_tile_row(buf, pc, base, row, values):
    pc = ldx_imm(buf, pc, base + (row << 5))
    for value in values:
        pc = ldb_imm(buf, pc, value)
        pc = stb_x_postinc(buf, pc)
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
    flip_screen = os.environ.get("MZONE_SCROLLTEST_FLIP") == "1"
    show_sprites = os.environ.get("MZONE_SCROLLTEST_SPRITES") == "1"
    first2_yb = os.environ.get("MZONE_SCROLLTEST_FIRST2_YB") == "1"
    solid_marker = os.environ.get("MZONE_SCROLLTEST_SOLID_MARKER") == "1"
    column_numbers = os.environ.get("MZONE_SCROLLTEST_COLUMN_NUMBERS") == "1"
    scroll_towards_fix = os.environ.get("MZONE_SCROLLTEST_AWAY_FIX") != "1"
    # Move by one pixel per IRQ so short captures show genuine fine scrolling
    # rather than jumping by complete 8-pixel character columns.
    scroll_step = int(os.environ.get("MZONE_SCROLLTEST_SCROLL_STEP", "1"), 0) & 0xFF
    if scroll_step not in (0, 1, 2, 4, 8):
        raise ValueError("MZONE_SCROLLTEST_SCROLL_STEP must be 0, 1, 2, 4, or 8")

    # Give diagnostic markers two CRAM colors so the same tile can make a
    # checkerboard without changing graphics data between columns.
    marker_color = 0x0B
    marker_color_alt = 0x0A
    marker_color_red = 0x09
    marker_tile = 0x7F
    marker_hole_tile = 0x7E
    put(rom, PROM_START + 0x120 + 0xB7, 0x3E)
    put(rom, PROM_START + 0x120 + 0xBF, 0x3E)
    put(rom, PROM_START + 0x120 + 0xA7, 0x3D)
    put(rom, PROM_START + 0x120 + 0xAF, 0x3D)
    put(rom, PROM_START + 0x120 + 0x97, 0x3C)
    put(rom, PROM_START + 0x120 + 0x9F, 0x3C)
    put(rom, PROM_START + 0x01E, 0x3F)
    put(rom, PROM_START + 0x01D, 0xC0)
    put(rom, PROM_START + 0x01C, 0x07)
    # Decoded pens 1 and 2 are unused by the ordinary sprite. Map only those
    # through palette F to white and blue.
    put(rom, PROM_START + 0x020 + 0xF1, 0x05)
    put(rom, PROM_START + 0x020 + 0xF2, 0x0B)
    for pen in range(1, 16):
        put(rom, PROM_START + 0x020 + 0x10 + pen, 0x0D)

    # Put the outside-border marker on a high diagnostic tile code so the
    # normal 8/9 glyphs can still be used in numbered test rows.
    write_tile_rows(rom, marker_tile, (
        "########",
        "########",
        "########",
        "########",
        "########",
        "########",
        "########",
        "########",
    ))
    write_tile_rows(rom, marker_hole_tile, (
        "########",
        "########",
        "########",
        "###.####",
        "########",
        "########",
        "########",
        "########",
    ))

    letter_rows = {
        0x00: ("........", "..####..", ".##..##.", ".##..##.", ".##..##.", ".##..##.", "..####..", "........"),
        0x01: ("........", "...##...", "..###...", "...##...", "...##...", "...##...", ".######.", "........"),
        0x02: ("........", "..####..", ".##..##.", "....##..", "...##...", "..##....", ".######.", "........"),
        0x03: ("........", ".#####..", "....##..", "...###..", "....##..", ".##..##.", "..####..", "........"),
        0x04: ("........", "...###..", "..####..", ".##.##..", ".######.", "....##..", "....##..", "........"),
        0x05: ("........", ".######.", ".##.....", ".#####..", "....##..", ".##..##.", "..####..", "........"),
        0x06: ("........", "..####..", ".##.....", ".#####..", ".##..##.", ".##..##.", "..####..", "........"),
        0x07: ("........", ".######.", "....##..", "...##...", "..##....", "..##....", "..##....", "........"),
        0x08: ("........", "..####..", ".##..##.", "..####..", ".##..##.", ".##..##.", "..####..", "........"),
        0x09: ("........", "..####..", ".##..##.", ".##..##.", "..#####.", "....##..", "..####..", "........"),
        0x0A: ("........", "..####..", ".##..##.", ".##..##.", ".######.", ".##..##.", ".##..##.", "........"),
        0x0B: ("........", ".#####..", ".##..##.", ".#####..", ".##..##.", ".##..##.", ".#####..", "........"),
        0x0C: ("........", "..####..", ".##..##.", ".##.....", ".##.....", ".##..##.", "..####..", "........"),
        0x0D: ("........", ".#####..", ".##..##.", ".##..##.", ".##..##.", ".##..##.", ".#####..", "........"),
        0x0E: ("........", ".######.", ".##.....", ".#####..", ".##.....", ".##.....", ".######.", "........"),
        0x0F: ("........", ".######.", ".##.....", ".#####..", ".##.....", ".##.....", ".##.....", "........"),
        0x10: ("........", "..####..", ".##..##.", ".##.....", ".##.###.", ".##..##.", "..####..", "........"),
        0x11: ("........", ".##..##.", ".##..##.", ".######.", ".##..##.", ".##..##.", ".##..##.", "........"),
        0x12: ("........", "..####..", "...##...", "...##...", "...##...", "...##...", "..####..", "........"),
        0x13: ("........", "...####.", "....##..", "....##..", "....##..", ".##.##..", "..###...", "........"),
        0x14: ("........", ".##..##.", ".##.##..", ".####...", ".##.##..", ".##..##.", ".##..##.", "........"),
        0x15: ("........", ".##.....", ".##.....", ".##.....", ".##.....", ".##.....", ".######.", "........"),
        0x16: ("........", ".##..##.", ".######.", ".######.", ".##..##.", ".##..##.", ".##..##.", "........"),
        0x17: ("........", ".##..##.", ".###.##.", ".######.", ".##.###.", ".##..##.", ".##..##.", "........"),
        0x18: ("........", "..####..", ".##..##.", ".##..##.", ".##..##.", ".##..##.", "..####..", "........"),
        0x19: ("........", ".#####..", ".##..##.", ".##..##.", ".#####..", ".##.....", ".##.....", "........"),
        0x1A: ("........", "..####..", ".##..##.", ".##..##.", ".##.###.", ".##..##.", "..#####.", "........"),
        0x1B: ("........", ".#####..", ".##..##.", ".##..##.", ".#####..", ".##.##..", ".##..##.", "........"),
        0x1C: ("........", "..####..", ".##..##.", ".###....", "...###..", ".##..##.", "..####..", "........"),
        0x1D: ("........", ".######.", "...##...", "...##...", "...##...", "...##...", "...##...", "........"),
        0x1E: ("........", ".##..##.", ".##..##.", ".##..##.", ".##..##.", ".##..##.", "..####..", "........"),
        0x1F: ("........", ".##..##.", ".##..##.", ".##..##.", ".##..##.", "..####..", "...##...", "........"),
    }
    for tile, rows in letter_rows.items():
        write_tile_rows(rom, tile, rows)

    obj_code = 0xAA
    # Keep code bit 0 equal to source code AA: that bit participates in the
    # OBJ downloader's low-address transpose.
    edge_test_code = 0xD0
    write_edge_test_sprite(rom, obj_code, edge_test_code)
    probe_y = int(os.environ.get("MZONE_SCROLLTEST_PROBE_Y", "0x70"), 0) & 0xFF
    bottom_y = int(os.environ.get("MZONE_SCROLLTEST_BOTTOM_Y", "0x09"), 0) & 0xFF

    # Main CPU IRQ test program at $8000. Opcode bytes are Konami-1 encoded;
    # operands are stored plain because jtframe only decodes opcode fetches.
    # The IRQ handler advances the scroll register once per vblank IRQ.
    # Default to a one-pixel step for smooth-scroll diagnostics.
    pc = 0x8000
    op(rom, pc, 0x10)              # lds #$3fff, stack in shared RAM
    op(rom, pc + 1, 0xCE)
    put(rom, pc + 2, 0x3F, 0xFF)
    pc += 4
    if flip_screen:
        pc = lda_imm(rom, pc, 0x01)
        pc = sta_ext(rom, pc, 0x0005)  # screen flip latch

    for offs in range(240):
        pc = lda_imm(rom, pc, 0x00)
        pc = sta_ext(rom, pc, 0x3000 + offs)

    # Optional reference sprites for object tests. Keep them out of the default
    # scroll/FIX diagnostic so they do not cover tile boundary pixels.
    if show_sprites:
        pc = write_sprite(rom, pc, 0, 0x4E, 0xC5, obj_code, 0x13)
        pc = write_sprite(rom, pc, 7, 0x4F, bottom_y, obj_code, 0x40)

    for row in range(32):
        for col in range(7):
            pc = write_vram_cram(rom, pc, 0x2400, 0x2C00, (row << 5) | col, col + 1, 0x0F)

    for row in range(32):
        if column_numbers:
            scroll_tiles = [
                (col - 2) & 0x1F
                for col in range(32)
            ]
        else:
            scroll_tiles = [
                (col % 0x1F) + 1
                for col in range(32)
            ]
            scroll_tiles[0] = marker_tile if solid_marker or (row & 1) == 0 else marker_hole_tile
        scroll_colors = [
            0x0F
            for col in range(32)
        ]
        if not column_numbers:
            scroll_colors[0] = marker_color if (row & 1) == 0 else marker_color_alt
            if first2_yb:
                scroll_tiles[0] = marker_tile if solid_marker or (row & 1) == 0 else marker_hole_tile
                scroll_colors[0] = marker_color if (row & 1) == 0 else marker_color_alt
        pc = write_tile_row(rom, pc, 0x2000, row, scroll_tiles)
        pc = write_tile_row(rom, pc, 0x2800, row, scroll_colors)

    # First-visible probe cells seen by the core as 0x2042 and 0x2440.
    # Give them different colors so scroll/FIX address selection can be
    # checked visually at the boundary.
    if column_numbers:
        pc = write_vram_cram(rom, pc, 0x2000, 0x2800, 0x042, marker_tile, marker_color_alt)
    elif first2_yb:
        pc = write_vram_cram(rom, pc, 0x2000, 0x2800, 0x042, marker_tile, marker_color_alt)
        pc = write_vram_cram(rom, pc, 0x2000, 0x2800, 0x041, marker_tile, marker_color)
    else:
        pc = write_vram_cram(rom, pc, 0x2000, 0x2800, 0x042, marker_tile, 0x0A)
        pc = write_vram_cram(rom, pc, 0x2000, 0x2800, 0x041, marker_tile, marker_color_red)
    pc = write_vram_cram(rom, pc, 0x2400, 0x2C00, 0x040, marker_tile, 0x0B)
    if not column_numbers:
        pc = write_vram_cram(rom, pc, 0x2000, 0x2800, 0x3A2, 0x00, 0x0A)
        pc = write_vram_cram(rom, pc, 0x2400, 0x2C00, 0x3A0, 0x00, 0x0B)

    op(rom, pc, 0x4F)              # clra
    pc += 1
    pc = sta_ext(rom, pc, 0x3FF0)  # IRQ scroll/object counter
    pc = sta_ext(rom, pc, 0x1000)  # horizontal scroll
    pc = sta_ext(rom, pc, 0x1800)  # vertical scroll

    if show_sprites:
        sprite_codes = (
            obj_code, obj_code, obj_code, obj_code, obj_code,
            obj_code, 0x44, obj_code, obj_code,
        )
        sprite_attrs = (
            0x4F, 0x4F, 0x41, 0x4F,
            0x4F, 0x0F, 0xCF, 0x4F, 0x4F,
        )
        sprite_xpos = (0x13, 0x06, 0x05, 0x06, 0x20, 0x48, 0x70, 0x40, 0xFC)
        sprite_ypos = (0xC5, 0x30, 0x30, 0x30, probe_y, 0x70, 0xE0, bottom_y, probe_y)
        for i, code in enumerate(sprite_codes):
            attr = sprite_attrs[i]
            ypos = sprite_ypos[i]
            xpos = sprite_xpos[i]
            pc = write_sprite(rom, pc, i, attr, ypos, code, xpos)
        # Boundary reference sprites for raw line-buffer X.
        # Half-visible balloon/drop at the first scroll/OBJ pixel. X=F8
        # clips pixels at 248..255; the remaining half wraps to X=0..7.
        pc = write_sprite(rom, pc, 0x20, 0x4F, 0x6E, obj_code, 0xF8)
        # Identical, non-mirrored diagnostics: the first horizontal pixel
        # column is white and the last horizontal pixel column is blue across
        # all 16 occupied VDump scanlines.
        # Y=18 places the pair at VDump 215..230, away from the animated
        # sprites that otherwise overwrite its line-buffer addresses.
        pc = write_sprite(rom, pc, 0x21, 0x4F, 0x18, edge_test_code, 0x08)
        pc = write_sprite(rom, pc, 0x22, 0x4F, 0x18, edge_test_code, 0xEF)
        pc = write_sprite(rom, pc, 0x23, 0xCF, 0xE0, 0x44, 0x80)
        # Full edge-color diagnostic at raw sprite X48/Y57. The inverted
        # vertical counter places raw Y57 around VDump 182.
        pc = write_sprite(rom, pc, 0x1F, 0x4F, 0x39, edge_test_code, 0x00)
        # Matching edge-color diagnostic at raw X49, first visible on
        # VDump 80: raw X is xpos+48 and first VDump is 239-ypos.
        pc = write_sprite(rom, pc, 0x1E, 0x4F, 0x9F, edge_test_code, 0x01)

    pc = lda_imm(rom, pc, 0x01)
    pc = sta_ext(rom, pc, 0x0007)  # enable main IRQ latch
    op(rom, pc, 0x1C)              # andcc #$ef, enable CPU IRQ
    put(rom, pc + 1, 0xEF)
    pc += 2
    op(rom, pc, 0x20)              # bra self
    put(rom, pc + 1, 0xFE)

    pc = 0xFE00
    pc = lda_ext(rom, pc, 0x3FF0)  # irq: lda counter
    pc = adda_imm(rom, pc, 0x01)
    pc = sta_ext(rom, pc, 0x3FF0)
    pc = cmpa_imm(rom, pc, 0x04)   # keep early frames at zero scroll
    skip_scroll_branch = pc
    pc = bcs(rom, pc, 0x00)
    pc = adda_imm(rom, pc, 0xFD)   # then use (counter-3)*scroll_step
    if scroll_step == 1:
        pass
    elif scroll_step == 2:
        pc = lsla(rom, pc)
    elif scroll_step == 4:
        pc = lsla(rom, pc)
        pc = lsla(rom, pc)
    elif scroll_step == 8:
        pc = lsla(rom, pc)
        pc = lsla(rom, pc)
        pc = lsla(rom, pc)
    if scroll_towards_fix:
        pc = nega(rom, pc)         # default: move scroll layer toward FIX
    pc = sta_ext(rom, pc, 0x1000)  # horizontal scroll
    put(rom, skip_scroll_branch + 1, pc - (skip_scroll_branch + 2))

    if show_sprites:
        pc = write_sprite(rom, pc, 0, 0x4E, 0xC5, obj_code, 0x13)

        pc = lda_ext(rom, pc, 0x3FF0)  # sprite 1 x offset
        pc = adda_imm(rom, pc, 0x57)
        pc = sta_ext(rom, pc, 0x3007)
        pc = lda_ext(rom, pc, 0x3FF0)  # sprite 1 y moves down on screen
        pc = nega(rom, pc)
        pc = adda_imm(rom, pc, 0x70)
        pc = sta_ext(rom, pc, 0x3005)

        pc = lda_ext(rom, pc, 0x3FF0)  # sprite 2 x / visible y motion
        pc = adda_imm(rom, pc, 0xC7)
        pc = sta_ext(rom, pc, 0x300B)
        pc = lda_imm(rom, pc, 0x40)    # sprite 2 visible x fixed
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
    put(rom, 0x7FF8, 0xFE, 0x00)
    put(rom, 0x7FFE, 0x80, 0x00)
    put(rom, 0xFFF8, 0xFE, 0x00)
    put(rom, 0xFFFE, 0x80, 0x00)

    OUT.write_bytes(rom)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
