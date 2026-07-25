/*  This file is part of JTCORES.
    JTCORES program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version. */

module jtmzone_video(
    input               rst,
    input               clk,
    input               clk24,
    input               pxl_cen,
    input               pxl2_cen,

    input        [ 9:0] main_tile_addr,
    input        [ 7:0] main_vram_din,
    input               main_cpu_rnw,
    input               main_vram0_cs,
    input               main_vram1_cs,
    input               main_cram0_cs,
    input               main_cram1_cs,
    output       [ 7:0] main_vram0_dout,
    output       [ 7:0] main_vram1_dout,
    output       [ 7:0] main_cram0_dout,
    output       [ 7:0] main_cram1_dout,

    input        [ 7:0] scrolly,
    input        [ 7:0] scrollx,
    input               flip,

    input        [ 7:0] prog_data,
    input        [21:0] prog_addr,
    input               prom_we,

    output       [11:0] fixrom_addr,
    output              fixrom_cs,
    input        [31:0] fixrom_data,
    input               fixrom_ok,

    output       [11:0] scrrom_addr,
    output              scrrom_cs,
    input        [31:0] scrrom_data,
    input               scrrom_ok,

    output       [ 9:0] oram_addr,
    input        [ 7:0] oram_dout,
    output       [12:0] obj_addr,
    output              obj_cs,
    input        [31:0] obj_data,
    input               obj_ok,

    output              HS,
    output              VS,
    output              LHBL,
    output              LVBL,
    output              pre_LVBL,
    output       [ 3:0] red,
    output       [ 3:0] green,
    output       [ 3:0] blue,

    output              clkq_cen,
    output              h2,
    output              fix_en,
    output       [ 8:0] hdump,
    output       [ 8:0] vdump,
    output       [ 8:0] vrender
);

localparam [8:0] HVISIBLE = 9'd288;
localparam [8:0] HTOTAL   = 9'd384;
localparam [8:0] HB_END   = HTOTAL-9'd1;
localparam [8:0] HB_START = HVISIBLE-9'd1;
localparam [8:0] HS_START = 9'd319;
localparam [8:0] HS_END   = 9'd351;
localparam [8:0] H_VB     = H_VNEXT;
localparam [8:0] H_VNEXT  = HTOTAL-9'd9;
localparam [8:0] VB_START = 9'd240;
localparam [8:0] VB_END   = 9'd015;
localparam [8:0] VVISIBLE = 9'd016;
localparam [8:0] VS_START = 9'd256;
localparam [8:0] VS_END   = 9'd000;
localparam [8:0] VCNT_END = 9'd263;
localparam [21:0] OBJ_OFFSET = `ifdef JTFRAME_PROM_START `JTFRAME_PROM_START + 22'h020 `else 22'h020 `endif;
localparam [21:0] CHR_OFFSET = `ifdef JTFRAME_PROM_START `JTFRAME_PROM_START + 22'h120 `else 22'h120 `endif;

wire        pre_lhbl, pre_lvbl, vt_lvbl, pre_hs, vt_vs;
reg         pcb_vs;
wire [ 7:0] hcnt;
wire [ 8:0] tile_dbg_hcnt;
wire [11:0] tile_dbg_rom_addr;
wire        tile_dbg_fix;
wire [ 7:0] tile_dbg_scr_x, tile_dbg_pat_x, tile_dbg_scr_y, tile_dbg_pat_y;
wire [ 3:0] scr_pxl;
wire [ 3:0] fix_pxl;
wire [ 3:0] char_pxl;
wire [ 3:0] obj_pxl;
wire        pxl2_cen_unused = pxl2_cen;
wire        obj_lut_we, char_lut_we;
wire        dbg_show_fix;
wire        dbg_show_scroll;
wire        dbg_show_obj;
wire [ 3:0] dbg_fix_pxl;
wire [ 3:0] dbg_scr_pxl;
wire [ 3:0] dbg_obj_pxl;
wire        show_fix_en;

assign obj_lut_we = prom_we && prog_addr >= OBJ_OFFSET && prog_addr < OBJ_OFFSET+22'h100;
assign char_lut_we = prom_we && prog_addr >= CHR_OFFSET && prog_addr < CHR_OFFSET+22'h100;

assign HS     = pre_hs;
assign VS     = pcb_vs;
assign pre_lvbl = vdump >= VVISIBLE && vdump < VB_START;
assign pre_LVBL = pre_lvbl;

assign h2 = hcnt[1];
assign clkq_cen = 1'b0;

assign hcnt     = pcb_hcnt(hdump, flip);
`ifdef MZONE_ONLY_FIX
assign dbg_show_fix    = 1'b1;
assign dbg_show_scroll = 1'b0;
assign dbg_show_obj    = 1'b0;
`elsif MZONE_ONLY_SCROLL
assign dbg_show_fix    = 1'b0;
assign dbg_show_scroll = 1'b1;
assign dbg_show_obj    = 1'b0;
`elsif MZONE_ONLY_OBJ
assign dbg_show_fix    = 1'b0;
assign dbg_show_scroll = 1'b0;
assign dbg_show_obj    = 1'b1;
`else
assign dbg_show_fix =
`ifdef MZONE_HIDE_FIX
    1'b0;
`else
    1'b1;
`endif
assign dbg_show_scroll =
`ifdef MZONE_HIDE_SCROLL
    1'b0;
`else
    1'b1;
`endif
assign dbg_show_obj =
`ifdef MZONE_HIDE_OBJ
    1'b0;
`else
    1'b1;
`endif
`endif
assign dbg_fix_pxl    = dbg_show_fix    ? fix_pxl : 4'd0;
assign dbg_scr_pxl    = dbg_show_scroll ? scr_pxl : 4'd0;
assign dbg_obj_pxl    = dbg_show_obj    ? obj_pxl : 4'd0;
assign show_fix_en    = dbg_show_fix && fix_en;
`ifdef MZONE_ONLY_FIX
assign char_pxl       = dbg_fix_pxl;
`else
assign char_pxl       = show_fix_en ? dbg_fix_pxl : dbg_scr_pxl;
`endif

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

jtmzone_scroll u_scroll(
    .rst        ( rst             ),
    .clk        ( clk             ),
    .clk24      ( clk24           ),
    .pxl_cen    ( pxl_cen         ),
    .cpu_addr   ( main_tile_addr ),
    .cpu_dout   ( main_vram_din   ),
    .cpu_rnw    ( main_cpu_rnw    ),
    .vram_cs    ( main_vram0_cs   ),
    .cram_cs    ( main_cram0_cs   ),
    .vram_dout  ( main_vram0_dout ),
    .cram_dout  ( main_cram0_dout ),
    .hdump      ( hdump           ),
    .vdump      ( vdump           ),
    .scrollx    ( scrollx         ),
    .scrolly    ( scrolly         ),
    .flip       ( flip            ),
    .prog_data  ( prog_data[3:0]  ),
    .prog_addr  ( prog_addr[7:0] - CHR_OFFSET[7:0] ),
    .prog_en    ( char_lut_we     ),
    .scr_rom_data( scrrom_data    ),
    .scr_rom_ok  ( scrrom_ok      ),
    .scr_rom_addr( scrrom_addr    ),
    .scr_rom_cs  ( scrrom_cs      ),
    .pxl        ( scr_pxl         ),
    .dbg_hcnt   ( tile_dbg_hcnt   ),
    .dbg_fix    ( tile_dbg_fix    ),
    .dbg_rom_addr( tile_dbg_rom_addr ),
    .dbg_scr_x  ( tile_dbg_scr_x  ),
    .dbg_pat_x  ( tile_dbg_pat_x  ),
    .dbg_scr_y  ( tile_dbg_scr_y  ),
    .dbg_pat_y  ( tile_dbg_pat_y  )
);

jtmzone_fix u_fix(
    .rst        ( rst             ),
    .clk        ( clk             ),
    .clk24      ( clk24           ),
    .pxl_cen    ( pxl_cen         ),
    .cpu_addr   ( main_tile_addr  ),
    .cpu_dout   ( main_vram_din   ),
    .cpu_rnw    ( main_cpu_rnw    ),
    .vram_cs    ( main_vram1_cs   ),
    .cram_cs    ( main_cram1_cs   ),
    .vram_dout  ( main_vram1_dout ),
    .cram_dout  ( main_cram1_dout ),
    .hdump      ( hdump           ),
    .vdump      ( vdump           ),
    .flip       ( flip            ),
    .prog_data  ( prog_data[3:0]  ),
    .prog_addr  ( prog_addr[7:0] - CHR_OFFSET[7:0] ),
    .prog_en    ( char_lut_we     ),
    .rom_data   ( fixrom_data     ),
    .rom_ok     ( fixrom_ok       ),
    .rom_addr   ( fixrom_addr     ),
    .rom_cs     ( fixrom_cs       ),
    .pxl        ( fix_pxl         ),
    .fix_en     ( fix_en          )
);

jtmzone_obj u_obj(
    .rst        ( rst          ),
    .clk        ( clk          ),
    .pxl_cen    ( pxl_cen      ),
    .LVBL       ( LVBL         ),
    .HS         ( pre_hs       ),
    .hdump      ( hdump        ),
    .vdump      ( vdump        ),
    .flip       ( flip         ),
    .oram_addr  ( oram_addr    ),
    .oram_dout  ( oram_dout    ),
    .rom_addr   ( obj_addr     ),
    .rom_cs     ( obj_cs       ),
    .rom_data   ( obj_data     ),
    .rom_ok     ( obj_ok       ),
    .prog_data  ( prog_data[3:0] ),
    .prog_addr  ( prog_addr[7:0] - OBJ_OFFSET[7:0] ),
    .prog_en    ( obj_lut_we     ),
    .pxl        ( obj_pxl     )
);

jtmzone_colmix u_colmix(
    .rst        ( rst        ),
    .clk        ( clk        ),
    .pxl_cen    ( pxl_cen    ),
    .scr_pxl    ( char_pxl   ),
    .obj_pxl    ( dbg_obj_pxl    ),
    .fix_en     ( show_fix_en    ),
    .flip       ( flip       ),
    .preLHBL    ( pre_lhbl   ),
    .preLVBL    ( pre_lvbl   ),
    .hdump      ( hdump      ),
    .vdump      ( vdump      ),
    .prog_data  ( prog_data  ),
    .prog_addr  ( prog_addr  ),
    .prom_we    ( prom_we    ),
    .red        ( red        ),
    .green      ( green      ),
    .blue       ( blue       ),
    .LHBL       ( LHBL       ),
    .LVBL       ( LVBL       ),
    .preLBL     (           ),
    .dbg_pal_idx(           ),
    .dbg_obj_opaque(        )
);

`ifdef MZONE_FETCH_WATCH
reg        fetch_watch_vs_l;
reg [15:0] fetch_watch_frame;
always @(posedge clk) begin
    if( rst ) begin
        fetch_watch_vs_l  <= 1'b0;
        fetch_watch_frame <= 16'd0;
    end else if( pxl_cen ) begin
        fetch_watch_vs_l <= VS;
        if( VS && !fetch_watch_vs_l ) fetch_watch_frame <= fetch_watch_frame + 16'd1;
        if( fetch_watch_frame >= `MZONE_FETCH_WATCH_FROM &&
            fetch_watch_frame <= `MZONE_FETCH_WATCH_TO &&
            vdump >= `MZONE_FETCH_WATCH_V0 &&
            vdump <= `MZONE_FETCH_WATCH_V1 &&
            hdump >= `MZONE_FETCH_WATCH_X0 &&
            hdump <= `MZONE_FETCH_WATCH_X1 &&
            (tile_dbg_pat_x[2:0] == 3'd0 || tile_dbg_pat_x[2:0] == 3'd4) ) begin
            $display("MZONE_FETCH frame=%0d hdump=%0d vdump=%0d hcnt=%0d phase=%0d use_fix=%b fix_en=%b tile_addr=%03x req_addr=%03x rom_ok=%b rom_data=%08x pat_x=%02x pat_y=%02x",
                fetch_watch_frame, hdump, vdump, tile_dbg_hcnt,
                tile_dbg_pat_x[2:0], tile_dbg_fix,
                fix_en,
                tile_dbg_rom_addr,
                scrrom_addr,
                scrrom_ok,
                scrrom_data,
                tile_dbg_pat_x, tile_dbg_pat_y);
        end
    end
end
`endif

`ifdef MZONE_VIDEO_POINT_WATCH
reg        video_point_lvbl_l;
reg [15:0] video_point_frame;
reg [ 8:0] video_point_hdump_s;
reg [ 8:0] video_point_vdump_s;
always @(posedge clk) begin
    if( rst ) begin
        video_point_lvbl_l <= 1'b0;
        video_point_frame  <= 16'd0;
        video_point_hdump_s = 9'd0;
        video_point_vdump_s = 9'd0;
    end else if( pxl_cen ) begin
        video_point_lvbl_l <= pre_lvbl;
        if( pre_lvbl && !video_point_lvbl_l )
            video_point_frame <= video_point_frame + 16'd1;
        if( video_point_frame >= `MZONE_POINT_FRAME0 &&
            video_point_frame <= `MZONE_POINT_FRAME1 &&
            hdump >= `MZONE_POINT_X0 &&
            hdump <= `MZONE_POINT_X1 &&
            vdump >= `MZONE_POINT_Y0 &&
            vdump <= `MZONE_POINT_Y1 ) begin
            video_point_hdump_s = hdump;
            video_point_vdump_s = vdump;
            $strobe("MZONE_POINT_VIDEO frame=%0d hdump=%0d vdump=%0d red=%x green=%x blue=%x LHBL=%b LVBL=%b pre_lhbl=%b pre_lvbl=%b scr_pxl=%x fix_pxl=%x char_pxl=%x fix_en=%b",
                video_point_frame, video_point_hdump_s, video_point_vdump_s, red, green, blue,
                LHBL, LVBL, pre_lhbl, pre_lvbl, scr_pxl, fix_pxl,
                char_pxl, fix_en);
        end
    end
end
`endif

always @(posedge clk) begin
    if( rst ) begin
        pcb_vs <= 1'b0;
    end else if( pxl_cen ) begin
        pcb_vs <= vdump[8];
    end
end

`ifdef MZONE_VCNT_WATCH
reg        vcnt_watch_lvbl_l, vcnt_watch_vs_l;
always @(posedge clk) begin
    if( rst ) begin
        vcnt_watch_lvbl_l <= 1'b1;
        vcnt_watch_vs_l   <= 1'b0;
    end else if( pxl_cen ) begin
        vcnt_watch_lvbl_l <= pre_lvbl;
        vcnt_watch_vs_l   <= VS;
        if( VS != vcnt_watch_vs_l || pre_lvbl != vcnt_watch_lvbl_l ) begin
            $display("MZONE_VCNT_EDGE hdump=%03d vdump=%03d LVBL=%b VS=%b lvbl_edge=%b vs_edge=%b",
                hdump, vdump, pre_lvbl, VS,
                pre_lvbl != vcnt_watch_lvbl_l,
                VS != vcnt_watch_vs_l);
        end
        if( hdump == 9'd0 &&
            (vdump == 9'd240 || vdump == 9'd248 ||
             vdump == 9'd256 || vdump == 9'd263 ||
             vdump == 9'd0   || vdump == 9'd16) ) begin
            $display("MZONE_VCNT_MARK hdump=%03d vdump=%03d LVBL=%b VS=%b",
                hdump, vdump, pre_lvbl, VS);
        end
    end
end
`endif

jtframe_vtimer #(
    .VB_START   ( VB_START ),
    .VB_END     ( VB_END   ),
    .VCNT_END   ( VCNT_END ),
    .VS_START   ( VS_START ),
    .VS_END     ( VS_END   ),
    .HB_END     ( HB_END   ),
    .HB_START   ( HB_START ),
    .HCNT_END   ( HB_END   ),
    .HS_START   ( HS_START ),
    .HS_END     ( HS_END   ),
    .H_VB       ( H_VB     ),
    .H_VNEXT    ( H_VNEXT  )
) u_vtimer(
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .vdump      ( vdump     ),
    .vrender    ( vrender   ),
    .vrender1   (           ),
    .H          ( hdump     ),
    .Hinit      (           ),
    .Vinit      (           ),
    .LHBL       ( pre_lhbl  ),
    .LVBL       ( vt_lvbl   ),
    .HS         ( pre_hs    ),
    .VS         ( vt_vs     )
);

endmodule
