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
