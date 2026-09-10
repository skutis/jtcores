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

module jtmzone_game(
    `include "jtframe_game_ports.inc"
);

localparam [21:0] OBJ_OFFSET = `OBJ_START >> 1;
localparam [21:0] SCR_OFFSET = `SCR_START >> 1;

wire [15:0] main_rom_addr;
wire        main_rom_cs;
wire        main_cpu_rnw;
wire [ 8:0] video_vdump;
wire [ 8:0] video_hdump;
wire [ 8:0] video_vrender;
wire        vram0_cs, vram1_cs, cram0_cs, cram1_cs;
wire [ 9:0] vram_addr;
wire [ 9:0] main_tile_addr;
wire [ 7:0] vram_din;
wire [ 7:0] vram0_dout, vram1_dout, cram0_dout, cram1_dout;
wire [ 9:0] objram_addr;
wire [ 7:0] objram_din;
wire [ 7:0] objram_dout;
wire        objram_we;
wire [ 7:0] main_scrolly, main_scrollx;
wire        main_flip, main_int;
`ifdef SIMSCENE
reg  [ 7:0] scene_regs[0:2];
initial begin
    $readmemh("regs.hex", scene_regs);
    $display("MZONE scene registers: scrolly=%02x scrollx=%02x flip=%0d",
        scene_regs[0], scene_regs[1], scene_regs[2][0]);
end
wire [7:0] video_scrolly = scene_regs[0];
wire [7:0] video_scrollx = scene_regs[1];
wire       video_flip    = scene_regs[2][0];
`else
wire [7:0] video_scrolly = main_scrolly;
wire [7:0] video_scrollx = main_scrollx;
wire       video_flip    = main_flip;
`endif
wire        intmain_n;
wire        h2;

assign dip_flip   = 0;
assign debug_view = 0;

assign main_addr   = main_rom_addr;
assign main_cs     = main_rom_cs;
assign main_tile_addr = vram_addr;

wire [7:0] main_rom_data = main_data;
wire       main_rom_ok   = main_ok;

`ifdef JTFRAME_LF_BUFFER
assign game_hdump   = video_hdump;
assign game_vrender = video_vrender[7:0];
`endif

`ifdef JTFRAME_IOCTL_RD
assign ioctl_din = 8'hff;
`endif

reg [13:0] obj_pack_addr;
always @(*) begin
    post_addr = prog_addr;
    obj_pack_addr = prog_addr[13:0] - OBJ_OFFSET[13:0];
    if( prog_addr >= OBJ_OFFSET && prog_addr < SCR_OFFSET ) begin
        // Keep the paired object-plane bytes adjacent, but transpose the
        // within-tile address so group[0], rather than ysub[0], selects the
        // 16-bit lane of each 32-bit SDRAM word.  One response then contains
        // eight adjacent horizontal pixels for a selected sprite row.
        obj_pack_addr[5:0] = {
            obj_pack_addr[5], // y3
            obj_pack_addr[4], // group[1]
            obj_pack_addr[2], // y2
            obj_pack_addr[1], // y1
            obj_pack_addr[0], // y0
            obj_pack_addr[3]  // group[0], 32-bit lane select
        };
        post_addr = OBJ_OFFSET + {8'd0,obj_pack_addr};
    end
end

`ifndef NOMAIN
jtmzone_main u_main(
    .rst        ( rst24          ),
    .clk        ( clk24          ),
    .cpu_clk_cen( cpu4_cen       ),
    .rom_addr   ( main_rom_addr  ),
    .rom_cs     ( main_rom_cs    ),
    .rom_data   ( main_rom_data  ),
    .rom_ok     ( main_rom_ok    ),

    .cpu_rnw    ( main_cpu_rnw   ),
    .vram0_cs   ( vram0_cs   ),
    .vram1_cs   ( vram1_cs   ),
    .cram0_cs   ( cram0_cs   ),
    .cram1_cs   ( cram1_cs   ),
    .shared_addr( main_shared_addr ),
    .shared_dout( main_shared_din  ),
    .shared_we  ( main_shared_we   ),
    .shared_din ( main_shared_dout ),

    .vram_addr( vram_addr  ),
    .vram_din ( vram_din  ),
    .vram0_dout( vram0_dout ),
    .vram1_dout( vram1_dout ),
    .cram0_dout( cram0_dout ),
    .cram1_dout( cram1_dout ),
    .objram_addr( objram_addr ),
    .objram_din ( objram_din  ),
    .objram_we  ( objram_we   ),
    .objram_dout( objram_dout ),

    .scrolly    ( main_scrolly   ),
    .scrollx    ( main_scrollx   ),
    .flip       ( main_flip      ),
    .snd_int    ( main_int       ),

    .vblank     ( LVBL           ),
    .h2         ( h2             ),
    .dip_pause  ( dip_pause      ),
    .intmain_n  ( intmain_n      )
);
`else
assign main_rom_addr   = 16'd0;
assign main_rom_cs     = 1'b0;
assign main_cpu_rnw    = 1'b1;
assign vram0_cs   = 1'b0;
assign vram1_cs   = 1'b0;
assign cram0_cs   = 1'b0;
assign cram1_cs   = 1'b0;
assign main_shared_addr= 11'd0;
assign main_shared_din = 8'd0;
assign main_shared_we  = 1'b0;
assign vram_addr   = 10'd0;
assign vram_din   = 8'd0;
assign objram_addr= 10'd0;
assign objram_din = 8'd0;
assign objram_we  = 1'b0;
assign main_scrolly    = 8'd0;
assign main_scrollx    = 8'd0;
assign main_flip       = 1'b0;
assign main_int        = 1'b0;
`endif

jtmzone_snd u_snd(
    .rst        ( rst24          ),
    .clk        ( clk24          ),

    .rom_addr   ( snd_addr       ),
    .rom_cs     ( snd_cs         ),
    .rom_data   ( snd_data       ),
    .rom_ok     ( snd_ok         ),
    .mcu_rom_addr( mcu_rom_addr  ),
    .mcu_rom_cs  ( mcu_rom_cs    ),
    .mcu_rom_data( mcu_rom_data  ),
    .mcu_rom_ok  ( mcu_rom_ok    ),

    .cab_1p     ( cab_1p[1:0]    ),
    .coin       ( coin[1:0]      ),
    .joystick1  ( joystick1[5:0] ),
    .joystick2  ( joystick2[5:0] ),
    .service    ( service        ),
    .dipsw_a    ( dipsw[ 7:0]    ),
    .dipsw_b    ( dipsw[15:8]    ),
    .LVBL       ( LVBL           ),
    .h2         ( h2             ),
    .shared_addr( snd_shared_addr ),
    .shared_dout( snd_shared_dout ),
    .shared_we  ( snd_shared_we   ),
    .shared_din ( snd_shared_din  ),
    .main_int   ( main_int        ),
    .intmain_n  ( intmain_n       ),

    .ay0a       ( ay0a           ),
    .ay0a_rcen  ( ay0a_rcen      ),
    .ay0b       ( ay0b           ),
    .ay0b_rcen  ( ay0b_rcen      ),
    .ay0c       ( ay0c           ),
    .ay0c_rcen  ( ay0c_rcen      ),
    .dac        ( dac            )
);

jtmzone_video u_video(
    .rst        ( rst            ),
    .clk        ( clk            ),
    .clk24      ( clk24          ),
    .pxl_cen    ( pxl_cen        ),
    .pxl2_cen   ( pxl2_cen       ),

    .main_tile_addr( main_tile_addr ),
    .vram_din ( vram_din  ),
    .main_cpu_rnw  ( main_cpu_rnw   ),
    .vram0_cs ( vram0_cs  ),
    .vram1_cs ( vram1_cs  ),
    .cram0_cs ( cram0_cs  ),
    .cram1_cs ( cram1_cs  ),
    .vram0_dout( vram0_dout ),
    .vram1_dout( vram1_dout ),
    .cram0_dout( cram0_dout ),
    .cram1_dout( cram1_dout ),

    .objram_addr( objram_addr ),
    .objram_din ( objram_din  ),
    .objram_we  ( objram_we   ),
    .objram_dout( objram_dout ),

    .scrolly    ( video_scrolly  ),
    .scrollx    ( video_scrollx  ),
    .flip       ( video_flip     ),
    .gfx_en     ( gfx_en         ),
    .prog_data  ( prog_data      ),
    .prog_addr  ( prog_addr      ),
    .prom_we    ( prom_we        ),

    .fixrom_addr( fixrom_addr      ),
    .fixrom_cs  ( fixrom_cs        ),
    .fixrom_data( fixrom_data      ),
    .fixrom_ok  ( fixrom_ok        ),

    .scrrom_addr( scrrom_addr      ),
    .scrrom_cs  ( scrrom_cs        ),
    .scrrom_data( scrrom_data      ),
    .scrrom_ok  ( scrrom_ok        ),
    .obj_addr   ( objrom_addr      ),
    .obj_cs     ( objrom_cs        ),
    .obj_data   ( objrom_data      ),
    .obj_ok     ( objrom_ok        ),

    .HS         ( HS             ),
    .VS         ( VS             ),
    .LHBL       ( LHBL           ),
    .LVBL       ( LVBL           ),
    .red        ( red            ),
    .green      ( green          ),
    .blue       ( blue           ),

    .h2         ( h2             ),
    .hdump      ( video_hdump    ),
    .vdump      ( video_vdump    ),
    .vrender    ( video_vrender  )
);

endmodule
