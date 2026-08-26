/*  This file is part of JTCORES.
    JTCORES program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version. */

module jtmzone_objdraw(
    input               rst,
    input               clk,
    input               pxl_cen,
    input               cen2,

    input               HS,
    input        [ 8:0] hdump,
    input        [ 8:0] vdump,
    input               flip,

    input               draw,
    output reg          busy,

    input        [ 7:0] code,
    input        [ 8:0] xpos,
    input        [ 3:0] pal,
    input               hflip,
    input        [ 3:0] ysub,

    input        [ 3:0] prog_data,
    input        [ 7:0] prog_addr,
    input               prog_en,

    output reg   [12:0] rom_addr,
    output reg          rom_cs,
    input        [31:0] rom_data,
    input               rom_ok,

    output       [ 3:0] pxl
);

// Mixer-aligned physical read origins. The object RAM and wrapper registers
// settle within one four-master-clock pixel period.
localparam [8:0] HOFFSET      = 9'd54;
localparam [8:0] HOFFSET_FLIP = 9'd6;
localparam [7:0] PCB_RD_ORIGIN      = 8'd9;
localparam [7:0] PCB_RD_ORIGIN_FLIP = 8'd16;
localparam [7:0] RAM_RD_PHASE  = 8'd1;

reg [ 1:0] dr_st;
reg [31:0] pxl_data;
reg [ 2:0] cnt;
reg [ 3:0] cur_pal;
reg        cur_hflip;
reg [ 7:0] buf_a;
reg        buf_we;
reg  [7:0] buf_al;
reg        buf_wel;
wire [ 3:0] draw_pal_pxl;
wire [ 3:0] pal_pxl;
wire [31:0] decoded_rom_data = {
    {rom_data[24],rom_data[28],rom_data[16],rom_data[20]}, // pixel 7
    {rom_data[25],rom_data[29],rom_data[17],rom_data[21]}, // pixel 6
    {rom_data[26],rom_data[30],rom_data[18],rom_data[22]}, // pixel 5
    {rom_data[27],rom_data[31],rom_data[19],rom_data[23]}, // pixel 4
    {rom_data[ 8],rom_data[12],rom_data[ 0],rom_data[ 4]}, // pixel 3
    {rom_data[ 9],rom_data[13],rom_data[ 1],rom_data[ 5]}, // pixel 2
    {rom_data[10],rom_data[14],rom_data[ 2],rom_data[ 6]}, // pixel 1
    {rom_data[11],rom_data[15],rom_data[ 3],rom_data[ 7]}  // pixel 0
};
wire [3:0] draw_pen = pxl_data[3:0];
// Switch banks on the leading edge of HS, during horizontal blank.  The
// object buffer switches on a falling LHBL input, hence the inversion.
wire       obj_buf_lhbl = ~HS;
// Layer pixels reach the color-mixer input six pixels after raw timing.
wire [8:0] hoffset = flip ? HOFFSET_FLIP : HOFFSET;
// Read the 240 visible object addresses. The delayed buffer output continues
// to drain after the final read pulse.
wire [8:0] hread = hdump - hoffset;
// The PCB starts its circular line-buffer display at address 9. The generic
// synchronous RAM/output path adds one pixel of request-to-output phase, so
// request one additional address ahead. Start the read-enable window two
// pixels before the normal sequence, requesting circular addresses 8..9;
// keep the established trailing boundary unchanged.
wire       buf_rd = pxl_cen && (hread>=9'd510 || hread<9'd240);
// Core counters run forward in both orientations; flip selects only the
// PCB-observed circular starting address.
wire [7:0] buf_rd_origin = flip ? PCB_RD_ORIGIN_FLIP : PCB_RD_ORIGIN;
wire [7:0] buf_rd_addr = hread[7:0] + buf_rd_origin + RAM_RD_PHASE;

// Match Road Fighter's synchronous object-PROM path.  The PROM result becomes
// valid one master clock after {palette,pen}; delay its line-buffer write
// address and enable by the same clock.
always @(posedge clk) begin
    if( rst ) begin
        buf_al  <= 8'd0;
        buf_wel <= 1'b0;
    end else begin
        buf_al  <= buf_a;
        // The physical object line buffer is 256 pixels wide. Sprites crossing
        // address 255 wrap to address 0 before the 0..239 display window clips
        // them, so writes must not be limited to the 240 displayed addresses.
        buf_wel <= buf_we;
    end
end

always @(posedge clk) begin
    if( rst ) begin
        busy     <= 1'b0;
        rom_cs   <= 1'b0;
        rom_addr <= 13'd0;
        dr_st    <= 2'd0;
        cnt      <= 3'd0;
        pxl_data <= 32'd0;
        buf_a    <= 8'd0;
        buf_we   <= 1'b0;
    end else begin
        if( cen2 ) case( dr_st )
            2'd0: if( draw && !busy ) begin
                cur_pal       <= pal;
                cur_hflip     <= hflip;
                buf_a         <= xpos[7:0] + (hflip ? 8'd15 : 8'd0);
                rom_addr      <= { code, ysub[3], 1'b0, ysub[2:0] };
                rom_cs        <= 1'b1;
                busy          <= 1'b1;
                dr_st         <= 2'd1;
            end
            2'd1: if( rom_cs && rom_ok ) begin
                pxl_data   <= decoded_rom_data;
                rom_cs     <= 1'b0;
                cnt         <= 3'd7;
                buf_we      <= 1'b1;
                dr_st      <= 2'd2;
            end
            2'd2: begin
                pxl_data <= pxl_data >> 4;
                buf_a    <= cur_hflip ? buf_a-8'd1 : buf_a+8'd1;
                cnt      <= cnt-3'd1;
                if( cnt==0 ) begin
                    if( rom_addr[3] ) begin
                        busy  <= 1'b0;
                        buf_we <= 1'b0;
                        dr_st <= 2'd0;
                    end else begin
                        rom_addr[3] <= 1'b1;
                        rom_cs <= 1'b1;
                        dr_st <= 2'd1;
                    end
                end
            end
            default: begin
                dr_st <= 2'd0;
            end
        endcase
    end
end

jtframe_obj_buffer #(
    .AW         ( 8  ),
    .DW         ( 4  ),
    .ALPHA      ( 0  ),
    .BLANK      ( 0  )
) u_line(
    .clk    ( clk          ),
    .LHBL   ( obj_buf_lhbl ),
    .flip   ( 1'b0         ),
    .wr_data( draw_pal_pxl ),
    .wr_addr( buf_al        ),
    .we     ( buf_wel       ),
    .rd_addr( buf_rd_addr   ),
    .rd     ( buf_rd       ),
    .rd_data( pal_pxl )
);

`ifdef MZONE_NOOBJ
assign pxl = 4'd0;
`else
assign pxl = pal_pxl;
`endif

jtframe_prom #(
    .DW     ( 4 ),
    .AW     ( 8 )
) u_palette(
    .clk    ( clk                    ),
    .cen    ( 1'b1                   ),
    .data   ( prog_data              ),
    .wr_addr( prog_addr              ),
    .we     ( prog_en                ),
    .rd_addr( { cur_pal, draw_pen } ),
    .q      ( draw_pal_pxl          )
);

endmodule
