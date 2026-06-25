/*  This file is part of JTCORES.
    JTCORES program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version. */

module jtmzone_scroll(
    input               rst,
    input               clk,
    input               pxl_cen,

    input               LHBL,
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

    output reg   [11:0] scr_rom_addr,
    output reg          scr_rom_cs,
    input        [31:0] scr_rom_data,
    input               scr_rom_ok,

    output       [ 3:0] pxl,
    output              fix_n,
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
localparam [8:0] BLANK_DLY = 9'd9;
localparam [8:0] FIX_MUX_DLY = 9'd8;
localparam [8:0] FIX_ADDR_HPOS_OFS = 9'd2;
localparam [7:0] FIX_ADDR_VPOS_OFS = 8'd1;
localparam [7:0] SCR_ADDR_VPOS_OFS = -8'sd1;
localparam [2:0] FETCH_PHASE = 3'd0;
localparam [2:0] LOAD_PHASE  = 3'd4;
localparam       DISABLE_SCROLL = 1'b0;

reg  [31:0] fix_pxl_data, scr_pxl_data;
reg  [31:0] fix_row, scr_row;
reg  [ 3:0] fix_color, scr_color;
reg         fix_hflip, scr_hflip;
reg  [ 7:0] fix_row_attr, scr_row_attr;
reg  [ 7:0] rom_attr;
reg  [11:0] req_addr;
reg  [ 7:0] req_attr;
reg         req_pending, req_fix;
reg         rom_req_fix;

wire [ 7:0] h_eff = pcb_hcnt(hdump, flip);
wire [ 7:0] v_raw = vdump[8] ? vdump[7:0] - 8'd8 : vdump[7:0];
wire [ 8:0] v_eff = { 1'b0, v_raw ^ {8{flip}} };

wire [ 7:0] fix_addr_x = h_eff + FIX_ADDR_HPOS_OFS[7:0];
wire [ 7:0] fix_addr_y = v_eff[7:0] + FIX_ADDR_VPOS_OFS;
wire [ 7:0] fix_fetch_x = fix_addr_x;
// The source window starts the FIX fetch path; the mux window selects FIX
// pixels after the character pipeline delay.
wire        fix_src = flip ? hdump >= HVISIBLE - FIX_WIDTH :
                             !LHBL || hdump < FIX_WIDTH;
wire        fix_mux = flip ? hdump >= HVISIBLE - FIX_WIDTH + FIX_MUX_DLY :
                             hdump < FIX_WIDTH + FIX_MUX_DLY;
assign fix_n = ~fix_src;
assign fix_en = fix_mux;

wire [ 7:0] fix_vdf = fix_addr_y;
wire [ 7:0] fix_rd_x = fix_addr_x;
wire        fix_load = fix_src && fix_fetch_x[2:0] == LOAD_PHASE;
wire [11:0] fix_tile_addr = { cram1[7], vram1, fix_vdf[2:0] ^ {3{cram1[5]}} };
wire [31:0] rom_decoded_row;
wire        fix_rom_ok = scr_rom_ok && rom_req_fix;
wire        fix_load_fresh = fix_rom_ok && scr_rom_addr == fix_tile_addr;
wire [31:0] fix_load_data = fix_load_fresh ? rom_decoded_row : fix_row;
wire [ 7:0] fix_load_attr = fix_load_fresh ? rom_attr : fix_row_attr;

wire [ 7:0] scr_addr_x  = h_eff + scrolly;
wire [ 7:0] scr_addr_y  = v_eff[7:0] + SCR_ADDR_VPOS_OFS + scrollx;
wire [ 7:0] scr_fetch_x = scr_addr_x;
wire [ 7:0] scr_hdf = scr_fetch_x;
wire [ 7:0] scr_vdf = scr_addr_y;
wire [ 7:0] scr_rd_x = scr_addr_x;
wire        scr_load = !DISABLE_SCROLL && scr_hdf[2:0] == LOAD_PHASE;
wire [11:0] scr_tile_addr = { cram0[7], vram0, scr_vdf[2:0] ^ {3{cram0[5]}} };
wire        scr_rom_ok_int = scr_rom_ok && !rom_req_fix;
wire        scr_load_fresh = scr_rom_ok_int && scr_rom_addr == scr_tile_addr;
wire [31:0] scr_load_data = scr_load_fresh ? rom_decoded_row : scr_row;
wire [ 7:0] scr_load_attr = scr_load_fresh ? rom_attr : scr_row_attr;

wire        scan_fix = fix_src;
wire [ 7:0] scan_hdf = scan_fix ? fix_fetch_x : scr_hdf;
wire [11:0] scan_addr = scan_fix ? fix_tile_addr : scr_tile_addr;
wire [ 7:0] scan_attr = scan_fix ? cram1 : cram0;
wire        scan_fetch = (scan_fix || !DISABLE_SCROLL) && scan_hdf[2:0] == FETCH_PHASE;
wire        scan_busy = scr_rom_cs && (rom_req_fix == scan_fix);

wire [ 3:0] fix_pxl_raw = fix_hflip ? fix_pxl_data[3:0] : fix_pxl_data[31:28];
wire [ 3:0] scr_pxl_raw = scr_hflip ? scr_pxl_data[3:0] : scr_pxl_data[31:28];
wire [ 3:0] pxl_raw = fix_en ? fix_pxl_raw : scr_pxl_raw;
wire [ 3:0] color_raw = DISABLE_SCROLL && !fix_en ? 4'd0 :
                         fix_en ? fix_color : scr_color;
wire [ 7:0] pal_addr = { color_raw, pxl_raw[0], pxl_raw[1], pxl_raw[2], pxl_raw[3] };

assign fix_ram_addr    = { fix_vdf[7:3], fix_rd_x[7:3] };
assign scroll_ram_addr = { scr_vdf[7:3], scr_rd_x[7:3] };
assign rom_decoded_row = decode_row(scr_rom_data);
assign dbg_hcnt = fix_en ? {1'b0,fix_fetch_x} : {1'b0,scr_fetch_x};
assign dbg_fix = fix_en;
assign dbg_rom_addr = fix_en ? fix_tile_addr : scr_tile_addr;
assign dbg_scr_x = scr_fetch_x;
assign dbg_pat_x = fix_en ? fix_fetch_x : scr_hdf;
assign dbg_scr_y = scr_addr_y;
assign dbg_pat_y = fix_en ? fix_vdf : scr_vdf;

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

function [7:0] pcb_hcnt;
    input [8:0] h;
    input       f;
    reg   [8:0] hn;
begin
    if( f ) begin
        hn = h < 9'd048 ? 9'd047 - h :
             h < 9'd128 ? 9'd271 - h :
             h < 9'd144 ? 9'd143 - h :
             h < 9'd288 ? 9'd399 - h :
                           9'd399 - h;
    end else begin
        hn = h < 9'd048 ? h :
             h < 9'd288 ? h - 9'd032 :
                           h - 9'd160;
    end
    pcb_hcnt = hn[7:0];
end
endfunction

always @(posedge clk) begin
    if( rst ) begin
        scr_rom_addr <= 12'd0;
        scr_rom_cs <= 1'b0;
        rom_req_fix <= 1'b0;
        fix_pxl_data <= 32'd0;
        scr_pxl_data <= 32'd0;
        fix_row <= 32'd0;
        scr_row <= 32'd0;
        fix_color <= 4'd0;
        scr_color <= 4'd0;
        fix_hflip <= 1'b0;
        scr_hflip <= 1'b0;
        fix_row_attr <= 8'd0;
        scr_row_attr <= 8'd0;
        rom_attr <= 8'd0;
        req_addr <= 12'd0;
        req_attr <= 8'd0;
        req_pending <= 1'b0;
        req_fix <= 1'b0;
    end else begin
        if( scr_rom_ok ) begin
            scr_rom_cs <= 1'b0;
            if( rom_req_fix ) begin
                fix_row <= rom_decoded_row;
                fix_row_attr <= rom_attr;
            end else begin
                scr_row <= rom_decoded_row;
                scr_row_attr <= rom_attr;
            end
        end

        if( pxl_cen ) begin
            if( scan_fetch && !req_pending && !scan_busy ) begin
                req_addr    <= scan_addr;
                req_attr    <= scan_attr;
                req_fix     <= scan_fix;
                req_pending <= 1'b1;
            end

            if( req_pending && (!scr_rom_cs || scr_rom_ok) ) begin
                scr_rom_addr <= req_addr;
                rom_attr     <= req_attr;
                rom_req_fix  <= req_fix;
                scr_rom_cs   <= 1'b1;
                req_pending  <= 1'b0;
            end

            if( fix_load ) begin
                fix_pxl_data <= fix_load_data;
                fix_color <= fix_load_attr[3:0];
                fix_hflip <= fix_load_attr[6] ^ flip;
            end else begin
                fix_pxl_data <= fix_hflip ? fix_pxl_data >> 4 : fix_pxl_data << 4;
            end

            if( scr_load ) begin
                scr_pxl_data <= scr_load_data;
                scr_color <= scr_load_attr[3:0];
                scr_hflip <= scr_load_attr[6] ^ flip;
            end else begin
                scr_pxl_data <= scr_hflip ? scr_pxl_data >> 4 : scr_pxl_data << 4;
            end

`ifdef MZONE_SCROLL_WATCH
            if( v_eff >= `MZONE_SCROLL_WATCH_V0 &&
                v_eff <= `MZONE_SCROLL_WATCH_V1 &&
                hdump >= `MZONE_SCROLL_WATCH_X0 &&
                hdump <= `MZONE_SCROLL_WATCH_X1 ) begin
                $display("MZONE_SCROLL hdump=%0d vdump=%0d hcnt=%0d scan_fix=%b scan_hdf=%02x scan_fetch=%b fix_load=%b scr_load=%b rom_addr=%03x fix_ok=%b scr_ok=%b fix_en=%b vram0=%02x cram0=%02x scr_tile=%03x scr_data=%08x scr_dec=%08x scr_row=%08x scr_sh=%08x fix_pxl=%x scr_pxl=%x pxl=%x",
                    hdump, v_eff, h_eff, scan_fix, scan_hdf, scan_fetch, fix_load, scr_load,
                    scr_rom_addr, fix_rom_ok, scr_rom_ok_int, fix_en,
                    vram0, cram0, scr_tile_addr, scr_rom_data, rom_decoded_row,
                    scr_row, scr_pxl_data, fix_pxl_raw, scr_pxl_raw, pxl);
            end
`endif
        end
    end
end

jtframe_prom #(
    .DW ( 4 ),
    .AW ( 8 ),
    .ASYNC( 1 )
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
