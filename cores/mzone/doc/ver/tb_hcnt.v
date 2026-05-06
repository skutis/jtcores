`timescale 1ns/1ps

module tb_hcnt;

localparam real CLK_HALF_NS = 27.126736111; // 18.432 MHz

reg         clk       = 1'b0;
reg         rst       = 1'b0;
reg         pxl_cen   = 1'b0;
reg         flip      = 1'b0;
reg  [ 7:0] prog_data = 8'h00;
reg  [21:0] prog_addr = 22'h000000;
reg         prom_we   = 1'b0;

wire [ 8:0] hdump, hcnt_sim;
wire        hinit, LHBL, HS;
wire        h1, h2, h4, h8, h16, h16_n;
wire        clkq, clkq_n, clkq_cen;
wire        hblank_n, thblk_n, hsync_n;
wire [ 7:0] e9_q;

integer sim_us;

always #(CLK_HALF_NS) clk = ~clk;

jtmzone_hcnt uut(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .flip       ( flip      ),
    .prog_data  ( prog_data ),
    .prog_addr  ( prog_addr ),
    .prom_we    ( prom_we   ),
    .hdump      ( hdump     ),
    .hcnt_sim   ( hcnt_sim  ),
    .hinit      ( hinit     ),
    .LHBL       ( LHBL      ),
    .HS         ( HS        ),
    .h1         ( h1        ),
    .h2         ( h2        ),
    .h4         ( h4        ),
    .h8         ( h8        ),
    .h16        ( h16       ),
    .h16_n      ( h16_n     ),
    .clkq       ( clkq      ),
    .clkq_n     ( clkq_n    ),
    .clkq_cen   ( clkq_cen  ),
    .hblank_n   ( hblank_n  ),
    .thblk_n    ( thblk_n   ),
    .hsync_n    ( hsync_n   ),
    .e9_q       ( e9_q      )
);

initial begin
    $dumpfile("hcnt.vcd");
    $dumpvars(0, tb_hcnt);

    pxl_cen = 1'b1;

    if( !$value$plusargs("US=%d", sim_us) )
        sim_us = 1000;

    #(sim_us * 1000);

    $display("MZONE hcnt done hdump=%03x e9=%02x LHBL=%b HS=%b HBLK_N=%b THBLK_N=%b",
        hdump, e9_q, LHBL, HS, hblank_n, thblk_n);
    $finish;
end

endmodule
