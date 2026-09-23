# M-Zone TODO

- [ ] Check SiDi128 HDMI output for the suspected pixel-delay/alignment issue.

- [ ] Adjust sound volume and verify PSG/DAC balance.
  - Use a repeatable gameplay section containing simultaneous PSG and DAC sounds.
  - Compare with a PCB recording at a documented volume-pot setting; use MAME as
    a secondary reference, not proof of the original analogue levels.
  - Establish PSG-to-DAC balance first. Mixing resistor values alone do not
    establish the relative output voltages of the two sources.
  - Measure mixed-output peaks and RMS level, and check for clipping or limiter
    activity during loud effects. Leave headroom for combinations not yet tested.
  - Adjust overall gain separately from channel balance; preserve the intended
    filter characteristics. Current audio configuration is in cfg/mem.yaml.
  - Listen on FPGA hardware at fixed platform/output volume settings. Record
    the test sequence, reference, measurements, and chosen settings.
