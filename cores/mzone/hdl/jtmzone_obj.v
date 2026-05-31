/*  This file is part of JTCORES.
    JTCORES program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version. */

module jtmzone_obj(
    input               rst,
    input               clk,
    input               pxl_cen,

    input               LHBL,
    input               LVBL,
    input        [ 8:0] hdump,
    input        [ 8:0] vdump,
    input               flip,

    output reg   [ 9:0] oram_addr,
    input        [ 7:0] oram_dout,

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

/*
On real Megazone PCB:

Object rendering:
Object render RAM is scanned from byte A=0..143 once per line. The scan
starts at HCNT=40 and completes before the next HCNT=40. The 144 bytes are
36 object entries, four bytes each.

Object DMA:
DMA starts one HCNT after VBLK goes active and lasts for 240*4+1 HCNTs.
The object RAM and object render RAM address go from 0 to 240 in that time.

*/
localparam [8:0] OBJ_START       = 9'd40;
localparam [8:0] OBJ_ARM         = OBJ_START - 9'd1;
localparam [9:0] OBJ_SCAN_LAST   = 10'd35;
localparam [9:0] OBJ_ENTRY_BYTES = 10'd4;
localparam [8:0] HCOUNTS         = 9'd384;
localparam [9:0] DMA_COPY_BYTES  = 10'd240;
localparam [9:0] DMA_HCOUNTS     = DMA_COPY_BYTES*10'd4 + 10'd1;

reg        lhbl_l, lvbl_l;
`ifdef MZONE_OBJ_WATCH
reg [15:0] frame_cnt;
`elsif MZONE_OBJ_DMA_WATCH
reg [15:0] frame_cnt;
`endif
reg [ 9:0] scan_base;
reg [ 9:0] scan_obj;
reg [ 9:0] scan_addr;
reg [ 3:0] sub_cnt;
reg [ 8:0] scan_hcnt;
reg [ 8:0] scan_acc;
reg        scan_cen, scan_done;
reg [ 7:0] attr, ypos, code, raw_xpos;
reg [ 9:0] dma_addr;
reg [ 7:0] dma_din;
reg        scan_en;
reg        dma_en, dma_start_wait, dma_wr;
reg [ 9:0] dma_hcnt;

reg        draw;
reg [ 7:0] dr_code;
reg [ 8:0] dr_xpos;
reg [ 3:0] dr_pal;
reg        dr_hflip, dr_rom_hflip;
reg [ 3:0] dr_ysub;
wire       busy;
wire       line_start = lhbl_l && !LHBL;
    wire       scan_start = pxl_cen && hdump == OBJ_ARM;
wire       vblk_start = !LVBL && lvbl_l;
wire       dma_copy = pxl_cen && dma_hcnt[1:0]==2'd0 && dma_addr != DMA_COPY_BYTES;
wire       dma_we = dma_en && dma_wr;
wire [7:0] scan_dout;
wire       dbg_dma_window     /* verilator public_flat */;
wire       dbg_dma_copy       /* verilator public_flat */;
wire       dbg_dma_we         /* verilator public_flat */;
wire [7:0] raw_sy = 8'd255 - (ypos + 8'd16);
wire [7:0] ydiff  = vdump[7:0] - raw_sy;
wire       inzone = ydiff < 8'd16;
wire [3:0] ysub   = attr[7] ? ~ydiff[3:0] : ydiff[3:0];
	wire [8:0] xpos   = {1'b0,raw_xpos};
	// PCB OBJ X/read counter. It is independent from the core's continuous
	// hdump numbering: the PCB holds OBJ X at 0 for HCNT 40..43, switches the
	// object line buffer at HCNT 44, then advances X from 0. Before HCNT 40 it
	// wraps through the end of the 384-count line, so HCNT 39 reads as X=383.
	wire       draw_hs = hdump == 9'd44;
	wire [8:0] draw_hdump = hdump < 9'd40 ? hdump + 9'd344 :
	                        hdump < 9'd44 ? 9'd0 :
	                                        hdump - 9'd44;
	wire       draw_lhbl = ~draw_hs;
wire [9:0] scan_acc_next = {1'b0,scan_acc} + (OBJ_SCAN_LAST+10'd1);
wire       scan_acc_step = scan_acc_next >= {1'b0,HCOUNTS};

assign dbg_dma_window     = dma_en;
assign dbg_dma_copy       = dma_copy;
assign dbg_dma_we         = dma_we;

always @(posedge clk) begin
    lhbl_l <= LHBL;
    lvbl_l <= LVBL;
    if( rst ) begin
        scan_base   <= 10'd0;
        scan_obj    <= 10'd0;
        scan_addr   <= 10'd0;
        sub_cnt     <= 4'd0;
        scan_hcnt   <= 9'd0;
        scan_acc    <= 9'd0;
        scan_cen    <= 1'b0;
        scan_done   <= 1'b0;
        draw        <= 1'b0;
        dr_code     <= 8'd0;
        dr_xpos     <= 9'd0;
        dr_pal      <= 4'd0;
        dr_hflip    <= 1'b0;
        dr_rom_hflip<= 1'b0;
        dr_ysub     <= 4'd0;
        raw_xpos    <= 8'd0;
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
        scan_cen <= 1'b0;
        if( busy ) draw <= 1'b0;
        if( vblk_start ) begin
            scan_addr   <= 10'd0;
            sub_cnt <= 4'd0;
            draw <= 1'b0;
            scan_en <= 1'b0;
            scan_done <= 1'b0;
            scan_hcnt <= 9'd0;
            scan_acc <= 9'd0;
        end else if( scan_start ) begin
            scan_base <= 10'd0;
            scan_obj  <= 10'd0;
            scan_addr <= 10'd0;
            sub_cnt   <= 4'd1;
            draw      <= 1'b0;
            scan_en   <= 1'b1;
            scan_done <= 1'b0;
            scan_hcnt <= 9'd0;
            scan_acc  <= 9'd0;
        end else begin
            if( scan_en && pxl_cen && scan_hcnt != HCOUNTS ) begin
                scan_hcnt <= scan_hcnt + 9'd1;
                scan_acc  <= scan_acc_step ? scan_acc_next[8:0] - HCOUNTS :
                                             scan_acc_next[8:0];
                scan_cen  <= scan_acc_step;
            end

            if( scan_cen && sub_cnt==4'd0 && !scan_done ) begin
                scan_addr <= scan_base;
                sub_cnt   <= 4'd1;
            end else if( sub_cnt!=4'd0 && !scan_done ) begin
                case( sub_cnt )
                    4'd1: begin
                        sub_cnt <= 4'd2;
                    end
                    4'd2: begin
                        attr      <= scan_dout;
                        scan_addr <= scan_base + 10'd1;
                        sub_cnt   <= 4'd3;
                    end
                    4'd3: begin
                        sub_cnt <= 4'd4;
                    end
                    4'd4: begin
                        ypos      <= scan_dout;
                        scan_addr <= scan_base + 10'd2;
                        sub_cnt   <= 4'd5;
                    end
                    4'd5: begin
                        sub_cnt <= 4'd6;
                    end
                    4'd6: begin
                        code      <= scan_dout;
                        scan_addr <= scan_base + 10'd3;
                        sub_cnt   <= 4'd7;
                    end
                    4'd7: begin
                        sub_cnt <= 4'd8;
                    end
                    4'd8: begin
                        raw_xpos <= scan_dout;
                        sub_cnt  <= 4'd9;
                    end
                    default: begin
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
                                    frame_cnt, vdump[7:0], scan_base, attr, ypos, code, raw_xpos,
                                    raw_sy, ydiff, ysub, attr[6], attr[7], attr[3:0]);
`endif
                        end
                        if( scan_obj==OBJ_SCAN_LAST ) begin
                            scan_done <= 1'b1;
                            scan_en   <= 1'b0;
                            sub_cnt   <= 4'd0;
`ifdef MZONE_OBJ_SCAN_WATCH
                            $display("MZONE_OBJ_SCAN_DONE vdump=%0d hdump=%0d scan_obj=%0d scan_base=%0d scan_addr=%0d scan_hcnt=%0d",
                                vdump, hdump, scan_obj, scan_base, scan_base + 10'd3, scan_hcnt);
`endif
                        end else begin
                            scan_obj  <= scan_obj + 10'd1;
                            scan_base <= scan_base + OBJ_ENTRY_BYTES;
                            scan_addr <= scan_base + OBJ_ENTRY_BYTES;
                            sub_cnt   <= 4'd0;
                        end
                    end
                endcase
            end
        end
    end
end

`ifndef MZONE_OBJ_DMA_WATCH
always @(posedge clk) begin
    if( rst ) begin
        oram_addr <= 10'd0;
        dma_addr  <= 10'd0;
        dma_din   <= 8'd0;
        dma_en    <= 1'b0;
        dma_start_wait <= 1'b0;
        dma_wr    <= 1'b0;
        dma_hcnt  <= 10'd0;
    end else begin
        if( vblk_start ) begin
            dma_start_wait <= 1'b1;
            dma_en    <= 1'b0;
            dma_wr    <= 1'b0;
            dma_hcnt  <= 10'd0;
            oram_addr <= 10'd0;
            dma_addr  <= 10'd0;
            dma_din   <= 8'd0;
        end else if( dma_start_wait && pxl_cen ) begin
            dma_start_wait <= 1'b0;
            dma_en    <= 1'b1;
            dma_wr    <= 1'b0;
            oram_addr <= 10'd0;
            dma_addr  <= 10'd0;
            dma_din   <= 8'd0;
            dma_hcnt  <= 10'd0;
        end else if( dma_en ) begin
            if( dma_copy ) begin
                dma_din   <= oram_dout;
                oram_addr <= dma_addr + 10'd1;
                dma_wr    <= 1'b1;
            end else if( dma_wr ) begin
                dma_addr <= dma_addr + 10'd1;
                dma_wr <= 1'b0;
            end

            if( pxl_cen && dma_hcnt != DMA_HCOUNTS )
                dma_hcnt <= dma_hcnt + 10'd1;

            if( pxl_cen && dma_hcnt==DMA_HCOUNTS && dma_addr==DMA_COPY_BYTES && !dma_wr ) begin
                dma_en <= 1'b0;
            end
        end
    end
end
`else
always @(posedge clk) begin
    if( rst ) begin
        oram_addr <= 10'd0;
        dma_addr  <= 10'd0;
        dma_din   <= 8'd0;
        dma_en    <= 1'b0;
        dma_start_wait <= 1'b0;
        dma_wr    <= 1'b0;
        dma_hcnt  <= 10'd0;
    end else begin
        if( vblk_start ) begin
            $display("MZONE_OBJ_DMA_ARM frame=%0d hdump=%0d vdump=%0d LVBL=%b",
                frame_cnt, hdump, vdump, LVBL);
            dma_start_wait <= 1'b1;
            dma_en    <= 1'b0;
            dma_wr    <= 1'b0;
            dma_hcnt  <= 10'd0;
            oram_addr <= 10'd0;
            dma_addr  <= 10'd0;
            dma_din   <= 8'd0;
        end else if( dma_start_wait && pxl_cen ) begin
            $display("MZONE_OBJ_DMA_START frame=%0d hdump=%0d vdump=%0d LVBL=%b",
                frame_cnt, hdump, vdump, LVBL);
            dma_start_wait <= 1'b0;
            dma_en    <= 1'b1;
            dma_wr    <= 1'b0;
            oram_addr <= 10'd0;
            dma_addr  <= 10'd0;
            dma_din   <= 8'd0;
            dma_hcnt  <= 10'd0;
        end else if( dma_en ) begin
            if( dma_copy ) begin
                dma_din   <= oram_dout;
                oram_addr <= dma_addr + 10'd1;
                dma_wr    <= 1'b1;
            end else if( dma_wr ) begin
                if( dma_addr < 10'd32 || dma_addr >= DMA_COPY_BYTES-OBJ_ENTRY_BYTES )
                    $display("MZONE_OBJ_DMA frame=%0d hcnt=%0d dst=%03x data=%02x",
                        frame_cnt, dma_hcnt, dma_addr, dma_din);
                dma_addr <= dma_addr + 10'd1;
                dma_wr <= 1'b0;
            end

            if( pxl_cen && dma_hcnt != DMA_HCOUNTS )
                dma_hcnt <= dma_hcnt + 10'd1;

            if( pxl_cen && dma_hcnt==DMA_HCOUNTS && dma_addr==DMA_COPY_BYTES && !dma_wr ) begin
                $display("MZONE_OBJ_DMA_DONE frame=%0d hcnt=%0d dma_addr=%03x hdump=%0d vdump=%0d",
                    frame_cnt, dma_hcnt, dma_addr, hdump, vdump);
                dma_en <= 1'b0;
            end
        end
    end
end
`endif

// DMA buffer
jtframe_dual_ram #(
    .AW ( 10 ),
    .DW ( 8  )
) u_table(
    .clk0   ( clk              ),
    .data0  ( dma_din          ),
    .addr0  ( dma_addr         ),
    .we0    ( dma_we           ),
    .q0     (                  ),

    .clk1   ( clk              ),
    .data1  ( 8'd0             ),
    .addr1  ( scan_addr        ),
    .we1    ( 1'b0             ),
    .q1     ( scan_dout        )
);

jtmzone_objdraw u_draw(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),

	    .LHBL       ( draw_lhbl ),
	    .hdump      ( draw_hdump),

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
