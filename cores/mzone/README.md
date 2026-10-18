# JTMZONE — Mega Zone FPGA core

FPGA implementation of Konami's Mega Zone (1983, GX319), developed by
Ulf Skutnabba using the JTFRAME framework.

The implementation is based on the Mega Zone PCB schematics and hardware
investigation, with MAME used as an additional reference. The KiCad schematics
are in [sch/](sch/).

## Status

The core is under development. The intended targets are SiDi128, MiSTer, and
Analogue Pocket.

| Platform | Hardware testing |
| --- | --- |
| SiDi128 | Used during development; release validation remains to be completed |
| MiSTer | Testing status to be confirmed |
| Analogue Pocket | Not tested on hardware; a tester is needed |

Platform build and timing results should be recorded before release. Inclusion
of a ROM set in the configuration does not mean that every revision has been
tested on hardware.

Remaining validation includes video alignment on SiDi128 HDMI output and
comparison of the PSG/DAC audio balance with the original PCB.

## Video options

Mega Zone uses a vertically oriented display. The **Video width** option selects
between the default 288-pixel width and the original 287-pixel non-flipped
visible width. In flipped mode, the original-width setting retains 288 pixels.

## Hardware

- Konami-1/6809-compatible main CPU.
- Z80 sound and input CPU, with shared RAM.
- 8039 CPU for DAC audio.
- AY-3-8910 programmable sound generator.
- Scrolling character layer, fixed character layer, sprites, and PROM palettes.

## Credits

- **Ulf Skutnabba** — Mega Zone core development and schematic work.
- **Ace9921** — Author of the `k501.v` Verilog module reused in this core.
- **JOTEGO and jtcores contributors** — JTFRAME and shared FPGA components.
- **MAME contributors** — Mega Zone emulation and hardware documentation used
  as reference material.
