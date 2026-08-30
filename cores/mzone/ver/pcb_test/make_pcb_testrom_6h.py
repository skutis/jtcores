#!/usr/bin/env python3
"""Build a sprite-free 6H version of the numbered SCROLL/FIX test."""

from pathlib import Path
import os


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BASE = 0xE000
SIZE = 0x2000
DATA_BASE = 0xE400
OUTPUT_NAME = os.environ.get("MZONE_GRID_NAME", "t0")
SCROLLY = int(os.environ.get("MZONE_GRID_SCROLLY", "0"), 0) & 0xFF
RED_FIX_BOX = os.environ.get("MZONE_RED_FIX_BOX") == "1"
YELLOW_FIX_BOX = os.environ.get("MZONE_YELLOW_FIX_BOX") == "1"
SPRITE_X0 = os.environ.get("MZONE_SPRITE_X0") == "1"
SPRITE_X1 = os.environ.get("MZONE_SPRITE_X1") == "1"
SPRITE_X10 = os.environ.get("MZONE_SPRITE_X10") == "1"
SPRITE_X239 = os.environ.get("MZONE_SPRITE_X239") == "1"
SPRITE_X250 = os.environ.get("MZONE_SPRITE_X250") == "1"
WHITE_MIDDLE = os.environ.get("MZONE_WHITE_MIDDLE") == "1"
WHITE_MIDDLE_X = int(os.environ.get("MZONE_WHITE_MIDDLE_X", "0x60"), 0) & 0xFF
WHITE_MIDDLE_Y = int(os.environ.get("MZONE_WHITE_MIDDLE_Y", "0xDF"), 0) & 0xFF
WHITE_MIDDLE_ATTR = int(os.environ.get("MZONE_WHITE_MIDDLE_ATTR", "0x4E"), 0) & 0xFF
FLIP_WHITE_X255 = os.environ.get("MZONE_FLIP_WHITE_X255") == "1"
WHITE_TOP_Y = int(os.environ.get("MZONE_WHITE_TOP_Y", "0xA5"), 0) & 0xFF
WHITE_EDGES = os.environ.get("MZONE_WHITE_EDGES") == "1"
FLIPPED_Y_ADJUST = int(os.environ.get("MZONE_FLIPPED_Y_ADJUST", "0"), 0) & 0xFF
FLIPPED_Y_MIRROR = os.environ.get("MZONE_FLIPPED_Y_MIRROR") == "1"
FLIPPED_ATTR_TOGGLE = int(os.environ.get("MZONE_FLIPPED_ATTR_TOGGLE", "0"), 0) & 0xC0
SCREEN_FLIP = 1 if os.environ.get("MZONE_SCREEN_FLIP") == "1" else 0


def flipped_x(value):
    return (251 - value) & 0xFF


# PCB reference: white_top exposes one column at the FIX edge in either mode.
# Apply the same 251-x transform used by every paired flipped sprite.
WHITE_TOP_X = int(os.environ.get(
    "MZONE_WHITE_TOP_X", str(flipped_x(250) if SCREEN_FLIP else 250)
), 0) & 0xFF
SMOOTH_SCROLL = os.environ.get("MZONE_SMOOTH_SCROLL") == "1"
CPU_SCROLL = os.environ.get("MZONE_CPU_SCROLL") == "1"
if SMOOTH_SCROLL and CPU_SCROLL:
    raise ValueError("select only one of MZONE_SMOOTH_SCROLL and MZONE_CPU_SCROLL")
SCROLL_REG = os.environ.get("MZONE_SCROLL_REG", "both")
if SCROLL_REG not in ("1000", "1800", "both"):
    raise ValueError("MZONE_SCROLL_REG must be 1000, 1800, or both")
SCROLL_DIR = os.environ.get("MZONE_SCROLL_DIR", "inc")
if SCROLL_DIR not in ("inc", "dec"):
    raise ValueError("MZONE_SCROLL_DIR must be inc or dec")
FLIP_LATCH_ADDR = int(os.environ.get("MZONE_FLIP_LATCH_ADDR", "0x0005"), 0)
IRQ_LATCH_ADDR = int(os.environ.get("MZONE_IRQ_LATCH_ADDR", "0x0007"), 0)
SKIP_IRQ_LATCH = os.environ.get("MZONE_SKIP_IRQ_LATCH") == "1"
if FLIP_LATCH_ADDR not in range(0x0000, 0x0008):
    raise ValueError("MZONE_FLIP_LATCH_ADDR must be in $0000..$0007")
if IRQ_LATCH_ADDR not in range(0x0000, 0x0008):
    raise ValueError("MZONE_IRQ_LATCH_ADDR must be in $0000..$0007")
SCROLL_DIV = int(os.environ.get("MZONE_SCROLL_DIV", "1"), 0)
if SCROLL_DIV < 1 or SCROLL_DIV > 256 or SCROLL_DIV & (SCROLL_DIV - 1):
    raise ValueError("MZONE_SCROLL_DIV must be a power of two from 1 to 256")
SCROLL_RANGE = int(os.environ.get("MZONE_SCROLL_RANGE", "256"), 0)
if SCROLL_RANGE < 1 or SCROLL_RANGE > 256 or SCROLL_RANGE & (SCROLL_RANGE - 1):
    raise ValueError("MZONE_SCROLL_RANGE must be a power of two from 1 to 256")
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


def lda_ext(pc, addr):
    op(pc, 0xB6)
    put(pc + 1, addr >> 8, addr)
    return pc + 3


def jmp_ext(pc, addr):
    op(pc, 0x7E)
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
        pc = sta_ext(pc, 0x0800)  # keep the physical 555 watchdog retriggered
    return pc


vram0 = bytearray(0x400)
vram1 = bytearray(0x400)
cram0 = bytearray(0x400)
cram1 = bytearray(0x400)
obj = bytearray(0x400)      # clear every sprite unless explicitly enabled
if SPRITE_X0:
    # One stock diagnostic sprite: attr, ypos, code, raw xpos.
    obj[0:4] = bytes((0x4E, 0xC5, 0xAA, 0x00))
if SPRITE_X1:
    obj[4:8] = bytes((0x4E, 0xC5, 0xAA, 0x01))
if SPRITE_X10:
    obj[4:8] = bytes((0x4E, 0xC5, 0xAA, 0x10))
if SPRITE_X239:
    # Put stock code $44 across the 8-bit X wrap to test the real PCB edge.
    obj[8:12] = bytes((0x4E, 0xC5, 0x44, 0xF8))
    # Separate vertical reference at raw X=250 so it cannot be confused with
    # the X=251 sprite or the two code-$AA sprites on the original row.
    obj[12:16] = bytes((0x4E, 0xA5, 0x44, 0xFA))
if SPRITE_X250:
    # A single named white reference; its raw X may differ with screen flip.
    obj[0:4] = bytes((0x4E, WHITE_TOP_Y, 0x44, WHITE_TOP_X))
middle_x = flipped_x(WHITE_MIDDLE_X) if SCREEN_FLIP else WHITE_MIDDLE_X
if WHITE_MIDDLE:
    obj[16:20] = bytes((WHITE_MIDDLE_ATTR, WHITE_MIDDLE_Y, 0x44, middle_x))
if FLIP_WHITE_X255:
    obj[20:24] = bytes((WHITE_MIDDLE_ATTR, WHITE_MIDDLE_Y, 0x44, 0xFF))
if WHITE_EDGES:
    # Apply one 251-x conversion to balloons and white reference sprites.
    flipped_attr = 0x4E ^ FLIPPED_ATTR_TOGGLE
    def flipped_y(value):
        base = 241 - value if FLIPPED_Y_MIRROR else value
        return (base + FLIPPED_Y_ADJUST) & 0xFF
    obj[0:4] = bytes((flipped_attr, flipped_y(0xC5), 0xAA, flipped_x(0x00)))
    obj[4:8] = bytes((flipped_attr, flipped_y(0xC5), 0xAA, flipped_x(0x10)))
    obj[8:12] = bytes((flipped_attr, flipped_y(0xC5), 0x44, flipped_x(0xF8)))
    obj[12:16] = bytes((flipped_attr, flipped_y(0xA5), 0x44, flipped_x(0xFA)))

# Match the regular diagnostic layout. Stock tile $3F is solid pen $F. With
# the unmodified physical lookup/palette PROMs, CRAM $09 maps it to blue and
# CRAM $0D maps it to yellow, so no graphics or PROM patches are needed.
for row in range(32):
    for col in range(32):
        offs = row * 32 + col
        vram0[offs] = (col % 0x1F) + 1
        cram0[offs] = 0x0F
    vram0[row * 32] = 0x3F
    cram0[row * 32] = 0x0D if (row & 1) == 0 else 0x09

    # FIX/status area: seven numbered cells, with the rest explicitly blank.
    for col in range(7):
        offs = row * 32 + col
        vram1[offs] = col + 1
        cram1[offs] = 0x0F

# Keep the regular test's visible reference cells.
vram0[0x042] = 0x31
cram0[0x042] = 0x0D
vram0[0x041] = 0x7F
cram0[0x041] = 0x09
# Guaranteed-visible solid references in the first FIX cells: yellow, blue.
vram1[0x040] = 0x3F
cram1[0x040] = 0x0D
vram1[0x041] = 0x3F
cram1[0x041] = 0x09
if RED_FIX_BOX:
    # Last FIX cell before SCROLL at hdump 40..47, vdump 16..23.
    vram1[0x045] = 0x3F
    cram1[0x045] = 0x0E
if YELLOW_FIX_BOX:
    # Last FIX cell at hdump 40..47, vdump 48..55.
    vram1[0x0C5] = 0x3F
    cram1[0x0C5] = 0x0D
vram0[0x3A2] = 0x00
cram0[0x3A2] = 0x0A
vram1[0x3A0] = 0x00
cram1[0x3A0] = 0x0B

captures = (
    ("vram0", vram0, 0x2000),
    ("vram1", vram1, 0x2400),
    ("cram0", cram0, 0x2800),
    ("cram1", cram1, 0x2C00),
    ("obj", obj, 0x3000),
)

sources = []
data_pc = DATA_BASE
for label, data, destination in captures:
    if len(data) != 0x400:
        raise ValueError(f"{label}: expected 1024 bytes, got {len(data)}")
    put(data_pc, *data)
    sources.append((data_pc, destination))
    data_pc += len(data)

pc = BASE
op(pc, 0x10)               # lds #$3fff
op(pc + 1, 0xCE)
put(pc + 2, 0x3F, 0xFF)
pc += 4

pc = lda_imm(pc, SCROLLY)
pc = sta_ext(pc, 0x1000)   # horizontal source offset
pc = lda_imm(pc, 0)
pc = sta_ext(pc, 0x1800)   # scrollx = 0
pc = lda_imm(pc, SCREEN_FLIP)
pc = sta_ext(pc, FLIP_LATCH_ADDR)  # schematic FLIP latch

for source, destination in sources:
    pc = copy_1k(pc, source, destination)

if SMOOTH_SCROLL:
    # Advance both scroll registers from the vertical IRQ so a complete frame
    # uses one value. Initialization already services the physical watchdog;
    # keep servicing it continuously while waiting for each IRQ as well.
    pc = lda_imm(pc, SCROLLY)
    pc = sta_ext(pc, 0x3800)
    pc = lda_imm(pc, 0)
    pc = sta_ext(pc, 0x3801)
    pc = lda_imm(pc, 1)
    if not SKIP_IRQ_LATCH:
        pc = sta_ext(pc, IRQ_LATCH_ADDR)  # enable vertical IRQ latch
    if SCREEN_FLIP:
        # Assert flip after every other latch setup write. The physical PCB
        # test showed that enabling animation after the early flip write could
        # leave the board non-flipped.
        pc = lda_imm(pc, SCREEN_FLIP)
        pc = sta_ext(pc, FLIP_LATCH_ADDR)
    op(pc, 0x1C)              # andcc #$ef: enable maskable IRQ
    put(pc + 1, 0xEF)
    pc += 2
    watchdog_loop = pc
    pc = sta_ext(pc, 0x0800)
    pc = jmp_ext(pc, watchdog_loop)

    irq_vector = 0xE300
    irq_pc = irq_vector
    skip_scroll_branch = None
    if SCROLL_DIV > 1:
        irq_pc = lda_ext(irq_pc, 0x3801)
        op(irq_pc, 0x4C)          # inca
        irq_pc += 1
        op(irq_pc, 0x84)          # anda #(divider-1)
        put(irq_pc + 1, SCROLL_DIV - 1)
        irq_pc += 2
        irq_pc = sta_ext(irq_pc, 0x3801)
        skip_scroll_branch = irq_pc
        op(irq_pc, 0x26)          # bne watchdog service / rti
        put(irq_pc + 1, 0)
        irq_pc += 2
    irq_pc = lda_ext(irq_pc, 0x3800)
    op(irq_pc, 0x4C if SCROLL_DIR == "inc" else 0x4A)  # inca/deca
    irq_pc += 1
    if SCROLL_RANGE < 256:
        op(irq_pc, 0x84)          # anda #(range-1): repeat fine-scroll cycle
        put(irq_pc + 1, SCROLL_RANGE - 1)
        irq_pc += 2
    irq_pc = sta_ext(irq_pc, 0x3800)
    if SCROLL_REG in ("1000", "both"):
        irq_pc = sta_ext(irq_pc, 0x1000)
    if SCROLL_REG in ("1800", "both"):
        irq_pc = sta_ext(irq_pc, 0x1800)
    if skip_scroll_branch is not None:
        put(skip_scroll_branch + 1, irq_pc - (skip_scroll_branch + 2))
    if SCREEN_FLIP:
        irq_pc = lda_imm(irq_pc, SCREEN_FLIP)
        irq_pc = sta_ext(irq_pc, FLIP_LATCH_ADDR)
    irq_pc = sta_ext(irq_pc, 0x0800)
    op(irq_pc, 0x3B)          # rti
elif CPU_SCROLL:
    # PCB diagnostic without INTST: update $1000 from a CPU delay loop and
    # service the physical 555 watchdog continuously. Two RAM counters give
    # roughly frame-rate motion without relying on a video interrupt.
    pc = lda_imm(pc, SCROLLY)
    pc = sta_ext(pc, 0x3800)
    pc = lda_imm(pc, 0)
    pc = sta_ext(pc, 0x3801)
    pc = sta_ext(pc, 0x3802)
    delay_loop = pc
    pc = sta_ext(pc, 0x0800)
    pc = lda_ext(pc, 0x3801)
    op(pc, 0x4C)              # inca (delay counter)
    pc += 1
    pc = sta_ext(pc, 0x3801)
    op(pc, 0x26)              # bne delay_loop
    put(pc + 1, delay_loop - (pc + 2))
    pc += 2
    pc = lda_ext(pc, 0x3802)
    op(pc, 0x4C)              # inca (delay counter)
    pc += 1
    op(pc, 0x84)              # anda #$0f
    put(pc + 1, 0x0F)
    pc += 2
    pc = sta_ext(pc, 0x3802)
    op(pc, 0x26)              # bne delay_loop
    put(pc + 1, delay_loop - (pc + 2))
    pc += 2
    pc = lda_ext(pc, 0x3800)
    op(pc, 0x4C if SCROLL_DIR == "inc" else 0x4A)  # inca/deca
    pc += 1
    pc = sta_ext(pc, 0x3800)
    pc = sta_ext(pc, 0x1000)
    pc = jmp_ext(pc, delay_loop)
else:
    watchdog_loop = pc
    pc = sta_ext(pc, 0x0800)
    op(pc, 0x20)           # bra watchdog_loop
    put(pc + 1, watchdog_loop - (pc + 2))
    pc += 2

if pc > DATA_BASE:
    raise ValueError(f"program overlaps captured data at ${pc:04X}")

if SMOOTH_SCROLL:
    put(0xFFF8, irq_vector >> 8, irq_vector)
else:
    put(0xFFF8, 0xE0, 0x00)
put(0xFFFC, 0xE0, 0x00)    # NMI (unused)
put(0xFFFE, 0xE0, 0x00)    # reset -> $E000

OUT.write_bytes(rom)
print(f"Wrote {OUT} ({len(rom)} bytes), program end ${pc:04X}")
print(f"SCROLLY=${SCROLLY:02X} (visible SCROLL shift {-SCROLLY:d} px modulo 256)")
print(f"Screen flip: {SCREEN_FLIP}")
print(f"Flip latch candidate address: ${FLIP_LATCH_ADDR:04X}")
print(f"IRQ latch address: ${IRQ_LATCH_ADDR:04X}")
print(f"IRQ latch write skipped: {SKIP_IRQ_LATCH}")
if SMOOTH_SCROLL:
    print(f"Smooth scroll register(s) {SCROLL_REG}: vertical-IRQ {SCROLL_DIR} every {SCROLL_DIV} frame(s), {SCROLL_RANGE}-pixel cycle")
if CPU_SCROLL:
    print("CPU-loop scroll register $1000: no INTST write, watchdog serviced continuously")
if RED_FIX_BOX:
    print("Red FIX box: VRAM $2445=$3F, CRAM $2C45=$0E")
if YELLOW_FIX_BOX:
    print("Yellow FIX box: VRAM $24C5=$3F, CRAM $2CC5=$0D")
if SPRITE_X0:
    print("Sprite 0: attr=$4E, ypos=$C5, code=$AA, xpos=$00")
if SPRITE_X1:
    print("Sprite 1: attr=$4E, ypos=$C5, code=$AA, xpos=$01")
if SPRITE_X10:
    print("Sprite 1: attr=$4E, ypos=$C5, code=$AA, xpos=$10")
if SPRITE_X239:
    print("Sprite 2: attr=$4E, ypos=$C5, code=$44, xpos=$F8 (248)")
    print("Sprite 3: attr=$4E, ypos=$A5, code=$44, xpos=$FA (250)")
if SPRITE_X250:
    print(f"white_top sprite: attr=$4E, ypos=${WHITE_TOP_Y:02X}, code=$44, xpos=${WHITE_TOP_X:02X} ({WHITE_TOP_X})")
if WHITE_MIDDLE:
    middle_vdump = (255 - ((WHITE_MIDDLE_Y + 16) & 0xFF)) & 0xFF
    middle_hdump = ((middle_x - 11) if SCREEN_FLIP else (middle_x + 32)) & 0xFF
    print(f"white_middle sprite: attr=${WHITE_MIDDLE_ATTR:02X}, ypos=${WHITE_MIDDLE_Y:02X}, code=$44, xpos=${middle_x:02X} (screen near hdump={middle_hdump}, vdump={middle_vdump})")
if FLIP_WHITE_X255:
    print(f"white_flip_x255 sprite: attr=${WHITE_MIDDLE_ATTR:02X}, ypos=${WHITE_MIDDLE_Y:02X}, code=$44, xpos=$FF (255)")
if WHITE_EDGES:
    print("Flipped sprite raw-X transform: 251-x")
    print(f"Flipped sprite raw-Y mirror: {FLIPPED_Y_MIRROR}")
    print(f"Flipped sprite raw-Y adjustment: +{FLIPPED_Y_ADJUST}")
    print(f"Flipped sprite attribute: ${flipped_attr:02X}")
    print(f"Balloon 0 flipped reference: ypos=${flipped_y(0xC5):02X}, code=$AA, xpos=${flipped_x(0x00):02X} ({flipped_x(0x00)})")
    print(f"Balloon 1 flipped reference: ypos=${flipped_y(0xC5):02X}, code=$AA, xpos=${flipped_x(0x10):02X} ({flipped_x(0x10)})")
    print(f"white_top sprite: ypos=${flipped_y(0xA5):02X}, code=$44, xpos=${flipped_x(0xFA):02X} ({flipped_x(0xFA)})")
    print(f"white_bottom sprite: ypos=${flipped_y(0xC5):02X}, code=$44, xpos=${flipped_x(0xF8):02X} ({flipped_x(0xF8)})")

sim_rom = bytearray(SOURCE_ROM.read_bytes())
if len(sim_rom) < BASE + SIZE:
    raise ValueError(f"assembled ROM is too small: {SOURCE_ROM}")
sim_rom[BASE:BASE + SIZE] = rom
SIM_OUT.write_bytes(sim_rom)
print(f"Wrote {SIM_OUT} ({len(sim_rom)} bytes) using {SOURCE_ROM}")
