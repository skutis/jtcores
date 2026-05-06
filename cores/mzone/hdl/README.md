# Mega Zone HDL

Local HDL should use the `jtmzone_` prefix and keep the same rough split used by
`roc`, `yiear`, and `kicker`:

- `jtmzone_game.v` for the JTFRAME wrapper.
- `jtmzone_main.v` for the Konami-1/6809 side and shared RAM.
- `jtmzone_snd.v` for the Z80, AY-3-8910, and 8039/DAC path.
- `jtmzone_video.v` for tile/object/timing logic from the KiCad schematics.

Do not fork shared Konami blocks until the Mega Zone schematic proves that the
existing interface is wrong for this PCB.

