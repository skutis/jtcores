/*  This file is part of JTKUNIO.
    JTKUNIO program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    ( at your option) any later version.

    JTKUNIO program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JTKUNIO.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 30-7-2022 */

module jtkunio_game(
    `include "jtframe_game_ports.inc" // see $JTFRAME/hdl/inc/jtframe_game_ports.inc
);

// CPU bus
wire [ 7:0] cpu_dout, ram_dout, snd_latch,
            scr_dout, obj_dout, pal_dout;
wire        cpu_rnw, int_n, v8, h8, snd_irq,
            ram_cs, scrram_cs, objram_cs, pal_cs;
wire [12:0] cpu_addr;

// SDRAM
wire [ 9:0] scrpos;
wire        flip, prom_we;

assign dip_flip   = flip;
assign debug_view = 0;
assign gfx_cs     = ~VS & ~HS;

// temporary hack to get gfx16_en signal correctly generated by `jtframe mem`
assign dummy_cs=0;
assign dummy_addr=0;

jtkunio_main u_main(
    .rst         ( rst24        ),
    .clk         ( clk24        ),
    .cen3        ( cen3         ),
    .cen1p5      ( cen1p5       ),
    .LVBL        ( LVBL         ),
    .v8          ( v8           ),

    .bus_addr    ( cpu_addr     ),
    .cpu_rnw     ( cpu_rnw      ),
    .cpu_dout    ( cpu_dout     ),

    .dip_pause   ( dip_pause    ),
    // video
    .flip        ( flip         ),
    .scrpos      ( scrpos       ),

    .ram_cs      ( ram_cs       ),
    .scrram_cs   ( scrram_cs    ),
    .objram_cs   ( objram_cs    ),
    .pal_cs      ( pal_cs       ),
    .pal_dout    ( pal_dout     ),
    .ram_dout    ( ram_dout     ),
    .scr_dout    ( scr_dout     ),
    .obj_dout    ( obj_dout     ),

    // Sound
    .snd_irq     ( snd_irq      ),
    .snd_latch   ( snd_latch    ),

    .joystick1   ( joystick1[6:0]),
    .joystick2   ( joystick2[6:0]),
    .start       ( cab_1p       ),
    .coin        ( coin         ),
    .dipsw_a     ( dipsw[ 7:0]  ),
    .dipsw_b     ( dipsw[15:8]  ),
    .service     ( service      ),

    // ROM
    .rom_addr    ( main_addr    ),
    .rom_cs      ( main_cs      ),
    .rom_data    ( main_data    ),
    .rom_ok      ( main_ok      ),
    // MCU ROM
    .mcu_addr    ( mcu_addr     ),
    .mcu_data    ( mcu_data     )
);

jtkunio_sound u_sound(
    .rst        ( rst24         ),
    .clk        ( clk24         ),
    .cen3       ( cen3          ),
    .cen1p5     ( cen1p5        ),
    .h8         ( h8            ),

    .snd_latch  ( snd_latch     ),
    .snd_irq    ( snd_irq       ),

    .rom_addr   ( snd_addr      ),
    .rom_data   ( snd_data      ),
    .rom_cs     ( snd_cs        ),
    .rom_ok     ( snd_ok        ),

    .pcm_addr   ( pcm_addr      ),
    .pcm_data   ( pcm_data      ),
    .pcm_cs     ( pcm_cs        ),
    .pcm_ok     ( pcm_ok        ),

    .pcm        ( pcm           ),
    .fm         ( fm            )
);

jtkunio_video u_video(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .clk_cpu    ( clk           ),

    .pxl2_cen   ( pxl2_cen      ),
    .pxl_cen    ( pxl_cen       ),

    .LHBL       ( LHBL          ),
    .LVBL       ( LVBL          ),
    .HS         ( HS            ),
    .VS         ( VS            ),
    .flip       ( flip          ),
    .h8         ( h8            ),
    .v8         ( v8            ),

    .scrpos     ( scrpos        ),

    .pal_cs     ( pal_cs        ),
    .ram_cs     ( ram_cs        ),
    .scrram_cs  ( scrram_cs     ),
    .objram_cs  ( objram_cs     ),
    .cpu_wrn    ( cpu_rnw       ),
    .cpu_addr   ( cpu_addr      ),
    .cpu_dout   ( cpu_dout      ),

    .ram_dout   ( ram_dout      ),
    .scr_dout   ( scr_dout      ),
    .obj_dout   ( obj_dout      ),
    .pal_dout   ( pal_dout      ),

    .char_addr  ( char_addr     ),
    .char_data  ( char_data     ),
    .char_ok    ( char_ok       ),

    .scr_addr   ( scr_addr      ),
    .scr_data   ( scr_data      ),
    .scr_ok     ( scr_ok        ),

    .obj_addr   ( obj_addr      ),
    .obj_data   ( obj_data      ),
    .obj_cs     ( obj_cs        ),
    .obj_ok     ( obj_ok        ),

    .red        ( red           ),
    .green      ( green         ),
    .blue       ( blue          ),
    .gfx_en     ( gfx_en        ),
    .debug_bus  ( debug_bus     )
);

endmodule
