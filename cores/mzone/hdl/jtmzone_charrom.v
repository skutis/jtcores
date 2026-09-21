/* This file is part of JTCORES. Licensed under GPL-3.0-or-later. */

// One 16 kB character ROM, with independent FIX and SCROLL read ports.
// Download bytes use port 0 while the game is held in reset. At runtime both
// ports are synchronous ROM reads; neither competes for SDRAM service.
module jtmzone_charrom #(
    parameter [25:0] OFFSET = 26'h1b000
)(
    input             clk,
    input             rst,
    input      [25:0] prog_addr,
    input      [ 7:0] prog_data,
    input             prog_we,
    input      [11:0] fix_addr,
    input             fix_cs,
    output     [31:0] fix_data,
    output reg        fix_ok,
    input      [11:0] scr_addr,
    input             scr_cs,
    output     [31:0] scr_data,
    output reg        scr_ok
);

wire        write_en = prog_we && prog_addr >= OFFSET &&
                       prog_addr < OFFSET + 26'h4000;
wire [25:0] write_addr = prog_addr - OFFSET;
wire [11:0] port0_addr = write_en ? write_addr[13:2] : fix_addr;

genvar lane;
generate for( lane=0; lane<4; lane=lane+1 ) begin: g_lane
    // Match the little-endian 32-bit words supplied by the SDRAM ROM slots.
    jtframe_dual_ram #(.AW(12),.DW(8)) u_rom(
        .clk0 ( clk ),
        .addr0( port0_addr ),
        .data0( prog_data ),
        .we0  ( write_en && write_addr[1:0] == lane[1:0] ),
        .q0   ( fix_data[lane*8+:8] ),
        .clk1 ( clk ),
        .addr1( scr_addr ),
        .data1( 8'd0 ),
        .we1  ( 1'b0 ),
        .q1   ( scr_data[lane*8+:8] )
    );
end endgenerate

// These acknowledgements and RAM data update together, one clock after the
// renderer publishes an address. Do not clear ROM contents on a game reset.
always @(posedge clk) begin
    fix_ok <= !rst && fix_cs && !write_en;
    scr_ok <= !rst && scr_cs && !write_en;
end

endmodule
