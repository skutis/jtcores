/*  This file is part of JTCORES.
    JTCORES program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version. */

module jtmzone_video(
    input               rst,
    input               clk,
    input               pxl_cen,
    input               pxl2_cen,
    input               obj_dma_cen,

    input        [ 7:0] scrolly,
    input        [ 7:0] scrollx,
    input               flip,

    input        [ 7:0] prog_data,
    input        [21:0] prog_addr,
    input               prom_we,

    output       [ 9:0] video_scroll_ram_addr,
    output       [ 9:0] video_fix_ram_addr,
    input        [ 7:0] video_vram0,
    input        [ 7:0] video_vram1,
    input        [ 7:0] video_cram0,
    input        [ 7:0] video_cram1,

    output       [11:0] fixrom_addr,
    output              fixrom_cs,
    input        [31:0] fixrom_data,
    input               fixrom_ok,
    output       [11:0] scrrom_addr,
    output              scrrom_cs,
    input        [31:0] scrrom_data,
    input               scrrom_ok,

    output       [ 9:0] objram_addr,
    input        [ 7:0] objram_data,
    output       [13:0] obj_addr,
    output              obj_cs,
    input        [15:0] obj_data,
    input               obj_ok,

    output              HS,
    output              VS,
    output              LHBL,
    output              LVBL,
    output       [ 3:0] red,
    output       [ 3:0] green,
    output       [ 3:0] blue,

    output              clkq_cen,
    output              h2,
    output              fix_n,
    output              fix_en,
    output              fix_delayed_n,
    output       [ 8:0] hdump,
    output       [ 8:0] vdump,
    output       [ 8:0] vrender
);

localparam [8:0] HVISIBLE = 9'd288;
localparam [8:0] VPHASE   = 9'd2;
localparam [8:0] FIX_WIDTH= 9'd48;
localparam [8:0] HTOTAL   = 9'd384;
localparam [8:0] HB_END   = HTOTAL-9'd1;
localparam [8:0] HB_START = HVISIBLE-9'd1;
localparam [8:0] HS_START = 9'd319;
localparam [8:0] HS_END   = 9'd351;
localparam [8:0] H_VNEXT  = HTOTAL-9'd9;
localparam [8:0] VB_START = 9'd238;
localparam [8:0] VB_END   = 9'd014;
localparam [21:0] OBJ_OFFSET = `ifdef JTFRAME_PROM_START `JTFRAME_PROM_START + 22'h020 `else 22'h020 `endif;
localparam [21:0] CHR_OFFSET = `ifdef JTFRAME_PROM_START `JTFRAME_PROM_START + 22'h120 `else 22'h120 `endif;

wire        pre_lhbl, pre_lvbl, pre_hs;
wire        lhbl_dly, lvbl_dly, pre_lbl_dly;
wire [ 8:0] raw_hdump, raw_vdump;
wire [ 8:0] tile_vcnt;
wire        fix_active;
wire [ 9:0] tile_scroll_ram_addr, tile_fix_ram_addr;
wire [ 8:0] tile_dbg_hcnt;
wire [11:0] tile_dbg_rom_addr;
wire        tile_dbg_fix;
wire [ 7:0] tile_dbg_scr_x, tile_dbg_pat_x, tile_dbg_scr_y, tile_dbg_pat_y;
wire [ 3:0] scr_pxl;
wire        tile_fix_en;
wire [ 3:0] obj_pxl;
wire        obj_pxl_en;
wire [ 4:0] dbg_pal_idx;
wire        dbg_obj_opaque;
wire        pxl2_cen_unused = pxl2_cen;
wire        obj_lut_we, char_lut_we;

assign obj_lut_we = prom_we && prog_addr >= OBJ_OFFSET && prog_addr < OBJ_OFFSET+22'h100;
assign char_lut_we = prom_we && prog_addr >= CHR_OFFSET && prog_addr < CHR_OFFSET+22'h100;

assign hdump  = raw_hdump;
assign vdump  = tile_vcnt;
assign HS     = pre_hs;
assign LHBL   = lhbl_dly;
assign LVBL   = lvbl_dly;
assign fix_active = raw_hdump < FIX_WIDTH;
assign tile_vcnt = raw_vdump + VPHASE;

assign fix_n = ~fix_active;
assign fix_en = fix_active;
assign fix_delayed_n = ~fix_active;
assign h2 = tile_dbg_hcnt[1];
assign clkq_cen = 1'b0;

jtmzone_scroll u_scroll(
    .rst        ( rst             ),
    .clk        ( clk             ),
    .pxl_cen    ( pxl_cen         ),
    .hdump      ( raw_hdump       ),
    .vdump      ( tile_vcnt       ),
    .scrollx    ( scrollx         ),
    .scrolly    ( scrolly         ),
    .flip       ( flip            ),
    .scroll_ram_addr( tile_scroll_ram_addr ),
    .fix_ram_addr   ( tile_fix_ram_addr    ),
    .vram0      ( video_vram0     ),
    .vram1      ( video_vram1     ),
    .cram0      ( video_cram0     ),
    .cram1      ( video_cram1     ),
    .prog_data  ( prog_data[3:0]  ),
    .prog_addr  ( prog_addr[7:0] - CHR_OFFSET[7:0] ),
    .prog_en    ( char_lut_we     ),
    .fix_rom_data( fixrom_data    ),
    .fix_rom_ok  ( fixrom_ok      ),
    .fix_rom_addr( fixrom_addr    ),
    .fix_rom_cs  ( fixrom_cs      ),
    .scr_rom_data( scrrom_data    ),
    .scr_rom_ok  ( scrrom_ok      ),
    .scr_rom_addr( scrrom_addr    ),
    .scr_rom_cs  ( scrrom_cs      ),
    .pxl        ( scr_pxl         ),
    .fix_en     ( tile_fix_en     ),
    .dbg_hcnt   ( tile_dbg_hcnt   ),
    .dbg_fix    ( tile_dbg_fix    ),
    .dbg_rom_addr( tile_dbg_rom_addr ),
    .dbg_scr_x  ( tile_dbg_scr_x  ),
    .dbg_pat_x  ( tile_dbg_pat_x  ),
    .dbg_scr_y  ( tile_dbg_scr_y  ),
    .dbg_pat_y  ( tile_dbg_pat_y  )
);

assign video_scroll_ram_addr = tile_scroll_ram_addr;
assign video_fix_ram_addr = tile_fix_ram_addr;

jtmzone_obj u_obj(
    .rst        ( rst          ),
    .clk        ( clk          ),
    .pxl_cen    ( pxl_cen      ),
    .dma_cen    ( obj_dma_cen  ),
    .LHBL       ( pre_lhbl     ),
    .LVBL       ( pre_lvbl     ),
    .hdump      ( hdump        ),
    .vdump      ( vdump        ),
    .flip       ( flip         ),
    .ram_addr   ( objram_addr  ),
    .ram_data   ( objram_data  ),
    .rom_addr   ( obj_addr     ),
    .rom_cs     ( obj_cs       ),
    .rom_data   ( obj_data     ),
    .rom_ok     ( obj_ok       ),
    .prog_data  ( prog_data[3:0] ),
    .prog_addr  ( prog_addr[7:0] - OBJ_OFFSET[7:0] ),
    .prog_en    ( obj_lut_we     ),
    .pxl        ( obj_pxl     ),
    .pxl_en     ( obj_pxl_en  )
);

jtmzone_colmix u_colmix(
    .rst        ( rst        ),
    .clk        ( clk        ),
    .pxl_cen    ( pxl_cen    ),
    .scr_pxl    ( scr_pxl    ),
    .obj_pxl    ( obj_pxl    ),
    .obj_pxl_en ( obj_pxl_en ),
    .fix_en     ( tile_fix_en ),
    .LHBL       ( pre_lhbl   ),
    .LVBL       ( pre_lvbl   ),
    .hdump      ( hdump      ),
    .vdump      ( vdump      ),
    .prog_data  ( prog_data  ),
    .prog_addr  ( prog_addr  ),
    .prom_we    ( prom_we    ),
    .red        ( red        ),
    .green      ( green      ),
    .blue       ( blue       ),
    .LHBL_dly   ( lhbl_dly   ),
    .LVBL_dly   ( lvbl_dly   ),
    .preLBL     ( pre_lbl_dly ),
    .dbg_pal_idx( dbg_pal_idx ),
    .dbg_obj_opaque( dbg_obj_opaque )
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
            raw_hdump >= `MZONE_FETCH_WATCH_X0 &&
            raw_hdump <= `MZONE_FETCH_WATCH_X1 &&
            (tile_dbg_pat_x[2:0] == 3'd0 || tile_dbg_pat_x[2:0] == 3'd4) ) begin
            $display("MZONE_FETCH frame=%0d hdump=%0d vdump=%0d hcnt=%0d phase=%0d fix=%b ram_addr=%03x vram=%02x cram=%02x tile_addr=%03x req_addr=%03x rom_ok=%b rom_data=%08x pat_x=%02x pat_y=%02x",
                fetch_watch_frame, hdump, vdump, tile_dbg_hcnt,
                tile_dbg_pat_x[2:0], tile_dbg_fix,
                tile_dbg_fix ? video_fix_ram_addr : video_scroll_ram_addr,
                tile_dbg_fix ? video_vram1 : video_vram0,
                tile_dbg_fix ? video_cram1 : video_cram0,
                tile_dbg_rom_addr,
                tile_dbg_fix ? fixrom_addr : scrrom_addr,
                tile_dbg_fix ? fixrom_ok : scrrom_ok,
                tile_dbg_fix ? fixrom_data : scrrom_data,
                tile_dbg_pat_x, tile_dbg_pat_y);
        end
    end
end
`endif

jtframe_vtimer #(
    .VB_START   ( VB_START ),
    .VB_END     ( VB_END   ),
    .VCNT_END   ( 9'd255 ),
    .VS_START   ( 9'd248 ),
    .HB_END     ( HB_END   ),
    .HB_START   ( HB_START ),
    .HCNT_END   ( HB_END   ),
    .HS_START   ( HS_START ),
    .HS_END     ( HS_END   ),
    .H_VB       ( HB_END   ),
    .H_VNEXT    ( H_VNEXT  )
) u_vtimer(
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .vdump      ( raw_vdump ),
    .vrender    ( vrender   ),
    .vrender1   (           ),
    .H          ( raw_hdump ),
    .Hinit      (           ),
    .Vinit      (           ),
    .LHBL       ( pre_lhbl  ),
    .LVBL       ( pre_lvbl  ),
    .HS         ( pre_hs    ),
    .VS         ( VS        )
);

endmodule
