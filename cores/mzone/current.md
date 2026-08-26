# Mega Zone Current Work

This is a handoff note for continuing the MZONE work.

## 2026-08-26 — Current flipped-OBJ experiment (authoritative)

The latest flipped simulation looks better after removing the core-side
sprite-X mirror. Preserve the raw object-RAM X coordinate in both screen
orientations:

```verilog
dr_xpos <= {1'b0, scan_dout};
```

Do not restore the recently tested `flip ? 8'd240-scan_dout : scan_dout`
without new PCB evidence. The `240-x` expression mirrors the bounding box of
a 16-pixel sprite in a 256-coordinate domain, but it added an unwanted second
position transformation for the current flipped PCB-test ROM.

The flipped PCB-test ROM intentionally retains its already calibrated sprite
coordinates. The coordinate conversion is in
`ver/pcb_test/make_pcb_testrom_6h.py`, functions `flipped_x()` and
`flipped_y()`, and is enabled/configured by `ver/pcb_test/build_static_tests.sh`.
Do not remove that test-program conversion: the same generated ROM must be
used for both the real PCB and simulation.

### Current core behavior

In `hdl/jtmzone_obj.v`:

```verilog
wire [3:0] ysub = ysum[3:0] ^ {4{attr[7]}};
dr_xpos  <= {1'b0, scan_dout};
dr_hflip <= ~attr[6];
dr_vflip <= attr[7];
```

Consequently global `flip` currently does not reverse sprite artwork rows or
columns and does not transform the raw sprite X coordinate. Local sprite
orientation continues to come from the sprite attribute bits. This remains an
experiment to compare against PCB behavior.

In `hdl/jtmzone_objdraw.v`, global `flip` still selects different physical
line-buffer display timing/origins:

```verilog
HOFFSET=54,      HOFFSET_FLIP=6
PCB_RD_ORIGIN=9, PCB_RD_ORIGIN_FLIP=16
RAM_RD_PHASE=1
```

`PCB_RD_ORIGIN_FLIP=16` is an active experiment. Baseline was 13. Decreasing
it to 10 moved the sprites three pixels in the wrong direction, so the current
opposite-direction test increases it by three to 16. Non-flipped timing is
unchanged.

The read addresses advance forward in both modes. The physical line buffer is
256 bytes and sprite writes may wrap through all 256 addresses. Display reads
are gated to `hread=510,511,0..239`: two priming requests followed by the 240
visible object pixels. In flipped mode these map to circular addresses
`15,16,17..255,0` with the current origin and phase.

### PCB-test sprite-coordinate policy

The standard flipped ROM is `ver/pcb_test/tflip_standard_static_6h_sim.rom`
(simulation) and `tflip_standard_static_6h.bin` (PicoROM). Its flipped
coordinates are deliberate:

- Balloons use the generator's calibrated `flipped_x()`/`flipped_y()` mapping.
- White edge and middle sprites use separately calibrated raw coordinates.
- The flipped sprite attribute toggle is `$C0` in the standard build, so the
  normal `$4E` attribute becomes `$8E` and reverses both local sprite
  orientations while preserving palette `$E`. The separately calibrated
  middle and X=`$FF` references also use `$8E`.
- MAME decodes local OBJ orientation as `flipx=~attr[6]` and
  `flipy=attr[7]`. Game software was observed changing orientation attributes
  by `$C0` between normal and flipped play. `$C0` is an XOR mask, not the final
  PCB-test attribute: `$4E ^ $C0 = $8E`.
- Do not also XOR global `flip` into the core's local OBJ orientation based on
  the game screenshots; that would double-flip sprites already adjusted by
  software. A real-PCB A/B test using the same asymmetric sprite with `$4E`
  and `$8E` is still the definitive way to prove whether the PCB adds another
  global OBJ orientation transform.
- The core must be corrected to match the real PCB; do not compensate by
  silently changing these test-ROM coordinates.

The rebuilt artifacts are:

```text
tflip_standard_static_6h.bin
SHA-256 7b71d7a7f1d8fe27c3100abfbbf7dfef7d6a88f64afcfee72122eb54665db295

tflip_standard_static_6h_sim.rom
SHA-256 4f34f9729c74e7fca400b700eee0325d77d5359c9cd3228f0453d6ff6ee0b6f6
```

### Latest reproduction and artifacts

From `cores/mzone/ver/game`:

```bash
source ../../env.sh
MZONE_SOUND=1 \
MZONE_ROM="$PWD/../pcb_test/tflip_standard_static_6h_sim.rom" \
./sim.sh -video 6 -w
```

This runs SCROLL, FIX, and OBJ together. The 2026-08-26 run completed
successfully with the rebuilt `$8E` sprite attributes and the active flipped
read-origin experiment at 16:

```text
cores/mzone/ver/game/frames/frame_00004.png
cores/mzone/ver/game/test.fst
```

`test.fst` was fully read back with `fst2vcd` and is valid. Current hashes:

```text
test.fst
SHA-256 5a2db81804571a4255498a6fb4ed613d93d6b56517522027239cf550612157c2

frames/frame_00004.png
SHA-256 053cff0291b97121b20b9f883cce303cb8ea778c87d3c043f4177288f70c507f
```

For flipped experiments, overwrite `test.fst` rather than renaming it so an
open GTKWave session can reload the file without rebuilding its signal list.
Keep the flipped ROM fixed while changing one core mechanism at a time.

## 2026-08-17 09:13:15 CEST — Real-PCB PicoROM program in 6H

The goal is to run new main-CPU code on a real Mega Zone PCB using PicoROM in
the `.6h` ROM socket. The existing
`cores/mzone/tools/make_scrolltest_rom.py` already contains the required
Konami-1 opcode encoding and instruction emitters; a separate assembler
backend is not required for the instructions covered by those emitters.

The 8 KiB `.6h` device maps to main-CPU addresses `$E000-$FFFF`. A standalone
PicoROM image for this socket must therefore be exactly `$2000` bytes, with
CPU addresses translated to file offsets as:

```python
BASE = 0xE000
rom = bytearray([0xFF] * 0x2000)

def put_cpu(addr, *values):
    offset = addr - BASE
    for i, value in enumerate(values):
        rom[offset + i] = value & 0xFF
```

Konami-1 encoding is applied only to opcode bytes. Operands, immediate data,
addresses, and vectors remain plain. Encoding depends on the absolute CPU
address, not the offset within the 6H image:

```python
def konami_opcode(addr, plain):
    mask = (
        ((addr >> 1) & 1) << 7
        | ((~(addr >> 1)) & 1) << 5
        | ((addr >> 3) & 1) << 3
        | ((~(addr >> 3)) & 1) << 1
    )
    return plain ^ mask

def op(addr, plain_opcode):
    put_cpu(addr, konami_opcode(addr, plain_opcode))
```

The scroll-test program currently starts at `$8000`, which belongs to a
different ROM socket. For a 6H-only PicoROM test, relocate its entry point to
an address such as `$E000` and retain an IRQ routine at an address such as
`$FE00`. Patch the vectors as unencoded bytes:

```python
put_cpu(0xFFF8, 0xFE, 0x00)  # IRQ vector -> $FE00
put_cpu(0xFFFE, 0xE0, 0x00)  # reset vector -> $E000
```

The CPU reads the reset vector from `.6h` at `$FFFE-$FFFF` and will then begin
executing the encoded opcode stream at `$E000`. Reuse the existing helpers
such as `lda_imm`, `sta_ext`, `ldx_imm`, and the branch emitters, changing
their storage calls to `put_cpu` while continuing to pass absolute CPU
addresses to `konami_opcode`.

## 2026-08-01 Latest Handoff (Authoritative)

This section supersedes the implementation status and Verilator paths in all
older sections below. The older sections are retained as an experiment log.

### Current objective

Determine why the Road Fighter and Mega Zone object line buffers are one pixel
away from the MAME sprite positions and why the first sprite pixel at the
horizontal boundary can reappear at the far end of the rendered line. The
result must be correct in the synthesized FPGA core, not just adjusted in the
PNG conversion.

The Mega Zone background is aligned correctly. The unresolved work is the OBJ
read/output/clear phase relative to the final RGB and blanking pipeline.

### Current repository state

At this handoff, `git status --short` from the repository root is:

```text
M  cores/mzone/hdl/jtmzone_objdraw.v
M  cores/roadf/hdl/jtroadf_game.v
?? cores/mzone/=
```

The two HDL modifications are staged. `cores/mzone/=` is an unrelated empty,
untracked file and has not been removed. Updating this handoff makes
`cores/mzone/current.md` an additional unstaged tracked modification.

The active Mega Zone change is in `hdl/jtmzone_objdraw.v`:

```verilog
wire [8:0] hread = hdump - hoffset;
wire       buf_rd = pxl_cen && hread<9'd240;
wire [7:0] buf_rd_addr = hread[7:0];
```

This replaces the previous `<246` window. Mega Zone now requests only the 240
visible object-buffer addresses; the registered output path is allowed to
drain after the last request. The temporary address-hold/address-zero
workaround was removed as requested. Do not assume this is the final fix.

The staged Road Fighter change adds a simulation-only scene control under
`NOMAIN` in `cores/roadf/hdl/jtroadf_game.v`:

```verilog
`ifdef ROADF_FORCE_FLIP
    assign flip = 1;
`else
    assign flip = 0;
`endif
```

It does not affect a normal FPGA build unless both `NOMAIN` and
`ROADF_FORCE_FLIP` are defined.

### Latest simulation artifacts

Mega Zone outputs from the current no-workaround `<240` implementation:

```text
cores/mzone/ver/game/test.fst
cores/mzone/ver/game/frames/frame_00004.png
```

They were generated on 2026-07-31 07:11 CEST. The PNG is very small because
the test scene is mostly black; it is not the earlier completely black failed
render.

Road Fighter MAME scene 1141 remains at:

```text
cores/roadf/ver/game/scenes/1141/vram_lo.bin  (2048 bytes)
cores/roadf/ver/game/scenes/1141/vram_hi.bin  (2048 bytes)
cores/roadf/ver/game/scenes/1141/obj.bin       (1024 bytes)
```

Latest Road Fighter outputs:

```text
cores/roadf/ver/game/test.fst
cores/roadf/ver/game/frames/frame_00001.png
```

They were generated on 2026-07-30 07:13 CEST. `obj.bin` is the object/sprite
attribute RAM dump, not sprite graphics. `vram_lo.bin` and `vram_hi.bin` are
the two video-RAM planes.

### Commands to reproduce

Mega Zone scroll-test simulation, from `cores/mzone/ver/game`:

```bash
source ../../env.sh
MZONE_ROM=../../../../rom/megazone_scrolltest.rom \
MZONE_SOUND=1 ./sim.sh -video 4 -w
```

Road Fighter scene simulation, from the repository root:

```bash
source ./setprj.sh
export VERILATOR_ROOT=/home/skutis/verilator
export PATH="$VERILATOR_ROOT/bin:$PATH"
hash -r
cd cores/roadf/ver/game
./sim.sh -g roadf -s scenes/1141 -w
```

Add `-d JTFRAME_SIM_GFXEN=8` for Road Fighter objects only. Add
`-d ROADF_FORCE_FLIP` to exercise the scene-only flip control.

### Observed timing and orientation

- The scene flip/orientation test was correct. With the portrait PNG oriented
  with its origin at the upper right and its long direction horizontal, the
  sprite horizontal position is effectively `-1-hpos`.
- User comparison against the open MAME debugger showed all Road Fighter
  sprites one pixel away in horizontal position.
- Mega Zone was examined around `vdump=183`, `hdump=54,55`: the expected first
  white diagnostic pixel was absent.
- The background is correct, so a global PNG or whole-video shift is not an
  acceptable explanation/fix.
- In Road Fighter, the OBJ reader uses `HOFFSET=5`, so
  `hread = hdump-5`. The generic Kicker drawer asserts reads while
  `hread < {1'b1,HOFFSET}`, which is `hread<261`. Because only the low eight
  address bits reach the line buffer, the tail reads wrap addresses 256..260
  onto addresses 0..4.
- Road Fighter observation at `vdump=74`: at `hdump=261`, `rd_addr=0` and
  `rd_data=1` (the blue diagnostic pen); by approximately `hdump=264`, the
  final blue output is nonzero. This is the pixel seen at the last visible PNG
  position instead of immediately after blanking.
- Do not confuse internal `preLHBL`, exported `LHBL`, object `pxl`, palette
  `raw/rgb`, and final RGB. Road Fighter uses
  `jtyiear_colmix #(.BLANK_DLY(9))`, so blanking and RGB pass through the same
  delayed color pipeline.

### Important `jtframe_obj_buffer` finding

Both cores use `modules/jtframe/hdl/ram/jtframe_obj_buffer.v`. Its object RAM
port continuously uses the current `rd_addr`. A read pulse starts `dly`; later,
when `delete_we=dly[0]`, the module captures `dump_data` and clears the RAM at
the **then-current** `rd_addr`:

```verilog
if( rd ) dly <= {1'b1,{BLANK_DLY-1{1'b0}}};
else     dly <= dly>>1;
if( delete_we ) rd_data <= dump_data;

.addr1 ({~line,rd_addr}),
.we1   (delete_we),
.q1    (dump_data)
```

There is no registered request address paired with the delayed output/clear.
In the Road Fighter FST, a pulse for address 0 can therefore capture/clear the
next address after `rd_addr` advances. The data at address 0 can survive and
be read again when the low eight address bits wrap at the end of the line.
This is the leading explanation for the boundary duplicate, but it is not yet
proven against the final RGB coordinate and has not been changed in JTFRAME.

This same behavior exists in FPGA RTL. Verilator is not an independent
software renderer. If different simulators produce different results here,
that would indicate an ambiguous RAM/scheduling assumption that must be made
explicit in RTL; selecting a convenient simulator version is not a valid FPGA
fix.

### Verilator status (corrected)

The Verilator actually installed and used now is:

```text
/home/skutis/verilator/bin/verilator
Verilator 5.018 2023-10-30 rev v5.018
repository tag: v5.018
```

There is currently no `/home/skutis/github/verilator` stable checkout. Older
notes below saying `/home/skutis/verilator` is 5.046 and
`/home/skutis/github/verilator` is 5.024 are stale.

JTFRAME does not pin a Verilator release. `modules/jtframe/bin/jtsim` uses
`$VERILATOR_ROOT/bin/verilator` when `VERILATOR_ROOT` is set and otherwise
uses `verilator` from `PATH`. `modules/jtframe/doc/sim.md` mentions Verilator
4.224 only as the version used in an old performance comparison.

### FST signals to inspect next

For the object line buffer, keep these together at individual master-clock
edges, not only at `hdump` changes:

```text
clk
pxl_cen
hdump
vdump
hread
buf_rd / buf_clr
buf_rd_addr / rd_addr
u_line.dly (M-Zone) or u_buffer.dly (Road Fighter)
delete_we
dump_data
rd_data
object pxl / obj_pxl
color-mixer mux
color-mixer raw
color-mixer rgb
preLHBL
LHBL
red, green, blue
```

Relevant hierarchy roots are:

```text
M-Zone:      u_game.u_game.u_video.u_obj.u_draw
Road Fighter: u_game.u_game.u_video.u_obj.u_draw
Road Fighter color mixer: u_game.u_game.u_video.u_colmix
```

### Recommended continuation

1. In the Road Fighter FST at `vdump=74`, trace one master-clock edge at a time
   across `hdump=255..265`. Establish exactly which raw object coordinate is
   present at `obj_pxl`, palette `raw/rgb`, and final RGB, and compare it with
   exported `LHBL`.
2. Trace the normal address-zero read near `hdump=5` and the wrapped address-zero
   read near `hdump=261`. Confirm whether the delayed clear wrote address 1
   instead of address 0 on the first read.
3. Repeat the same address/output/clear trace for Mega Zone around
   `vdump=183`, `hdump=53..57` with the current `<240` window.
4. If the address association is confirmed, fix it explicitly—preferably in a
   narrowly tested JTFRAME/object-buffer change or a core-local wrapper—and
   compare final object position against MAME and the already-correct
   background. Do not merely alter the PNG, blanking, or Verilator version.
5. For simulator cross-checking, run the identical scene with Icarus/ModelSim
   or another Verilator release if available. A changed result is evidence of
   underspecified RTL, not evidence that one version is the FPGA truth.

## Current Focus

OBJ DMA/rendering in `cores/mzone`.

## Current State

- OBJ DMA enable/window is HCLK-derived.
- OBJ DMA copy counter/address increments from the 18.432 MHz derived `dma_cen`.
- The DMA copy counter stops at 240 and holds there until the HCLK-derived window disables DMA.
- OBJ scan/draw sequencing is on the normal core clock, not `dma_cen`.
- Test ROM drops are visible again around frame 8 with:

```sh
cd cores/mzone/ver/game
source ../../env.sh && ./sim.sh -video 20
```

## Key Files

- `cores/mzone/hdl/jtmzone_obj.v`
- `cores/mzone/hdl/jtmzone_objdraw.v`
- `cores/mzone/hdl/jtmzone_video.v`
- `cores/mzone/hdl/jtmzone_game.v`
- `cores/mzone/cfg/game.yaml`

## Important Notes

- `objram` is now instantiated as `jtframe_dual_ram` in `jtmzone_game.v`.
- CPU-visible OBJ RAM is written/read from `jtmzone_main.v`.
- The video/OBJ side reads CPU OBJ RAM through `objram_rd_addr/objram_rd_data`.
- `obj_render_ram` is a separate dual RAM inside `jtmzone_obj.v`.
- `obj_render_ram` is written by DMA copy address and read by the OBJ scanner through its own local render address.
- The previous `dma_slot`, `dma_group`, and `dma_quota` scheduler was removed. The copy address itself is the DMA counter now.

## Last Known Good Check

Short test:

```sh
cd cores/mzone/ver/game
source ../../env.sh && ./sim.sh -video 20
```

Expected result:

- `frames/frame_00008.jpg` shows the test drops.

## Context For Next Session

Continue from this assumption:

> DMA enable/window is controlled by HCLK timing, but the DMA counter is clocked by 18.432 MHz. OBJ scan/draw should not be gated by `dma_cen`; only the DMA copy counter/address stepping should use it.

## OBJ Counter / MAME Offset Notes From 2026-06-07

Current working HDL object horizontal path is still MAME/screen-coordinate style:

```verilog
draw_hs    = hdump == 9'd0;
draw_hdump = hdump;
dr_xpos    = flip ? xpos - 9'd11 : xpos + 9'd32;
```

The `+32` and `-11` come from MAME `src/mame/konami/megazone.cpp`:

```cpp
int sx = m_spriteram[offs + 3];
if (m_flipscreen)
    sx = sx - 11;
else
    sx = sx + 32;
```

These are not literal PCB adders. They are MAME's conversion from raw 8-bit OBJ RAM X into bitmap/screen X. On the PCB, raw OBJ X is a 0..255 modulo line-buffer/object-counter coordinate. The offset should come from line-buffer timing and visible origin.

Important PCB-derived mapping notes:

- Core `hdump=48` corresponds to PCB `HCNT=16`.
- Therefore the simple mapping after the PCB reset/wrap point is `pcb_hcnt = hdump - 32`.
- This does not work before `hdump=48`; the pre-wrap/blank tail needs a separate mapping.
- Proposed shadow mapping for PCB `HCNT` from core `hdump`:

```verilog
wire [8:0] pcb_hcnt = hdump < 9'd48 ? hdump + 9'd208 : hdump - 9'd32;
```

This gives:

```text
hdump 0  -> pcb_hcnt 208
hdump 47 -> pcb_hcnt 255
hdump 48 -> pcb_hcnt 16
hdump 79 -> pcb_hcnt 47
```

User observation from PCB/schematic tracing:

- PCB `HCNT` resets to 16 after 47.
- At real PCB `HCNT=255`, object X/read coordinate is 243 when `HBLK_N` goes active.
- That implies an object X phase of approximately `obj_x = pcb_hcnt - 12` modulo 256 during the relevant active range.
- At PCB `HCNT=44`, this gives `obj_x=32`, which explains MAME's normal-screen `sx = raw_x + 32`: visible/screen X 0 corresponds to object coordinate 32.

Experiments tried and reverted:

- Moving only `draw_hs` from `hdump==0` to `hdump==44` made the sprite/drop holes return. This proves `jtframe_objdraw` cannot use PCB LB enable timing directly through its single `hs` input.
- Moving `draw_hs` to 44, changing `draw_hdump` to `hdump-44`, and using raw `dr_xpos<=xpos` also broke sprites.
- Reason: `jtframe_objdraw` ties several PCB-separate concepts to one `hs`: line-buffer bank swap, `hdfix` behavior, read address phase, and read/clear timing.
- Real PCB has separate timing concepts: `LBRST_N` around HCNT 40..43, `LB1EN_N/LB2EN_N` active at HCNT 44, object/read counter phase, RAM output delay, and read/clear behavior.

Vertical OBJ state:

The current vertical object test was changed to PCB-style and did not bring back the watched drop hole:

```verilog
ysum   = {1'b0,vdump[7:0]} + {1'b0,ypos};
inzone = ysum[7:4] == 4'hf;
ysub   = ysum[3:0] ^ {4{attr[7]}};
```

Next PCB-style OBJ attempt should start by adding a local `pcb_hcnt`/object counter shadow and either:

- write a Mega Zone-specific line-buffer/read-clear wrapper where buffer swap, read address, and clear timing are separate signals, or
- modify/wrap `jtframe_objdraw_gate` so `hs` is not responsible for all of those phases.

Do not remove the MAME `+32/-11` compensation until the object line-buffer domain is really PCB-like.

Useful FST signals for this work:

```text
u_game.u_game.u_video.u_obj.hdump
u_game.u_game.u_video.u_obj.vdump
u_game.u_game.u_video.u_obj.draw_hs
u_game.u_game.u_video.u_obj.draw_hdump
u_game.u_game.u_video.u_obj.obj_visible
u_game.u_game.u_video.u_obj.dr_xpos
u_game.u_game.u_video.u_obj.ysum
u_game.u_game.u_video.u_obj.ysub
u_game.u_game.u_video.u_obj.draw
u_game.u_game.u_video.u_obj.busy
u_game.u_game.u_video.u_obj.pxl_en
u_game.u_game.u_video.u_obj.pxl
u_game.u_game.u_video.u_obj.u_draw.u_gate.hdfix
u_game.u_game.u_video.u_obj.u_draw.u_gate.hdf
u_game.u_game.u_video.u_obj.u_draw.u_gate.buf_addr
u_game.u_game.u_video.u_obj.u_draw.u_gate.buf_we
u_game.u_game.u_video.u_obj.u_draw.u_gate.u_linebuf.line
u_game.u_game.u_video.u_obj.u_draw.u_gate.u_linebuf.delete_we
u_game.u_game.u_video.u_obj.u_draw.u_gate.u_linebuf.rd_data
```

## OBJ X/Drop Notes From 2026-05-31

- `HEAD` / `0769d0d18 mzone core` still shows the wrong/smeared drop form in the scroll test.
- The parent commit `22b57b32d mzone core` shows a clean drop in the same test ROM.
- Parent-commit sim crop is saved as `ver/game/drop_crop_prev_commit.png`.
- Last-commit crop is saved as `ver/game/drop_crop_head2.png`.
- Expected decoded OBJ `$aa`, color `$f` data is saved as `ver/game/expected_drop_aa.txt`; expected visual is `ver/game/expected_drop_aa.png`.
- Staged drop reference data is saved as `ver/game/drop_aa_stage_data.txt`.
- Documentation pointer is saved as `doc/obj_drop_reference.md`.

Changes tried today before reverting to commit comparisons:

- Removed `dr_rom_hflip` / `rom_hflip` and used only `dr_hflip` for the ROM half/word compensation.
- Tried raw PCB object X: `xpos = {1'b0,xpos_raw_eff}`.
- Tried PCB-like read counter where line-buffer read X is held at zero around HCNT 40..44:
  `hdump < 40 ? hdump + 344 : hdump < 45 ? 0 : hdump - 44`.
- Tried a local `jtmzone_objdraw` wrapper using `jtframe_draw` but an 8-bit wrapping line buffer to avoid `jtframe_objdraw_gate`'s `hdfix`.
- Tried adapting `jtmzone_objdraw2` / 4-pixel group drawer; that was not the right path for this regression.

Useful conclusion:

- The clean-vs-bad comparison points to the `0769d0d18` object/ROM/mem-layout changes, not only today's PCB X experiment.
- For implementing PCB X, start from the clean parent behavior and preserve the parent object ROM interface assumptions first, then change only the line-buffer X domain.

## 2026-07-25 Current OBJ Timing Handoff

This section describes the current working tree and supersedes the older OBJ
implementation notes above. The work is not yet considered finished. The main
remaining issue is verifying the first and last object columns at the active
display boundaries without adding an address-zero special case.

### Current implementation

`hdl/jtmzone_objdraw.v` now follows the simpler Road Fighter/Kicker structure:

- Each 32-bit object-ROM response supplies eight decoded pixels.
- A 16-pixel row uses two ROM requests, selected by `rom_addr[3]`.
- Pixels are drawn at `cen2` cadence.
- `rom_pending`, four-pixel grouping, `wr_phase`, and explicit transparent-write
  suppression were removed.
- The palette PROM is synchronous BRAM. Its line-buffer address and write enable
  are delayed one master clock in `buf_al` and `buf_wel`.
- The color mixer, rather than the object drawer, decides whether object pen
  zero is transparent.
- Global horizontal flip is resolved when object coordinates are prepared in
  `jtmzone_obj.v`; the line buffer itself uses ascending read coordinates.
- The object-buffer bank switch is driven from `HS` through
  `obj_buf_lhbl = ~HS`. Reads and writes control actual buffer activity, so the
  switch can occur safely during horizontal blank.

The current non-flipped read timing is:

```verilog
localparam [8:0] HOFFSET = 9'd54;
wire [8:0] hread = hdump - hoffset;
wire       buf_rd = pxl_cen && hread < 9'd246;
wire [7:0] buf_rd_addr = hread[7:0];
```

There is currently no first-pixel prefetch or special address-zero request.
The six extra reads let the registered object-buffer/mixer path drain after the
240 object addresses. `HOFFSET_FLIP` remains 6, although flipped operation is
not the current focus.

The intended non-flipped mapping is line-buffer address 0..239 to raw display
X 48..287. Physical writes are clipped with `buf_a < 240`.

### Timing experiments and observations

- `HOFFSET` 53 and 54 have both been simulated repeatedly. The current value is
  54 because the displayed sprites appeared one pixel too far toward lower
  `hdump` with 53.
- Changing the read address to `hread + 1` shifted every sprite another pixel
  toward lower `hdump`; it was reverted.
- Requesting address zero at wrapped `hread=511` was tried as a prefetch and
  then removed. Requesting address zero twice could make the left boundary
  visible, but is not considered a clean solution.
- With some earlier timing combinations the right-edge diagnostic intended for
  raw X 287 appeared at X 286, while the first object column at raw X 48 was
  blank or stale.
- The user observed in the FST that output appears about two pixel clocks after
  the corresponding `hread` request. `jtframe_obj_buffer` has a synchronous RAM
  read plus registered output/clear behavior; its default `BLANK_DLY` is two
  master clocks.
- `fix_en` is delayed into the mixer with the other layers. Testing indicates
  that its active window is not the main cause of the object-boundary problem.

Do not infer a fix from the rendered frame alone. Compare `hread`,
`buf_rd_addr`, the internal object-buffer RAM output, `pxl`, `fix_en`, and the
final mixer output in the same FST.

### Diagnostic scroll-test ROM

Regenerate it from `ver/game` with:

```bash
MZONE_SCROLLTEST_SPRITES=1 ../../tools/make_scrolltest_rom.py
```

The generator now makes object code `0xd0` as a solid 16x16 diagnostic sprite:

- first pixel column: pen 1, mapped to white by object palette F;
- middle columns: pen 8, red;
- last pixel column: pen 2, mapped to blue.

The unusual packed ROM generation is intentional. It reverses the object-ROM
download address transpose in `jtmzone_game.v`. FST inspection confirmed that
the first eight-pixel response ends with decoded nibble 1, the second response
starts with decoded nibble 2, and the interior nibbles are 8.

Relevant test objects currently include:

- Entry `0x20`: balloon/drop wrapping across the left boundary.
- Entry `0x21`: full `0xd0` diagnostic around raw X 56, isolated vertically
  around raw VDump 215..230.
- Entry `0x22`: `0xd0` right-boundary diagnostic; only address 239 should
  survive, at raw X 287.
- Entry `0x1f`: `0xd0` left-boundary diagnostic with stored object X 0 and
  stored raw Y 57. Stored raw Y 57 displays around VDump 182; stored object X 0
  maps to raw display X 48.

The object scan covers entries 35 down to 0 (`0x23` through `0x00`). A test
placed at `0x24` will not be scanned.

### Simulation commands

From `ver/game`, run five non-flipped frames with:

```bash
source ../../env.sh
MZONE_ROM=../../../../rom/megazone_scrolltest.rom \
MZONE_SOUND=1 ./sim.sh -video 5 -w
```

For a flipped comparison, append:

```text
-d MZONE_FORCE_FLIP
```

Primary outputs:

```text
ver/game/test.fst
ver/game/frames/frame_00005.png
```

Useful FST signals are under `u_game.u_game.u_video.u_obj.u_draw`; inspect at
least `hdump`, `vdump`, `hread`, `buf_rd`, `buf_rd_addr`, `pxl`, object-buffer
RAM/read data, `fix_en`, and the color-mixer inputs/output.

### Suggested next check

Use the `0xd0` sprites to trace one complete row at raw X 48 and the single
surviving column at raw X 287. Record, for each pixel clock, the requested
address, synchronous RAM result, registered object-buffer output, and mixer
result. This should distinguish a read-origin error from the one-read latency
at activation. Preserve the current HOFFSET=54/no-prefetch result as the
comparison baseline.

## 2026-07-26 OBJ Read-Timing Handoff

This section supersedes the `HOFFSET=54/no-prefetch` baseline above for the
current working tree. The boundary problem is still under investigation.

### Active working-tree changes

`hdl/jtmzone_video.v` has a waveform-only coordinate reference:

```verilog
wire [8:0] dbg_hdump_colmix = hdump - 9'd6;
```

This expresses the raw layer coordinate currently expected at the color-mixer
input. A layer pixel for raw X should reach the mixer at physical
`hdump = X+6`. The color mixer then has two palette stages and the final
`jtframe_blank` RGB register, giving nine pixel clocks total from raw timing to
the simulation-picture RGB. `BLANK_DLY=9` includes that final RGB register.

`hdl/jtmzone_objdraw.v` currently has an experimental address-zero
pre-request:

```verilog
wire       buf_first = hread == 9'd511;
wire       buf_rd = pxl_cen && (buf_first || hread<9'd246);
wire [7:0] buf_rd_addr = buf_first ? 8'd0 : hread[7:0];
```

With `HOFFSET=54`, this requests address zero at `hdump=53`, then requests it
again in the normal sequence at `hdump=54`. This experiment did not make the
raw-X 48 first column visible in the latest simulation.

The diagnostic-generator comment in `tools/make_scrolltest_rom.py` was fixed
to describe the actual `0xd0` pattern: every row has a white first horizontal
column (pen 1), red interior (pen 8), and blue last horizontal column (pen 2).

### Latest simulation

The latest non-flipped five-frame test used:

```bash
source ../../env.sh
MZONE_SOUND=1 MZONE_ROM=../../../../rom/megazone_scrolltest.rom \
    ./sim.sh -video 5 -w
```

It completed successfully. The local outputs are:

```text
ver/game/test.fst
ver/game/frames/frame_00005.png
```

The FST includes both `dbg_hdump_colmix` and `u_obj.u_draw.buf_first`.

### Current coordinate/read relationship

For non-flipped operation:

```verilog
hread       = hdump - 54;
buf_rd_addr = hread[7:0];
```

Ignoring event/delta-cycle presentation:

```text
hdump 54 -> buffer address 0 -> mixer-coordinate 48
hdump 55 -> buffer address 1 -> mixer-coordinate 49
hdump 62 -> buffer address 8 -> mixer-coordinate 56
```

The ordinary read window covers addresses 0..245 at `hdump` 54..299. Addresses
240..245 are trailing reads used to drain the registered buffer/mixer path.
The line-buffer bank switches on the rising edge of `HS`, around `hdump=319`,
through `obj_buf_lhbl = ~HS`.

### `jtframe_obj_buffer` timing

The generic object buffer continuously presents `rd_addr` to a synchronous
dual-port RAM. Its `rd` input does not enable the RAM read; it starts the
delayed output/clear sequence. With the default `BLANK_DLY=2`, conceptually:

```text
E0, rd=1: RAM samples rd_addr; dly becomes 2'b10
E1:       dump_data gets the E0 address data; dly becomes 2'b01
E2:       rd_data captures dump_data; delete_we clears the current rd_addr
```

Neither the requested address nor its RAM result is explicitly paired with
the delayed clear event. `rd_addr` also drives the RAM continuously. Correct
behavior therefore depends on the address remaining stable through the
relevant master-clock edges.

In the waveform being examined, the raw-X 48 diagnostic's first column does
not reach the picture, while its second column at raw X49 is correct.
`delete_we` is observed during physical `hdump=55`, which corresponds to
`dbg_hdump_colmix=49`. The important unresolved question is exactly which
`rd_addr` produced `dump_data` at the clock where `rd_data` is updated; inspect
master-clock edges rather than only pixel-clock/`hdump` transitions.

### Recommended next step

At one affected row (the user was examining approximately `vdump=198`), zoom
to individual master-clock edges around physical `hdump=53..56` and display:

```text
clk
pxl_cen
hdump
dbg_hdump_colmix
hread
buf_first
buf_rd
buf_rd_addr
u_line.dly
u_line.delete_we
u_line.dump_data
u_line.rd_data
pal_pxl
u_colmix.obj_pxl
```

Record the value before and after each rising `clk` edge. Determine whether
address zero is lost because the address changes before the `rd_data` capture,
or because the first `rd` pulse and `dly` phase are one master clock too late.
Do not change `HOFFSET` or globally shift `buf_rd_addr`: address 1 and later
pixels already align with mixer coordinates. If a fix is needed, prefer
pairing/capturing the RAM data associated with the request or separating
output capture from delayed clearing.

## 2026-07-28 10:49:57 CEST — Road Fighter Comparison and Scene Handoff

This section records the current cross-core comparison work. It also corrects
the active M-Zone state described in the previous handoff: the current
`jtmzone_objdraw.v` uses `HOFFSET=54` with no address-zero prefetch.

### Road Fighter object-edge test

A new, currently untracked generator exists at:

```text
cores/roadf/ver/game/make_objedge_test_rom.py
```

It builds:

```text
rom/roadf_objedge_test.rom
```

from `rom/roadf.rom`. The diagnostic program clears the 34 scanned object
entries and writes exactly two objects:

```text
object entry 33: raw X=0, raw Y reference=96
object entry 32: raw X=8, raw Y reference=128
```

The assembled Road Fighter main-CPU region retains the complete 64 KiB CPU
address space after the eight-byte header. Consequently, the correct patch
mapping is:

```python
rom_offset = 8 + cpu_address
```

There is no byte XOR and no subtraction of `0x4000` at this stage. Konami-1
opcode encryption is applied only to opcode bytes. The program reads CPU
address `0x1400` once to toggle `obj_frame` and expose the written object-RAM
bank.

Road Fighter object RAM is CPU-visible at `0x1000..0x13ff`. Each entry is:

```text
+0 attribute/palette/flip/code-high
+1 stored/inverted Y
+2 sprite code
+3 X position
```

The game has two 1 KiB object-RAM banks. Pixel graphics themselves remain in
the ROM `sprites` region at `OBJ_START`; `obj.bin` contains only object-list
RAM.

### Orientation

Both Road Fighter and M-Zone MRAs specify:

```text
vertical (cw)
```

The simulation PNG conversion rotates both games clockwise. Raw hardware X
therefore becomes the displayed PNG vertical axis. Road Fighter objects at
raw X 0 and 8 appear at the bottom edge of the portrait PNG. Earlier
references to M-Zone X 48/56 were raw `hdump` coordinates, not unrotated PNG
coordinates.

### Road Fighter scene 1141

The captured scene is:

```text
cores/roadf/ver/game/scenes/1141/
    vram_lo.bin   (2048 bytes)
    vram_hi.bin   (2048 bytes)
    obj.bin       (1024 bytes)
```

These files are ignored by the repository's Git rules. Road Fighter's
`sim.sh -s` copies the VRAM snapshots and duplicates `obj.bin` into the two
simulation object-bank files. It also defines `NOMAIN`, `NOSND`, and a
two-frame video run.

The successful object-only scene command was:

```bash
cd /home/skutis/github/jtcores-fork
source ./setprj.sh
export VERILATOR_ROOT=/home/skutis/github/verilator
export PATH="$VERILATOR_ROOT/bin:$PATH"
hash -r
cd cores/roadf/ver/game
rm -rf obj_dir frames
./sim.sh -s scenes/1141 -w -d JTFRAME_SIM_GFXEN=8
```

Outputs from the successful run:

```text
cores/roadf/ver/game/frames/frame_00001.png
cores/roadf/ver/game/test.fst
```

`JTFRAME_SIM_GFXEN=8` enables only `gfx_en[3]`, the object layer. The captured
scene renders a vertical group of Road Fighter objects plus the bottom
CHECK/road-edge objects on a black background.

### Simulator toolchain finding

The Verilator build selected by the default environment:

```text
/home/skutis/verilator  (Verilator 5.046 development build)
```

segfaults before simulation initialization for the `NOMAIN` scene build. GDB
places the failure in `VL_MURMUR64_HASH(vlSelf->vlNamep)` during generated
model reset. Explicitly passing `"TOP"` to the model constructor did not fix
it and that experiment was fully reverted.

The repository-local stable build:

```text
/home/skutis/github/verilator  (Verilator 5.024)
```

runs scene 1141 successfully and produces both PNG and FST.

All experimental modifications to `modules/jtframe/hdl/ver/test.cpp` have
been reverted; that file currently has no Git diff.

### MAME scene capture

The tracked Road Fighter helper:

```text
cores/roadf/ver/game/save.mame
```

contains:

```text
save vram_lo.bin,2000,800
save vram_hi.bin,2800,800
save obj.bin,1000,400
```

From the MAME debugger, capture with:

```text
source /home/skutis/github/jtcores-fork/cores/roadf/ver/game/save.mame
```

Then place the three outputs in
`cores/roadf/ver/game/scenes/<scene-name>/` and simulate with:

```bash
./sim.sh -s scenes/<scene-name> -w
```

Append `-d JTFRAME_SIM_GFXEN=8` for an object-only render.

### Git state at handoff

There are no tracked modifications under `cores/roadf`. The only visible new
Road Fighter source file is:

```text
?? cores/roadf/ver/game/make_objedge_test_rom.py
```

Road Fighter FSTs, PNG frames, assembled ROMs, scene snapshots, generated RAM
files, and `obj_dir` are ignored build/debug artifacts. `save.mame` was
already tracked and remains unchanged.

## 2026-08-05 23:07:44 CEST — M-Zone OBJ Origin, ROM Order, and FIX Masking

### Current HDL and simulation state

The non-flipped object read offset experiment has been reverted. The active
value in `hdl/jtmzone_objdraw.v` is again:

```verilog
localparam [8:0] HOFFSET      = 9'd54;
localparam [8:0] HOFFSET_FLIP = 9'd6;
```

The address-255 priming read remains active:

```verilog
wire buf_rd = pxl_cen && (hread==9'h1ff || hread<9'd240);
```

`HOFFSET=48` and then `HOFFSET=44` were tested. `44` made ordinary sprite
positions look better, but moved the line-buffer read window so its pixels no
longer fit the FIX/HBL boundary correctly. It was not retained. Recent scene
and test-ROM simulations completed successfully with waveform output; the
latest standard test-ROM run used the restored `HOFFSET=54`.

### PCB sprite coordinate observations

On the PCB/model, the object read counter reaches position zero four pixel
clocks before the SCROLL/OBJ boundary. This is the measured PCB object-pipeline
lead. Keep that physical lead separate from the HDL line-buffer request phase
and from final RGB coordinates.

The game was observed changing a moving sprite's raw OBJ RAM X byte through:

```text
$01, $02, $03, ... $F7
```

The object is then erased. At `$01`, only the bottom/second eight source pixels
of the non-opaque sprite are visible at the entry boundary. This is not an
`$F8` wrap case. Raw X bytes remain the useful evidence; MAME's `sx+32` and
`sx-11` conversions are bitmap-coordinate adjustments and are not literal PCB
adders.

### Newly identified FIX masking

The current leading explanation for the eight-pixel entry behaviour is that
object rendering begins while FIX priority is still active. The first eight
object pixels are produced but covered by `fix_en`; the following eight arrive
after `fix_en` deasserts and become visible.

The color mixer implements this directly:

```verilog
wire obj_en = obj_pxl != 4'd0 && !fix_en;
```

Confirm on one affected row by tracing:

```text
hdump
buf_rd_addr
obj_pxl
fix_en_pre
fix_en
pal_mux / selected layer
final RGB
```

The expected signature is nonzero object pixels for source positions 0..7
while `fix_en=1`, followed by source positions 8..15 with `fix_en=0`. Per the
video-pipeline rules, treat `fix_src`/`fix_en_pre` as source/address timing and
delayed `fix_en` as mixer priority. Do not change FIX timing independently of
SCROLL without a PCB-aligned trace.

FIX masking can explain clipping at the FIX boundary. It cannot by itself
explain a uniform horizontal displacement of sprites that are entirely inside
the playfield.

### Sprite ROM group order and K083

The M-Zone schematic annotation records the physical four-group sequence as:

```text
01, 00, 11, 10
```

The PCB Verilog model has also appeared as:

```text
10, 01, 00, 11
```

These are cyclic rotations of the same repeating sequence. The actual sprite
group zero must be determined by sampling the ROM address on the valid K083
`LD` edge together with the local sprite counter and effective line-buffer
write enable. A free-running waveform window cannot define the origin.

Mega Zone does not use a K503. Time Pilot's K503 sequence is only a comparison;
Mega Zone generates its object addresses with discrete logic. The K083 does
not generate the group-address sequence. It captures ROM data on `LD`, emits
the first pixel immediately after that load edge, and shifts the remaining
three pixels over the next pixel clocks. Horizontal flip reverses the four
pixels within each loaded group. The live ROM address may already show the
next group while the K083 is shifting the previously latched group.

MAME's `spritelayout` describes final decoded source X using byte offsets:

```text
$00, $08, $10, $18  -> groups 00, 01, 10, 11
```

This is not an electrical model of Mega Zone's discrete address generator and
K083 load phase. Before changing the core, establish whether the current MRA
packing/download transpose has already converted the raw ROMs into MAME's
logical order. Do not apply both a packing conversion and a runtime physical
group permutation.

An incorrect four-pixel group order can move recognizable or nontransparent
features inside a 16-pixel sprite, but it does not move the allocated
line-buffer span `xpos..xpos+15` by itself.

### Object lookup PROM and transparency

The original `319b16.c6` object lookup PROM maps raw K083 pen zero to lookup
value zero for all 16 sprite palettes:

```text
{palette, raw_pen=0} -> 0
```

The final palette entry zero is black. More importantly, object lookup output
zero is transparent. Some nonzero raw K083 pens also map to lookup value zero
for particular palettes, so transparency must be checked after the object
lookup PROM:

```text
lookup output 0000       -> transparent
lookup output 0001..1111 -> opaque
```

The PCB/K502-style line-buffer merge preserves an existing nonzero pixel; a
later sprite only fills a zero location. Therefore any genuine nonzero writes
seen at positions 0..11 should remain visible later unless they are overwritten
before priority applies, written to the other bank, cleared before display, or
masked by FIX/HBLANK. Inspect the last effective stored value before the bank
handoff rather than only the first RAM data-input transition.

### Next focused check

At the PCB/model boundary case with raw OBJ X `$01`, capture the four K083 load
groups and line-buffer writes. For each pixel record:

```text
local sprite X count
OCHA/address group at K083 LD
K083 input and shifted output
object lookup PROM output
line-buffer bank/address/data/WE/CS
fix_en_pre and fix_en
```

This will distinguish three presently coupled questions: the physical ROM
group origin, whether positions 0..11 are genuine nonzero stored writes, and
whether the first eight valid object pixels are intentionally hidden by FIX
priority.

## Status 2026-08-10 08:16:45 CEST

### Current video timing experiment

The color mixer currently uses:

```verilog
localparam BLANK_DLY = 8;
```

FIX has a PCB-counter experiment only during the first part of horizontal
blanking:

```verilog
wire        blank_fetch = hdump >= 9'd288 && hdump <= 9'd375;
wire [ 8:0] heff = blank_fetch ? hdump - 9'd160 :
                    flip ? FIX_WIDTH - 9'd1 - hsum : hsum;
```

This produces:

```text
hdump 288..375 -> FIX heff 128..215
hdump 376      -> original FIX mapping resumes at heff 0
hdump 376..383 -> FIX heff 0..7
```

The restricted range is intentional. Applying `hdump-160` through 383 was
wrong because it removed the existing `heff=0` restart at hdump 376. SCROLL
was restored and has no equivalent override; its effective coordinate remains:

```verilog
wire [7:0] heff = h_eff + scrolly;
```

FIX and SCROLL fetch phases remain:

```text
heff[2:0] = 7 -> read_tile
heff[2:0] = 0 -> fetch_tile
heff[2:0] = 4 -> load_tile
```

Thus `load_tile` never coincides with `heff=0`; zero is the graphics-ROM
request phase and phase four loads the returned row. `FIX_EN_DLY` remains 6.

### Original-PCB solid character combinations

The following existing character-ROM and CRAM combinations were identified:

```text
solid blue:   character 0x31, palette/attribute 0x0D
solid yellow: character 0x34, palette/attribute 0x0E
```

They are also recorded in `ver/game/pcb_chars.txt`. These combinations can be
selected by main CPU ROM code on an original PCB without replacing the
character ROM or palette PROMs.

Attribute bits are:

```text
CRAM[3:0] palette
CRAM[4]   unused
CRAM[5]   vertical flip
CRAM[6]   horizontal flip
CRAM[7]   character code high bit/bank
```

FIX tile RAM `0x2400..0x27ff` corresponds to FIX color RAM
`0x2c00..0x2fff`; for example tile address `0x2440` uses attribute address
`0x2c40`. SCROLL tile `0x2042` uses attribute address `0x2842`.

### Current scroll-test ROM probes

`tools/make_scrolltest_rom.py` now writes the existing solid character
combinations into the default first-visible probes:

```text
SCROLL 0x2042 / CRAM 0x2842 -> character 0x31, attribute 0x0D (blue)
FIX    0x2440 / CRAM 0x2c40 -> character 0x34, attribute 0x0E (yellow)
```

The generated diagnostic characters `0x7f` and `0x7e` remain in the test-ROM
generator for other marker cells. Those generated markers are not suitable
for a main-ROM-only original-PCB test because the generator modifies graphics
and PROM data as well as the CPU program.

The standard non-flipped test ROM was regenerated with sprites and one-pixel
scroll steps, then simulated for 10 frames with sound and waveform output.
The latest run completed successfully on 2026-08-10 and produced:

```text
cores/mzone/ver/game/frames/frame_00010.png
cores/mzone/ver/game/test.fst (about 13 MiB)
```
