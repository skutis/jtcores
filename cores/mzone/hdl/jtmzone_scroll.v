/*  This file is part of JTCORES.
    JTCORES program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version. */

module jtmzone_scroll(
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
    input        [ 7:0] scrollx,
    input        [ 7:0] scrolly,
    input               flip,

    input        [ 3:0] prog_data,
    input        [ 7:0] prog_addr,
    input               prog_en,

    output reg   [11:0] scr_rom_addr,
    output reg          scr_rom_cs,
    input        [31:0] scr_rom_data,
    input               scr_rom_ok,

    output       [ 3:0] pxl
);

localparam [8:0] HVISIBLE    = 9'd288;
localparam [8:0] SCR_ORIGIN  = 9'd32;
localparam [8:0] SCR_LEAD    = 9'd8;
localparam [2:0] RD_PHASE    = 3'd7;
localparam [2:0] FETCH_PHASE = 3'd0;
localparam [2:0] LOAD_PHASE  = 3'd4;

reg  [31:0] pxl_data;
reg  [ 9:0] ram_addr;
reg  [ 3:0] pal_msb, cur_pal;
reg         hflip, cur_hf;
wire [ 7:0] vram, cram;
wire        vram_we = vram_cs & ~cpu_rnw;
wire        cram_we = cram_cs & ~cpu_rnw;
wire [ 9:0] eff_addr = cpu_addr;

wire [ 8:0] hsum_base = hdump < HVISIBLE ? hdump : hdump - 9'd384;
wire [ 8:0] scroll_origin = flip ? 9'd0 : SCR_ORIGIN;
wire [ 8:0] scroll_hsum = hsum_base - scroll_origin;
wire [ 8:0] hsum = scroll_hsum + SCR_LEAD - { 8'd0, flip };
// hsum_base is the common raw hdump reference, sign-extended in HBLANK.
// scroll_origin makes non-flipped scroll H addressing hdump-32. In flip, the
// mirrored counter already lands on the PCB tile-map origin, so no origin
// subtraction is applied. SCR_LEAD is only the pipeline lookahead before
// pixels reach colmix.
wire [ 7:0] h_eff = flip ? ~hsum[7:0] : hsum[7:0];
wire [ 7:0] v_eff = pcb_vcnt(vdump, flip);
wire [ 7:0] heff = h_eff + scrolly;
wire [ 7:0] veff = v_eff + scrollx;

wire [31:0] rom_decoded_row;
wire [11:0] tile_addr = { cram[7], vram, veff[2:0] ^ {3{cram[5]}} };
wire        read_tile = heff[2:0] == RD_PHASE;
wire        load_tile = heff[2:0] == LOAD_PHASE;
wire        fetch_tile = heff[2:0] == FETCH_PHASE;
wire [ 3:0] pxl_raw = cur_hf ? pxl_data[3:0] : pxl_data[31:28];
wire [ 3:0] color_raw = cur_pal;
wire [ 7:0] pal_addr = { color_raw, pxl_raw[0], pxl_raw[1], pxl_raw[2], pxl_raw[3] };

assign rom_decoded_row = decode_row(scr_rom_data);

function [31:0] decode_row;
    input [31:0] data;
begin
    decode_row = {
        { data[4],  data[5],  data[6],  data[7]  },
        { data[0],  data[1],  data[2],  data[3]  },
        { data[12], data[13], data[14], data[15] },
        { data[8],  data[9],  data[10], data[11] },
        { data[20], data[21], data[22], data[23] },
        { data[16], data[17], data[18], data[19] },
        { data[28], data[29], data[30], data[31] },
        { data[24], data[25], data[26], data[27] }
    };
end
endfunction

function [7:0] pcb_vcnt;
    input [8:0] v;
    input       f;
    reg   [7:0] vn;
begin
    // Raw vdump[8] wraps the bottom blanking lines back to PCB 248..255;
    // flip mirrors the final 8-bit PCB vcount.
    vn = v[8] ? v[7:0] - 8'd8 : v[7:0];
    pcb_vcnt = f ? ~vn : vn;
end
endfunction

always @(posedge clk) begin
    if( rst ) begin
        scr_rom_addr <= 12'd0;
        scr_rom_cs <= 1'b0;
        ram_addr <= 10'd0;
        pxl_data <= 32'd0;
        pal_msb <= 4'd0;
        cur_pal <= 4'd0;
        hflip <= 1'b0;
        cur_hf <= 1'b0;
    end else if( pxl_cen ) begin
        if( read_tile )
            ram_addr <= { veff[7:3], heff[7:3] };

        if( fetch_tile ) begin
            scr_rom_addr <= tile_addr;
            scr_rom_cs   <= 1'b1;
            pal_msb      <= cram[3:0];
            hflip        <= cram[6] ^ flip;
        end else begin
            scr_rom_cs <= 1'b0;
        end

        if( load_tile ) begin
            pxl_data <= rom_decoded_row;
            cur_pal  <= pal_msb;
            cur_hf   <= hflip;
        end else begin
            pxl_data <= cur_hf ? pxl_data >> 4 : pxl_data << 4;
        end
    end
end

jtframe_dual_ram #(
`ifdef SIMSCENE
    .SIMFILE ( "vram0.bin" ),
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
    .SIMFILE ( "cram0.bin" ),
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
