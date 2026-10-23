Items to document in the main M-Zone README.md

- Development and verification methods:
  - Development using an original Mega Zone PCB.
  - Existing PCB schematics used as hardware references.
  - Custom ROM code run on the original hardware using PicoROM to test
    and investigate hardware behaviour.
  - New schematics produced during the hardware investigation.
  - MAME used for quick code verification and cross-checks. Final verification
    is against the original PCB.

- Findings compared with MAME:
  - The core provides a DIP-switch option for 287 visible pixels per line
    in non-flipped mode. This is the PCB behaviour. Default is 288 visible pixels.
  - MAME sprite positions are incorrect.
  - MAME tile-layer offsets are incorrect.
  - At horizontal position 47, sprites take priority over tiles when placed there.

- Remaining hardware validation:
  - Verify core operation and video output on SiDi128.
  - Verify video timing and image alignment through MiSTer FPGA's analogue output.
  - Hardware validation on Analogue Pocket is pending until a device is available for testing.

- Build and timing validation summary:
  SiDi128, MiSTer FPGA, and Analogue Pocket builds compile successfully and
  pass JTCORE's timing checks with Quartus Prime Lite 20.1 and fitter seed 1.
  MiSTer and Pocket reports include unconstrained paths, and shared platform
  clock warnings remain under review; these results do not establish complete
  timing closure or hardware validation.
