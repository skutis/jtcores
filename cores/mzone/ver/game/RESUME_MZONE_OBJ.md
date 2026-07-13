# M-Zone OBJ Debug Resume

Date: 2026-07-01

## 2026-07-01 Non-Flipped `0xeb` Sprite Line Fix

- Symptom: the non-flipped test sprite at raw OBJ `xpos=0xeb` missed some horizontal rows.
- Cause found in `../../hdl/jtmzone_obj.v`:
  - OBJ scan only issued a draw on `inzone && !busy`;
  - adjacent active sprites can be scanned while `jtmzone_objdraw` is still busy;
  - the `0xeb` test sprite rows `ysub=3`, `ysub=8`, and `ysub=14` were skipped.
- Fix implemented:
  - added a one-entry pending draw latch in `jtmzone_obj.v`;
  - if an active sprite is scanned while the drawer is busy, it is queued and issued as soon as `busy` clears;
  - `MZONE_OBJ_WATCH` now reports `MZONE_OBJ_QUEUE` and `MZONE_OBJ_DROP` for this path.
- Verification:
  - ROM regenerated with `MZONE_SCROLLTEST_SPRITES=1 ../../tools/make_scrolltest_rom.py`;
  - non-flipped OBJ-only trace: `/tmp/mzone_eb_nonflip_queue.log`;
  - `base=088`, code `44`, raw `xpos=eb` now queues rows `ysub=3,8,14`;
  - no `MZONE_OBJ_DROP` entries for `base=088`;
  - linebuffer writes to addresses `0xeb..0xfa` are present on all sprite rows `119..134`;
  - visible OBJ pixels at the right edge are continuous on lines `120..134`.

## Current Symptom

- Flipped OBJ/sprite rendering may still need re-checking after the non-flipped queue fix.
- User-observed issue:
  - Around `hdump` line `225`, sprites are black.
  - In previous lines around `hdump 221:223`, pixels are shifted in `vpos +1` for two sprites.
  - The fixed test sprite is one of the affected sprites.
- The test sprite currently used in the scroll test ROM is intended to be:
  - OBJ bytes: `00 78 44 10`
  - Meaning used in our current test context: attr `00`, ypos `78`, code `44`, xpos `10`.

## Important Context

- Non-flip sprite x placement had looked correct before this latest flipped-y investigation.
- The issue appears in forced flipped simulations.
- Use `-d MZONE_FORCE_FLIP` for reliable flipped testing. The ROM flip register write alone was not reliable early enough in short sims.
- PNG coordinates are easy to confuse:
  - The generated PNG is rotated relative to core naming.
  - The final RGB debug position is delayed: `rgb_hdump_debug` was observed as `hdump - 9` in colmix point traces.
  - Therefore an apparent visible/raw point may need a +9 hdump input watch when tracing through colmix.

## OBJ X Counter Timing Note

- During normal rendering, the OBJ `xpos` counter reaches 0 four pixel clocks before `fix_n` goes inactive.
- That point is the visible area outside the FIX layer, where SCROLL or OBJ can be visible.
- The four-pixel lead accounts for the OBJ pipeline delay into the color mixer.
- The last rendered `xpos` is 239, which fits the visible window after pipeline delays.
- In flipped rendering, OBJ rendering starts 12 pixels before `hblk_n` goes inactive, accounting for the four-pixel OBJ pipeline delay.
- While flip is active, the counter wraps while `fix_n` is active; those OBJ pixels are not visible.
- Core implementation in `../../hdl/jtmzone_objdraw.v` uses the HDL render-to-colmix delay, not the PCB four-pixel delay:
  - `OBJ_CORE_DLY=1` because the linebuffer read reaches colmix one pixel later;
  - normal: `hread=0` is at `hdump=40`;
  - flipped: first visible after hblank has sprite counter `8`;
  - flipped: with current core timing, `hread=8` is read at `hdump=31` and reaches colmix at `hdump=32`;
  - flipped: the OBJ read counter counts down, so raw `xpos=0xeb` appears near the same screen position as non-flipped raw `xpos=0x10`;
  - the read counter rolls over; FIX priority, OBJ pixel enable, and blanking mask hidden pixels in colmix/output.
- MAME-observed flipped X equivalence: raw `xpos=0xeb` in flipped mode matches raw `xpos=0x10` in non-flipped mode.
  - These are OBJ RAM values; do not rewrite the scanned OBJ RAM X byte in HDL.
  - Use this as a MAME/PCB reference, not as a direct HDL X transform.
- Scrolltest sprite references in `../../tools/make_scrolltest_rom.py`:
  - bytes from OBJ RAM `0x3085`: `78 44 eb c0` for flipped reference boundary;
  - object index `0x21` uses attr `0f` so the boundary-reference sprite is visible while preserving bytes at `0x3085`;
  - complete flipped reference entry at object index `0x22`: `c0 78 44 eb`;
  - non-flip reference entry kept at object index `0x23`: `00 78 44 10`.

## Latest Attempt That Did Not Fix It

In `../../hdl/jtmzone_obj.v`, the latest attempted change was:

```verilog
wire [7:0] draw_vdump = vdump[7:0] + (flip ? 8'd2 : 8'd1);
```

This was based on a comparison:

- `flip ? +0 : +1` moved flipped OBJ components one raw line later, the wrong direction.
- `flip ? +2 : +1` moved flipped OBJ components one raw line earlier.
- User then reported the same problem still exists, so this change is not proven and should be treated as suspect.

If restarting, first decide whether to keep this for comparison or revert to the previous:

```verilog
wire [7:0] draw_vdump = vdump[7:0] + 8'd1;
```

## Useful Logs From This Machine

These may not exist on another computer, but show the exact commands/results used:

- Failed-direction test:
  - `/tmp/mzone_flip_obj_ycomp_4.log`
- Latest failed attempt:
  - `/tmp/mzone_flip_obj_ycomp2_4.log`
  - `/tmp/mzone_nonflip_obj_ycomp2_4.log`
- Earlier broad forced-flip OBJ trace:
  - `/tmp/mzone_flip_obj_all_code44_4.log`

Broad OBJ pixel component comparison from logs:

```text
before ycomp2:
  test-like flipped components included x=234..247 y=119..134

with ycomp2:
  same component moved to x=234..247 y=118..133
```

That proves the y compensation moves the raw OBJ output, but it did not solve the visible issue.

## Commands To Reproduce

Generate the sprite test ROM:

```sh
MZONE_SCROLLTEST_SPRITES=1 ../../tools/make_scrolltest_rom.py
```

Run forced-flip short sim with broad OBJ pixel trace:

```sh
source ../../env.sh && \
MZONE_ROM=../../../../rom/megazone_scrolltest.rom \
./sim.sh -video 4 \
  -d MZONE_FORCE_FLIP \
  -d MZONE_OBJ_PXL_WATCH \
  -d MZONE_OBJ_PXL_WATCH_FROM=3 \
  -d MZONE_OBJ_PXL_WATCH_TO=3 \
  -d MZONE_OBJ_PXL_X0=0 \
  -d MZONE_OBJ_PXL_X1=287 \
  -d MZONE_OBJ_PXL_Y0=0 \
  -d MZONE_OBJ_PXL_Y1=239
```

Run focused point/colmix trace around a visible point, remembering RGB delay:

```sh
source ../../env.sh && \
MZONE_ROM=../../../../rom/megazone_scrolltest.rom \
./sim.sh -video 4 \
  -d MZONE_FORCE_FLIP \
  -d MZONE_POINT_WATCH \
  -d MZONE_POINT_FRAME0=3 \
  -d MZONE_POINT_FRAME1=3 \
  -d MZONE_POINT_X0=230 \
  -d MZONE_POINT_X1=238 \
  -d MZONE_POINT_Y0=184 \
  -d MZONE_POINT_Y1=194 \
  -d MZONE_OBJ_PXL_WATCH \
  -d MZONE_OBJ_PXL_WATCH_FROM=3 \
  -d MZONE_OBJ_PXL_WATCH_TO=3 \
  -d MZONE_OBJ_PXL_X0=230 \
  -d MZONE_OBJ_PXL_X1=238 \
  -d MZONE_OBJ_PXL_Y0=184 \
  -d MZONE_OBJ_PXL_Y1=194 \
  -d MZONE_OBJ_LINEBUF_WATCH \
  -d MZONE_OBJ_LINEBUF_X0=230 \
  -d MZONE_OBJ_LINEBUF_X1=238 \
  -d MZONE_OBJ_LINEBUF_Y0=184 \
  -d MZONE_OBJ_LINEBUF_Y1=194 \
  -d MZONE_OBJ_LINEBUF_WA0=20 \
  -d MZONE_OBJ_LINEBUF_WA1=55
```

## Where To Look Next

- Do not assume the issue is solved by a simple `draw_vdump` offset.
- Re-check whether the black/shifted pixels are from:
  - linebuffer read address phase,
  - linebuffer bank switch phase tied to `fix_src`,
  - `obj_visible` / fix priority gating,
  - or final colmix/RGB delayed position mapping.
- In the last aligned traces, several linebuffer reads had `line_has=1` but `pal_pxl=0`, meaning the read address was not hitting sprite data for that coordinate.
- Also remember `jtframe_obj_buffer` clears after reads. Its `rd` timing matters; M-Zone currently drives `rd` across the whole active object span, unlike Kicker/Road Fighter style `buf_clr = pxl_cen && hread < {1'b1, HOFFSET}`.

## 2026-06-30 Counter Direction Update

- User observed that raw `xpos=0xeb` in flipped mode should match raw `xpos=0x10` in non-flipped mode.
- The previous core change made flipped `hread` count upward from the first visible value, which put `0xeb` near the far/right end.
- `../../hdl/jtmzone_objdraw.v` now makes flipped `hread` count down:
  - `OBJ_FLIP_RD_BASE = OBJ_FLIP_VIS_START - OBJ_CORE_DLY + OBJ_FLIP_FIRST_X`;
  - `hread = OBJ_FLIP_RD_BASE - hdump`.
- Focused forced-flip trace: `/tmp/mzone_flip_downcounter_xref.log`.
  - Shows `hread=0xeb` at raw trace x around 60.
  - Shows the raw `0x10` reference around the same visible neighborhood instead of the opposite end.
- Non-flipped smoke sim after this change: `/tmp/mzone_nonflip_after_downcounter.log`.

## 2026-06-30 PCB Linebuffer Update

- User clarified the PCB OBJ linebuffer is 256 x 4 bits, doubled for the two line buffers.
- `../../hdl/jtmzone_objdraw.v` now instantiates `jtframe_obj_buffer` with `AW=8`, so each jtframe line is 256 x 4.
- OBJ linebuffer writes use `draw_x[7:0]`; wrapping is intentional.
- OBJ linebuffer reads run for one 256-clock pass:
  - normal pass starts at `OBJ_NORM_RD_START`;
  - flipped pass starts at `OBJ_FLIP_VIS_START - OBJ_CORE_DLY`.
- Focused forced-flip trace after this change: `/tmp/mzone_flip_256buf.log`.
- Non-flipped smoke sim after this change: `/tmp/mzone_nonflip_256buf.log`.

## 2026-07-01 Non-Flipped OBJ Read Boundary

- User clarified that for OBJ, CPU/write X=0 should appear immediately after `fix_n` goes high, i.e. when core `fix_src` goes low.
- Current non-flipped test state in `../../hdl/jtmzone_objdraw.v`:
  - `hread` resets to 0 at `hdump == 46`, two pixels before the non-flipped `fix_src` falling boundary at `hdump == 48`.
  - Line state still latches at `hdump == 48`, so the counter lead does not move the linebuffer line boundary.
  - OBJ output is visible only while `hread < 240`, matching the expected last visible OBJ X of 239.
  - The logical `hread` counter remains the PCB/reference counter; physical linebuffer `read_addr` is `hread+7` to compensate core output placement.
  - OBJ visibility still uses `hread < 240`, not the compensated `read_addr`, so the right edge is not cut at raw `x=279`.
  - OBJ linebuffer writes are clipped to `draw_x < 256` so the 8-bit linebuffer address cannot wrap right-side writes into low addresses.
  - Linebuffer bank switch is still driven by `fix_src`.
- Latest focused non-flipped object-only sim:
  - log: `/tmp/mzone_nonflip_readaddr_plus7_vis_hread.log`
  - waveform: `/tmp/mzone_nonflip_readaddr_plus7_vis_hread.fst`
  - PNG: `frames/frame_00008.png`
- Trace summary: writes and visible OBJ pixels are present on consecutive sprite rows; after the physical read-address shift, OBJ output still reaches `x=286`, so the read-visible window is not cut at raw `x=279`.

## 2026-07-02 SCROLL/FIX Colmix Timing

- Current colmix state in `../../hdl/jtmzone_colmix.v`:
  - removed the old `CHAR_DLY=3` path;
  - `BLANK_DLY=1`;
  - the mixer uses incoming `scr_pxl` and `fix_en` directly;
  - OBJ debug marker `MZONE_OBJ_X0_MARKER` still bypasses raw RGB to white when enabled.
- Current FIX state in `../../hdl/jtmzone_fix.v`:
  - `fix_src` remains the source/address reference;
  - `fix_sel`/`fix_en` are delayed by 5 clocks in non-flipped mode;
  - non-flipped `pcb_hcnt` currently advances the renderer by 5 clocks: `h < FIX_WIDTH ? h + 9'd5 : h - 9'd123`;
  - non-flipped `fix_vis_at` is currently shortened to `FIX_WIDTH-5` so delayed FIX priority drops at the scroll boundary in the watched trace.
- Current SCROLL state in `../../hdl/jtmzone_scroll.v`:
  - non-flipped `pcb_hcnt` uses `hn = h - 9'd020`;
  - this advances scroll fetch/address phase so rendered scroll pixels, not just source address, start at the boundary.
- Latest non-flipped full scroll/FIX sim:
  - log: `/tmp/mzone_full_scroll_hlead13.log`
  - waveform: `/tmp/mzone_full_scroll_hlead13.fst`
  - PNG: `/tmp/mzone_full_scroll_hlead13_frame_00008.png`
- Trace result from that sim:
  - scroll nonzero pixels now start at `hdump=48`;
  - previous `h - 9'd028` experiment had first nonzero scroll pixels at `hdump=56`;
  - FIX pixels are visible in the left strip on rows with nonblank glyph data;
  - the watched `y=16` row is blank for the FIX glyph, so use rows `17..22` when verifying FIX visibility.
- Follow-up after user reported FIX shifted `+5 hpos`:
  - log before change: `/tmp/mzone_fix_shift_before.log`
  - current log: `/tmp/mzone_fix_shift_hlead5.log`
  - current waveform: `/tmp/mzone_fix_shift_hlead5.fst`
  - current PNG: `/tmp/mzone_fix_shift_hlead5_frame_00008.png`
  - only the non-flipped FIX `pcb_hcnt` phase was changed; scroll and colmix were not touched.

## 2026-07-03 PCB OBJ X Write Rule

- Schematic/PCB observation supersedes the earlier speculative OBJ X compensation notes:
  - OBJ RAM byte 3 is the raw `xpos`.
  - When byte 3 is read, the PCB resets the local OBJ pixel counter to 0.
  - During sprite write, the counter runs 0..15.
  - The effective write coordinate is `xpos + counter`.
  - There is no PCB `+16` or `-16` compensation on OBJ RAM X.
- Current HDL state matches this on the non-flipped write side:
  - `../../hdl/jtmzone_obj.v` passes `xpos_raw_eff` directly into `dr_xpos`.
  - `../../hdl/jtmzone_obj.v` uses `attr[6]` directly for OBJ horizontal flip.
  - `../../hdl/jtmzone_objdraw.v` non-flipped write address is `cur_xpos + group*4 + pix_cnt[1:0]`.
- Therefore, do not add or subtract 16 from OBJ RAM byte 3 in the scan path.
- Non-flipped OBJ read phase was adjusted in `../../hdl/jtmzone_objdraw.v` so the visible boundary reads linebuffer address `0x10`:
  - at `hdump == 47`, `hread <= 8'h10`;
  - this moves the raw `xpos=0x10` reference sprite from `x=64` to `x=49` in the OBJ-only trace;
  - the remaining one-pixel difference is the linebuffer/output latency to be checked against the full mixer path.
- Latest non-flipped OBJ-only sim after this read-phase change:
  - log: `/tmp/mzone_obj_readphase10_nonflip.log`
  - waveform: `/tmp/mzone_obj_readphase10_nonflip.fst`
  - PNG: `/tmp/mzone_obj_readphase10_nonflip_frame_00008.png`

## 2026-07-12 Stale Assembled ROM Diagnosis

- Fragmented sprites initially appeared identical under Verilator 5.024 and
  5.046, so the simulator version was not the cause.
- Both development computers had the same Git commit, OBJ HDL, ROM generator,
  and source `megazone.zip`, but different ignored `rom/megazone.rom` files.
- Cause: the bad local MRA/ROM had been generated on 2026-05-15, before commit
  `990f0eb36` added the required OBJ `gfx1` packing rule
  `width=16, sequence=[0,2,1,3]`. The OBJ reader expects this interleaved
  16-bit layout; the stale concatenated layout renders fragmented sprites.
- Rebuild ignored ROM artifacts after ROM packing changes or branch updates:

  ```sh
  jtframe mra mzone --path ~/.mame/roms -v
  ```

- Known-good development hashes:
  - source `megazone.zip` SHA-256: `3714f20cb504e7731135b37208a2181faee1291c99fa4a59c236ee616130e4f6`
  - assembled `rom/megazone.rom` SHA-256: `8d5b0340c55a5710aa5877246b09acaba0a1cde08637c82feded22898ba1905f`
  - assembled ROM MD5 / MRA `asm_md5`: `5fdca75da5459ff95354f028efc103ae`
- Standard non-flipped OBJ test-ROM generation:

  ```sh
  unset MZONE_SCROLLTEST_FLIP MZONE_FORCE_FLIP
  MZONE_SCROLLTEST_SPRITES=1 MZONE_SCROLLTEST_SCROLL_STEP=1 \
    ../../tools/make_scrolltest_rom.py
  ```

- Expected generated scroll-test ROM SHA-256 with that base and configuration:
  `1ae75cd091ee43a9ace80abc41cb30d5ef8df9bcc5904d1ff758af754237fdfd`.

## 2026-07-12 OBJ Line-Buffer Read Latency

- PCB timing shows that the OBJ counter reaches X=0 four pixel clocks before
  the SCROLL/OBJ visible boundary; those four clocks are the PCB render lead.
- The HDL `jtframe_obj_buffer` read path has two OBJ-specific registered stages:
  1. the internal synchronous dual-port RAM updates `dump_data`;
  2. the wrapper registers `dump_data` into `rd_data`/`pal_pxl`.
- Applying the full PCB lead as `read_addr = hread - 4` left fully opaque test
  sprites two pixels late in final output.
- The physical HDL line-buffer address now uses `read_addr = hread - 2`: the
  buffer's two registered clocks consume two clocks of the PCB four-clock lead,
  and the address phase supplies the remaining two.
- Reference test: fully opaque sprite code `0xd0`, raw `xpos=0x08`, should begin
  at raw X=56 when raw OBJ X=0 aligns with the boundary at raw X=48.
- A second fully opaque reference at raw `xpos=0xef` exposed a separate counter
  origin error: it appeared at raw X=279 instead of X=287. The raw `xpos=0`
  reference had only looked correct because FIX priority masked its early pixels
  at X=40..47.
- Keep the two-clock physical buffer compensation (`read_addr = hread - 2`)
  separate from the logical read-counter origin. The non-flipped `hread` reset
  origin moved from `hdump=43` to `hdump=51`, while the line-buffer bank handoff
  remains at `hdump=44`. This shifts the natural mapping from `OBJ X + 40` to
  the required `OBJ X + 48` without changing buffer latency.
- A focused adjacent-sprite trace then showed addresses `0x76..0x7d` were
  written (`linebuf_we=1` and internal `new_we=1`) but cleared before their
  visible read. Cause: the old 8-bit `hread` wrapped during the 384-pixel line
  while `buf_rd` remained asserted continuously.
- The read/clear path now follows Road Fighter: `hread` is the 9-bit coordinate
  `hdump-OBJ_RD_START`, and `buf_rd` is asserted only while
  `hread < {1'b1,OBJ_RD_START[7:0]}`. The ninth bit suppresses the unwanted
  pre-window clear pass; `read_addr` uses `hread[7:0]-2`.
- Flipped OBJ reads use the mirrored 9-bit coordinate `306-hdump` under the
  same bounded clear window and physical `-2` buffer compensation. The base is
  derived from the established equivalence: flipped raw OBJ X=`0xeb` must land
  at the same final X as non-flipped raw OBJ X=`0x10`.
- The first flipped test exposed a separate bank-handoff issue: OBJ output was
  absent at final raw X=0..38 even though the mirrored read window was active.
  The FST showed both `jtframe_obj_buffer.line` and `read_line_has_obj` still
  changed at the non-flipped `hdump=44`; after the shared pipeline/blank phase,
  OBJ enable therefore began around raw X=39.
- The bank and line-state handoff remains `hdump=44` normally and uses
  `hdump=5` when flipped. The flipped phase maps the handoff to final raw X=0;
  it does not change the read-address coordinate or add a layer-wide X offset.
