# JTMZONE FPGA core compatible with Mega Zone hardware

This core is being organized as a JTFRAME core. The current source of truth for
the board-level implementation is the KiCad schematic set in `sch/`.

## Structure

- `cfg/`: JTFRAME metadata, ROM conversion, SDRAM bus, and macro definitions.
- `hdl/`: local Mega Zone modules. Shared Konami 082/083-style blocks should be
  reused from `kicker`, `yiear`, and `roc` when the interfaces match.
- `sch/`: extracted KiCad schematics for the Mega Zone PCB.
- `ver/`: simulation and regression entry points.
- `doc/`: implementation notes derived from schematics and measurements.

## Hardware Notes

Mega Zone uses a Konami-1/6809-compatible main CPU, a Z80 sound CPU, an 8039 DAC
CPU, one AY-3-8910 PSG, and Konami 083 video logic. The MAME driver lists a
18.432 MHz video/main clock and a 14.31818 MHz sound/DAC clock.

The first HDL split should follow the small Konami cores:

- `jtmzone_game.v`: JTFRAME game wrapper and SDRAM address swizzle.
- `jtmzone_main.v`: main CPU, shared RAM, scroll, video RAM, object RAM, I/O.
- `jtmzone_snd.v`: Z80, AY-3-8910, 8039/DAC command path.
- `jtmzone_video.v`: tile, object, timing, and mixer integration.

