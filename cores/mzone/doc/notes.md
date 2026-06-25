# Mega Zone Implementation Notes

Reference points from `../../../mame/src/mame/konami/megazone.cpp`:

- Main CPU: Konami-1, 18.432 MHz / 12.
- Sound CPU: Z80, 18.432 MHz / 6.
- DAC CPU: 8039, 14.318181 MHz / 2.
- PSG: AY-3-8910, 14.318181 MHz / 8.
- Screen: 36 x 32 tiles, visible area 288 x 224, vertical orientation.
- ROM regions: `maincpu`, `audiocpu`, `daccpu`, `gfx1`, `gfx2`, `proms`.

Main CPU address map from MAME:

- `0000-0007`: main latch.
- `0800`: watchdog.
- `1000`: vertical scroll.
- `1800`: horizontal scroll.
- `2000-23ff`: playfield video RAM.
- `2400-27ff`: overlay video RAM.
- `2800-2bff`: playfield color RAM.
- `2c00-2fff`: overlay color RAM.
- `3000-33ff`: sprite RAM.
- `3800-3fff`: shared RAM with sound CPU.
- `4000-ffff`: program ROM.

MAME `screen_update()` video RAM use:

- Reference source: `/home/skutis77/github/mame/src/mame/konami/megazone.cpp`.
- `m_videoram[0]` is the scrolling 32x32 playfield. MAME draws all 1024 entries to a temporary bitmap, then applies scroll:
  - tile index: `m_videoram[0][offs]`
  - tile bank bit: `m_colorram[0][offs][7]`, adding 256 to the tile index
  - flip X/Y: `m_colorram[0][offs][6:5]`
  - palette/color: low nibble of `m_colorram[0][offs]`, plus `0x10`
  - scroll uses `scrolly` as screen X scroll and `scrollx` as screen Y scroll in non-flip mode
- `m_videoram[1]` is not a full second scrolling layer in MAME. It is a fixed overlay/status area: only 6 columns per row are drawn, for all 32 rows.
  - MAME uses `offs = y * 32 + x`, `x = 0..5`
  - same tile, bank, flip, and color rules as `m_videoram[0]`, but using `m_colorram[1]`
  - in non-flip mode it draws at screen columns `0..5`; in flip mode it maps to `35..30`

Timing notes and schematic-derived signal mapping live in [timing.md](timing.md).

## Simulation Debugging Notes

Keep trace/watch windows narrow. Redirect large simulation logs to `/tmp/*.log`,
then inspect them with `rg`/`tail` and copy only the relevant lines into notes or
discussion. Avoid dumping broad multi-frame traces into chat or review context.

Follow the Kicker core naming style for video signals. Keep mzone HDL compact:
avoid verbose helper names and avoid carrying several names for the same signal.

## Verilator Compatibility Notes

The Mega Zone simulation has been checked on these Verilator versions:

- Verilator 5.024, 2024-04-05, `v5.024-42-gc561fe8ba`: known-good reference
  during initial bring-up. `./sim.sh -video 5` transferred the ROM by frame 3,
  the main CPU reached the expected boot code area, and video frames were not
  black.
- Verilator 5.044: treated upstream as the last safe Verilator release for
  JTCORES image-producing simulations after 5.046 regressed them. Commit
  `2dc101217` (`verilator v5.046 does not produce images in simulation`,
  2026-03-21) changed `modules/jtframe/bin/install/jotego_20.04.sh` to check
  out `v5.044` and records the reason in a comment.
- Verilator 5.046, 2026-02-28, `v5.046-55-g1264184fb`: exposed a simulation
  issue when the external SDRAM data bus was left as a Verilog `inout` in the
  Verilator build. The C++ SDRAM model read the ROM data correctly, but the HDL
  side saw zeroed data at the top-level bus. The result was black video except
  for local debug markers, no useful VRAM/CRAM writes, and the main CPU running
  from a bad reset/vector path instead of the expected ROM code.

Verilator's 5.046 changelog does not call out this exact SDRAM `inout` symptom.
The local evidence narrows the JTCORES regression window to `v5.044` good /
`v5.046` bad; finding the exact Verilator commit still requires a Verilator
git bisect between those tags using the unfixed JTFRAME SDRAM `inout` code.

The framework-side fix is to make the SDRAM data bus input-only in Verilator
builds and keep it bidirectional for synthesis:

- `modules/jtframe/hdl/ver/game_test.v`: `SDRAM_DQ` is `input [15:0]` under
  `ifdef VERILATOR`, otherwise `inout [15:0]`.
- `modules/jtframe/hdl/sdram/jtframe_sdram64.v`: `sdram_dq` is `input [15:0]`
  under `ifdef VERILATOR`, otherwise `inout [15:0]`.

After that change, Verilator 5.046 produced the same useful behavior as 5.024:
the CPU reached the boot ROM area and `./sim.sh -video 5` generated non-black
frames. The same `inout` symptom was also observed with `kicker` on 5.046, so
this should be treated as a JTFRAME simulation-port issue rather than a
Mega Zone reset or ROM packing bug.
