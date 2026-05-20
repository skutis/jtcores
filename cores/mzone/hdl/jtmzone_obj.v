/*  This file is part of JTCORES.
    JTCORES program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version. */

module jtmzone_obj(
    input               rst,
    input               clk,
    input               pxl_cen,
    input               dma_cen,

    input               LHBL,
    input               LVBL,
    input        [ 8:0] hdump,
    input        [ 8:0] vdump,
    input               flip,

    output reg   [ 9:0] ram_addr,
    input        [ 7:0] ram_data,

    output       [13:0] rom_addr,
    output              rom_cs,
    input        [15:0] rom_data,
    input               rom_ok,

    input        [ 3:0] prog_data,
    input        [ 7:0] prog_addr,
    input               prog_en,

    output       [ 3:0] pxl,
    output              pxl_en
);

localparam [8:0] OBJ_START = 9'd40;
localparam [9:0] OBJ_SCAN_LAST = 10'd143*10'd4;
localparam [9:0] DMA_HCOUNTS = 10'd1008;
localparam [8:0] DMA_BYTES   = 9'd240;
localparam [9:0] DMA_STOP    = {1'b0,DMA_BYTES};

reg        lhbl_l, lvbl_l;
`ifdef MZONE_OBJ_WATCH
reg [15:0] frame_cnt;
`elsif MZONE_OBJ_DMA_WATCH
reg [15:0] frame_cnt;
`endif
reg [ 9:0] scan_base;
reg [ 9:0] obj_render_addr;
reg [ 2:0] scan_st;
reg [ 7:0] attr, ypos, code;
reg [ 9:0] copy_addr, copy_addr_l;
reg [ 7:0] copy_data_l;
reg        scan_en;
reg        dma_en, dma_wait, dma_wr;
reg [ 9:0] dma_hcnt;

reg        draw;
reg [ 7:0] dr_code;
reg [ 8:0] dr_xpos;
reg [ 3:0] dr_pal;
reg        dr_hflip, dr_rom_hflip;
reg [ 3:0] dr_ysub;
wire       busy, done;
wire       line_start = lhbl_l && !LHBL;
wire       scan_start = hdump == OBJ_START;
wire       vblk_start = !LVBL && lvbl_l;
wire       dma_hstep = dma_en && !dma_wait && pxl_cen && dma_hcnt != DMA_HCOUNTS;
wire       dma_count_step = dma_en && !dma_wait && dma_cen && copy_addr != DMA_STOP;
wire       obj_render_we = dma_en && !dma_wait && dma_wr;
wire [7:0] obj_render_q;
wire [7:0] raw_sy = 8'd255 - (ypos + 8'd16);
wire [7:0] ydiff  = vdump[7:0] - raw_sy;
wire       inzone = ydiff < 8'd16;
wire [3:0] ysub   = attr[7] ? ~ydiff[3:0] : ydiff[3:0];
wire [8:0] xpos   = flip ? {1'b0,obj_render_q} - 9'd11 :
                           {1'b0,obj_render_q} + 9'd32;

always @(posedge clk) begin
    lhbl_l <= LHBL;
    lvbl_l <= LVBL;
    if( rst ) begin
        scan_st     <= 3'd0;
        scan_base   <= 10'd0;
        obj_render_addr <= 10'd0;
        ram_addr    <= 10'd0;
        copy_addr   <= 10'd0;
        copy_addr_l <= 10'd0;
        copy_data_l <= 8'd0;
        dma_en      <= 1'b0;
        dma_wait    <= 1'b0;
        dma_wr      <= 1'b0;
        dma_hcnt    <= 10'd0;
        draw        <= 1'b0;
        dr_code     <= 8'd0;
        dr_xpos     <= 9'd0;
        dr_pal      <= 4'd0;
        dr_hflip    <= 1'b0;
        dr_rom_hflip<= 1'b0;
        dr_ysub     <= 4'd0;
        scan_en     <= 1'b0;
        lvbl_l    <= 1'b0;
`ifdef MZONE_OBJ_WATCH
        frame_cnt <= 16'd0;
`elsif MZONE_OBJ_DMA_WATCH
        frame_cnt <= 16'd0;
`endif
    end else begin
`ifdef MZONE_OBJ_WATCH
        if( LVBL && !lvbl_l ) frame_cnt <= frame_cnt + 16'd1;
`elsif MZONE_OBJ_DMA_WATCH
        if( LVBL && !lvbl_l ) frame_cnt <= frame_cnt + 16'd1;
`endif
        if( busy ) draw <= 1'b0;

        if( vblk_start ) begin
`ifdef MZONE_OBJ_DMA_WATCH
            $display("MZONE_OBJ_DMA_START frame=%0d hdump=%0d vdump=%0d LVBL=%b",
                frame_cnt, hdump, vdump, LVBL);
`endif
            copy_addr   <= 10'd0;
            copy_addr_l <= 10'd0;
            copy_data_l <= 8'd0;
            dma_wait    <= 1'b1;
            dma_en      <= 1'b1;
            dma_wr      <= 1'b0;
            dma_hcnt    <= 10'd0;
            ram_addr    <= 10'd0;
            obj_render_addr <= 10'd0;
            scan_st <= 3'd0;
            draw <= 1'b0;
            scan_en <= 1'b0;
        end else if( dma_en ) begin
            if( dma_wait ) begin
                if( dma_cen ) begin
                    dma_wait <= 1'b0;
                    dma_wr <= 1'b0;
                    copy_addr <= 10'd0;
                    copy_addr_l <= 10'd0;
                    copy_data_l <= 8'd0;
                    ram_addr <= 10'd0;
                    dma_hcnt <= 10'd0;
                end
            end else begin
                if( dma_count_step ) begin
                    if( dma_wr ) begin
`ifdef MZONE_OBJ_DMA_WATCH
                        if( copy_addr_l < 10'd32 || copy_addr_l >= DMA_STOP-10'd4 )
                            $display("MZONE_OBJ_DMA frame=%0d hcnt=%0d dst=%03x data=%02x",
                                frame_cnt, dma_hcnt, copy_addr_l, copy_data_l);
`endif
                    end
                    copy_data_l <= ram_data;
                    copy_addr_l <= copy_addr;
                    ram_addr <= copy_addr + 10'd1;
                    copy_addr <= copy_addr + 10'd1;
                    dma_wr <= 1'b1;
                end else if( dma_wr ) begin
`ifdef MZONE_OBJ_DMA_WATCH
                    if( copy_addr_l < 10'd32 || copy_addr_l >= DMA_STOP-10'd4 )
                        $display("MZONE_OBJ_DMA frame=%0d hcnt=%0d dst=%03x data=%02x",
                            frame_cnt, dma_hcnt, copy_addr_l, copy_data_l);
`endif
                    dma_wr <= 1'b0;
                end

                if( dma_hstep )
                    dma_hcnt <= dma_hcnt + 10'd1;

                if( pxl_cen && dma_hcnt==DMA_HCOUNTS && copy_addr==DMA_STOP && !dma_wr ) begin
`ifdef MZONE_OBJ_DMA_WATCH
                    $display("MZONE_OBJ_DMA_DONE frame=%0d hcnt=%0d copy_addr=%03x hdump=%0d vdump=%0d",
                        frame_cnt, dma_hcnt, copy_addr, hdump, vdump);
`endif
                    dma_en <= 1'b0;
                end
            end
        end else if( line_start ) begin
            scan_st   <= 3'd0;
            scan_base <= 10'd0;
            obj_render_addr <= 10'd0;
            draw      <= 1'b0;
            scan_en   <= 1'b0;
        end else if( scan_start ) begin
            scan_st   <= 3'd0;
            scan_base <= 10'd0;
            obj_render_addr <= 10'd0;
            draw      <= 1'b0;
            scan_en   <= 1'b1;
        end else if( scan_en && dma_cen ) begin
            case( scan_st )
                3'd0: if( !busy ) begin
                    obj_render_addr <= scan_base + 10'd1;
                    scan_st  <= 3'd1;
                end
                3'd1: begin
                    attr     <= obj_render_q;
                    obj_render_addr <= scan_base + 10'd2;
                    scan_st  <= 3'd2;
                end
                3'd2: begin
                    ypos     <= obj_render_q;
                    obj_render_addr <= scan_base + 10'd3;
                    scan_st  <= 3'd3;
                end
                3'd3: begin
                    code     <= obj_render_q;
                    obj_render_addr <= scan_base + 10'd3;
                    scan_st  <= 3'd4;
                end
                3'd4: begin
                    if( inzone && !busy ) begin
                        dr_code      <= code;
                        dr_xpos      <= xpos;
                        dr_pal       <= attr[3:0];
                        dr_hflip     <= attr[6];
                        dr_rom_hflip <= ~attr[6];
                        dr_ysub      <= ysub;
                        draw <= 1'b1;
`ifdef MZONE_OBJ_WATCH
                        if( frame_cnt >= `MZONE_OBJ_WATCH_FROM && frame_cnt <= `MZONE_OBJ_WATCH_TO )
                            $display("MZONE_OBJ frame=%0d line=%0d base=%03x attr=%02x ypos=%02x code=%02x xpos=%02x raw_sy=%02x ydiff=%02x ysub=%x hflip=%b vflip=%b color=%x",
                                frame_cnt, vdump[7:0], scan_base, attr, ypos, code, obj_render_q,
                                raw_sy, ydiff, ysub, attr[6], attr[7], attr[3:0]);
`endif
                    end
                    if( scan_base==OBJ_SCAN_LAST ) begin
                        scan_st <= 3'd0;
                        scan_en <= 1'b0;
                    end else begin
                        scan_base <= scan_base + 10'd4;
                        obj_render_addr <= scan_base + 10'd4;
                        scan_st   <= inzone ? 3'd5 : 3'd0;
                    end
                end
                3'd5: scan_st <= 3'd0;
                default: scan_st <= 3'd0;
            endcase
        end
    end
end

assign done = scan_base==OBJ_SCAN_LAST;

jtframe_dual_ram #(
    .AW ( 10 ),
    .DW ( 8  )
) u_obj_render_ram(
    .clk0   ( clk              ),
    .data0  ( copy_data_l      ),
    .addr0  ( copy_addr_l      ),
    .we0    ( obj_render_we    ),
    .q0     (                  ),

    .clk1   ( clk              ),
    .data1  ( 8'd0             ),
    .addr1  ( obj_render_addr  ),
    .we1    ( 1'b0             ),
    .q1     ( obj_render_q     )
);

jtmzone_objdraw u_draw(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .obj_cen    ( dma_cen   ),

    .LHBL       ( LHBL      ),
    .hdump      ( hdump     ),

    .draw       ( draw      ),
    .busy       ( busy      ),

    .code       ( dr_code      ),
    .xpos       ( dr_xpos      ),
    .pal        ( dr_pal       ),
    .hflip      ( dr_hflip     ),
    .rom_hflip  ( dr_rom_hflip ),
    .ysub       ( dr_ysub      ),

    .prog_data  ( prog_data ),
    .prog_addr  ( prog_addr ),
    .prog_en    ( prog_en   ),

    .rom_addr   ( rom_addr  ),
    .rom_cs     ( rom_cs    ),
    .rom_data   ( rom_data  ),
    .rom_ok     ( rom_ok    ),

    .pxl        ( pxl       ),
    .pxl_en     ( pxl_en    )
);

endmodule
