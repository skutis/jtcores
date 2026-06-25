/*  This file is part of JTCORES.
    JTCORES program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JTCORES program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JTCORES.  If not, see <http://www.gnu.org/licenses/>. */

module jtmzone_colmix(
    input               rst,
    input               clk,
    input               pxl_cen,

    input         [3:0] scr_pxl,
    input         [3:0] obj_pxl,
    input               obj_pxl_en,
    input               fix_en,
    input               flip,
    input               LHBL,
    input               LVBL,
    input         [8:0] hdump,
    input         [8:0] vdump,

    input         [7:0] prog_data,
    input        [21:0] prog_addr,
    input               prom_we,

    output        [3:0] red,
    output        [3:0] green,
    output        [3:0] blue,
    output              LHBL_dly,
    output              LVBL_dly,
    output              preLBL,
    output        [4:0] dbg_pal_idx,
    output              dbg_obj_opaque
);

localparam [21:0] PAL_OFFSET = `ifdef JTFRAME_PROM_START `JTFRAME_PROM_START + 22'h000 `else 22'h000 `endif;
localparam        BLANK_DLY  = 9;
localparam        CHAR_DLY   = 3;

wire [ 7:0] pal_prom_dout;
wire [ 7:0] pal_addr;
wire [ 3:0] red_raw, green_raw, blue_raw;
wire [11:0] raw, rgb;
wire        pal_we;
wire [ 3:0] red_blank, green_blank, blue_blank;
wire [ 3:0] char_pxl_dly;
wire        fix_en_dly;
wire        obj_en = obj_pxl_en && !fix_en_dly;
wire        pal_a4 = !obj_en;
wire [ 3:0] char_pxl = char_pxl_dly;
wire [ 4:0] pal_mux = { pal_a4, obj_en ? obj_pxl : char_pxl };
wire [17:0] rgb_pos_dly;
wire [17:0] char_pos_dly;
wire [17:0] raw_pos_dly;
wire [ 8:0] hdump_debug = hdump;
wire [ 8:0] vdump_debug = vdump;
wire [ 8:0] rgb_hdump_debug = rgb_pos_dly[17:9];
wire [ 8:0] rgb_vdump_debug = rgb_pos_dly[8:0];
wire [ 8:0] char_hdump_debug = char_pos_dly[17:9];
wire [ 8:0] char_vdump_debug = char_pos_dly[8:0];
wire [ 8:0] raw_hdump_debug = raw_pos_dly[17:9];
wire [ 8:0] raw_vdump_debug = raw_pos_dly[8:0];

`ifdef MZONE_COLMIX_WATCH
reg  [15:0] frame_cnt;
reg         lvbl_l;
`endif
`ifdef MZONE_POINT_WATCH
reg  [15:0] point_frame;
reg         point_lvbl_l;
reg  [ 8:0] point_hdump_s;
reg  [ 8:0] point_vdump_s;
reg  [ 8:0] point_hdump_debug_s;
reg  [ 8:0] point_vdump_debug_s;
reg  [ 8:0] point_rgb_hdump_debug_s;
reg  [ 8:0] point_rgb_vdump_debug_s;
reg  [ 8:0] point_raw_hdump_debug_s;
reg  [ 8:0] point_raw_vdump_debug_s;
reg  [ 8:0] point_char_hdump_debug_s;
reg  [ 8:0] point_char_vdump_debug_s;
`endif

assign pal_addr = { 3'd0, pal_mux };
assign dbg_pal_idx = pal_mux;
assign dbg_obj_opaque = !pal_mux[4];
assign red_raw   = rg_dac( pal_prom_dout[2:0] );
assign green_raw = rg_dac( pal_prom_dout[5:3] );
assign blue_raw  = b_dac ( pal_prom_dout[7:6] );

assign pal_we = prom_we && prog_addr >= PAL_OFFSET && prog_addr < PAL_OFFSET+22'h20;

assign raw = { red_raw, green_raw, blue_raw };
assign { red_blank, green_blank, blue_blank } = rgb;

jtframe_prom #(
    .DW ( 8 ),
    .AW ( 5 ),
    .ASYNC( 1 )
) u_pal_prom(
    .clk    ( clk              ),
    .cen    ( pxl_cen          ),
    .data   ( prog_data        ),
    .wr_addr( prog_addr[4:0]   ),
    .we     ( pal_we           ),
    .rd_addr( pal_addr[4:0]   ),
    .q      ( pal_prom_dout    )
);

jtframe_sh #(.W(4),.L(CHAR_DLY)) u_char_pxl_dly(
    .clk    ( clk         ),
    .clk_en ( pxl_cen     ),
    .din    ( scr_pxl     ),
    .drop   ( char_pxl_dly )
);

jtframe_sh #(.W(18),.L(CHAR_DLY)) u_raw_pos_dly(
    .clk    ( clk             ),
    .clk_en ( pxl_cen         ),
    .din    ( { hdump, vdump } ),
    .drop   ( raw_pos_dly     )
);

jtframe_sh #(.W(18),.L(CHAR_DLY+BLANK_DLY)) u_char_pos_dly(
    .clk    ( clk             ),
    .clk_en ( pxl_cen         ),
    .din    ( { hdump, vdump } ),
    .drop   ( char_pos_dly    )
);

jtframe_sh #(.W(1),.L(CHAR_DLY)) u_fix_en_dly(
    .clk    ( clk        ),
    .clk_en ( pxl_cen    ),
    .din    ( fix_en     ),
    .drop   ( fix_en_dly )
);

jtframe_blank #(.DLY(BLANK_DLY),.DW(12)) u_blank(
    .clk        ( clk      ),
    .pxl_cen    ( pxl_cen  ),
    .preLHBL    ( LHBL     ),
    .preLVBL    ( LVBL     ),
    .LHBL       ( LHBL_dly ),
    .LVBL       ( LVBL_dly ),
    .preLBL     ( preLBL   ),
    .rgb_in     ( raw      ),
    .rgb_out    ( rgb      )
);

jtframe_sh #(.W(18),.L(BLANK_DLY)) u_rgb_pos_dly(
    .clk    ( clk             ),
    .clk_en ( pxl_cen         ),
    .din    ( { hdump, vdump } ),
    .drop   ( rgb_pos_dly     )
);

jtmzone_video_debug u_debug(
    .rst        ( rst         ),
    .clk        ( clk         ),
    .pxl_cen    ( pxl_cen     ),
    .LHBL       ( LHBL_dly    ),
    .LVBL       ( LVBL_dly    ),
    .flip       ( flip        ),
    .red_in     ( red_blank   ),
    .green_in   ( green_blank ),
    .blue_in    ( blue_blank  ),
    .red        ( red         ),
    .green      ( green       ),
    .blue       ( blue        )
);

always @(posedge clk) begin
    if( rst ) begin
`ifdef MZONE_COLMIX_WATCH
        frame_cnt <= 16'd0;
        lvbl_l    <= 1'b0;
`endif
`ifdef MZONE_POINT_WATCH
        point_frame  <= 16'd0;
        point_lvbl_l <= 1'b0;
        point_hdump_s = 9'd0;
        point_vdump_s = 9'd0;
        point_hdump_debug_s = 9'd0;
        point_vdump_debug_s = 9'd0;
        point_rgb_hdump_debug_s = 9'd0;
        point_rgb_vdump_debug_s = 9'd0;
        point_raw_hdump_debug_s = 9'd0;
        point_raw_vdump_debug_s = 9'd0;
        point_char_hdump_debug_s = 9'd0;
        point_char_vdump_debug_s = 9'd0;
`endif
    end else if( pxl_cen ) begin
`ifdef MZONE_COLMIX_WATCH
        lvbl_l <= LVBL;
        if( LVBL && !lvbl_l ) frame_cnt <= frame_cnt + 16'd1;
`endif
`ifdef MZONE_POINT_WATCH
        point_lvbl_l <= LVBL;
        if( LVBL && !point_lvbl_l ) point_frame <= point_frame + 16'd1;
`endif
`ifdef MZONE_COLMIX_WATCH
        if( frame_cnt >= `MZONE_COLMIX_WATCH_FROM && frame_cnt <= `MZONE_COLMIX_WATCH_TO &&
            hdump >= `MZONE_COLMIX_X0 && hdump <= `MZONE_COLMIX_X1 &&
            vdump >= `MZONE_COLMIX_Y0 && vdump <= `MZONE_COLMIX_Y1 ) begin
            $display("MZONE_COLMIX frame=%0d x=%0d y=%0d obj_en=%b obj=%b fix=%b obj_pxl=%x char_in=%x char_pxl=%x pal_mux=%02x prom=%02x rgb=%x%x%x",
                frame_cnt, hdump, vdump, obj_en, obj_pxl_en, fix_en_dly, obj_pxl, scr_pxl, char_pxl_dly,
                pal_mux, pal_prom_dout, red_raw, green_raw, blue_raw);
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
            point_hdump_debug_s = hdump_debug;
            point_vdump_debug_s = vdump_debug;
            point_rgb_hdump_debug_s = rgb_hdump_debug;
            point_rgb_vdump_debug_s = rgb_vdump_debug;
            point_raw_hdump_debug_s = raw_hdump_debug;
            point_raw_vdump_debug_s = raw_vdump_debug;
            point_char_hdump_debug_s = char_hdump_debug;
            point_char_vdump_debug_s = char_vdump_debug;
            $strobe("MZONE_POINT_COLMIX frame=%0d hdump=%0d vdump=%0d hdump_debug=%0d vdump_debug=%0d rgb_hdump_debug=%0d rgb_vdump_debug=%0d raw_hdump_debug=%0d raw_vdump_debug=%0d char_hdump_debug=%0d char_vdump_debug=%0d obj_en=%b obj_pxl_en=%b fix_en=%b fix_en_dly=%b obj_pxl=%x char_in=%x char_dly=%x pal_mux=%02x prom=%02x raw=%x%x%x blank=%x%x%x rgb=%x%x%x LHBL=%b LVBL=%b LHBL_dly=%b LVBL_dly=%b",
                point_frame, point_hdump_s, point_vdump_s,
                point_hdump_debug_s, point_vdump_debug_s,
                point_rgb_hdump_debug_s, point_rgb_vdump_debug_s,
                point_raw_hdump_debug_s, point_raw_vdump_debug_s,
                point_char_hdump_debug_s, point_char_vdump_debug_s,
                obj_en, obj_pxl_en, fix_en,
                fix_en_dly, obj_pxl, scr_pxl, char_pxl_dly, pal_mux,
                pal_prom_dout, red_raw, green_raw, blue_raw,
                red_blank, green_blank, blue_blank, red, green, blue,
                LHBL, LVBL, LHBL_dly, LVBL_dly);
        end
`endif
    end
end

function [3:0] rg_dac;
    input [2:0] bits;
begin
    case( bits )
        3'b000: rg_dac = 4'h0;
        3'b001: rg_dac = 4'h2;
        3'b010: rg_dac = 4'h4;
        3'b011: rg_dac = 4'h6;
        3'b100: rg_dac = 4'h9;
        3'b101: rg_dac = 4'hb;
        3'b110: rg_dac = 4'hd;
        default: rg_dac = 4'hf;
    endcase
end
endfunction

function [3:0] b_dac;
    input [1:0] bits;
begin
    case( bits )
        2'b00: b_dac = 4'h0;
        2'b01: b_dac = 4'h5;
        2'b10: b_dac = 4'ha;
        default: b_dac = 4'hf;
    endcase
end
endfunction

endmodule
