/*  This file is part of JTCORES.
    JTCORES program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version. */

module jtmzone_fix #(
    // Align the FIX window with FIX pixels at the color mixer input.
    parameter FIX_SRC_DLY=6
)(
    input               rst,
    input               clk,
    input               clk24,
    input               pxl_cen,

    input        [ 9:0] cpu_addr,
    input        [ 7:0] cpu_dout,
    input               cpu_rnw,
    input               vram_cs,
    input               cram_cs,
    output       [ 7:0] vram_dout,
    output       [ 7:0] cram_dout,

    input        [ 8:0] hdump,
    input        [ 8:0] vdump,
    input               flip,

    input        [ 3:0] prog_data,
    input        [ 7:0] prog_addr,
    input               prog_en,

    output reg   [11:0] rom_addr,
    output reg          rom_cs,
    input        [31:0] rom_data,
    input               rom_ok,

    output       [ 3:0] pxl,
    output              fix_src
);

localparam [8:0] HVISIBLE       = 9'd288;
localparam [8:0] HTOTAL         = 9'd384;
localparam [8:0] FIX_WIDTH      = 9'd48;
localparam [8:0] FIX_FLIP_START = HVISIBLE-FIX_WIDTH;
localparam [8:0] FIX_LEAD       = 9'd8;
localparam [8:0] FIX_SRC_END    = 9'd48;
localparam [2:0] RD_PHASE       = 3'd7;
localparam [2:0] FETCH_PHASE    = 3'd0;
// A row loaded on phase 4 becomes glyph bits on the next pixel and reaches
// colmix after the character palette. This effective delay is what the
// colmix blanking delay must match.
localparam [2:0] LOAD_PHASE     = 3'd4;

reg  [31:0] pxl_data;
reg  [ 9:0] ram_addr;
reg  [ 3:0] pal_msb, cur_pal;
reg         hflip, cur_hf;
wire [ 7:0] vram, cram;
wire        vram_we = vram_cs & ~cpu_rnw;
wire        cram_we = cram_cs & ~cpu_rnw;
wire [ 9:0] eff_addr = cpu_addr;

wire [ 8:0] hsum_base = hdump < HVISIBLE ? hdump : { ~6'h0, hdump[2:0] };
wire [ 8:0] fix_origin = flip ? FIX_FLIP_START : 9'd0;
wire [ 8:0] fix_hsum = hsum_base - fix_origin;
wire [ 8:0] hsum = fix_hsum + FIX_LEAD - {8'd0, flip};
wire        blank_fetch = hdump >= 9'd288 && hdump <= 9'd375;
wire [ 8:0] heff = blank_fetch ? hdump - 9'd160 :
                    flip ? FIX_WIDTH - 9'd1 - hsum : hsum;
// Use the PCB's 8-bit wrapped h counter for phase and tile column.
wire [ 7:0] h_eff = heff[7:0];
wire [ 7:0] vsum = vdump[8] ? vdump[7:0] - 8'd8 : vdump[7:0];
wire [ 7:0] v_eff = flip ? ~vsum : vsum;
wire [11:0] tile_addr = { cram[7], vram, v_eff[2:0] ^ {3{cram[5]}} };
wire        read_tile = h_eff[2:0] == RD_PHASE;
wire        load_tile = h_eff[2:0] == LOAD_PHASE;
wire        fetch_tile = h_eff[2:0] == FETCH_PHASE;
wire [ 3:0] pxl_raw = cur_hf ? pxl_data[3:0] : pxl_data[31:28];
wire [ 3:0] color_raw = cur_pal;
wire [ 7:0] pal_addr = { color_raw, pxl_raw[0], pxl_raw[1], pxl_raw[2], pxl_raw[3] };
wire        fix_src_pre = flip ? hdump >= FIX_FLIP_START && hdump < HVISIBLE :
                                 hdump >= HVISIBLE || hdump < FIX_SRC_END;

jtframe_sh #(.W(1),.L(FIX_SRC_DLY)) u_fix_src_dly(
    .clk    ( clk         ),
    .clk_en ( pxl_cen     ),
    .din    ( fix_src_pre ),
    .drop   ( fix_src     )
);

// PCB vcount mapping:
// raw vdump 0..255   -> PCB vcount 0..255
// raw vdump 256..263 -> PCB vcount 248..255
// flip mirrors the final 8-bit PCB vcount with bitwise inversion
//
// if( vdump[8] )
//     vsum = vdump[7:0] - 8'd8;
// else
//     vsum = vdump[7:0];
//
// v_eff = flip ? ~vsum : vsum;
// PCB hcount mapping noted for reference. Do not use this directly in the
// current FIX fetch path; it already has its own effective counter.
//
// The active FIX counter is RoadF-like, but with a M-Zone local origin:
// hsum_base   = common raw hdump reference, sign-extended in HBLANK
// fix_hsum    = local FIX X, origin 0 normally and 240 when flipped
// hsum/heff   = fetch-leaded address counter; flip mirrors the local 0..47 span
//               and uses the RoadF-style -flip one-pixel phase correction
//
// During the visible FIX span this corresponds to:
// non-flip: raw hdump 0..47   -> local counter 0..47
// flip:     raw hdump 240..287 -> local counter 47..0
//
// if( flip ) begin
//     hn = h < 9'd048 ? 9'd047 - h :
//          h < 9'd128 ? 9'd271 - h :
//          h < 9'd144 ? 9'd143 - h :
//          h < 9'd288 ? 9'd399 - h :
//                        9'd399 - h;
// end else begin
//     hn = h < 9'd048 ? h :
//          h < 9'd288 ? h - 9'd032 :
//                        h - 9'd160;
// end
// pcb_hcnt = hn[7:0];

always @(posedge clk) begin
    if( rst ) begin
        rom_addr <= 12'd0;
        rom_cs <= 1'b0;
        ram_addr <= 10'd0;
        pxl_data <= 32'd0;
        pal_msb <= 4'd0;
        cur_pal <= 4'd0;
        hflip <= 1'b0;
        cur_hf <= 1'b0;
    end else if( pxl_cen ) begin
        if( read_tile )
            ram_addr <= { v_eff[7:3], h_eff[7:3] };

        if( fetch_tile ) begin
            rom_addr <= tile_addr;
            rom_cs   <= 1'b1;
            pal_msb  <= cram[3:0];
            hflip    <= cram[6] ^ flip;
        end else begin
            rom_cs <= 1'b0;
        end

        if( load_tile ) begin
            pxl_data <= {
                rom_data[4],  rom_data[5],  rom_data[6],  rom_data[7],
                rom_data[0],  rom_data[1],  rom_data[2],  rom_data[3],
                rom_data[12], rom_data[13], rom_data[14], rom_data[15],
                rom_data[8],  rom_data[9],  rom_data[10], rom_data[11],
                rom_data[20], rom_data[21], rom_data[22], rom_data[23],
                rom_data[16], rom_data[17], rom_data[18], rom_data[19],
                rom_data[28], rom_data[29], rom_data[30], rom_data[31],
                rom_data[24], rom_data[25], rom_data[26], rom_data[27]
            };
            cur_pal  <= pal_msb;
            cur_hf   <= hflip;
        end else begin
            pxl_data <= cur_hf ? pxl_data >> 4 : pxl_data << 4;
        end

    end
end

jtframe_dual_ram #(
`ifdef SIMSCENE
    .SIMFILE ( "vram1.bin" ),
`endif
    .AW ( 10 ),
    .DW ( 8  )
) u_vram(
    .clk0   ( clk           ),
    .data0  ( 8'd0          ),
    .addr0  ( ram_addr      ),
    .we0    ( 1'b0          ),
    .q0     ( vram          ),

    .clk1   ( clk24         ),
    .data1  ( cpu_dout      ),
    .addr1  ( eff_addr      ),
    .we1    ( vram_we       ),
    .q1     ( vram_dout     )
);

jtframe_dual_ram #(
`ifdef SIMSCENE
    .SIMFILE ( "cram1.bin" ),
`endif
    .AW ( 10 ),
    .DW ( 8  )
) u_cram(
    .clk0   ( clk           ),
    .data0  ( 8'd0          ),
    .addr0  ( ram_addr      ),
    .we0    ( 1'b0          ),
    .q0     ( cram          ),

    .clk1   ( clk24         ),
    .data1  ( cpu_dout      ),
    .addr1  ( eff_addr      ),
    .we1    ( cram_we       ),
    .q1     ( cram_dout     )
);

jtframe_prom #(
    .DW ( 4 ),
    .AW ( 8 )
) u_palette(
    .clk    ( clk              ),
    .cen    ( pxl_cen          ),
    .data   ( prog_data        ),
    .wr_addr( prog_addr        ),
    .we     ( prog_en          ),
    .rd_addr( pal_addr         ),
    .q      ( pxl              )
);

endmodule
