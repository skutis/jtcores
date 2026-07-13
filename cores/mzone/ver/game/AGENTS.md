# M-Zone Core Instructions

These rules apply when working from `cores/mzone/ver/game`.

## Video Rendering

- FIX and SCROLL must use the same character rendering pipeline.
- FIX differs from SCROLL only by selecting the FIX VRAM/CRAM bank, forcing the scroll values used by the renderer to zero, and taking priority over object pixels.
- Do not add FIX-only or SCROLL-only timing, address, or phase offsets unless they are explicitly proven from PCB or MAME traces.
- Keep VRAM/CRAM tile-map addressing separate from pixel/fetch pipeline phase when debugging timing.
- Treat `fix_src` as the source/address reference and `fix_en` as the delayed priority/output reference.
- Expected first visible tile-map cells:
  - `SCROLL`: first visible character is at CPU address `0x2042`.
  - `FIX`: first visible character is at CPU address `0x2440`.

## Simulation

- Short simulations should use sound enabled and waveform output (`-w`) unless explicitly requested otherwise.
- Do not use `NOSOUND` unless explicitly requested.
- When testing visual timing, prefer focused traces around the exact `hdump`/`vdump` range being discussed.
- `rom/megazone.rom` and generated MRAs are ignored build artifacts; a clean Git status does not prove that their layout matches the current core configuration.
- After changing or checking out ROM packing rules in `cores/mzone/cfg/mame2mra.toml`, rebuild before generating a scroll-test ROM:
  `jtframe mra mzone --path ~/.mame/roms -v`.
- The OBJ reader requires the `gfx1` rule `width=16, sequence=[0,2,1,3]`. A stale ROM assembled before this rule produces fragmented sprites.
- Known-good `megazone` artifacts for the MAME 0.251 ZIP used during development:
  - source ZIP SHA-256: `3714f20cb504e7731135b37208a2181faee1291c99fa4a59c236ee616130e4f6`
  - assembled `rom/megazone.rom` SHA-256: `8d5b0340c55a5710aa5877246b09acaba0a1cde08637c82feded22898ba1905f`
  - assembled ROM MD5 / MRA `asm_md5`: `5fdca75da5459ff95354f028efc103ae`
- For the standard non-flipped OBJ scroll test, generate with
  `MZONE_SCROLLTEST_SPRITES=1 MZONE_SCROLLTEST_SCROLL_STEP=1 ../../tools/make_scrolltest_rom.py`.
