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

module jtmzone_video(
    input               rst,
    input               clk,
    input               pxl_cen,
    input               pxl2_cen,

    input        [ 7:0] scrolly,
    input        [ 7:0] scrollx,
    input               flip,

    input        [ 7:0] prog_data,
    input        [21:0] prog_addr,
    input               prom_we,

    output       [ 9:0] video_ram_addr,
    input        [ 7:0] video_vram0,
    input        [ 7:0] video_vram1,
    input        [ 7:0] video_cram0,
    input        [ 7:0] video_cram1,

    output       [11:0] scr_addr,
    output              scr_cs,
    input        [31:0] scr_data,
    input               scr_ok,

    output              HS,
    output              VS,
    output              LHBL,
    output              LVBL,
    output       [ 3:0] red,
    output       [ 3:0] green,
    output       [ 3:0] blue,

    output              clkq_cen,
    output              h2,
    output              thblk_n,
    output              thblk_delayed_n,
    output       [ 8:0] hdump,
    output       [ 8:0] vdump,
    output       [ 8:0] vrender
);

wire        hinit;
wire        pre_lhbl, pre_hs;
wire        pre_lhbl_vtimer, pre_hs_vtimer;
wire [ 8:0] pre_hdump;
wire [ 8:0] pre_hdump_vtimer;
wire [ 8:0] pre_hcnt_sim;
wire        pre_hsync_n;
wire        pre_thblk_n;
wire        clkq, clkq_n;
wire        h1, h4;
wire        active;
wire        rst_unused, pxl2_cen_unused;
wire        thblk;
wire [ 8:0] scr_x_sum, scr_y_sum;
wire [ 7:0] scr_x, scr_y, pat_x, pat_y;
wire [ 8:0] render_x, render_y, fixed_x;
wire [ 7:0] fixed_y;
wire [ 5:0] fixed_tile_x, fixed_addr_x_full;
wire [ 4:0] scroll_tile_x, scroll_tile_y, fixed_addr_x, fixed_addr_y;
wire [ 2:0] scroll_tile_px, scroll_tile_py, fixed_tile_px, fixed_tile_py;
wire [ 9:0] scroll_ram_addr, fixed_ram_addr;
wire        fixed_area;
wire [ 2:0] tile_px, tile_py, fetch_phase;
wire [ 2:0] gfx_px, gfx_py;
wire [ 7:0] tile_code, tile_attr;
wire [ 3:0] tile_pen, tile_color;
wire [31:0] decoded_row;
wire [ 7:0] pal_prom_dout;
wire [ 3:0] char_lut_dout;
wire [ 4:0] pal_idx;
wire [ 3:0] red_raw, green_raw, blue_raw;
wire       pal_we, char_lut_we;
reg         h1_l, h4_l;
reg         thblk_h1_q, thblk_h4_q;
reg  [11:0] scr_addr_l;
reg  [31:0] pxl_data;
reg  [ 3:0] cur_color;
reg         cur_hflip;

localparam [21:0] PAL_OFFSET = `ifdef JTFRAME_PROM_START `JTFRAME_PROM_START + 22'h000 `else 22'h000 `endif;
localparam [21:0] CHR_OFFSET = `ifdef JTFRAME_PROM_START `JTFRAME_PROM_START + 22'h120 `else 22'h120 `endif;
localparam [ 8:0] HPHASE = 9'd0;
localparam [ 8:0] VPHASE = 9'd0;

assign LHBL   = pre_lhbl;
assign HS     = pre_hs;
assign hdump  = pre_hdump;
assign active = pre_lhbl & LVBL;
assign thblk_n = pre_thblk_n;
assign thblk_delayed_n = ~thblk_h4_q;

assign thblk = ~pre_thblk_n;
assign render_x  = hdump + HPHASE;
assign render_y  = vrender + VPHASE;
assign scr_x_sum = {1'b0, render_x[7:0]} + {1'b0, scrollx};
assign scr_y_sum = {1'b0, render_y[7:0]} + {1'b0, scrolly};
assign scr_x = scr_x_sum[7:0];
assign scr_y = scr_y_sum[7:0];
assign pat_x = flip ? ~scr_x : scr_x;
assign pat_y = flip ? ~scr_y : scr_y;
assign scroll_tile_x  = pat_x[7:3];
assign scroll_tile_y  = pat_y[7:3];
assign scroll_tile_px = pat_x[2:0];
assign scroll_tile_py = pat_y[2:0];
assign scroll_ram_addr = { scroll_tile_y, scroll_tile_x };

assign fixed_x      = render_x;
assign fixed_y      = render_y[7:0];
assign fixed_tile_x = fixed_x[8:3];
assign fixed_addr_x_full = flip ? 6'd35-fixed_tile_x : fixed_tile_x;
assign fixed_addr_x = fixed_addr_x_full[4:0];
assign fixed_addr_y = flip ? ~fixed_y[7:3] : fixed_y[7:3];
assign fixed_tile_px = flip ? ~fixed_x[2:0] : fixed_x[2:0];
assign fixed_tile_py = flip ? ~fixed_y[2:0] : fixed_y[2:0];
assign fixed_area    = flip ? fixed_tile_x >= 6'd30 : fixed_tile_x < 6'd6;
assign fixed_ram_addr = { fixed_addr_y, fixed_addr_x };

assign video_ram_addr = fixed_area ? fixed_ram_addr : scroll_ram_addr;
assign tile_px = fixed_area ? fixed_tile_px : scroll_tile_px;
assign tile_py = fixed_area ? fixed_tile_py : scroll_tile_py;
assign fetch_phase = render_x[2:0];
assign tile_code = fixed_area ? video_vram1 : video_vram0;
assign tile_attr = fixed_area ? video_cram1 : video_cram0;
assign gfx_px = tile_px ^ {3{tile_attr[6]}};
assign gfx_py = tile_py ^ {3{tile_attr[5]}};
assign scr_addr = scr_addr_l;
assign scr_cs   = active;
assign decoded_row = {
    { scr_data[4],  scr_data[5],  scr_data[6],  scr_data[7]  },
    { scr_data[0],  scr_data[1],  scr_data[2],  scr_data[3]  },
    { scr_data[12], scr_data[13], scr_data[14], scr_data[15] },
    { scr_data[8],  scr_data[9],  scr_data[10], scr_data[11] },
    { scr_data[20], scr_data[21], scr_data[22], scr_data[23] },
    { scr_data[16], scr_data[17], scr_data[18], scr_data[19] },
    { scr_data[28], scr_data[29], scr_data[30], scr_data[31] },
    { scr_data[24], scr_data[25], scr_data[26], scr_data[27] }
};
assign tile_pen   = cur_hflip ? pxl_data[3:0] : pxl_data[31:28];
assign tile_color = cur_color;
assign pal_idx    = { 1'b1, char_lut_dout };
assign red_raw    = {4{pal_prom_dout[0]}} & 4'h2 |
                    {4{pal_prom_dout[1]}} & 4'h5 |
                    {4{pal_prom_dout[2]}} & 4'h8;
assign green_raw  = {4{pal_prom_dout[3]}} & 4'h2 |
                    {4{pal_prom_dout[4]}} & 4'h5 |
                    {4{pal_prom_dout[5]}} & 4'h8;
assign blue_raw   = {4{pal_prom_dout[6]}} & 4'h6 |
                    {4{pal_prom_dout[7]}} & 4'h9;

assign red   = active ? red_raw   : 4'h0;
assign green = active ? green_raw : 4'h0;
assign blue  = active ? blue_raw  : 4'h0;

assign pxl2_cen_unused = pxl2_cen;
assign rst_unused      = rst;
assign pal_we          = prom_we && prog_addr >= PAL_OFFSET && prog_addr < PAL_OFFSET+22'h20;
assign char_lut_we     = prom_we && prog_addr >= CHR_OFFSET && prog_addr < CHR_OFFSET+22'h100;

always @(posedge clk) begin
    if( rst ) begin
        h1_l       <= 1'b0;
        h4_l       <= 1'b0;
        thblk_h1_q <= 1'b0;
        thblk_h4_q <= 1'b0;
        scr_addr_l <= 12'd0;
        pxl_data   <= 32'd0;
        cur_color  <= 4'd0;
        cur_hflip  <= 1'b0;
    end else if( pxl_cen ) begin
        if( fetch_phase==3'd0 ) begin
            scr_addr_l <= { tile_attr[7], tile_code, gfx_py };
        end
        if( fetch_phase==3'd4 ) begin
            pxl_data  <= decoded_row;
            cur_color <= tile_attr[3:0];
            cur_hflip <= tile_attr[6];
        end else begin
            pxl_data <= cur_hflip ? pxl_data >> 4 : pxl_data << 4;
        end
        if( h1 && !h1_l ) thblk_h1_q <= thblk;
        if( h4 && !h4_l ) thblk_h4_q <= thblk_h1_q;
        h1_l <= h1;
        h4_l <= h4;
    end
end

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
    .rd_addr( pal_idx          ),
    .q      ( pal_prom_dout    )
);

jtframe_prom #(
    .DW ( 4 ),
    .AW ( 8 ),
    .ASYNC( 1 )
) u_char_lut(
    .clk    ( clk                    ),
    .cen    ( pxl_cen                ),
    .data   ( prog_data[3:0]         ),
    .wr_addr( prog_addr[7:0] - CHR_OFFSET[7:0] ),
    .we     ( char_lut_we            ),
    .rd_addr( { tile_color, tile_pen } ),
    .q      ( char_lut_dout          )
);

jtframe_vtimer #(
    .VB_START   ( 9'd239 ),
    .VB_END     ( 9'd015 ),
    .VCNT_END   ( 9'd263 ),
    .VS_START   ( 9'd260 ),
    .HB_END     ( 9'd257 ), // Is one more needed?
    .HB_START   ( 9'd161 ),
    .HCNT_END   ( 9'd383 ),
    .HS_START   ( 9'd193 ),
    .HS_END     ( 9'd224 )
) u_vtimer(
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .vdump      ( vdump     ),
    .vrender    ( vrender   ),
    .vrender1   (           ),
    .H          ( pre_hdump_vtimer ),
    .Hinit      ( hinit     ),
    .Vinit      (           ),
    .LHBL       ( pre_lhbl_vtimer ),
    .LVBL       ( LVBL      ),
    .HS         ( pre_hs_vtimer ),
    .VS         ( VS        )
);

`ifdef JTMZONE_SCH_HCNT
jtmzone_hcnt u_hcnt(
    .rst        ( rst              ),
    .clk        ( clk              ),
    .pxl_cen    ( pxl_cen          ),
    .flip       ( flip             ),
    .prog_data  ( prog_data        ),
    .prog_addr  ( prog_addr        ),
    .prom_we    ( prom_we          ),
    .hdump      ( pre_hdump        ),
    .hcnt_sim   ( pre_hcnt_sim     ),
    .hinit      (                  ),
    .LHBL       ( pre_lhbl         ),
    .HS         ( pre_hs           ),
    .h1         ( h1               ),
    .h2         ( h2               ),
    .h4         ( h4               ),
    .h8         (                  ),
    .h16        (                  ),
    .h16_n      (                  ),
    .clkq       ( clkq             ),
    .clkq_n     ( clkq_n           ),
    .clkq_cen   ( clkq_cen         ),
    .hblank_n   (                  ),
    .thblk_n    ( pre_thblk_n      ),
    .hsync_n    ( pre_hsync_n      ),
    .e9_q       (                  )
);
`else
assign pre_hdump = pre_hdump_vtimer;
assign pre_lhbl  = pre_lhbl_vtimer;
assign pre_hs    = pre_hs_vtimer;
assign clkq_cen  = 1'b0;
assign h1        = pre_hdump_vtimer[0];
assign h2        = pre_hdump_vtimer[1];
assign h4        = pre_hdump_vtimer[2];
assign pre_thblk_n = ~(pre_hdump_vtimer >= 9'd113 && pre_hdump_vtimer < 9'd241);
`endif

endmodule
