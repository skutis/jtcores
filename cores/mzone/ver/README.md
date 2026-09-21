# M-Zone simulations and PCB tests

- `game/`: FPGA simulation launcher, traces, frames, and temporary RAM files.
- `game/scenes/`: captured scenes and MAME capture scripts. `989` supports automatic capture.
- `pcb_test/`: physical-PCB ROM generators and fixed test presets; generated ROMs stay here.
- `regrun/`: regression reference hashes.

Source `cores/mzone/env.sh` first. The following commands are from the repository
root, but the scripts work from any directory using their full path.

## Simulate

```bash
cores/mzone/ver/game/sim.sh -video 2 -w
cores/mzone/ver/game/sim.sh -scene 989 -video 3 -w
MZONE_ROM=cores/mzone/ver/pcb_test/tfix_boundary_6h_sim.rom \
    cores/mzone/ver/game/sim.sh -video 5 -w
```

Sound is enabled by default; explicitly pass `-d NOSOUND` to bypass audio.
The launcher supplies the ROM set required by current JTFRAME and stages custom
`MZONE_ROM` files under that set name without rebuilding or replacing them.
`MZONE_SOUND` is no longer needed. Output always goes into `ver/game`.
Explicit relative ROM, scene-directory and `MZONE_SAVE_FILE`/`MZONE_LOAD_FILE`
paths are resolved relative to the caller. Scene names resolve under `game/scenes`.
Scene RAM files may remain in `game`, but shared RAM loads them only with `SIMSCENE`.

## Build PCB tests

```bash
jtframe mra mzone --path "$HOME/.mame/roms" -v
bash cores/mzone/ver/pcb_test/build_all_tests.sh
```

The build verifies the base `rom/megazone.rom` hash and OBJ packing, then builds
static, scrolling, and grid → boundary → FIX-boundary tests in dependency order.
Use `build_static_tests.sh`, `build_scroll_tests.sh`, or `build_boundary_tests.sh`
for just one group. Fixed presets clear inherited `MZONE_*` settings. Invoke the
Python generators directly only for custom experiments; they do not perform the
preset preflight or rebuild dependencies.

The verified base uses the development MAME 0.251 ZIP:

- ZIP SHA-256: `3714f20cb504e7731135b37208a2181faee1291c99fa4a59c236ee616130e4f6`
- Assembled SHA-256: `8d5b0340c55a5710aa5877246b09acaba0a1cde08637c82feded22898ba1905f`
- OBJ `gfx1`: `width=16, sequence=[0,2,1,3]`.

Boundary tests also require the five captured grid RAM files listed in
`pcb_test/grid_capture.sha256`. They are ignored local inputs, not included in a
fresh checkout. Restore the documented capture (see `game/current.md`), or use
`pcb_test/save.mame` to export it from the matching MAME grid state; the checksum
check rejects other captures. Static and scrolling presets do not need these files.
No build script uploads to hardware. To upload an 8 KiB image and reset the PCB:

```bash
bash cores/mzone/ver/pcb_test/run_pcb_test.sh tfix_boundary DEVICE_NAME
```

Build prerequisites: Bash, Python 3, and `sha256sum`. Simulation
also needs the usual JTFRAME/Verilator tools; scene recapture needs MAME.
