# Mega Zone Timing Notes

This file records the current schematic-derived timing work for the Mega Zone
core. The source references are:

- `sch/timing.kicad_sch`
- `sch/mcpu.kicad_sch`
- GTKWave traces from `jtsim`
- the temporary PROM-backed model in `hdl/jtmzone_hcnt.v`

## Horizontal timing

The board pixel chain is driven from `18.432 MHz` through the `C16` JK FFs to
create `CLK1`, `CLK2`, and `CLK2'`. In the HDL, `CLK2'` is modeled with
`pxl_cen`.

Current confirmed net mapping:

- `C15` is the raw horizontal counter.
- `H1`, `H2`, `H4`, `H8` come from `C15`.
- `16H` is the terminal-count output of `C15`.
- `H16` is the registered `E9` output bit `Q7`.
- `E9` is clocked by `CLK2'`.
- `E9` enable is `~16H`.
- `E8` is selected in the non-flip reset state.
- `E7` is selected when flip is active.
- `RA4` pulls the PROM outputs up to `VCC` at reset.
- `F2` is a 74LS164 shift register.
- `F2` clock is `(H2 & FLIP) | (~FLIP & H4)`.
- `F2` serial inputs are `~HSYNC`.
- `F2 Q7` is `~HSYNC60`.
- `F2 Q4` is `~HSYNC68`.
- `F2 Q5` is `~HSYNC76`.

The PROM path currently used in simulation is:

```verilog
.address({h16,h32,hrdp2,hrdp3,thblk_n})
```

with the `E9` input packing:

- `Q7 <- PROM O1`
- `Q6 <- PROM O4`
- `Q5 <- PROM O5`
- `Q4 <- PROM O8`
- `Q3 <- PROM O7`
- `Q2 <- PROM O6`
- `Q1 <- PROM O3`
- `Q0 <- PROM O2`

That is the same ordering used by the earlier standalone sim model.

## Timing outputs

Current schematic-derived outputs exposed by `jtmzone_hcnt`:

- `hblank_n` from `E9 Q4`
- `hblk_n` is the internal schematic blank net name for the same `E9 Q4` signal
- `hsync_n = hblk_n | h32_n`
- `thblk_n` from `E9 Q5`
- `HS` derived from the `E10 / B11A / E10` chain
- `hcycle` remains a JTFRAME-visible placeholder counter for fallback timing

Measured GTKWave note:

- `hblk_n` is low from `161..256`
- `hblk_n` is high from `257..383` and `0..160`
- that gives a `96`-pixel blank and a `288`-pixel visible span
- the raw line length still appears to be `384`
- the public JTFRAME blank output now uses the schematic `hblk_n`

## Vertical timing

MAME target for this game is:

- visible area: `288 x 224`
- logical line length: `384`
- visible vertical window: `16..239`

The current `jtframe_vtimer` parameters are still a provisional fit and may
need the start points adjusted once the raw horizontal phase is fully matched.

## Line-buffer and sync timing

Timing-sheet text notes currently recorded in the schematic:

- `~OHSTART` is `~HSYNC` rising-edge delayed by 76 pixels, active for 4 pixels
- `~LB1EN` toggles every second frame and is 98 pixels after `~HSYNC` goes active
- the raw `~HBLANK` and `~HSYNC` pulse lengths currently match in GTKWave

That means the remaining work is mostly phase alignment, not pulse-width
correction.

## Layer pipeline design rule

Use raw `hdump == 0` as the horizontal reference for all video layers. SCROLL,
FIX, and OBJ logic should derive their counters from the same free-running
`hdump` timeline. Prefer free-running counters throughout the layer pipelines;
do not pause counters to hide latency. Reset a counter only where the hardware
timing requires a real line/frame reset.

Do not add separate per-layer global X references or source offsets to make a
layer line up at the mixer. Any ROM/RAM fetch lead must be expressed as the
layer's local pipeline timing from the common `hdump` reference, not as a second
horizontal coordinate system.

Each layer has at most eight `hdump` counts of total output latency budget to
line up with the color mixer. Delay already consumed by the layer's own
fetch/decode/pixel pipeline counts against that budget. Only add the remaining
delay needed to reach the shared mixer phase; do not add a blind extra
eight-count delay at the layer output. Horizontal blanking must then be delayed
in the color mixer to the same final output phase.

The color mixer should contain one pixel-clock register stage for the final
palette/priority mux path. Avoid adding extra layer-specific delay in the mixer
unless it is matching this shared output phase.

This is the same general structure used by the Kicker/Road Fighter video path:
the scroll and object layers receive the common `hdump`, and the color mixer
applies the final blank/output delay (`BLANK_DLY(9)` there) after the layer mux
and palette path.

## Main CPU decode

The main CPU address decode has been written explicitly in HDL as active-low
terms in `jtmzone_main.v`. That part is not the remaining timing problem.

## Open items

- wire the remaining timing-sheet phase chain explicitly if needed
- verify the exact `HSYNC` and `OHSTART` edge placement against the schematic
- decide whether `jtframe_vtimer` start offsets should absorb the final visible
  window shift
- keep checking the phase of `HS` and `OHSTART` against the remaining timing
  chain

## PCB vertical counter mapping

The mapping below was moved from the reference comments in
`hdl/jtmzone_fix.v`. It describes the current `vsum`/`v_eff` calculation;
the original comment did not identify a specific PCB or MAME trace proving
the mapping independently.

```verilog
PCB vcount mapping:
raw vdump 0..255   -> PCB vcount 0..255
raw vdump 256..263 -> PCB vcount 248..255
flip mirrors the final 8-bit PCB vcount with bitwise inversion

if( vdump[8] )
    vsum = vdump[7:0] - 8'd8;
else
    vsum = vdump[7:0];

v_eff = flip ? ~vsum : vsum;
```

## PCB horizontal counter mapping

The following reference formula was preserved from comments in
`hdl/jtmzone_fix.v`. Its original comment did not identify a specific PCB or
MAME trace, so treat it as provisional rather than independently validated
hardware timing. It is not applied directly to the current FIX renderer.

```verilog
if( flip ) begin
    hn = h < 9'd048 ? 9'd047 - h :
         h < 9'd128 ? 9'd271 - h :
         h < 9'd144 ? 9'd143 - h :
         h < 9'd288 ? 9'd399 - h :
                       9'd399 - h;
end else begin
    hn = h < 9'd048 ? h :
         h < 9'd288 ? h - 9'd032 :
                       h - 9'd160;
end
pcb_hcnt = hn[7:0];
```

The current FIX implementation instead derives a local X counter from the
common raw `hdump` reference, sign-extended in HBLANK. The origin is 0 normally
and 240 when flipped. Before fetch lead and phase corrections, the visible
spans correspond to local X 0..47 for raw `hdump` 0..47, and mirrored local X
47..0 for raw `hdump` 240..287. The `hsum`/`heff` calculation includes the
existing fetch lead and `-flip` one-pixel phase correction. This documents
existing code; it does not establish evidence for a layer-specific offset.

Keep tile-map addressing separate from pixel/fetch pipeline phase. FIX and
SCROLL must use the same character rendering pipeline; any difference in
timing, address, or phase requires explicit PCB or MAME trace evidence.

## PCB object hardware

PCB findings supplied during core development; a specific trace or schematic
reference has not yet been recorded here.

### Render RAM scan
Object render RAM is scanned from byte A=0..143 once per line. The scan
starts at HCNT=40 and completes before the next HCNT=40. The 144 bytes are
36 object entries, four bytes each.

### Object DMA
DMA arms when VBLK goes active, starts one pixel count after HSYNC goes
active, and lasts for 240*4+1 HCNTs. The object RAM and object render RAM
address go from 0 to 240 in that time.


### Object ROM organization
Four ROMs are read as two selectable pairs. Object code byte 2 bit 7 selects
the pair:

    code[7]=0: codes 0x00..0x7f output { byte23, byte01 }
    code[7]=1: codes 0x80..0xff output { byte23, byte01 }

For one 4-pixel group, MAME's x offsets use bit 0 for pixel 0:

    byte01 = { pl0_px3, pl0_px2, pl0_px1, pl0_px0,
               pl1_px3, pl1_px2, pl1_px1, pl1_px0 }

    byte23 = { pl2_px3, pl2_px2, pl2_px1, pl2_px0,
               pl3_px3, pl3_px2, pl3_px1, pl3_px0 }

Pixels are reconstructed as:

    pxN = { pl3_pxN, pl2_pxN, pl1_pxN, pl0_pxN }

PCB address order inside the selected ROM pair:

    addr[0] = v0
    addr[1] = v1
    addr[2] = v2
    addr[3] = h0
    addr[4] = h1
    addr[5] = v3

### MAME and core ROM layout

MAME flattens the four ROMs into one `gfx1` region:

    gfx1 + 0x0000: byte01 for codes 0x00..0x7f
    gfx1 + 0x2000: byte01 for codes 0x80..0xff
    gfx1 + 0x4000: byte23 for codes 0x00..0x7f
    gfx1 + 0x6000: byte23 for codes 0x80..0xff

Core ROM layout without jtframe gfx_sort:
mame2mra repacks MAME order with sequence=[0,2,1,3], width=16 so matching
bytes from the selected ROM pair become adjacent:

    word16 = { byte23, byte01 }

The download address mapper transposes the packed within-tile address so each
32-bit SDRAM word contains two adjacent four-pixel groups for one row.  The
custom object drawer reads words as:

    rom_addr = { code, ysub[3], half, ysub[2:0] }

where half selects the left or right eight-pixel half.  Each response contains
two adjacent four-pixel groups in its lower and upper 16-bit lanes:

    pixels 0..3 = rom_data[15:0]
    pixels 4..7 = rom_data[31:16]

Thus one response supplies eight horizontal pixels and a 16-pixel sprite row
needs two requests, like Road Fighter.  Pixels are decoded from byte01/byte23
and written to a one-line object buffer.
