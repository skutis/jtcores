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
