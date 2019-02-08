/*  This file is part of JT_GNG.
    JT_GNG program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JT_GNG program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JT_GNG.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 8-2-2019 */

module jt1942_zxuno(
   input         CLOCK_50,
   // Addon output
   output [5:0]  VGA_R,
   output [5:0]  VGA_G,
   output [5:0]  VGA_B,
   // Simple output
   output [2:0]  VGA2_R,
   output [2:0]  VGA2_G,
   output [2:0]  VGA2_B,
   output        VGA_HS,
   output        VGA_VS,
   // keyboard
   inout         PS2_KBD_CLK,
   inout         PS2_KBD_DATA,
   output        AUDIO_L,
   output        AUDIO_R,
   // Composite output
   output        STDN,
   output        STDNB,
   output [20:0] SRAM_ADDR,
   inout  [ 7:0] SRAM_DATA,
   output        SRAM_WE_N,
   // Flash ROM
   output        FLASH_CS_N,
   output        FLASH_CLK,
   output        FLASH_MOSI,
   input         FLASH_MISO,
   input         FLASH_WP,
   input         FLASH_HOLD,
   // SD Card
   // output        SD_CS_N,
   // output        SD_CLK,
   // output        SD_MOSI,
   // input         SD_MISO,
   output        LED,   // nos servir como testigo de uso de la SPI
   // joystick
   input    [5:0] JOYSTICK
);

wire clk_rgb, clk_vga;

jtgng_pll u_pll(
    .CLK_IN1    ( CLOCK_50  ),
    .clk_rgb    ( clk_rgb   ), // 12 MHz
    .clk_vga    ( clk_vga   ), // 25 MHz
    .locked     ( locked    )
);

wire [1:0] game_start, game_coin;
wire [5:0] game_joystick1, game_joystick2;

wire cen12, cen6, cen3, cen1p5;

jtgng_cen #(.CLK_SPEED(24)) u_cen(
    .clk    ( clk_rgb   ),
    .cen12  ( cen12     ),
    .cen6   ( cen6      ),
    .cen3   ( cen3      ),
    .cen1p5 ( cen1p5    )
);

wire        sram_we_n;
wire [20:0] sram_addr, romload_addr, game_addr16;
wire [19:0] game_addr;
wire [ 7:0] sram_data;
wire        downloading;

jtgng_zxuno_prog u_prog(
    .rst         ( rst          ),
    .clk         ( clk          ),
    // Flash
    // SRAM
    .sram_we_n   ( sram_we_n    ),
    .romload_addr( romload_addr ),
    .game_addr   ( game_addr16  ),
    .sram_addr   ( SRAM_ADDR    ),
    .sram_data   ( sram_data    ),
    .game_addr   ( game_addr    ),
    // 
    .downloading( downloading   )
);

wire [15:0] sram_data16;

jtgng_zxuno_sram u_sram(
    .clk         ( clk           ),
    .cen24       ( 1'b1          ),
    .cen12       ( cen12         ),
    .game_addr   ( game_addr     ),
    .sram_addr   ( game_addr16   ),
    .sram_data   ( sram_data     ),
    .sram_data16 ( sram_data16   )
);

wire [9:0] prom_we;
jt1942_prom_we u_prom_we(
    .downloading    ( downloading           ), 
    .romload_addr   ( {4'd0, romload_addr}  ),
    .prom_we        ( prom_we               )
);

wire [1:0] nc;

jt1942_game u_game(
    .rst         ( rst           ),
    .soft_rst    ( soft_rst      ),
    .clk         ( clk_rgb       ),
    .cen12       ( cen12         ),
    .cen6        ( cen6          ),
    .cen3        ( cen3          ),
    .cen1p5      ( cen1p5        ),
    .red         ( red           ),
    .green       ( green         ),
    .blue        ( blue          ),
    .LHBL        ( LHBL          ),
    .LVBL        ( LVBL          ),
    .HS          ( hs            ),
    .VS          ( vs            ),

    .start_button( game_start        ),
    .coin_input  ( game_coin         ),
    .joystick1   ( game_joystick1    ),
    .joystick2   ( game_joystick2    ),

    // PROM programming
    .prog_addr   ( romload_addr[7:0] ),
    .prog_din    ( romload_data[3:0] ),
    .prom_k6_we  ( prom_we[0]        ),
    .prom_d1_we  ( prom_we[1]        ),
    .prom_d2_we  ( prom_we[2]        ),
    .prom_d6_we  ( prom_we[3]        ),
    .prom_e8_we  ( prom_we[4]        ),
    .prom_e9_we  ( prom_we[5]        ),
    .prom_e10_we ( prom_we[6]        ),
    .prom_f1_we  ( prom_we[7]        ),  
    .prom_k3_we  ( prom_we[8]        ),  
    .prom_m11_we ( prom_we[9]        ),  

    // ROM load
    .downloading ( downloading       ),
    .loop_rst    ( loop_rst          ),
    .autorefresh ( autorefresh       ),
    .sdram_addr  ( {nc, game_addr}   ),
    .data_read   ( sram_data16       ),
    // DIP switches
    
    .dip_pause   ( 1'b1          ),
    .dip_level   ( 2'b11         ),
    .dip_test    ( 1'b1          ),
    .dip_upright ( 1'b0          ),
    .dip_planes  ( 2'b11         ),
    .dip_price   ( 3'b111        ), // 1 credit, 1 coin
    .dip_bonus   ( 2'b11         ),
    // sound
    .snd         ( snd           ),
    .coin_cnt    (               ),
    .sample      (               )
);

assign AUDIO_R = AUDIO_L;

jtgng_board u_board(
    .rst            ( rst             ),
    .clk_dac        ( clk_rom         ),
    // audio
    .snd            ( { snd, 7'd0 }   ),
    .snd_pwm        ( AUDIO_L         ),
    // VGA
    .clk_rgb        ( clk_rgb         ),
    .clk_vga        ( clk_vga         ),
    .en_mixing      ( 1'b1            ),    
    .game_r         ( red             ),
    .game_g         ( green           ),
    .game_b         ( blue            ),
    .LHBL           ( LHBL            ),
    .LVBL           ( LVBL            ),
    .vga_r          ( VGA_R           ),
    .vga_g          ( VGA_G           ),
    .vga_b          ( VGA_B           ),    
    .vga_hsync      ( VGA_HS          ),
    .vga_vsync      ( VGA_VS          ),
    // joystick
    .ps2_kbd_clk    ( PS2_KBD_CLK     ),
    .ps2_kbd_data   ( PS2_KBD_DATA    ),    
    .board_joystick1( ~{2'b0, JOYSTICK} ),
    .board_joystick2( 8'hFF           ),
    .game_joystick1 ( game_joystick1  ),
    .game_joystick2 ( game_joystick2  ),
    .game_coin      ( game_coin       ),
    .game_start     ( game_start      )
);

endmodule