/*  This file is part of JTCORES.
    JTCORES program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version. */

module jtmzone_objdraw(
    input               rst,
    input               clk,
    input               pxl_cen,
    input               obj_cen,

    input               LHBL,
    input        [ 8:0] hdump,

    input               draw,
    output reg          busy,

    input        [ 7:0] code,
    input        [ 8:0] xpos,
    input        [ 3:0] pal,
    input               hflip,
    input               rom_hflip,
    input        [ 3:0] ysub,

    input        [ 3:0] prog_data,
    input        [ 7:0] prog_addr,
    input               prog_en,

    output reg   [13:0] rom_addr,
    output reg          rom_cs,
    input        [15:0] rom_data,
    input               rom_ok,

    output       [ 3:0] pxl,
    output              pxl_en
);

localparam [8:0] HOFFSET = 9'd0;
localparam [8:0] HVISIBLE = 9'd288;
localparam [8:0] OBJ_START = 9'd44;
localparam [8:0] OBJ_VISIBLE = 9'd48;

reg        lhbl_l;
reg [ 1:0] group;
reg [ 1:0] dr_st;
reg [ 7:0] low_byte, high_byte;
reg [ 3:0] pix_cnt;
reg        req_byte_lsb;
reg        rom_done;
reg [15:0] rom_data_l;
reg        buf_we;
reg [ 3:0] draw_pen;
reg [ 3:0] cur_pal;
reg [ 7:0] cur_code;
reg [ 8:0] cur_xpos;
reg [ 3:0] cur_ysub;
reg        cur_hflip, cur_rom_hflip;
reg        draw_line_has_obj;
reg        read_line_has_obj;
`ifdef MZONE_OBJ_WATCH
reg [7:0] watch_code;
`endif
wire [ 3:0] draw_lut_pxl;
wire [ 3:0] lut_pxl;
wire       line_start = lhbl_l && !LHBL;
wire [8:0] hread = hdump - HOFFSET;
wire       buf_active = hdump >= OBJ_START && hdump < HVISIBLE;
wire       obj_visible = hdump >= OBJ_VISIBLE && hdump < HVISIBLE;
wire       buf_rd = pxl_cen && buf_active;
wire [5:0] row_base = cur_ysub[3] ? {3'b100,cur_ysub[2:0]} : {3'b000,cur_ysub[2:0]};
wire [1:0] rom_group = cur_rom_hflip ? ~group : group;
wire [1:0] next_group = group + 2'd1;
wire [1:0] next_rom_group = cur_rom_hflip ? ~next_group : next_group;
wire [15:0] byte_addr = {2'd0,cur_code,6'd0} + {10'd0,row_base} + {11'd0,rom_group,3'd0};
wire [15:0] next_byte_addr = {2'd0,cur_code,6'd0} + {10'd0,row_base} + {11'd0,next_rom_group,3'd0};
wire [15:0] high_byte_addr = byte_addr + 16'h4000;
wire [5:0] start_row_base = ysub[3] ? {3'b100,ysub[2:0]} : {3'b000,ysub[2:0]};
wire [15:0] start_byte_addr = {2'd0,code,6'd0} +
                               {10'd0,start_row_base} +
                               {11'd0,(rom_hflip ? 2'd3 : 2'd0),3'd0};
wire [8:0] draw_x = cur_hflip ? cur_xpos + 9'd15 - { 5'd0, group, 2'd0 } - {7'd0,pix_cnt[1:0]} :
                                 cur_xpos + { 5'd0, group, 2'd0 } + {7'd0,pix_cnt[1:0]};
wire [9:0] draw_addr = lbuf_addr(draw_x[7:0]);
wire [9:0] read_addr = lbuf_addr(hread[7:0]);

function [9:0] lbuf_addr;
    input [7:0] xpos2;
begin
    lbuf_addr = {
        xpos2[3], xpos2[2], xpos2[1], xpos2[0],
        xpos2[4], xpos2[5], xpos2[6],
        2'b00,
        xpos2[7]
    };
end
endfunction

always @* begin
    case( pix_cnt[1:0] )
        2'd0: draw_pen = { high_byte[0], high_byte[4], low_byte[0], low_byte[4] };
        2'd1: draw_pen = { high_byte[1], high_byte[5], low_byte[1], low_byte[5] };
        2'd2: draw_pen = { high_byte[2], high_byte[6], low_byte[2], low_byte[6] };
        default: draw_pen = { high_byte[3], high_byte[7], low_byte[3], low_byte[7] };
    endcase
end

always @(posedge clk) begin
    lhbl_l <= LHBL;
    if( rst ) begin
        busy     <= 1'b0;
        rom_cs   <= 1'b0;
        rom_addr <= 14'd0;
        group    <= 2'd0;
        dr_st    <= 2'd0;
        pix_cnt  <= 4'd0;
        rom_done <= 1'b0;
        rom_data_l <= 16'd0;
        buf_we   <= 1'b0;
        draw_line_has_obj <= 1'b0;
        read_line_has_obj <= 1'b0;
`ifdef MZONE_OBJ_WATCH
        watch_code <= 8'd0;
`endif
    end else begin
        buf_we <= 1'b0;

        if( rom_ok ) begin
            rom_done <= 1'b1;
            rom_data_l <= rom_data;
        end

        if( line_start ) begin
            read_line_has_obj <= draw_line_has_obj;
            draw_line_has_obj <= 1'b0;
        end

        if( obj_cen ) begin
            case( dr_st )
                2'd0: if( draw && !busy ) begin
                    cur_code      <= code;
                    cur_xpos      <= xpos;
                    cur_pal       <= pal;
                    cur_hflip     <= hflip;
                    cur_rom_hflip <= rom_hflip;
                    cur_ysub      <= ysub;
`ifdef MZONE_OBJ_WATCH
                    watch_code     <= code;
`endif
                    group         <= 2'd0;
                    rom_addr      <= start_byte_addr[14:1];
                    req_byte_lsb  <= start_byte_addr[0];
                    rom_done      <= 1'b0;
                    rom_cs        <= 1'b1;
                    busy          <= 1'b1;
                    dr_st         <= 2'd1;
                end
                2'd1: if( rom_done ) begin
                    low_byte <= req_byte_lsb ? rom_data_l[15:8] : rom_data_l[7:0];
                    rom_addr <= high_byte_addr[14:1];
                    rom_cs   <= 1'b1;
                    req_byte_lsb <= high_byte_addr[0];
                    rom_done <= 1'b0;
                    dr_st <= 2'd2;
                end
                2'd2: if( rom_done ) begin
                    high_byte <= req_byte_lsb ? rom_data_l[15:8] : rom_data_l[7:0];
                    rom_cs    <= 1'b0;
                    rom_done  <= 1'b0;
                    pix_cnt   <= 4'd0;
                    dr_st     <= 2'd3;
                end
                2'd3: begin
                    if( pix_cnt < 4'd4 ) begin
                        buf_we  <= 1'b1;
`ifdef MZONE_OBJ_WATCH
                        if( watch_code==8'haa )
                            $display("MZONE_OBJ_DRAW hdump=%0d xpos=%0d group=%0d pix=%0d draw_x=%0d draw_addr=%03x pen=%x lut=%x",
                                hdump, cur_xpos, group, pix_cnt[1:0], draw_x, draw_addr,
                                draw_pen, draw_lut_pxl);
`endif
                        pix_cnt <= pix_cnt + 4'd1;
                        if( draw_lut_pxl != 4'd0 ) draw_line_has_obj <= 1'b1;
                    end else if( group==2'd3 ) begin
                        busy  <= 1'b0;
                        dr_st <= 2'd0;
                    end else begin
                        group <= next_group;
                        rom_addr <= next_byte_addr[14:1];
                        req_byte_lsb <= next_byte_addr[0];
                        rom_done <= 1'b0;
                        rom_cs <= 1'b1;
                        pix_cnt <= 4'd0;
                        dr_st <= 2'd1;
                    end
                end
            endcase
        end
    end
end

jtframe_obj_buffer #(
    .AW     ( 10 ),
    .DW     ( 4 ),
    .ALPHAW ( 4 ),
    .ALPHA  ( 0 )
) u_line(
    .clk    ( clk          ),
    .LHBL   ( LHBL         ),
    .flip   ( 1'b0         ),
    .wr_data( draw_lut_pxl ),
    .wr_addr( draw_addr     ),
    .we     ( buf_we       ),
    .rd_addr( read_addr     ),
    .rd     ( buf_rd       ),
    .rd_data( lut_pxl       )
);

`ifdef MZONE_NOOBJ
assign pxl = 4'd0;
assign pxl_en = 1'b0;
`else
assign pxl_en = pxl_cen && obj_visible && read_line_has_obj && lut_pxl != 4'd0;
assign pxl = pxl_en ? lut_pxl : 4'd0;
`endif

jtframe_prom #(
    .DW     ( 4 ),
    .AW     ( 8 ),
    .ASYNC  ( 1 )
) u_obj_lut(
    .clk    ( clk                    ),
    .cen    ( pxl_cen                ),
    .data   ( prog_data              ),
    .wr_addr( prog_addr              ),
    .we     ( prog_en                ),
    .rd_addr( { cur_pal, draw_pen }  ),
    .q      ( draw_lut_pxl           )
);

endmodule
