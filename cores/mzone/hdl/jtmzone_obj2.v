/*  This file is part of JTCORES.
    JTCORES program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version. */

module jtmzone_obj2(
    input               rst,
    input               clk,
    input               pxl_cen,

    input               LHBL,
    input               LVBL,
    input        [ 8:0] hdump,
    input        [ 8:0] vdump,
    input               flip,

    output reg   [ 9:0] ram_addr,
    input        [ 7:0] ram_data,

    output reg   [13:0] rom_addr,
    output reg          rom_cs,
    input        [15:0] rom_data,
    input               rom_ok,

    input        [ 3:0] prog_data,
    input        [ 7:0] prog_addr,
    input               prog_en,

    output       [ 3:0] pxl,
    output              pxl_en
);

localparam [8:0] HOFFSET = 9'd0;
localparam [8:0] HVISIBLE = 9'd288;

reg        lhbl_l;
`ifdef MZONE_OBJ_WATCH
reg        lvbl_l;
reg [15:0] frame_cnt;
`endif
reg [ 9:0] scan_base;
reg [ 3:0] scan_st;
reg [ 7:0] attr, ypos, code, xpos;
reg [ 7:0] spram [0:1023];
reg [ 9:0] copy_addr, copy_addr_l;
integer spram_i;
reg [ 7:0] line_y;
reg [ 3:0] obj_y;
reg        obj_hflip, obj_rom_hflip, obj_vflip;
reg [ 3:0] obj_color;
reg [ 8:0] obj_x;
reg [ 1:0] group;
reg [ 7:0] low_byte, high_byte;
reg [ 3:0] pix_cnt;
reg        req_byte_lsb;
reg        buf_we;
reg [ 3:0] draw_pen;
reg        draw_line_has_obj;
reg        read_line_has_obj;
wire [ 3:0] buf_pen;
wire [ 3:0] buf_color_out;
wire [ 3:0] lut_pxl;
wire       line_start = lhbl_l && !LHBL;
wire [7:0] objram_q = spram[ram_addr];
wire [7:0] raw_sy = 8'd255 - (ypos + 8'd16);
wire [7:0] ydiff  = line_y - raw_sy;
wire       inzone = ydiff < 8'd16;
wire [3:0] row    = obj_vflip ? ~ydiff[3:0] : ydiff[3:0];
wire [3:0] first_row = attr[7] ? ~ydiff[3:0] : ydiff[3:0];
wire [5:0] row_base = row[3] ? {3'b100,row[2:0]} : {3'b000,row[2:0]};
wire [5:0] first_row_base = first_row[3] ? {3'b100,first_row[2:0]} : {3'b000,first_row[2:0]};
wire [1:0] rom_group = obj_rom_hflip ? ~group : group;
wire [1:0] first_rom_group = attr[6] ? 2'd3 : 2'd0;
wire [15:0] byte_addr = {2'd0,code,6'd0} + {10'd0,row_base} + {11'd0,rom_group,3'd0};
wire [15:0] first_byte_addr = {2'd0,code,6'd0} + {10'd0,first_row_base} + {11'd0,first_rom_group,3'd0};
wire [15:0] high_byte_addr = byte_addr + 16'h4000;
wire [1:0]  next_group = group + 2'd1;
wire [5:0]  obj_row_base = obj_y[3] ? {3'b100,obj_y[2:0]} : {3'b000,obj_y[2:0]};
wire [1:0]  next_rom_group = obj_rom_hflip ? ~next_group : next_group;
wire [15:0] next_byte_addr = {2'd0,code,6'd0} + {10'd0,obj_row_base} + {11'd0,next_rom_group,3'd0};
wire [8:0] hread = hdump - HOFFSET;
wire       buf_rd = pxl_cen && hread < HVISIBLE;
wire [8:0] draw_addr = obj_hflip ? obj_x + 9'd15 - { 5'd0, group, 2'd0 } - {7'd0,pix_cnt[1:0]} :
                                    obj_x + { 5'd0, group, 2'd0 } + {7'd0,pix_cnt[1:0]};

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
`ifdef MZONE_OBJ_WATCH
    lvbl_l <= LVBL;
`endif
    if( rst ) begin
        scan_st   <= 4'd0;
        scan_base <= 10'h3fc;
        ram_addr  <= 10'd0;
        rom_addr  <= 14'd0;
        rom_cs    <= 1'b0;
        buf_we    <= 1'b0;
        pix_cnt   <= 4'd0;
        req_byte_lsb <= 1'b0;
        copy_addr <= 10'd0;
        copy_addr_l <= 10'd0;
        draw_line_has_obj <= 1'b0;
        read_line_has_obj <= 1'b0;
        for( spram_i=0; spram_i<1024; spram_i=spram_i+1 )
            spram[spram_i] = 8'd0;
`ifdef MZONE_OBJ_WATCH
        lvbl_l    <= 1'b0;
        frame_cnt <= 16'd0;
`endif
    end else begin
`ifdef MZONE_OBJ_WATCH
        if( LVBL && !lvbl_l ) frame_cnt <= frame_cnt + 16'd1;
`endif
        buf_we <= 1'b0;
        if( !LVBL ) begin
            ram_addr <= copy_addr;
            spram[copy_addr_l] <= ram_data;
            copy_addr_l <= copy_addr;
            copy_addr <= copy_addr + 10'd1;
            scan_st <= 4'd0;
            rom_cs <= 1'b0;
        end else if( line_start ) begin
            scan_st   <= 4'd1;
            scan_base <= 10'h3fc;
            ram_addr  <= 10'h3fc;
            line_y    <= vdump[7:0];
            rom_cs    <= 1'b0;
            read_line_has_obj <= draw_line_has_obj;
            draw_line_has_obj <= 1'b0;
        end else begin
            case( scan_st )
                4'd0: begin
                    rom_cs <= 1'b0;
                end
                4'd1: begin
                    attr     <= objram_q;
                    ram_addr <= scan_base + 10'd1;
                    scan_st  <= 4'd2;
                end
                4'd2: begin
                    ypos     <= objram_q;
                    ram_addr <= scan_base + 10'd2;
                    scan_st  <= 4'd3;
                end
                4'd3: begin
                    code     <= objram_q;
                    ram_addr <= scan_base + 10'd3;
                    scan_st  <= 4'd4;
                end
                4'd4: begin
                    xpos       <= objram_q;
                    obj_color  <= attr[3:0];
                    obj_hflip  <=  attr[6];
                    obj_rom_hflip <= ~attr[6];
                    obj_vflip  <=  attr[7];
                    obj_y      <= first_row;
                    obj_x      <= flip ? {1'b0,objram_q} - 9'd11 :
                                          {1'b0,objram_q} + 9'd32;
                    group      <= 2'd0;
                    if( inzone && LVBL ) begin
`ifdef MZONE_OBJ_WATCH
                        if( frame_cnt >= `MZONE_OBJ_WATCH_FROM && frame_cnt <= `MZONE_OBJ_WATCH_TO )
                            $display("MZONE_OBJ frame=%0d line=%0d base=%03x attr=%02x ypos=%02x code=%02x xpos=%02x raw_sy=%02x ydiff=%02x row=%x hflip=%b vflip=%b color=%x",
                                frame_cnt, line_y, scan_base, attr, ypos, code, objram_q,
                                raw_sy, ydiff, first_row, attr[6], attr[7], attr[3:0]);
`endif
                        rom_addr <= first_byte_addr[14:1];
                        req_byte_lsb <= first_byte_addr[0];
                        rom_cs   <= 1'b1;
                        scan_st  <= 4'd5;
                    end else begin
                        scan_st  <= 4'd7;
                    end
                end
                4'd5: if( rom_ok ) begin
                    low_byte <= req_byte_lsb ? rom_data[15:8] : rom_data[7:0];
                    rom_addr <= high_byte_addr[14:1];
                    rom_cs   <= 1'b1;
                    scan_st  <= 4'd9;
                end
                4'd9: begin
                    rom_cs  <= 1'b1;
                    scan_st <= 4'd6;
                end
                4'd6: if( rom_ok ) begin
                    high_byte <= req_byte_lsb ? rom_data[15:8] : rom_data[7:0];
                    pix_cnt   <= 4'd0;
                    rom_cs    <= 1'b0;
                    scan_st   <= 4'd8;
                end
                4'd7: begin
                    scan_st <= scan_base==10'd0 ? 4'd0 : 4'd1;
                    if( scan_base!=10'd0 ) begin
                        scan_base <= scan_base - 10'd4;
                        ram_addr  <= scan_base - 10'd4;
                    end
                end
                4'd8: begin
                    if( pix_cnt < 4'd4 ) begin
                        buf_we   <= 1'b1;
`ifdef MZONE_OBJ_PIX_WATCH
`ifndef MZONE_OBJ_PIX_WATCH_CODE
`define MZONE_OBJ_PIX_WATCH_CODE 8'haa
`endif
                        if( frame_cnt >= `MZONE_OBJ_WATCH_FROM && frame_cnt <= `MZONE_OBJ_WATCH_TO && code==`MZONE_OBJ_PIX_WATCH_CODE )
                            $display("MZONE_OBJ_PIX frame=%0d line=%0d row=%x group=%0d pix=%0d addr=%0d pen=%x low=%02x high=%02x hflip=%b",
                                frame_cnt, line_y, obj_y, group, pix_cnt[1:0], draw_addr, draw_pen, low_byte, high_byte, obj_hflip);
`endif
`ifdef MZONE_OBJ_WRITE_WATCH
                        if( frame_cnt >= `MZONE_OBJ_WATCH_FROM && frame_cnt <= `MZONE_OBJ_WATCH_TO &&
                            draw_pen != 4'd0 &&
                            draw_addr >= `MZONE_OBJ_WRITE_X0 && draw_addr <= `MZONE_OBJ_WRITE_X1 &&
                            line_y >= `MZONE_OBJ_WRITE_Y0 && line_y <= `MZONE_OBJ_WRITE_Y1 )
                            $display("MZONE_OBJ_WR frame=%0d line=%0d base=%03x attr=%02x code=%02x color=%x row=%x group=%0d pix=%0d addr=%0d pen=%x low=%02x high=%02x hflip=%b",
                                frame_cnt, line_y, scan_base, attr, code, obj_color, obj_y,
                                group, pix_cnt[1:0], draw_addr, draw_pen, low_byte, high_byte, obj_hflip);
`endif
                        if( draw_pen != 4'd0 ) draw_line_has_obj <= 1'b1;
                        pix_cnt <= pix_cnt + 4'd1;
                    end else if( group != 2'd3 ) begin
                        group    <= next_group;
                        rom_addr <= next_byte_addr[14:1];
                        req_byte_lsb <= next_byte_addr[0];
                        rom_cs   <= 1'b1;
                        scan_st  <= 4'd5;
                    end else begin
                        scan_st <= 4'd7;
                    end
                    end
                default: scan_st <= 4'd0;
            endcase
        end
    end
end

jtframe_obj_buffer #(
    .AW     ( 9 ),
    .DW     ( 8 ),
    .ALPHAW ( 4 ),
    .ALPHA  ( 0 )
) u_line(
    .clk    ( clk          ),
    .LHBL   ( LHBL         ),
    .flip   ( 1'b0         ),
    .wr_data( { obj_color, draw_pen } ),
    .wr_addr( draw_addr     ),
    .we     ( buf_we       ),
    .rd_addr( hread         ),
    .rd     ( buf_rd       ),
    .rd_data( { buf_color_out, buf_pen })
);

`ifdef MZONE_NOOBJ
assign pxl = 4'd0;
assign pxl_en = 1'b0;
`else
assign pxl_en = buf_rd && read_line_has_obj && lut_pxl != 4'd0;
assign pxl = buf_rd && read_line_has_obj && lut_pxl != 4'd0 ? lut_pxl : 4'd0;
`endif

`ifdef MZONE_OBJ_COLOR_WATCH
always @(posedge clk) if( pxl_cen && pxl_en &&
    frame_cnt >= `MZONE_OBJ_WATCH_FROM && frame_cnt <= `MZONE_OBJ_WATCH_TO &&
    hdump >= `MZONE_OBJ_COLOR_X0 && hdump <= `MZONE_OBJ_COLOR_X1 &&
    vdump >= `MZONE_OBJ_COLOR_Y0 && vdump <= `MZONE_OBJ_COLOR_Y1 ) begin
    $display("MZONE_OBJ_COLOR frame=%0d x=%0d y=%0d color=%x pen=%x c6_addr=%02x c6_raw=%x lut=%x",
        frame_cnt, hdump, vdump, buf_color_out, buf_pen,
        { buf_color_out, buf_pen }, lut_pxl, lut_pxl);
end
`endif

jtframe_prom #(
    .DW ( 4 ),
    .AW ( 8 ),
    .ASYNC( 1 )
) u_obj_lut(
    .clk    ( clk                    ),
    .cen    ( pxl_cen                ),
    .data   ( prog_data              ),
    .wr_addr( prog_addr              ),
    .we     ( prog_en                ),
    .rd_addr( { buf_color_out, buf_pen } ),
    .q      ( lut_pxl                )
);

endmodule
