/*  This file is part of JTCORES.
    JTCORES program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version. */

module jtmzone_scroll(
    input               rst,
    input               clk,
    input               pxl_cen,

    input        [ 8:0] hdump,
    input        [ 8:0] vdump,
    input        [ 7:0] scrollx,
    input        [ 7:0] scrolly,
    input               flip,

    output       [ 9:0] scroll_ram_addr,
    output       [ 9:0] fix_ram_addr,
    input        [ 7:0] vram0,
    input        [ 7:0] vram1,
    input        [ 7:0] cram0,
    input        [ 7:0] cram1,

    input        [ 3:0] prog_data,
    input        [ 7:0] prog_addr,
    input               prog_en,

    output reg   [11:0] fix_rom_addr,
    output reg          fix_rom_cs,
    input        [31:0] fix_rom_data,
    input               fix_rom_ok,

    output reg   [11:0] scr_rom_addr,
    output reg          scr_rom_cs,
    input        [31:0] scr_rom_data,
    input               scr_rom_ok,

    output       [ 3:0] pxl,
    output              fix_en,
    output       [ 8:0] dbg_hcnt,
    output              dbg_fix,
    output       [11:0] dbg_rom_addr,
    output       [ 7:0] dbg_scr_x,
    output       [ 7:0] dbg_pat_x,
    output       [ 7:0] dbg_scr_y,
    output       [ 7:0] dbg_pat_y
);

localparam [8:0] HVISIBLE  = 9'd288;
localparam [8:0] FIX_WIDTH = 9'd48;
localparam [8:0] SCROLL_START_DLY = 9'd5;
localparam [8:0] SCROLL_END_DLY = 9'd4;
localparam       DISABLE_SCROLL = 1'b0;

reg  [ 7:0] scrollx_lock, scrolly_lock;
reg  [31:0] fix_pxl_data, scr_pxl_data;
reg  [ 3:0] fix_color, scr_color;
reg         fix_hflip, scr_hflip;
reg  [ 3:0] pxl_d0, pxl_d1, pxl_d2;
reg  [ 3:0] color_d0, color_d1, color_d2;
reg         fix_d0, fix_d1, fix_d2;

wire        raw_visible = hdump < HVISIBLE;
wire        scroll_visible = hdump < HVISIBLE + SCROLL_END_DLY;
wire        display_fix = hdump < FIX_WIDTH + SCROLL_START_DLY;

wire [ 8:0] fix_hcnt = hdump;
wire [ 7:0] fix_x = fix_hcnt[7:0];
wire [ 7:0] fix_y = vdump[7:0];
// Prime the first FIX tile at the end of the previous line. The visible
// x=0 pixels are output before the normal x=4 ROM load can fill the shifter.
wire        fix_left_prime = hdump >= 9'd379;
wire [ 7:0] fix_mem_x = fix_left_prime ? 8'd0 : fix_x;
wire [ 7:0] fix_pat_x = flip ? ~fix_x : fix_x;
wire [ 7:0] fix_mem_pat_x = flip ? ~fix_mem_x : fix_mem_x;
wire [ 7:0] fix_pat_y = flip ? ~fix_y : fix_y;
wire [ 7:0] fix_rd_pat_x = fix_mem_pat_x + 8'd1;
wire        fix_fetch = (raw_visible && hdump < FIX_WIDTH &&
                         fix_pat_x[2:0] == 3'd0) ||
                        hdump == 9'd379;
wire        fix_load = (raw_visible && hdump < FIX_WIDTH &&
                        fix_pat_x[2:0] == 3'd4) ||
                       hdump == 9'd383;
wire [11:0] fix_tile_addr = { cram1[7], vram1, fix_pat_y[2:0] ^ {3{cram1[5]}} };
wire [31:0] fix_decoded_row;

wire [ 8:0] scr_hcnt = hdump - 9'd32;
wire [ 8:0] scr_x_sum = {1'b0,scr_hcnt[7:0]} + {1'b0,scrolly_lock};
wire [ 8:0] scr_y_sum = {1'b0,vdump[7:0]} + {1'b0,scrollx_lock};
wire [ 7:0] scr_x = scr_x_sum[7:0];
wire [ 7:0] scr_y = scr_y_sum[7:0];
wire [ 7:0] scr_pat_x = flip ? ~scr_x : scr_x;
wire [ 7:0] scr_pat_y = flip ? ~scr_y : scr_y;
wire [ 7:0] scr_rd_pat_x = scr_pat_x + 8'd1;
wire        scr_fetch = !DISABLE_SCROLL && scroll_visible &&
                        hdump >= FIX_WIDTH-9'd16 &&
                        scr_pat_x[2:0] == 3'd0;
wire        scr_load = !DISABLE_SCROLL && scroll_visible &&
                       hdump >= FIX_WIDTH-9'd16 &&
                       scr_pat_x[2:0] == 3'd4;
wire [11:0] scr_tile_addr = { cram0[7], vram0, scr_pat_y[2:0] ^ {3{cram0[5]}} };
wire [31:0] scr_decoded_row;

wire [ 3:0] fix_pxl_raw = fix_hflip ? fix_pxl_data[3:0] : fix_pxl_data[31:28];
wire [ 3:0] scr_pxl_raw = scr_hflip ? scr_pxl_data[3:0] : scr_pxl_data[31:28];
wire [ 3:0] pxl_raw = display_fix ? fix_pxl_raw : scr_pxl_raw;
wire [ 3:0] color_raw = DISABLE_SCROLL && !display_fix ? 4'd0 :
                         display_fix ? fix_color : scr_color;
wire [ 3:0] lut_pxl;
wire [ 3:0] lut_pen = { pxl_d1[0], pxl_d1[1], pxl_d1[2], pxl_d1[3] };

assign fix_ram_addr    = { fix_pat_y[7:3], fix_rd_pat_x[7:3] };
assign scroll_ram_addr = { scr_pat_y[7:3], scr_rd_pat_x[7:3] };
assign fix_decoded_row = decode_row(fix_rom_data);
assign scr_decoded_row = decode_row(scr_rom_data);
assign pxl = lut_pxl;
assign fix_en = fix_d1;
assign dbg_hcnt = display_fix ? fix_hcnt : scr_hcnt;
assign dbg_fix = display_fix;
assign dbg_rom_addr = display_fix ? fix_tile_addr : scr_tile_addr;
assign dbg_scr_x = scr_x;
assign dbg_pat_x = display_fix ? fix_pat_x : scr_pat_x;
assign dbg_scr_y = scr_y;
assign dbg_pat_y = display_fix ? fix_pat_y : scr_pat_y;

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

always @(posedge clk) begin
    if( rst ) begin
        scrollx_lock <= 8'd0;
        scrolly_lock <= 8'd0;
        fix_rom_addr <= 12'd0;
        fix_rom_cs <= 1'b0;
        scr_rom_addr <= 12'd0;
        scr_rom_cs <= 1'b0;
        fix_pxl_data <= 32'd0;
        scr_pxl_data <= 32'd0;
        fix_color <= 4'd0;
        scr_color <= 4'd0;
        fix_hflip <= 1'b0;
        scr_hflip <= 1'b0;
        pxl_d0 <= 4'd0;
        pxl_d1 <= 4'd0;
        pxl_d2 <= 4'd0;
        color_d0 <= 4'd0;
        color_d1 <= 4'd0;
        color_d2 <= 4'd0;
        fix_d0 <= 1'b0;
        fix_d1 <= 1'b0;
        fix_d2 <= 1'b0;
    end else if( pxl_cen ) begin
        if( hdump[0] == 1'b0 ) begin
            scrollx_lock <= scrollx;
            scrolly_lock <= scrolly;
        end

        fix_rom_cs <= fix_fetch;
        if( fix_fetch ) fix_rom_addr <= fix_tile_addr;
        scr_rom_cs <= scr_fetch;
        if( scr_fetch ) scr_rom_addr <= scr_tile_addr;

        if( fix_load ) begin
            fix_pxl_data <= fix_decoded_row;
            fix_color <= cram1[3:0];
            fix_hflip <= cram1[6];
        end else begin
            fix_pxl_data <= fix_hflip ? fix_pxl_data >> 4 : fix_pxl_data << 4;
        end

        if( scr_load ) begin
            scr_pxl_data <= scr_decoded_row;
            scr_color <= cram0[3:0];
            scr_hflip <= cram0[6];
        end else begin
            scr_pxl_data <= scr_hflip ? scr_pxl_data >> 4 : scr_pxl_data << 4;
        end

        pxl_d0 <= pxl_raw;
        pxl_d1 <= pxl_d0;
        pxl_d2 <= pxl_d1;
        color_d0 <= color_raw;
        color_d1 <= color_d0;
        color_d2 <= color_d1;
        fix_d0 <= display_fix;
        fix_d1 <= fix_d0;
        fix_d2 <= fix_d1;

`ifdef MZONE_SCROLL_WATCH
        if( vdump >= `MZONE_SCROLL_WATCH_V0 &&
            vdump <= `MZONE_SCROLL_WATCH_V1 &&
            hdump >= `MZONE_SCROLL_WATCH_X0 &&
            hdump <= `MZONE_SCROLL_WATCH_X1 ) begin
            $display("MZONE_SCROLL hdump=%0d vdump=%0d fix_fetch=%b fix_load=%b scr_fetch=%b scr_load=%b fix_addr=%03x scr_addr=%03x fix_ok=%b scr_ok=%b disp_fix=%b fix_pxl=%x scr_pxl=%x lut_pxl=%x",
                hdump, vdump, fix_fetch, fix_load, scr_fetch, scr_load,
                fix_rom_addr, scr_rom_addr, fix_rom_ok, scr_rom_ok, display_fix,
                fix_pxl_raw, scr_pxl_raw, lut_pxl);
        end
`endif
    end
end

jtframe_prom #(
    .DW ( 4 ),
    .AW ( 8 ),
    .ASYNC( 1 )
) u_char_lut(
    .clk    ( clk              ),
    .cen    ( pxl_cen          ),
    .data   ( prog_data        ),
    .wr_addr( prog_addr        ),
    .we     ( prog_en          ),
    .rd_addr( { color_d1, lut_pen } ),
    .q      ( lut_pxl          )
);

endmodule
