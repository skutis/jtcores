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

module jtmzone_8039(
    input               rst,
    input               clk,
    input               cen,

    input       [ 7:0]  din,
    input               latch_we,
    input               irq_we,

    output      [ 7:0]  status,

    output      [11:0]  rom_addr,
    output              rom_cs,
    input       [ 7:0]  rom_data,
    input               rom_ok,

    output      [ 7:0]  dac
);

wire        xtal3, ram_we;
wire [ 7:0] ram_addr, ram_din, ram_dout;
wire [ 7:0] p2_out;
reg  [ 7:0] latch, timer;
reg  [ 7:0] p2_last;
reg         irq_pending, rstn_t48;

assign rom_cs = 1'b1;
assign status = { timer[7:4], 1'b0, p2_out[6:4] };

always @(posedge clk) begin
    rstn_t48 <= ~rst;
    if( rst ) begin
        irq_pending <= 1'b0;
        latch       <= 8'd0;
        timer       <= 8'd0;
        p2_last     <= 8'd0;
    end else begin
        if( cen ) timer <= timer + 8'd1;
        if( latch_we ) latch <= din;
        if( irq_we ) irq_pending <= 1'b1;
        if( p2_out != p2_last ) begin
            p2_last <= p2_out;
            if( !p2_out[7] ) irq_pending <= 1'b0;
        end
    end
end

t48_core u_mcu(
    .reset_i        ( rstn_t48           ),
    .xtal_i         ( clk                ),
    .xtal_en_i      ( cen & (~rstn_t48 | rom_ok) ),
    .clk_i          ( clk                ),
    .en_clk_i       ( xtal3              ),
    .xtal3_o        ( xtal3              ),
    .t0_i           ( 1'b0               ),
    .t1_i           ( 1'b0               ),
    .t0_o           (                    ),
    .t0_dir_o       (                    ),
    .int_n_i        ( ~irq_pending       ),
    .ea_i           ( 1'b0               ),
    .rd_n_o         (                    ),
    .wr_n_o         (                    ),
    .psen_n_o       (                    ),
    .ale_o          (                    ),
    .db_i           ( latch              ),
    .db_o           (                    ),
    .db_dir_o       (                    ),
    .p2_i           ( 8'hff              ),
    .p2_o           ( p2_out             ),
    .p2l_low_imp_o  (                    ),
    .p2h_low_imp_o  (                    ),
    .p1_i           ( 8'd0               ),
    .p1_o           ( dac                ),
    .p1_low_imp_o   (                    ),
    .prog_n_o       (                    ),
    .pmem_addr_o    ( rom_addr           ),
    .pmem_data_i    ( rom_data           ),
    .dmem_addr_o    ( ram_addr           ),
    .dmem_we_o      ( ram_we             ),
    .dmem_data_i    ( ram_dout           ),
    .dmem_data_o    ( ram_din            )
);

jtframe_ram #(.AW(8)) u_ram(
    .clk    ( clk       ),
    .cen    ( 1'b1      ),
    .data   ( ram_din   ),
    .addr   ( ram_addr  ),
    .we     ( ram_we    ),
    .q      ( ram_dout  )
);

endmodule
