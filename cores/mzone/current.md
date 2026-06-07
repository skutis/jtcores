# Mega Zone Current Work

This is a handoff note for continuing the MZONE work.

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
