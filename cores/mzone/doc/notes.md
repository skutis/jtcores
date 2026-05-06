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
