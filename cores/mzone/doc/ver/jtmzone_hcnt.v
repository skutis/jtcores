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

module jtmzone_hcnt(
    input               rst,
    input               clk,
    input               pxl_cen,
    input               flip,

    input        [ 7:0] prog_data,
    input        [21:0] prog_addr,
    input               prom_we,

    output       [ 8:0] hdump,
    output       [ 8:0] hcnt_sim,
    output              hinit,
    output              LHBL,
    output              HS,

    output              h1,
    output              h2,
    output              h4,
    output              h8,
    output              h16,
    output              h16_n,
    output              clkq,
    output              clkq_n,
    output reg          clkq_cen,
    output              hblank_n,
    output              thblk_n,
    output              hsync_n,
    output reg   [ 7:0] e9_q
);

localparam [21:0] E7_OFFSET = `ifdef JTFRAME_PROM_START `JTFRAME_PROM_START + 22'h220 `else 22'h220 `endif;
localparam [21:0] E8_OFFSET = `ifdef JTFRAME_PROM_START `JTFRAME_PROM_START + 22'h240 `else 22'h240 `endif;

reg  [3:0] c15_q;
reg  [7:0] e7[0:31];
reg  [7:0] e8[0:31];
reg  [8:0] line_x;
wire [8:0] hdisp;
reg        clkq_n_q;
reg        hsync60_clk_q;
reg  [7:0] hsync60_q;
wire [4:0] prom_addr;
wire [7:0] prom_dout;
wire [7:0] e9_d;
wire [7:0] hcnt_pcb;

wire       c15_clr_n, c15_load_n, c15_enp, c15_ent, c15_rco;
wire       e9_en_n;
wire [3:0] c15_d;
wire       h32;
wire       h64;
wire       h128;
wire       hrdp2;
wire       hrdp3;
wire       e7_oe_n, e8_oe_n;
wire       h2_n;
wire       h2_n_clkq_n;
wire       h32_n;
wire       hsync60_n, hsync68_n;
wire       hsync76_n;
wire       hsync60_clk;
wire       flip_n;
wire       hblk_n;

assign h1    = c15_q[0];
assign h2    = c15_q[1];
assign h4    = c15_q[2];
assign h8    = c15_q[3];
assign h16_n = ~c15_rco;
assign h16   = e9_q[7];
assign h32   = e9_q[0];
assign h32_n = ~h32;
assign h64   = e9_q[5];
assign h128   = e9_q[6];

assign hrdp2 = e9_q[1];
assign hrdp3 = e9_q[6];
assign h2_n  = ~h2;
assign h2_n_clkq_n = h2_n & clkq_n_q;
assign hsync60_clk = (h2 & flip) | (flip_n & h4);
assign clkq_n = clkq_n_q;
assign clkq   = ~clkq_n_q;
assign hcnt_pcb = {h128, h64, h32, h16, h8, h4, h2, h1};

// C15 is a 74LS161. The schematic ties it as a free-running counter, but
// keep the LS161 control semantics explicit instead of using a bare +1.
assign c15_clr_n  = 1'b1;
assign c15_load_n = 1'b1;
assign c15_enp    = 1'b1;
assign c15_ent    = 1'b1;
assign c15_d      = 4'd0;
assign c15_rco    = c15_ent & &c15_q;
assign e9_en_n    = ~c15_rco;
// PROM address is driven directly from E9 outputs.
// Matches the standalone sim model:
// .address({h16,h32,hrdp2,hrdp3,thblk_n})
assign prom_addr = { e9_q[7], e9_q[0], e9_q[1], e9_q[6], e9_q[5] };

// E7 ~OE1 is FLIP', E8 ~OE1 is ~FLIP'. The enables are active low.
// Reset/non-flip starts on E8. Flipped mode selects E7.
assign flip_n    = ~flip;
assign e7_oe_n   =  flip_n;
assign e8_oe_n   = ~flip_n;
assign prom_dout = !e7_oe_n ? e7[prom_addr] :
                   !e8_oe_n ? e8[prom_addr] : 8'hff;

// PROM pins O1..O8 feed E9 pins D7,D0,D1,D6,D5,D2,D3,D4.
assign e9_d = {
    prom_dout[0], // Q7: H16
    prom_dout[3], // Q6: HRD'3
    prom_dout[4], // Q5: ~THBLK
    prom_dout[7], // Q4: ~HBLANK
    prom_dout[6], // Q3: H128
    prom_dout[5], // Q2: H64
    prom_dout[2], // Q1: HRD'2
    prom_dout[1]  // Q0: H32
};

assign hsync60_n = hsync60_q[7];
assign hsync68_n = hsync60_q[4];
assign hsync76_n = hsync60_q[5];

`ifdef SIMULATION
integer hcnt_prom_log;
reg     hcnt_e7_00_log;
reg     hcnt_e8_00_log;
initial begin
    c15_q = 4'd0;
    e9_q  = 8'h00;
    for( integer i=0; i<32; i=i+1 ) begin
        e7[i] = 8'hff;
        e8[i] = 8'hff;
    end
    line_x = 9'd0;
    clkq_n_q = 1'b1;
    clkq_cen = 1'b0;
    hsync60_clk_q = 1'b0;
    hsync60_q = 8'hff;
    hcnt_prom_log = 0;
    hcnt_e7_00_log = 1'b0;
    hcnt_e8_00_log = 1'b0;
end
`endif

always @(posedge clk) begin
    clkq_cen <= 1'b0;

    if( prom_we && prog_addr >= E7_OFFSET && prog_addr < E7_OFFSET+22'h20 ) begin
        e7[prog_addr[4:0]] <= prog_data;
`ifdef SIMULATION
        if( prog_addr[4:0] == 5'h00 && !hcnt_e7_00_log ) begin
            $display("MZONE hcnt load E7[00]=%02x t=%0t", prog_data, $time);
            hcnt_e7_00_log = 1'b1;
        end
`endif
    end

    if( prom_we && prog_addr >= E8_OFFSET && prog_addr < E8_OFFSET+22'h20 ) begin
        e8[prog_addr[4:0]] <= prog_data;
`ifdef SIMULATION
        if( prog_addr[4:0] == 5'h00 && !hcnt_e8_00_log ) begin
            $display("MZONE hcnt load E8[00]=%02x t=%0t", prog_data, $time);
            hcnt_e8_00_log = 1'b1;
        end
`endif
    end

    if( pxl_cen ) begin
        // B_C10B 74LS74 timing phase. The FPGA CPU keeps clk24 as its clock;
        // clkq_cen is the rising edge of the schematic CLKQ net.
        clkq_cen <= clkq_n_q & ~h2;
        clkq_n_q <= h2;
        hsync60_clk_q <= hsync60_clk;
        if( hsync60_clk && !hsync60_clk_q )
            hsync60_q <= { hsync60_q[6:0], ~HS };

        if( !c15_load_n )
            c15_q <= c15_d;
        else if( c15_enp && c15_ent )
            c15_q <= c15_q + 4'd1;
        line_x <= line_x == 9'd383 ? 9'd0 : line_x + 9'd1;

        // E9 is a 74LS377 clocked by the pixel clock. Its active-low enable is
        // the inverted LS161 overflow from C15. Nonblocking assignments mean
        // this samples on the first pixel-clock edge where old C15 is 4'hf.
        if( !e9_en_n ) begin
`ifdef SIMULATION
            if( hcnt_prom_log < 16 ) begin
                $display("MZONE hcnt E9 load addr=%02x dout=%02x d=%02x q=%02x flip=%b t=%0t",
                    prom_addr, prom_dout, e9_d, e9_q, flip, $time);
                hcnt_prom_log = hcnt_prom_log + 1;
            end
`endif
            e9_q <= e9_d;
        end
    end
end

assign hdump = line_x;
assign hinit = line_x == 9'd383;
// Stable scan-position probe for GTKWave.
// The schematic bit taps are still exposed individually as h1/h2/h4/h8/h16
// and through e9_q; this bus is just the monotonic horizontal position.
assign hcnt_sim = line_x;
assign hblk_n   = e9_q[4];
assign hblank_n = hblk_n;
assign thblk_n  = e9_q[5];
assign hsync_n  = hblk_n | h32_n;

// Rotate the raw 384-pixel scan so the measured visible span becomes
// contiguous in JTFRAME space:
// raw visible = 257..383, 0..160  ->  public visible = 0..287
assign hdisp = (line_x >= 9'd257) ? (line_x - 9'd257) : (line_x + 9'd127);
assign LHBL  = hdisp < 9'd288;

// E10 inverts H32, B11A ORs ~H32 with ~HBLANK to create ~HSYNC, then E10
// inverts again to create HSYNC.
assign HS   = e9_q[0] & ~e9_q[4];

endmodule
