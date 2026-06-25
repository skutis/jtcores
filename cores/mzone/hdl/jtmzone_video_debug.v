/*  This file is part of JTCORES.
    JTCORES program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version. */

module jtmzone_video_debug(
    input               rst,
    input               clk,
    input               pxl_cen,
    input               LHBL,
    input               LVBL,
    input               flip,
    input        [ 3:0] red_in,
    input        [ 3:0] green_in,
    input        [ 3:0] blue_in,
    output       [ 3:0] red,
    output       [ 3:0] green,
    output       [ 3:0] blue
);

localparam [8:0] FIX_WIDTH = 9'd48;
localparam [8:0] HVISIBLE  = 9'd288;

wire        marker_yellow;
wire        marker_green_ref, marker_blue_ref, marker_black_ref;
wire        fix_ref_green, fix_ref_blue, fix_ref_black;
wire        fix_only_blank, scroll_only_blank;
wire [ 8:0] fix_ref_x0, fix_ref_x1;

reg         dbg_active_l;
reg  [ 8:0] dbg_img_x;
reg  [ 7:0] dbg_img_y;

`ifdef MZONE_SCROLL_MARKER
reg         marker_lvbl_l;
reg  [ 9:0] marker_frame;
reg  [ 1:0] marker_yellow_dly;
wire [ 7:0] marker_step;
wire [ 7:0] marker_x;
wire [ 7:0] marker_y;
wire [ 7:0] marker_dx;
wire [ 7:0] marker_dy;
wire [ 2:0] marker_rom_x;
wire [ 2:0] marker_rom_y;
wire        marker_run;
wire        marker_char_1;
wire        marker_yellow_now;
`endif

assign fix_only_blank = `ifdef MZONE_FIX_ONLY dbg_img_x >= FIX_WIDTH `else 1'b0 `endif;
assign scroll_only_blank = `ifdef MZONE_SCROLL_ONLY dbg_img_x < FIX_WIDTH `else 1'b0 `endif;
assign marker_green_ref = 1'b0;
assign marker_blue_ref  = 1'b0;
assign marker_black_ref = 1'b0;
assign fix_ref_x0 = flip ? HVISIBLE-FIX_WIDTH-9'd2 : FIX_WIDTH-9'd2;
assign fix_ref_x1 = flip ? HVISIBLE-FIX_WIDTH-9'd1 : FIX_WIDTH-9'd1;
`ifdef MZONE_NO_BOUNDARY_MARKERS
assign fix_ref_green = 1'b0;
assign fix_ref_blue  = 1'b0;
`else
assign fix_ref_green = dbg_img_y == 8'd0 && dbg_img_x == fix_ref_x0;
assign fix_ref_blue  = dbg_img_y == 8'd0 && dbg_img_x == fix_ref_x1;
`endif
assign fix_ref_black = 1'b0;
`ifdef MZONE_SCROLL_MARKER
assign marker_run = marker_frame >= 10'd2;
assign marker_step = marker_run ? marker_frame[7:0] - 8'd2 : 8'd0;
`ifdef MZONE_SCROLL_MARKER_X
assign marker_x = `MZONE_SCROLL_MARKER_X + marker_step;
`else
assign marker_x = 8'd64 + marker_step;
`endif
`ifdef MZONE_SCROLL_MARKER_Y
assign marker_y = `MZONE_SCROLL_MARKER_Y;
`else
assign marker_y = 8'd96;
`endif
assign marker_dx = dbg_img_x[7:0] - marker_x;
assign marker_dy = dbg_img_y - marker_y;
assign marker_rom_x = 3'd7 - marker_dy[2:0];
assign marker_rom_y = marker_dx[2:0];
assign marker_char_1 = (marker_rom_y == 3'd3 && marker_rom_x <= 3'd6) ||
                       (marker_rom_y == 3'd4 && marker_rom_x <= 3'd6) ||
                       (marker_rom_y == 3'd5 && marker_rom_x == 3'd0);
assign marker_yellow_now = marker_run &&
                           dbg_img_x >= FIX_WIDTH &&
                           marker_dx < 8'd8 &&
                           marker_dy < 8'd8 &&
                           marker_char_1;
assign marker_yellow = marker_yellow_dly[1];
`else
assign marker_yellow = 1'b0;
`endif

assign red   = marker_yellow ? 4'hf :
               fix_ref_green || fix_ref_blue || fix_ref_black ||
               marker_green_ref || marker_blue_ref || marker_black_ref ? 4'h0 :
               scroll_only_blank || fix_only_blank ? 4'h0 : red_in;
assign green = marker_yellow || fix_ref_green || marker_green_ref ? 4'hf :
               fix_ref_blue || fix_ref_black || marker_blue_ref || marker_black_ref ? 4'h0 :
               scroll_only_blank || fix_only_blank ? 4'h0 : green_in;
assign blue  = fix_ref_blue || marker_blue_ref ? 4'hf :
               marker_yellow || fix_ref_green || fix_ref_black ||
               marker_green_ref || marker_black_ref ? 4'h0 :
               scroll_only_blank || fix_only_blank ? 4'h0 : blue_in;

always @(posedge clk) begin
    if( rst ) begin
        dbg_active_l <= 1'b0;
        dbg_img_x <= 9'd0;
        dbg_img_y <= 8'd0;
`ifdef MZONE_SCROLL_MARKER
        marker_lvbl_l <= 1'b0;
        marker_frame <= 10'd0;
        marker_yellow_dly <= 2'd0;
`endif
    end else if( pxl_cen ) begin
        dbg_active_l <= LHBL && LVBL;
        if( !LVBL ) begin
            dbg_img_x <= 9'd0;
            dbg_img_y <= 8'd0;
        end else if( LHBL ) begin
            dbg_img_x <= dbg_active_l ? dbg_img_x + 9'd1 : 9'd0;
        end else begin
            dbg_img_x <= 9'd0;
            if( dbg_active_l ) dbg_img_y <= dbg_img_y + 8'd1;
        end

`ifdef MZONE_SCROLL_MARKER
        marker_lvbl_l <= LVBL;
        if( LVBL && !marker_lvbl_l ) marker_frame <= marker_frame + 10'd1;
        marker_yellow_dly <= { marker_yellow_dly[0], marker_yellow_now };
`endif
    end
end

endmodule
