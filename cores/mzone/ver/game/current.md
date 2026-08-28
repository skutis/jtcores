# M-Zone current work checkpoint

Saved: 2026-08-28, Europe/Stockholm

Working directory:

`/home/skutis77/github/jtcores-fork/cores/mzone/ver/game`

## Current objective and result

- FIX and SCROLL timing are being compared at the left boundary around displayed
  `hdump 48`.
- `fix_src` is intentionally valid for one pixel longer at the mixer.
- The focused test uses the exact white grid captured from MAME as the FIX
  background, with the `7` and solid blue/yellow markers over it.
- FIX and SCROLL VRAM are filled with opaque-black tile `$10` before captured
  data is copied, preventing reset RAM contents from appearing.
- Each layer's CRAM is copied before its VRAM, so the captured tiles never use
  reset attributes.
- The remaining white column at displayed `hdump 48` is from SCROLL, not FIX.
  With the +1-pixel scroll (`$FF`), the last pixel of SCROLL cell `$2041` is
  exposed. That cell contains MAME grid tile `$2D`; its CRAM cell `$2841` is
  `$40`. The numbered SCROLL cells begin at `$2042`.

## JTCORES HDL state

Modified file:

`/home/skutis77/github/jtcores-fork/cores/mzone/hdl/jtmzone_fix.v`

Important current values:

```verilog
localparam [8:0] FIX_PRIO_END = 9'd47;
localparam [8:0] FIX_SRC_END  = 9'd48;

jtframe_sh #(.W(1),.L(FIX_EN_DLY)) u_fix_en_dly(...);
jtframe_sh #(.W(1),.L(FIX_EN_DLY)) u_fix_src_dly(...);
```

Thus the mixer-facing transition measured previously was:

| Raw `hdump` | `fix_en` | `fix_src` |
|---:|---:|---:|
| 52 | 1 | 1 |
| 53 | 0 | 1 |
| 54 | 0 | 0 |

The file also contains the existing debug-only address reference:

```verilog
localparam FIX_ADDR_COLMIX_DLY = 6;
wire [4:0] dbg_fix_addr_colmix /* verilator public_flat */;
```

Do not discard those debug additions when editing `fix_src`.

## Current PCB test

Directory:

`/home/skutis77/github/jtcores-fork/cores/mzone/ver/pcb_test`

The active generator is `make_pcb_grid_6h.py`. Its local changes:

1. Add `fill_1k()`.
2. Fill FIX VRAM `$2400-$27FF` with tile `$10` immediately after reset.
3. Fill SCROLL VRAM `$2000-$23FF` with tile `$10` immediately after reset.
4. Copy captured blocks in this order:

   ```text
   FIX CRAM -> FIX VRAM -> SCROLL CRAM -> SCROLL VRAM -> OBJ
   ```

The packed captured-data layout is unchanged:

| File | CPU destination | 6H data offset |
|---|---:|---:|
| `vram0.bin` | `$2000` | `$0400` |
| `vram1.bin` | `$2400` | `$0800` |
| `cram0.bin` | `$2800` | `$0C00` |
| `cram1.bin` | `$2C00` | `$1000` |
| `obj.bin` | `$3000` | `$1400` |

MAME dump input SHA-256 values:

```text
c73ea29867a0c450b33fceaf2176c5e9032f3176d57f2759a44769d240b36afc  vram0.bin
24dfe74873b95592d8a4151dcdbbf1f53830bc55dccd938bb1a3ebe56b0c1ecb  vram1.bin
7d6cfb13575067880eb07f0d648d637eba20ca37331701aad97916bdd6add9fb  cram0.bin
2b57f9144e0467654d1f9211bb0073902a6a94aa047c05a5ea50eb4a1e15d8fd  cram1.bin
5f70bf18a086007016e948b04aed3b82103a36bea41755b6cddfaf10ace3c6ef  obj.bin
```

Current script SHA-256 values:

```text
5ee1569c17d0c62c291ba83c641abfbeb6ec84a51045c6465ed7f992a399e882  make_pcb_grid_6h.py
d28c05c662b4f52686e5c332f1b701179f78ae6bc0c5767c3589582e4ec37383  make_boundary_scrollff_test.py
4465f8cef503dd6bd4e3afb76af5411bfc5cfa68e9b3f886a19710b3f4ce6534  make_fix_boundary_test.py
```

Rebuild the exact test in `pcb_test` with:

```bash
MZONE_GRID_NAME=megazone_grid_scrollp1px \
MZONE_GRID_SCROLLY=0xFF \
python3 make_pcb_grid_6h.py
python3 make_boundary_scrollff_test.py
python3 make_fix_boundary_test.py
```

Current focused output hashes:

```text
22924df6cb2f55fbc0174af889a200a466582afa0cf6b4ad1e5040ea889410e3  tfix_boundary_6h.bin
4853aaa05794af5a247da17277c49aed35138d512199bf9f965d964b6d22f12b  tfix_boundary_6h_sim.rom
```

## Current simulation script and command

Simulation script:

`/home/skutis77/github/jtcores-fork/cores/mzone/ver/game/sim.sh`

SHA-256:

```text
09fc25b4e81da2a9013cfac25d086b9e7b97a1b228a8bb56be41c14e24e3f0f7  sim.sh
```

`sim.sh` has no local Git diff. It selects the ROM with `MZONE_ROM`; setting
`MZONE_SOUND=1` prevents the default `MZONE_FAST_SOUND` define. The verified
five-frame waveform run is:

```bash
MZONE_SOUND=1 \
MZONE_ROM="$PWD/../pcb_test/tfix_boundary_6h_sim.rom" \
./sim.sh -video 5 -w
```

Outputs from the latest run:

- `frames/frame_00001.png`: both character layers initially black.
- `frames/frame_00002.png`: correct MAME FIX grid while SCROLL remains black.
- `frames/frame_00004.png`: final FIX grid, numbered SCROLL, markers and OBJ.
- `test.fst`: waveform output.

Current output SHA-256 values:

```text
7f891b56ad0bf29831e7120215a4ff39b00734202c09760517fb39ae0ea80e82  frames/frame_00001.png
e39a8b4b89bf199b1b73cfd092ee226bcd52a0677214332cf9edaf2fea5af258  frames/frame_00002.png
eac1eec105b5c2250077f10b1ac5f464d01de918d096e138e3087689acc07ba8  frames/frame_00004.png
eaf768e863424b5634e934344973a86755a00e06a87f7ba4eb943c192b5a2ba1  test.fst
```

## Gate-array reference

Repository:

`/home/skutis77/github/gate_arrays`

Current clean commit:

```text
8a711fe428a853dbee99d85b7e1d9255178480d7  mzone core
```

In `mzone/mzone.v`, TA now updates immediately when ODD becomes active and
holds the odd master. The LS273 captures TA on rising `H1'`:

```verilog
always @(negedge h1_n or negedge clr_n) begin
    if (!clr_n)
        TA_ODD <= 8'h00;
    else
        TA_ODD <= hcount;
end

assign TA = !clr_n ? 8'h00 : TA_ODD;

always @(posedge h1_n or negedge clr_n) begin
    if (!clr_n)
        TCHA <= 8'h00;
    else
        TCHA <= #TPD_LS273 TA;
end
```

`make all` passed. Waveform observation: when ODD became active,
`h1_n=0`, `hcount=3`, and `TA=3`; after rising `H1'` plus the LS273 delay,
`TCHA=3`.

## Working-tree caution

Current JTCORES status at checkpoint creation included:

```text
 M cores/mzone/hdl/jtmzone_fix.v
 M cores/mzone/sch/color_mixer.kicad_sch
 M cores/mzone/ver/pcb_test/make_pcb_grid_6h.py
?? modules/jt680x/crasm/
```

`color_mixer.kicad_sch` and `modules/jt680x/crasm/` are user-owned/unrelated
changes. Preserve them. Generated ROMs and MRA artifacts may be ignored by Git,
so use the hashes above rather than a clean status to identify them.

## Next focused question

Decide whether the white SCROLL column at displayed `hdump 48` is desired for
the `$FF` one-pixel-scroll test. If it must be removed without changing timing,
replace or cover the preceding SCROLL test cell `$2041` (and corresponding CRAM
cell `$2841`). If the goal is to prove `$2042` must already source `hdump 48`,
trace SCROLL `ram_addr`, fetch/load phase, and mixer input around raw
`hdump 53-54` before making a timing offset.
