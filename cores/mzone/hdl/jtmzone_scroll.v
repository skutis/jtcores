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

    output       [ 3:0] pxl,
    output       [ 8:0] dbg_hcnt,
    output              dbg_fix,
    output       [11:0] dbg_rom_addr,
    output       [ 7:0] dbg_scr_x,
    output       [ 7:0] dbg_pat_x,
    output       [ 7:0] dbg_scr_y,
    output       [ 7:0] dbg_pat_y
);

localparam [8:0] HVISIBLE    = 9'd288;
localparam [8:0] SCR_ORIGIN  = 9'd32;
localparam [8:0] SCR_LEAD    = 9'd8;
localparam [2:0] RD_PHASE    = 3'd7;
localparam [2:0] FETCH_PHASE = 3'd0;
localparam [2:0] LOAD_PHASE  = 3'd4;

reg  [31:0] pxl_data;
reg  [31:0] rom_data_latch;
reg  [ 9:0] ram_addr;
reg  [ 3:0] pal_msb, cur_pal;
reg         hflip, cur_hf;
reg         rom_data_valid;
`ifdef MZONE_SCROLL_WATCH
reg  [ 7:0] cur_vram_dbg, cur_cram_dbg;
reg  [11:0] cur_tile_dbg;
reg  [ 7:0] cur_heff_dbg, cur_veff_dbg;
`endif
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

wire [31:0] rom_row_data = scr_rom_ok ? scr_rom_data : rom_data_latch;
wire [31:0] rom_decoded_row;
wire        rom_load_ready = scr_rom_ok || rom_data_valid;
wire [11:0] tile_addr = { cram[7], vram, veff[2:0] ^ {3{cram[5]}} };
wire        read_tile = heff[2:0] == RD_PHASE;
wire        load_tile = heff[2:0] == LOAD_PHASE;
wire        fetch_tile = heff[2:0] == FETCH_PHASE;
wire [ 3:0] pxl_raw = cur_hf ? pxl_data[3:0] : pxl_data[31:28];
wire [ 3:0] color_raw = cur_pal;
wire [ 7:0] pal_addr = { color_raw, pxl_raw[0], pxl_raw[1], pxl_raw[2], pxl_raw[3] };

`ifdef MZONE_SCROLL_WATCH
reg [15:0] watch_frame;
reg        watch_lvbl_l;
wire       watch_lvbl = vdump >= 9'd16 && vdump < 9'd240;
`endif
`ifdef MZONE_POINT_WATCH
reg [15:0] point_frame;
reg        point_lvbl_l;
reg [ 8:0] point_hdump_s;
reg [ 8:0] point_vdump_s;
wire       point_lvbl = vdump >= 9'd16 && vdump < 9'd240;
`endif
`ifdef MZONE_ROM_MISS_WATCH
`ifndef MZONE_ROM_MISS_FRAME0
`define MZONE_ROM_MISS_FRAME0 0
`endif
`ifndef MZONE_ROM_MISS_FRAME1
`define MZONE_ROM_MISS_FRAME1 65535
`endif
`ifndef MZONE_ROM_MISS_X1
`define MZONE_ROM_MISS_X1 383
`endif
`ifndef MZONE_ROM_MISS_Y1
`define MZONE_ROM_MISS_Y1 263
`endif
reg [15:0] miss_frame;
reg        miss_lvbl_l;
reg        rom_req_pending;
reg        rom_req_ready;
reg [11:0] rom_req_addr;
reg [ 8:0] rom_req_hdump;
reg [ 8:0] rom_req_vdump;
reg [ 7:0] rom_req_heff;
reg [ 7:0] rom_req_veff;
wire       miss_lvbl = vdump >= 9'd16 && vdump < 9'd240;
wire       rom_req_match = scr_rom_ok && scr_rom_addr == rom_req_addr;
wire       rom_ready_now = rom_req_ready || rom_req_match;
wire       miss_visible = hdump < HVISIBLE && vdump >= 9'd16 && vdump < 9'd240;
`ifdef MZONE_ROM_MISS_X0
wire       miss_x0_ok = hdump >= `MZONE_ROM_MISS_X0;
`else
wire       miss_x0_ok = 1'b1;
`endif
`ifdef MZONE_ROM_MISS_Y0
wire       miss_y0_ok = vdump >= `MZONE_ROM_MISS_Y0;
`else
wire       miss_y0_ok = 1'b1;
`endif
wire       miss_window =
    miss_frame >= `MZONE_ROM_MISS_FRAME0 &&
    miss_frame <= `MZONE_ROM_MISS_FRAME1 &&
    miss_x0_ok &&
    hdump <= `MZONE_ROM_MISS_X1 &&
    miss_y0_ok &&
    vdump <= `MZONE_ROM_MISS_Y1
`ifndef MZONE_ROM_MISS_ALL
    && miss_visible
`endif
    ;
`endif

assign rom_decoded_row = decode_row(rom_row_data);
assign dbg_hcnt = { 1'b0, heff };
assign dbg_fix = 1'b0;
assign dbg_rom_addr = tile_addr;
assign dbg_scr_x = heff;
assign dbg_pat_x = heff;
assign dbg_scr_y = veff;
assign dbg_pat_y = veff;

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
        rom_data_latch <= 32'd0;
        rom_data_valid <= 1'b0;
        ram_addr <= 10'd0;
        pxl_data <= 32'd0;
        pal_msb <= 4'd0;
        cur_pal <= 4'd0;
        hflip <= 1'b0;
        cur_hf <= 1'b0;
`ifdef MZONE_SCROLL_WATCH
        watch_frame <= 16'd0;
        watch_lvbl_l <= 1'b0;
        cur_vram_dbg <= 8'd0;
        cur_cram_dbg <= 8'd0;
        cur_tile_dbg <= 12'd0;
        cur_heff_dbg <= 8'd0;
        cur_veff_dbg <= 8'd0;
`endif
`ifdef MZONE_POINT_WATCH
        point_frame <= 16'd0;
        point_lvbl_l <= 1'b0;
        point_hdump_s = 9'd0;
        point_vdump_s = 9'd0;
`endif
`ifdef MZONE_ROM_MISS_WATCH
        miss_frame      <= 16'd0;
        miss_lvbl_l     <= 1'b0;
        rom_req_pending <= 1'b0;
        rom_req_ready   <= 1'b0;
        rom_req_addr    <= 12'd0;
        rom_req_hdump   <= 9'd0;
        rom_req_vdump   <= 9'd0;
        rom_req_heff    <= 8'd0;
        rom_req_veff    <= 8'd0;
`endif
    end else begin
`ifdef MZONE_SCROLL_WATCH
        watch_lvbl_l <= watch_lvbl;
        if( !watch_lvbl_l && watch_lvbl )
            watch_frame <= watch_frame + 16'd1;
`endif
`ifdef MZONE_POINT_WATCH
        point_lvbl_l <= point_lvbl;
        if( !point_lvbl_l && point_lvbl )
            point_frame <= point_frame + 16'd1;
`endif
`ifdef MZONE_ROM_MISS_WATCH
        miss_lvbl_l <= miss_lvbl;
        if( !miss_lvbl_l && miss_lvbl )
            miss_frame <= miss_frame + 16'd1;
        if( rom_req_match )
            rom_req_ready <= 1'b1;
`endif
        if( scr_rom_ok && scr_rom_cs ) begin
            rom_data_latch <= scr_rom_data;
            rom_data_valid <= 1'b1;
            scr_rom_cs     <= 1'b0;
        end

        if( pxl_cen ) begin
            if( read_tile )
                ram_addr <= { veff[7:3], heff[7:3] };

            if( fetch_tile ) begin
                scr_rom_addr <= tile_addr;
                scr_rom_cs   <= 1'b1;
                rom_data_valid <= 1'b0;
                pal_msb      <= cram[3:0];
                hflip        <= cram[6] ^ flip;
`ifdef MZONE_ROM_MISS_WATCH
                if( miss_window && rom_req_pending && !rom_ready_now )
                    $display("MZONE_ROM_MISS_OVERWRITE layer=scr frame=%0d req_hdump=%0d req_vdump=%0d req_heff=%02x req_veff=%02x req_addr=%03x new_hdump=%0d new_vdump=%0d new_heff=%02x new_veff=%02x new_addr=%03x",
                        miss_frame, rom_req_hdump, rom_req_vdump, rom_req_heff, rom_req_veff, rom_req_addr,
                        hdump, vdump, heff, veff, tile_addr);
                rom_req_pending <= 1'b1;
                rom_req_ready   <= 1'b0;
                rom_req_addr    <= tile_addr;
                rom_req_hdump   <= hdump;
                rom_req_vdump   <= vdump;
                rom_req_heff    <= heff;
                rom_req_veff    <= veff;
`endif
            end

            if( load_tile ) begin
`ifdef MZONE_ROM_MISS_WATCH
                if( miss_window && rom_req_pending && !rom_ready_now && !rom_load_ready )
                    $display("MZONE_ROM_MISS layer=scr frame=%0d load_hdump=%0d load_vdump=%0d load_heff=%02x load_veff=%02x req_hdump=%0d req_vdump=%0d req_heff=%02x req_veff=%02x req_addr=%03x cur_addr=%03x rom_ok=%b rom_data=%08x",
                        miss_frame, hdump, vdump, heff, veff,
                        rom_req_hdump, rom_req_vdump, rom_req_heff, rom_req_veff,
                        rom_req_addr, scr_rom_addr, scr_rom_ok, scr_rom_data);
                rom_req_pending <= 1'b0;
`endif
                if( rom_load_ready ) begin
                    pxl_data <= rom_decoded_row;
                    cur_pal  <= pal_msb;
                    cur_hf   <= hflip;
                    rom_data_valid <= 1'b0;
                end else begin
                    pxl_data <= 32'd0;
                end
`ifdef MZONE_SCROLL_WATCH
                cur_vram_dbg <= vram;
                cur_cram_dbg <= cram;
                cur_tile_dbg <= tile_addr;
                cur_heff_dbg <= heff;
                cur_veff_dbg <= veff;
`endif
            end else begin
                pxl_data <= cur_hf ? pxl_data >> 4 : pxl_data << 4;
            end

`ifdef MZONE_SHIFT_WATCH
            if( point_frame >= `MZONE_POINT_FRAME0 &&
                point_frame <= `MZONE_POINT_FRAME1 &&
                hdump >= `MZONE_POINT_X0 &&
                hdump <= `MZONE_POINT_X1 &&
                vdump >= `MZONE_POINT_Y0 &&
                vdump <= `MZONE_POINT_Y1 ) begin
                $display("MZONE_SHIFT_PRE frame=%0d hdump=%0d vdump=%0d heff=%02x veff=%02x read=%b fetch=%b load=%b ram_addr=%03x ram_heff=%02x vram=%02x cram=%02x tile=%03x rom_addr=%03x rom_ok=%b rom_data=%08x dec=%08x hflip=%b cur_hf=%b sh=%08x pxl_raw=%x",
                    point_frame, hdump, vdump, heff, veff, read_tile, fetch_tile, load_tile,
                    ram_addr, heff, vram, cram, tile_addr, scr_rom_addr, scr_rom_ok,
                    scr_rom_data, rom_decoded_row, hflip, cur_hf, pxl_data, pxl_raw);
            end
`endif

`ifdef MZONE_SCROLL_WATCH
            if( v_eff >= `MZONE_SCROLL_WATCH_V0 &&
                v_eff <= `MZONE_SCROLL_WATCH_V1 &&
                hdump >= `MZONE_SCROLL_WATCH_X0 &&
                hdump <= `MZONE_SCROLL_WATCH_X1 ) begin
                $display("MZONE_SCROLL frame=%0d hdump=%0d vdump=%0d hcnt=%0d use_fix=%b scrolly=%02x scrollx=%02x ram_addr=%03x heff=%02x veff=%02x read=%b fetch=%b load=%b rom_addr=%03x rom_ok=%b fix_en=%b vram=%02x cram=%02x tile=%03x color=%x out_vram=%02x out_cram=%02x out_tile=%03x out_heff=%02x out_veff=%02x data=%08x dec=%08x sh=%08x pxl_raw=%x pxl=%x",
                    watch_frame, hdump, v_eff, h_eff, 1'b0,
                    scrolly, scrollx, ram_addr, heff, veff,
                    read_tile, fetch_tile, load_tile,
                    scr_rom_addr, scr_rom_ok, 1'b0,
                    vram, cram, tile_addr, color_raw,
                    cur_vram_dbg, cur_cram_dbg, cur_tile_dbg, cur_heff_dbg, cur_veff_dbg,
                    scr_rom_data, rom_decoded_row,
                    pxl_data, pxl_raw, pxl);
            end
`endif
`ifdef MZONE_POINT_WATCH
            if( point_frame >= `MZONE_POINT_FRAME0 &&
                point_frame <= `MZONE_POINT_FRAME1 &&
                hdump >= `MZONE_POINT_X0 &&
                hdump <= `MZONE_POINT_X1 &&
                vdump >= `MZONE_POINT_Y0 &&
                vdump <= `MZONE_POINT_Y1 ) begin
                point_hdump_s = hdump;
                point_vdump_s = vdump;
                $strobe("MZONE_POINT_SCROLL frame=%0d hdump=%0d vdump=%0d h_eff=%02x heff=%02x v_eff=%02x veff=%02x ram_addr=%03x ram_heff=%02x read=%b fetch=%b load=%b rom_cs=%b rom_addr=%03x rom_ok=%b rom_data=%08x vram=%02x cram=%02x tile=%03x pal=%x cur_pal=%x hflip=%b cur_hf=%b sh=%08x pxl_raw=%x pxl=%x",
                    point_frame, point_hdump_s, point_vdump_s, h_eff, heff, v_eff, veff,
                    ram_addr, heff, read_tile, fetch_tile, load_tile,
                    scr_rom_cs, scr_rom_addr, scr_rom_ok, scr_rom_data,
                    vram, cram, tile_addr, pal_msb, cur_pal, hflip, cur_hf,
                    pxl_data, pxl_raw, pxl);
            end
`endif
        end
    end
end

jtframe_dual_ram #(
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
