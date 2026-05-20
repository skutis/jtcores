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

