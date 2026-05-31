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
