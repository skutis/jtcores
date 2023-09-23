/*  This file is part of JTFRAME.
    JTFRAME program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JTFRAME program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JTFRAME.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 23-9-2023 */

module jtframe_ramslot_ctrl #(parameter
    SDRAMW   = 22,
    SW       = 3,         // number of slots
    SLOT0_DW = 16
)(
    input               rst,
    input               clk,
    input [SW-1:0]      req,
    input [SW*SDRAMW-1:0] slot_addr_req,
    input               req_rnw,        // only for slot0
    input [SLOT0_DW-1:0]slot0_din,
    input [1:0]         slot0_wrmask,   // only used if DW!=8
    output reg [SW-1:0] slot_sel,
    // SDRAM controller interface
    input               sdram_ack,
    output  reg         sdram_rd,
    output  reg         sdram_wr,
    output  reg [SDRAMW-1:0] sdram_addr,
    input               data_rdy,
    output  reg [15:0]  data_write,  // only 16-bit writes
    output  reg [ 1:0]  sdram_wrmask // each bit is active low
);

wire [SW-1:0] active = ~slot_sel & req;
reg  [SW-1:0] acthot; // priority encoding of active, only one bit is set

wire [SDRAMW-1:0] slot0_addr_req = slot_addr_req[0+:SDRAMW];
wire [SLOT0_DW*2-1:0] din2 = {2{slot0_din}};

integer i,j;

always @* begin
    acthot = 0;
    for( j=0; j<SW && acthot==0; j=j+1 ) begin
        if( active[j] ) acthot[j]=1;
    end
end

always @(posedge clk) begin
    if( rst ) begin
        sdram_addr <= 0;
        sdram_rd   <= 0;
        sdram_wr   <= 0;
        slot_sel   <= 0;
        data_write <= 0;
    end else begin
        if( sdram_ack ) begin
            sdram_rd   <= 0;
            sdram_wr   <= 0;
        end

        // accept a new request
        if( slot_sel==0 || data_rdy ) begin
            sdram_rd     <= |active;
            slot_sel     <= 0;
            sdram_wrmask <= 2'b11;
            if( active[0] ) begin
                data_write  <= din2[15:0];
                if( SLOT0_DW==8 ) begin
                    sdram_addr  <= slot0_addr_req>>1;
                    sdram_wrmask<= { ~slot0_addr_req[0], slot0_addr_req[0] };
                end else begin
                    sdram_addr  <= slot0_addr_req;
                    sdram_wrmask<= slot0_wrmask;
                end
                sdram_rd    <=  req_rnw;
                sdram_wr    <= ~req_rnw;
                slot_sel[0] <= 1;
            end else begin
                for( i=1; i<SW; i=i+1 ) begin
                    if( active[i] ) begin
                        sdram_addr  <= slot_addr_req[i*SDRAMW +: SDRAMW];
                        sdram_rd    <= 1;
                        sdram_wr    <= 0;
                        slot_sel[i] <= 1;
                    end
                end
            end
        end
    end
end

endmodule