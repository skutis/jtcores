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

## Sound ROM reads and boot RAM test

The Z80 input mux in `jtmzone_snd.v` registers `rom_data` on `clk24`, while
the SDRAM interface returns data and `rom_ok` on the faster clock. Using raw
`rom_ok` to release a bare Z80 can let it sample the previous byte before the
input register catches up. The sound CPU now uses `jtframe_z80_devwait`,
whose ROM wait controller holds CPU enable until the registered data can
be used. Pass `rom_cs` and `rom_ok` directly to that wrapper; no separate
`rom_ready` register is needed.

The external shared RAM remains in place. Its existing arbitration condition,
`shared_cs && h2`, drives `dev_busy`. `RECOVERY(0)` disables catch-up enable
pulses after ROM stalls. This changes shared-RAM stalling from the Z80's
`WAIT` input to CPU-enable gating; exact PCB bus-cycle timing still needs
hardware comparison. `MZONE_Z80_NO_WAIT` bypasses both wait sources for debug.

The original stale-data reads caused a reproducible `RAM BAD` at main-CPU
address `$3B20`: the main
CPU wrote `$55`, but a prematurely running sound CPU overwrote it with `$00`
before the comparison at `$B160`. The RAM itself was retaining writes. A
short CPU trace also showed a Z80 opcode fetch at `$01E0` consuming stale
`$02` instead of ROM byte `$3A`, corrupting the startup handshake.

For a cold-boot check, source `env.sh` and run
`ver/game/sim.sh -video 260 -w`. For detailed Z80 fetch timing, use a short
run with `-video 7 -w -d VERILATOR_KEEP_CPU`. Use the normal `megazone.rom`,
with sound enabled and without a scene snapshot.

Before the wrapper conversion, the separate ready-register fix was checked
with a 260-frame cold-boot simulation, which displayed
`RAM OK` and `ROM OK`. The sound CPU returned `$0606` for both boot handshakes
(about 1.355 s and 2.122 s); the capture ends during the main CPU's boot
delay, before attract mode.

With `jtframe_z80_devwait`, the seven-frame waveform check verified 86,164
post-reset ROM reads with no mismatches. The longer cold-boot run displayed
`RAM OK` (frame 86), `ROM OK` (frame 130), and advanced to the startup grid
(frame 265). The SiDi128 build passed compilation and timing checks.

## Video width option

The original-width option must mask `hdump == HB_START`, the last pixel for
which the registered timer `pre_lhbl` is high. Masking `HB_START-1` instead
created a 286-pixel active span, a one-pixel blank gap, and another one-pixel
active span. That extra blanking edge can disturb downstream video processing
even though HSYNC and VSYNC do not change.

Run `python3 ver/video_width/check.py` to check the actual timer and mixer
blanking with pixel fetchers stubbed out. It tests 600 lines per width/flip
combination, including option changes, and compares sync with a fixed-288
reference. Default mode is 288 active pixels; original mode is 287 unflipped
and 288 flipped. The full game simulation currently forces the default width,
so it does not replace this option test.

## Scrolling diagnostic ROM IRQ acknowledgement

Old `tscr4`, `tscr4f`, and `tsmooth_scroll8` ROM artifacts returned from the
vertical IRQ without clearing INTST at `$0007`. The latched IRQ remained
asserted, so the CPU repeatedly entered the handler and advanced scrolling
during visible drawing. A seven-frame trace of the old `tscr4` image counted
3,374 scroll-register changes, including 2,820 while LVBL was high.

The current generator writes zero then one to `$0007` before returning.
Rebuild these ignored ROM artifacts with `ver/pcb_test/build_scroll_tests.sh`;
it now includes both sprite-free, horizontal 0..7 fine-scroll variants as well
as `tscr4`, `tscr4f`, and `tscr4fs`. Refresh any copied SD-card ROMs afterward.
The diagnostic tile/sprite data does not need changing for this IRQ fix.

The `tsmooth_scroll8` pair holds each offset for 16 vertical IRQs (about
264 ms), making its eight-position cycle about 2.1 seconds long. The previous
one-step-per-frame preset wrapped 7 back to 0 about 7.6 times per second,
which made this fine-scroll inspection pattern look like rapid rolling.
