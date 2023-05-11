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
    along with JTCORES.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 1-2-2023 */

module jtaliens_game(
    `include "jtframe_game_ports.inc" // see $JTFRAME/hdl/inc/jtframe_game_ports.inc
);

wire [ 7:0] snd_latch;
wire        cpu_cen, snd_irq, rmrd, rst8;
wire        pal_we, cpu_we, tilesys_cs, objsys_cs, prio;
wire        cpu_rnw, cpu_irq_n;
wire [ 7:0] tilesys_dout, objsys_dout,
            obj_dout, pal_dout, cpu_dout,
            st_main, st_video, st_snd;
reg  [ 7:0] debug_mux;
reg         snd_cfg;

assign debug_view = debug_mux;
assign ram_din    = cpu_dout;

always @(posedge clk) begin
    case( debug_bus[7:6] )
        0: debug_mux <= st_main;
        1: debug_mux <= st_video;
        2: debug_mux <= st_snd;
        default: debug_mux <= {3'd0, prio, 3'd0, snd_cfg};
        //3: debug_mux <= { dipsw_c, buserror, prio, video_bank };
    endcase
end

always @(posedge clk) begin
    if( prog_addr==0 && prog_we && header ) snd_cfg <= prog_data[0];
end

// always @(*) begin
//     post_addr = prog_addr;
//     if( prog_ba[1] ) begin
//         post_addr[]
//     end
// end

jtaliens_main u_main(
    .rst            ( rst           ),
    .clk            ( clk           ),
    .cen24          ( cen24         ),
    .cen12          ( cen12         ),
    .cpu_cen        ( cpu_cen       ),

    .cfg            ( snd_cfg       ),
    .cpu_dout       ( cpu_dout      ),
    .cpu_we         ( cpu_we        ),

    .rom_addr       ( main_addr     ),
    .rom_data       ( main_data     ),
    .rom_cs         ( main_cs       ),
    .rom_ok         ( main_ok       ),
    // RAM
    .ram_we         ( ram_we        ),
    .ram_dout       ( ram_dout      ),
    // cabinet I/O
    .start_button   ( start_button  ),
    .coin_input     ( coin_input    ),
    .joystick1      ( joystick1     ),
    .joystick2      ( joystick2     ),
    .service        ( service       ),

    // From video
    .rst8           ( rst8          ),
    .irq_n          ( cpu_irq_n     ),

    .tilesys_dout   ( tilesys_dout  ),
    .objsys_dout    ( objsys_dout   ),

    .pal_dout       ( pal_dout      ),
    // To video
    .prio           ( prio          ),
    .objsys_cs      ( objsys_cs     ),
    .tilesys_cs     ( tilesys_cs    ),
    .rmrd           ( rmrd          ),
    .pal_we         ( pal_we        ),
    // To sound
    .snd_latch      ( snd_latch     ),
    .snd_irq        ( snd_irq       ),
    // DIP switches
    .dip_pause      ( dip_pause     ),
    .dipsw          ( dipsw[19:0]   ),
    // Debug
    .debug_bus      ( debug_bus     ),
    .st_dout        ( st_main       )
);

/* verilator tracing_off */
jtaliens_sound u_sound(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen_fm     ( cen_fm        ),
    .cen_fm2    ( cen_fm2       ),
    .fxlevel    ( dip_fxlevel   ),
    .cfg        ( snd_cfg       ),
    // communication with main CPU
    .snd_irq    ( snd_irq       ),
    .snd_latch  ( snd_latch     ),
    // ROM
    .rom_addr   ( snd_addr      ),
    .rom_cs     ( snd_cs        ),
    .rom_data   ( snd_data      ),
    .rom_ok     ( snd_ok        ),
    // ADPCM ROM
    .pcma_addr  ( pcma_addr     ),
    .pcma_dout  ( pcma_data     ),
    .pcma_cs    ( pcma_cs       ),
    .pcma_ok    ( pcma_ok       ),

    .pcmb_addr  ( pcmb_addr     ),
    .pcmb_dout  ( pcmb_data     ),
    .pcmb_cs    ( pcmb_cs       ),
    .pcmb_ok    ( pcmb_ok       ),

    // Sound output
    .snd        ( snd           ),
    .sample     ( sample        ),
    .peak       ( game_led      ),
    // Debug
    .debug_bus  ( debug_bus     ),
    .st_dout    ( st_snd        )
);
/* verilator tracing_on */

/* xxxverilator tracing_off */
jtaliens_video u_video (
    .rst            ( rst           ),
    .rst8           ( rst8          ),
    .clk            ( clk           ),
    .pxl_cen        ( pxl_cen       ),
    .lhbl           ( LHBL          ),
    .lvbl           ( LVBL          ),
    .hs             ( HS            ),
    .vs             ( VS            ),
    .flip           ( dip_flip      ),
    // PROMs
    .prom_we        ( prom_we       ),
    .prog_addr      (prog_addr[ 7:0]),
    .prog_data      ( prog_data[1:0]),
    // GFX - CPU interface
    .cpu_we         ( cpu_we        ),
    .objsys_cs      ( objsys_cs     ),
    .tilesys_cs     ( tilesys_cs    ),
    .pal_we         ( pal_we        ),
    .cpu_addr       (main_addr[15:0]),
    .cpu_dout       ( cpu_dout      ),
    .tilesys_dout   ( tilesys_dout  ),
    .objsys_dout    ( objsys_dout   ),
    .pal_dout       ( pal_dout      ),
    .rmrd           ( rmrd          ),
    .cpu_irq_n      ( cpu_irq_n     ),
    // SDRAM
    .lyra_addr      ( lyra_addr     ),
    .lyrb_addr      ( lyrb_addr     ),
    .lyrf_addr      ( lyrf_addr     ),
    .lyro_addr      ( lyro_addr     ),
    .lyra_data      ( lyra_data     ),
    .lyrb_data      ( lyrb_data     ),
    .lyro_data      ( lyro_data     ),
    .lyrf_data      ( lyrf_data     ),
    .lyrf_cs        ( lyrf_cs       ),
    .lyra_cs        ( lyra_cs       ),
    .lyrb_cs        ( lyrb_cs       ),
    .lyro_cs        ( lyro_cs       ),
    .lyro_ok        ( lyro_ok       ),
    // pixels
    .red            ( red           ),
    .green          ( green         ),
    .blue           ( blue          ),
    // Test
    .debug_bus      ( debug_bus     ),
    .gfx_en         ( gfx_en        ),
    .st_dout        ( st_video      )
);

endmodule