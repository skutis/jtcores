`timescale 1ns/1ps

module tb_hcnt;

localparam [21:0] PROM_START = `ifdef JTFRAME_PROM_START `JTFRAME_PROM_START `else 22'h1f000 `endif;
localparam [21:0] E7_OFFSET  = PROM_START + 22'h220;
localparam [21:0] E8_OFFSET  = PROM_START + 22'h240;
localparam [31:0] E7_FSEEK   = { 10'd0, E7_OFFSET };

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

reg  [ 7:0] e7_img[0:31];
reg  [ 7:0] e8_img[0:31];
reg  [1023:0] rom_path;
integer f, rc, i;
integer sim_us;

always #5 clk = ~clk;

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

task load_proms;
    begin
        if( !$value$plusargs("ROM=%s", rom_path) )
            rom_path = "../../ver/game/rom.bin";

        f = $fopen(rom_path, "rb");
        if( f == 0 ) begin
            $display("ERROR: cannot open ROM file %0s", rom_path);
            $finish;
        end

        rc = $fseek(f, E7_FSEEK, 0);
        rc = $fread(e7_img, f);
        rc = $fread(e8_img, f);
        $fclose(f);

        $display("MZONE hcnt preload E7[00]=%02x E8[00]=%02x", e7_img[0], e8_img[0]);

        for( i=0; i<32; i=i+1 ) begin
            uut.e7[i] = e7_img[i];
            uut.e8[i] = e8_img[i];
        end
    end
endtask

initial begin
    $dumpfile("hcnt.vcd");
    $dumpvars(0, tb_hcnt);

    load_proms();
    pxl_cen = 1'b1;

    if( !$value$plusargs("US=%d", sim_us) )
        sim_us = 1000;

    #(sim_us * 1000);

    $display("MZONE hcnt done hdump=%03x e9=%02x LHBL=%b HS=%b HBLK_N=%b THBLK_N=%b",
        hdump, e9_q, LHBL, HS, hblank_n, thblk_n);
    $finish;
end

endmodule
