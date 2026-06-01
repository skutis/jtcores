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

module jtmzone_snd(
    input               rst,
    input               clk,
    // ROM
    output      [12:0]  rom_addr,
    output reg          rom_cs,
    input       [ 7:0]  rom_data,
    input               rom_ok,
    output      [11:0]  dac_addr,
    output              dac_cs,
    input       [ 7:0]  dac_data,
    input               dac_ok,

    // Cabinet inputs, same Konami ports used by MAME
    input       [ 1:0]  cab_1p,
    input       [ 1:0]  coin,
    input       [ 5:0]  joystick1,
    input       [ 5:0]  joystick2,
    input               service,
    input       [ 7:0]  dipsw_a,
    input       [ 7:0]  dipsw_b,
    input               blank,
    input               h2,
    input               main_irq_ack,
    input               main_int,

    // Shared RAM with the main CPU
    output      [10:0]  shared_addr,
    output      [ 7:0]  shared_dout,
    output              shared_we,
    input       [ 7:0]  shared_din,
    output              main_irq_n,

    // Sound output
    output signed [9:0] ay0a, ay0b, ay0c,
    output       [1:0] ay0a_rcen, ay0b_rcen, ay0c_rcen,
    output       [7:0] dac
);
`ifndef NOSOUND

wire        [ 7:0] cpu_dout, ay_dout, ay_iob, ay_oa;
wire        [ 7:0] ay_a8, ay_b8, ay_c8;
wire        [ 7:0] dac_status;
wire        [15:0] A;
wire                m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n;
wire [1:0]          cpu_cen_v, dac_cen_v;
wire                cpu_cen, ay_cen, dac_cen, irq_rst, int_n, snmi_n;
wire                wdog_reset_n, snmi_set_n;
wire                wait_n;
wire                main_irq_req;
wire                ay_rd, ay_wr_addr, ay_wr_data;
reg         [ 7:0]  cpu_din;
reg         [ 1:0]  ay0a_rcen_r, ay0b_rcen_r, ay0c_rcen_r;
reg                 latch_cs, inp0_cs, inp1_cs, inp2_cs, dsw2_cs, dsw1_cs;
reg                 shared_cs, i8039_irq_cs, i8039_wdog_cs;
wire                snd_irq;
`ifdef MZONE_FAST_SOUND
reg         [ 7:0]  fast_timer;
`endif

function [1:0] rc_sel(input [1:0] sel);
begin
    rc_sel = sel[0] ? 2'b01 :
             sel[1] ? 2'b10 :
                      2'b00;
end
endfunction

function [7:0] pack_in0(input dummy);
begin
    pack_in0 = { 3'b111, cab_1p[1], cab_1p[0], service, coin[1], coin[0] };
end
endfunction

function [7:0] pack_in1(input dummy);
begin
    pack_in1 = { 2'b11, joystick1[5:0] };
end
endfunction

function [7:0] pack_in2(input dummy);
begin
    pack_in2 = { 2'b11, joystick2[5:0] };
end
endfunction

assign rom_addr    = A[12:0];
assign shared_addr = A[10:0];
assign shared_dout = cpu_dout;
assign shared_we   = shared_cs && !wr_n;
`ifndef MZONE_FAST_SOUND
assign ay0a_rcen   = ay0a_rcen_r;
assign ay0b_rcen   = ay0b_rcen_r;
assign ay0c_rcen   = ay0c_rcen_r;
assign ay0a        = { {2{ay_a8[7]}}, ay_a8 };
assign ay0b        = { {2{ay_b8[7]}}, ay_b8 };
assign ay0c        = { {2{ay_c8[7]}}, ay_c8 };
`else
assign ay0a_rcen   = 2'd0;
assign ay0b_rcen   = 2'd0;
assign ay0c_rcen   = 2'd0;
assign ay0a        = 10'd0;
assign ay0b        = 10'd0;
assign ay0c        = 10'd0;
assign dac         = 8'd0;
assign dac_addr    = 12'd0;
assign dac_cs      = 1'b0;
assign dac_cen     = 1'b0;
assign dac_status  = { fast_timer[7:4], 4'd0 };
assign ay_dout     = dac_status;
assign ay_iob      = 8'd0;
`endif
assign wait_n      = ((~rom_cs) | rom_ok) & ((~shared_cs) | ~h2);
assign wdog_reset_n = ~i8039_wdog_cs;
assign snmi_set_n   = ~rst & (wdog_reset_n | A[0]);
assign int_n        = ~snd_irq;
assign main_irq_req = iorq_n && !wr_n && A == 16'ha000;

// PCB Z80 clock is 18.432 MHz / (3*2) = 3.072 MHz. The core clock here is
// 24 MHz, so generate an exact 24 MHz * 16 / 125 enable.
jtframe_frac_cen #(.W(2),.WC(8)) u_cpu_cen(
    .clk    ( clk      ),
    .n      ( 8'd16    ),
    .m      ( 8'd125   ),
    .cen    ( cpu_cen_v ),
    .cenb   (          )
);

jtframe_cen3p57 #(.CLK24(1)) u_ay_cen(
    .clk      ( clk      ),
    .cen_3p57 (          ),
    .cen_1p78 ( ay_cen   )
);

`ifndef MZONE_FAST_SOUND
jtframe_frac_cen #(.W(2),.WC(8)) u_dac_cen(
    .clk    ( clk       ),
    .n      ( 8'd7      ),  // close to 14.31818 MHz / 2 from the 24 MHz sound clock
    .m      ( 8'd24     ),
    .cen    ( dac_cen_v ),
    .cenb   (           )
);
`endif

assign cpu_cen = cpu_cen_v[0];
`ifndef MZONE_FAST_SOUND
assign dac_cen = dac_cen_v[0];
`endif

always @(*) begin
    rom_cs       = 0;
    latch_cs     = 0;
    inp0_cs      = 0;
    inp1_cs      = 0;
    inp2_cs      = 0;
    dsw2_cs      = 0;
    dsw1_cs      = 0;
    shared_cs    = 0;
    i8039_irq_cs = 0;
    i8039_wdog_cs= 0;

    if( !mreq_n && rfsh_n ) begin
        if( A[15:13] == 3'b000 ) rom_cs = !rd_n;
        if( A == 16'h2000 ) i8039_irq_cs = !wr_n;
        if( A == 16'h4000 ) latch_cs = !wr_n;
        if( A == 16'h6000 ) inp0_cs = 1'b1;
        if( A == 16'h6001 ) inp1_cs = 1'b1;
        if( A == 16'h6002 ) inp2_cs = 1'b1;
        if( A == 16'h8000 ) dsw2_cs = 1'b1;
        if( A == 16'h8001 ) dsw1_cs = 1'b1;
        if( A == 16'hc001 ) i8039_wdog_cs = !wr_n;
        if( A[15:11] == 5'h1c ) shared_cs = 1'b1;
    end
end

always @(*) begin
    cpu_din = 8'hff;
    if( rom_cs ) begin
        cpu_din = rom_data;
    end else if( shared_cs ) begin
        cpu_din = shared_din;
    end else if( ay_rd ) begin
        cpu_din = ay_dout;
    end else if( inp0_cs ) begin
        cpu_din = pack_in0(1'b0);
    end else if( inp1_cs ) begin
        cpu_din = pack_in1(1'b0);
    end else if( inp2_cs ) begin
        cpu_din = pack_in2(1'b0);
    end else if( dsw2_cs ) begin
        cpu_din = dipsw_b;
    end else if( dsw1_cs ) begin
        cpu_din = dipsw_a;
    end
end

always @(posedge clk) begin
    if( rst ) begin
        ay0a_rcen_r <= 2'd0;
        ay0b_rcen_r <= 2'd0;
        ay0c_rcen_r <= 2'd0;
`ifdef MZONE_FAST_SOUND
        fast_timer  <= 8'd0;
`endif
    end else begin
`ifndef MZONE_FAST_SOUND
        ay0a_rcen_r <= rc_sel(ay_iob[1:0]);
        ay0b_rcen_r <= rc_sel(ay_iob[3:2]);
        ay0c_rcen_r <= rc_sel(ay_iob[5:4]);
`else
        if( ay_cen ) fast_timer <= fast_timer + 8'd1;
`endif
    end
end

jtframe_ff u_irq(
    .rst      ( rst         ),
    .clk      ( clk         ),
    .cen      ( 1'b1        ),
    .din      ( 1'b1        ),
    .q        ( snd_irq     ),
    .qn       (             ),
    .set      ( 1'b0        ),
    .clr      ( irq_rst     ),
    .sigedge  ( blank       )
);

// B_C9 / INTMAIN path: sound write at A000 asserts the main-CPU request.
jtframe_ff u_main_irq(
    .rst      ( rst          ),
    .clk      ( clk          ),
    .cen      ( 1'b1         ),
    .din      ( 1'b1         ),
    .q        (              ),
    .qn       ( main_irq_n   ),
    .set      ( 1'b0         ),
    .clr      ( main_irq_ack ),
    .sigedge  ( main_irq_req )
);

assign ay_oa = dac_status;
assign ay_rd      = !iorq_n && !rd_n && (A[1:0] <= 2'd2);
assign ay_wr_addr = !iorq_n && !wr_n && (A[1:0] == 2'd0);
assign ay_wr_data = !iorq_n && !wr_n && (A[1:0] == 2'd2);

// LS74 ~RST = (~SIORQ | ~SM1) & ~RESET, converted to active-high reset.
assign irq_rst = rst | (!iorq_n && !m1_n);

jtframe_ff u_snmi(
    .rst      ( rst         ),
    .clk      ( clk         ),
    .cen      ( 1'b1        ),
    .din      ( 1'b1        ),
    .q        (             ),
    .qn       ( snmi_n      ),
    .set      ( ~snmi_set_n ),
    .clr      ( 1'b0        ),
    .sigedge  ( main_int    )
);

jtframe_z80 u_cpu(
    .rst_n      ( ~rst      ),
    .clk        ( clk       ),
    .cen        ( cpu_cen   ),
    .wait_n     ( wait_n    ),
    .int_n      ( int_n     ),
    .nmi_n      ( snmi_n    ),
    .busrq_n    ( 1'b1      ),
    .m1_n       ( m1_n      ),
    .mreq_n     ( mreq_n    ),
    .iorq_n     ( iorq_n    ),
    .rd_n       ( rd_n      ),
    .wr_n       ( wr_n      ),
    .rfsh_n     ( rfsh_n    ),
    .halt_n     (           ),
    .busak_n    (           ),
    .A          ( A         ),
    .din        ( cpu_din   ),
    .dout       ( cpu_dout  )
);

`ifndef MZONE_FAST_SOUND
jt49_bus u_ay(
    .rst_n      ( ~rst      ),
    .clk        ( clk       ),
    .clk_en     ( ay_cen    ),
    .bdir       ( ay_wr_addr | ay_wr_data ),
    .bc1        ( ay_wr_addr | ay_rd      ),
    .din        ( cpu_dout  ),
    .sel        ( 1'b1      ),
    .dout       ( ay_dout   ),
    .sound      (           ),
    .sample     (           ),
    .IOA_in     ( ay_oa     ),
    .IOA_out    (           ),
    .IOA_oe     (           ),
    .IOB_in     ( 8'd0      ),
    .IOB_out    ( ay_iob    ),
    .IOB_oe     (           ),
    .A          ( ay_a8     ),
    .B          ( ay_b8     ),
    .C          ( ay_c8     )
);

// B4 8039 DAC MCU
jtmzone_8039 u_b4(
    .rst        ( rst                    ),
    .clk        ( clk                    ),
    .cen        ( dac_cen                ),
    .din        ( cpu_dout               ),
    .latch_we   ( latch_cs && !wr_n      ),
    .irq_we     ( i8039_irq_cs && !wr_n  ),
    .status     ( dac_status             ),
    .rom_addr   ( dac_addr               ),
    .rom_cs     ( dac_cs                 ),
    .rom_data   ( dac_data               ),
    .rom_ok     ( dac_ok                 ),
    .dac        ( dac                    )
);
`endif

`else
assign rom_addr    = 0;
assign dac_addr    = 0;
assign dac_cs      = 0;
assign shared_addr = 0;
assign shared_dout = 0;
assign shared_we   = 0;
assign main_irq_n  = 1'b1;
assign ay0a        = 0;
assign ay0b        = 0;
assign ay0c        = 0;
assign ay0a_rcen   = 0;
assign ay0b_rcen   = 0;
assign ay0c_rcen   = 0;
assign dac         = 0;

always @(*) begin
    rom_cs = 1'b0;
end
`endif
endmodule
