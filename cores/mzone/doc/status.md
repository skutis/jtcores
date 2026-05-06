# Mega Zone Status

Current state:

- `jtmzone_hcnt` models the raw schematic horizontal phase.
- `HS` is derived from the schematic `E9/E10/B11A` path.
- `hblank_n` / `hblk_n` expose the raw schematic blank net.
- Public `LHBL` is JTFRAME-aligned to a contiguous visible window.
- `jtmzone_main` decodes the main CPU address map explicitly.
- `jtmzone_snd` now carries the Z80/AY/shared-RAM side.
- `./sim.sh` passes in the current tree.

What is verified:

- PROM-backed timing lookup is wired through `E7`, `E8`, and `E9`.
- `hcnt_sim` is a stable probe signal for GTKWave.
- The CPU can run for multiple frames without a sim failure.
- `0x0800` is the watchdog write address.

What remains open:

- whether the watchdog should become an active reset source
- whether the CPU is only looping in the boot ROM or missing a later write
- object DMA / object-buffer behavior
- final vertical phase tuning if the visible window needs it

Suggested next waveform checks:

1. `A`, `VMA`, `RnW`, `rom_cs`, `cpu_cen`
2. `irq_n`, `irq_mask`, `LVBL`
3. writes to `0000-0007`, `0800`, `1000`, `1800`
4. sound/shared-RAM activity
