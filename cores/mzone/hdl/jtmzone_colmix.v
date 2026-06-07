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

wire [ 7:0] pal_prom_dout;
wire [ 7:0] pal_addr;
wire [ 3:0] red_raw, green_raw, blue_raw;
wire [11:0] raw, rgb;
wire        pal_we;
wire [ 3:0] red_blank, green_blank, blue_blank;
wire        obj_en = !fix_en && obj_pxl_en;
wire        pal_a4 = !obj_en;
wire [ 3:0] scr_gated = scr_pxl;
wire [ 4:0] pal_mux = { pal_a4, obj_en ? obj_pxl : scr_gated };

`ifdef MZONE_COLMIX_WATCH
reg  [15:0] frame_cnt;
reg         lvbl_l;
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

jtmzone_video_debug u_debug(
    .rst        ( rst         ),
    .clk        ( clk         ),
    .pxl_cen    ( pxl_cen     ),
    .LHBL       ( LHBL_dly    ),
    .LVBL       ( LVBL_dly    ),
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
    end else if( pxl_cen ) begin
`ifdef MZONE_COLMIX_WATCH
        lvbl_l <= LVBL;
        if( LVBL && !lvbl_l ) frame_cnt <= frame_cnt + 16'd1;
`endif
`ifdef MZONE_COLMIX_WATCH
        if( frame_cnt >= `MZONE_COLMIX_WATCH_FROM && frame_cnt <= `MZONE_COLMIX_WATCH_TO &&
            hdump >= `MZONE_COLMIX_X0 && hdump <= `MZONE_COLMIX_X1 &&
            vdump >= `MZONE_COLMIX_Y0 && vdump <= `MZONE_COLMIX_Y1 ) begin
            $display("MZONE_COLMIX frame=%0d x=%0d y=%0d obj_en=%b obj=%b fix=%b obj_pxl=%x scr_pxl=%x pal_mux=%02x prom=%02x rgb=%x%x%x",
                frame_cnt, hdump, vdump, obj_en, obj_pxl_en, fix_en, obj_pxl, scr_pxl,
                pal_mux, pal_prom_dout, red_raw, green_raw, blue_raw);
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
