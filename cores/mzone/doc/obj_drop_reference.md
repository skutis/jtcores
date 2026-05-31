# OBJ Drop Reference

This note records the reference data for the Mega Zone test ROM drop sprite used
while debugging OBJ X/line-buffer behavior.

## Commits

- Clean reference: `22b57b32d mzone core`
- Bad comparison: `0769d0d18 mzone core`

The clean parent commit renders the test ROM drop as a compact red/yellow drop.
The next commit renders the same object as a smeared form.

## Files

- `ver/game/drop_aa_stage_data.txt`
  - Authoritative staged data for OBJ code `$aa`, color `$f`.
  - Includes raw object ROM bytes per row/group.
  - Includes decoded 4-bit pens before C6/A16 PROM.
  - Includes post-C6 object pixel indices.
- `ver/game/expected_drop_aa.txt`
  - Short pen-matrix summary and file index.
- `ver/game/drop_crop_prev_commit.png`
  - Frame-8 crop from clean commit `22b57b32d`.
- `ver/game/drop_crop_head2.png`
  - Frame-8 crop from bad commit `0769d0d18`.

## Decode Checkpoints

Parent drawer byte addressing:

```text
byte_addr = code*64 + row_base + group*8
low_byte  = gfx[byte_addr]
high_byte = gfx[byte_addr+0x4000]
draw_pen[pix] = { high[pix], high[pix+4], low[pix], low[pix+4] }
```

Use `ver/game/drop_aa_stage_data.txt` when changing OBJ ROM fetch, pixel
unpack, PROM/LUT mapping, or line-buffer X addressing. The implementation
should reproduce the Stage B pen matrix before palette mapping.
