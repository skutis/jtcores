/*  This file is part of JTCORES.
    JTCORES program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version. */

module jtmzone_objdraw(
    input               rst,
    input               clk,
    input               pxl_cen,

    input               LHBL,
    input        [ 8:0] hdump,
    input        [ 8:0] vdump,
    input               flip,

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

    output reg   [12:0] rom_addr,
    output reg          rom_cs,
    input        [31:0] rom_data,
    input               rom_ok,

    output       [ 3:0] pxl,
    output              pxl_en
);

localparam [8:0] HVISIBLE = 9'd288;
localparam [8:0] BLANK_DLY = 9'd9;
localparam [8:0] HACTIVE = HVISIBLE + BLANK_DLY;
localparam [8:0] OBJ_RD_START = 9'd51;
localparam [8:0] OBJ_RD_FLIP_BASE = 9'd306;
localparam [8:0] OBJ_RD_LIMIT = { 1'b1, OBJ_RD_START[7:0] };
localparam [8:0] OBJ_LINE_START = 9'd44;
localparam [8:0] OBJ_LINE_START_FLIP = 9'd5;

reg [ 1:0] group;
reg [ 1:0] dr_st;
reg [ 7:0] low_byte, high_byte;
reg [ 3:0] pix_cnt;
reg        wr_phase;
reg        rom_pending;
reg [31:0] rom_pending_data;
reg [ 3:0] draw_pen;
reg [ 3:0] cur_pal;
reg [ 7:0] cur_code;
reg [ 8:0] cur_xpos;
reg [ 3:0] cur_ysub;
reg        cur_hflip;
reg        cur_rom_hflip;
reg        draw_line_has_obj;
reg        read_line_has_obj;
wire [ 3:0] draw_pal_pxl;
wire [ 3:0] pal_pxl;
wire       rom_ready = rom_pending || (rom_cs && rom_ok);
wire [31:0] rom_word = rom_pending ? rom_pending_data : rom_data;
wire [15:0] raw_word = cur_ysub[0] ? rom_word[31:16] : rom_word[15:0];
wire       buf_LHBL = hdump < HACTIVE;
// PCB line-buffer handoff is around hcount 40..43, with the buffer switch
// at 44.  Visible SCROLL/OBJ pixels start later at hdump 48.
// Flipped output is already visible at final raw X=0.  Switching the flipped
// bank at 44 left read_line_has_obj and the old bank active through raw X=38;
// hdump=5 accounts for the shared buffer/mixer/blank phase at the left edge.
wire [8:0] line_h = flip ? OBJ_LINE_START_FLIP : OBJ_LINE_START;
wire       obj_buf_lhbl = hdump != line_h;
wire       line_start = pxl_cen && hdump == line_h;
// Road Fighter-style 9-bit read coordinate.  Keeping the wrap bit prevents
// the 8-bit line-buffer address from starting an unwanted clear pass before
// OBJ_RD_START on the next 384-pixel raster line.
// Flipped reads count down.  With the common two-clock buffer compensation,
// OBJ_RD_FLIP_BASE makes raw OBJ X=eb land at the same final X as non-flipped
// raw OBJ X=10, matching the MAME/PCB reference.
wire [8:0] hread = flip ? OBJ_RD_FLIP_BASE - hdump :
                          hdump - OBJ_RD_START;
wire       buf_rd = pxl_cen && hread < OBJ_RD_LIMIT;
wire [5:0] row_base = cur_ysub[3] ? {3'b100,cur_ysub[2:0]} : {3'b000,cur_ysub[2:0]};
wire [1:0] rom_group = cur_rom_hflip ? ~group : group;
wire [1:0] next_group = group + 2'd1;
wire [1:0] next_rom_group = cur_rom_hflip ? ~next_group : next_group;
wire [12:0] byte_addr = { cur_code, cur_ysub[3], rom_group, cur_ysub[2:1] };
wire [12:0] next_byte_addr = { cur_code, cur_ysub[3], next_rom_group, cur_ysub[2:1] };
wire [5:0] start_row_base = ysub[3] ? {3'b100,ysub[2:0]} : {3'b000,ysub[2:0]};
wire [12:0] start_byte_addr = { code, ysub[3], (rom_hflip ? 2'd3 : 2'd0), ysub[2:1] };
wire [8:0] draw_x_base = cur_xpos;
wire [8:0] draw_x = cur_hflip ? draw_x_base + 9'd15 - { 5'd0, group, 2'd0 } - {7'd0,pix_cnt[1:0]} :
                                 draw_x_base + { 5'd0, group, 2'd0 } + {7'd0,pix_cnt[1:0]};
wire [7:0] draw_addr = draw_x[7:0];
// The PCB launches OBJ pixels four clocks before the visible boundary.  The
// jtframe line buffer consumes two of those clocks: its dual-port RAM updates
// dump_data synchronously, then jtframe_obj_buffer registers dump_data into
// rd_data.  Lead the physical read by the remaining two clocks so raw OBJ X=0
// reaches the mixer at the SCROLL/OBJ boundary.
wire [7:0] read_addr = hread[7:0] - 8'd2;
wire       linebuf_we = wr_phase && draw_pen != 4'd0;

always @* begin
    case( pix_cnt[1:0] )
        2'd0: draw_pen = { high_byte[3], high_byte[7], low_byte[3], low_byte[7] };
        2'd1: draw_pen = { high_byte[2], high_byte[6], low_byte[2], low_byte[6] };
        2'd2: draw_pen = { high_byte[1], high_byte[5], low_byte[1], low_byte[5] };
        default: draw_pen = { high_byte[0], high_byte[4], low_byte[0], low_byte[4] };
    endcase
end

always @(posedge clk) begin
    if( rst ) begin
        busy     <= 1'b0;
        rom_cs   <= 1'b0;
        rom_addr <= 13'd0;
        group    <= 2'd0;
        dr_st    <= 2'd0;
        pix_cnt  <= 4'd0;
        wr_phase <= 1'b0;
        rom_pending <= 1'b0;
        rom_pending_data <= 32'd0;
        draw_line_has_obj <= 1'b0;
        read_line_has_obj <= 1'b0;
    end else begin
        if( rom_cs && rom_ok && !rom_pending )
            rom_pending_data <= rom_data;
        if( rom_cs && rom_ok && !rom_pending )
            rom_pending <= 1'b1;

        if( line_start ) begin
            read_line_has_obj <= draw_line_has_obj;
            draw_line_has_obj <= 1'b0;
        end

        case( dr_st )
            2'd0: if( draw && !busy ) begin
                cur_code      <= code;
                cur_xpos      <= xpos;
                cur_pal       <= pal;
                cur_hflip     <= hflip;
                cur_rom_hflip <= rom_hflip;
                cur_ysub      <= ysub;
                group         <= 2'd0;
                rom_addr      <= start_byte_addr;
                rom_cs        <= 1'b1;
                busy          <= 1'b1;
                dr_st         <= 2'd1;
            end
            2'd1: if( rom_ready ) begin
                rom_pending <= 1'b0;
                low_byte <= raw_word[7:0];
                high_byte <= raw_word[15:8];
                rom_cs    <= 1'b0;
                pix_cnt   <= 4'd0;
                wr_phase  <= 1'b0;
                dr_st     <= 2'd3;
            end
            2'd3: begin
                if( pix_cnt < 4'd4 ) begin
                    if( !wr_phase ) begin
                        wr_phase <= draw_pen != 4'd0;
                    if( draw_pen == 4'd0 )
                            pix_cnt <= pix_cnt + 4'd1;
                    end else begin
                        wr_phase <= 1'b0;
                        pix_cnt <= pix_cnt + 4'd1;
                    end
                    if( draw_pen != 4'd0 ) draw_line_has_obj <= 1'b1;
                end else if( group==2'd3 ) begin
                    wr_phase <= 1'b0;
                    busy  <= 1'b0;
                    dr_st <= 2'd0;
                end else begin
                    group <= next_group;
                    rom_addr <= next_byte_addr;
                    rom_cs <= 1'b1;
                    pix_cnt <= 4'd0;
                    wr_phase <= 1'b0;
                    dr_st <= 2'd1;
                end
            end
            default: begin
                wr_phase <= 1'b0;
                dr_st <= 2'd0;
            end
        endcase
    end
end

jtframe_obj_buffer #(
    .AW         ( 8  ),
    .DW         ( 4  ),
    .ALPHA      ( 0  ),
    .BLANK      ( 0  ),
    .KEEP_OLD   ( 1  )
) u_line(
    .clk    ( clk          ),
    .LHBL   ( obj_buf_lhbl ),
    .flip   ( 1'b0         ),
    .wr_data( draw_pal_pxl ),
    .wr_addr( draw_addr     ),
    .we     ( linebuf_we    ),
    .rd_addr( read_addr     ),
    .rd     ( buf_rd       ),
    .rd_data( pal_pxl )
);

`ifdef MZONE_NOOBJ
assign pxl = 4'd0;
assign pxl_en = 1'b0;
`else
wire obj_pxl_en_now = read_line_has_obj && pal_pxl != 4'd0;
wire [3:0] obj_pxl_now = obj_pxl_en_now ? pal_pxl : 4'd0;
assign pxl_en = obj_pxl_en_now;
assign pxl = obj_pxl_now;
`endif

jtframe_prom #(
    .DW     ( 4 ),
    .AW     ( 8 ),
    .ASYNC  ( 1 )
) u_palette(
    .clk    ( clk                    ),
    .cen    ( pxl_cen                ),
    .data   ( prog_data              ),
    .wr_addr( prog_addr              ),
    .we     ( prog_en                ),
    .rd_addr( { cur_pal, draw_pen } ),
    .q      ( draw_pal_pxl          )
);

endmodule
