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

localparam [21:0] SND_START = `SND_START;

wire [15:0] main_stub_addr;
wire        main_stub_cs;
wire        main_cpu_cen;
wire        main_cpu_cen_src;
wire        clkq_cen;
wire        clkq_cen24;
wire        main_cpu_rnw;
wire [ 7:0] main_cpu_dout;
wire [ 8:0] video_vdump;
wire        main_scrolly_cs, main_scrollx_cs;
wire        main_vram0_cs, main_vram1_cs, main_cram0_cs, main_cram1_cs;
wire        main_objram_cs, main_shared_cs;
wire [ 7:0] main_scrolly, main_scrollx;
wire        main_flip, main_irq_mask, main_int;
wire        main_irq_ack, snd_irq_n;
wire        main_ba;
wire        main_bs;
wire        blank;
wire        h2;
wire        thblk_n, thblk_delayed_n;
reg         blank_q;
reg         v16_q;

assign dip_flip   = 0;
assign debug_view = 0;

assign objrom_addr = 0;
assign objrom_cs   = 0;
assign main_addr   = main_stub_addr;
assign main_cs     = main_stub_cs;
assign blank       = ~blank_q;

`ifdef JTFRAME_IOCTL_RD
assign ioctl_din = 8'hff;
`endif

always @(*) begin
    post_addr = prog_addr;
end

`ifdef JTMZONE_SCH_HCNT
assign main_cpu_cen_src = clkq_cen24;
`else
assign main_cpu_cen_src = cpu4_cen;
`endif

jtframe_crossclk_cen u_clkq_cen24(
    .clk_in     ( clk           ),
    .cen_in     ( clkq_cen      ),
    .clk_out    ( clk24         ),
    .cen_out    ( clkq_cen24    )
);

jtmzone_main u_main(
    .rst        ( rst24          ),
    .clk        ( clk24          ),
    .cpu_clk_cen( main_cpu_cen_src ),
    .cpu_cen    ( main_cpu_cen   ),

    .rom_addr   ( main_stub_addr ),
    .rom_cs     ( main_stub_cs   ),
    .rom_data   ( main_data      ),
    .rom_ok     ( main_ok        ),

    .cpu_rnw    ( main_cpu_rnw   ),
    .cpu_dout   ( main_cpu_dout  ),

    .scrolly_cs ( main_scrolly_cs ),
    .scrollx_cs ( main_scrollx_cs ),
    .vram0_cs   ( main_vram0_cs   ),
    .vram1_cs   ( main_vram1_cs   ),
    .cram0_cs   ( main_cram0_cs   ),
    .cram1_cs   ( main_cram1_cs   ),
    .objram_cs  ( main_objram_cs  ),
    .shared_cs  ( main_shared_cs  ),
    .shared_addr( main_shared_addr ),
    .shared_dout( main_shared_din  ),
    .shared_we  ( main_shared_we   ),
    .shared_din ( main_shared_dout ),

    .main_vram_addr( main_vram_addr ),
    .main_vram_din ( main_vram_din  ),
    .main_vram0_we ( main_vram0_we  ),
    .main_vram1_we ( main_vram1_we  ),
    .main_cram0_we ( main_cram0_we  ),
    .main_cram1_we ( main_cram1_we  ),
    .main_vram0_dout( main_vram0_dout ),
    .main_vram1_dout( main_vram1_dout ),
    .main_cram0_dout( main_cram0_dout ),
    .main_cram1_dout( main_cram1_dout ),

    .scrolly    ( main_scrolly   ),
    .scrollx    ( main_scrollx   ),
    .flip       ( main_flip      ),
    .irq_mask   ( main_irq_mask  ),
    .snd_int    ( main_int       ),

    .vblank     ( LVBL           ),
    .blank      ( blank          ),
    .dip_pause  ( dip_pause      ),
    .irq_ack    ( main_irq_ack   ),
    .BA         ( main_ba        ),
    .BS         ( main_bs        ),
    .snd_irq_n  ( snd_irq_n      ),
    .snd_dout   ( 8'hff          )
);

jtmzone_snd u_snd(
    .rst        ( rst24          ),
    .clk        ( clk24          ),

    .rom_addr   ( snd_addr       ),
    .rom_cs     ( snd_cs         ),
    .rom_data   ( snd_data       ),
    .rom_ok     ( snd_ok         ),

    .cab_1p     ( cab_1p[1:0]    ),
    .coin       ( coin[1:0]      ),
    .joystick1  ( joystick1[5:0] ),
    .joystick2  ( joystick2[5:0] ),
    .service    ( service        ),
    .dipsw_a    ( dipsw[ 7:0]    ),
    .dipsw_b    ( dipsw[15:8]    ),
    .blank      ( blank          ),
    .h2         ( h2             ),
    .main_irq_ack( main_irq_ack  ),

    .shared_addr( snd_shared_addr ),
    .shared_dout( snd_shared_dout ),
    .shared_we  ( snd_shared_we   ),
    .shared_din ( snd_shared_din  ),
    .main_int   ( main_int        ),
    .main_irq_n ( snd_irq_n       ),

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
    .pxl_cen    ( pxl_cen        ),
    .pxl2_cen   ( pxl2_cen       ),

    .scrolly    ( main_scrolly   ),
    .scrollx    ( main_scrollx   ),
    .flip       ( main_flip      ),
    .prog_data  ( prog_data      ),
    .prog_addr  ( prog_addr      ),
    .prom_we    ( prom_we        ),

    .video_ram_addr( video_ram_addr ),
    .video_vram0   ( vram0_dout     ),
    .video_vram1   ( vram1_dout     ),
    .video_cram0   ( cram0_dout     ),
    .video_cram1   ( cram1_dout     ),

    .scr_addr   ( scr_addr        ),
    .scr_cs     ( scr_cs          ),
    .scr_data   ( scr_data        ),
    .scr_ok     ( scr_ok          ),

    .HS         ( HS             ),
    .VS         ( VS             ),
    .LHBL       ( LHBL           ),
    .LVBL       ( LVBL           ),
    .red        ( red            ),
    .green      ( green          ),
    .blue       ( blue           ),

    .clkq_cen   ( clkq_cen       ),
    .h2         ( h2             ),
    .thblk_n    ( thblk_n        ),
    .thblk_delayed_n( thblk_delayed_n ),
    .hdump      (                ),
    .vdump      ( video_vdump    ),
    .vrender    (                )
);

always @(posedge clk) begin
    if( rst ) begin
        v16_q   <= 1'b0;
        blank_q <= 1'b1;
    end else if( pxl_cen ) begin
        // Schematic BLANK latch: G6B LS74, clocked by V16 and loaded from
        // ~(V32 & V64 & V128) on the V16 rising edge.
        if( !v16_q && video_vdump[4] ) begin
            blank_q <= ~(video_vdump[5] & video_vdump[6] & video_vdump[7]);
        end
        v16_q <= video_vdump[4];
    end
end

endmodule
