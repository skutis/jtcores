# M-Zone OBJ Debug Resume

Date: 2026-06-25

## Current Symptom

- Flipped OBJ/sprite rendering still has the same problem after the latest test.
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

