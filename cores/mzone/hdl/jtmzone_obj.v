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

    output       [12:0] rom_addr,
    output              rom_cs,
    input        [31:0] rom_data,
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


PCB object ROMs:
Four ROMs are read as two selectable pairs. Object code byte 2 bit 7 selects
the pair:

    code[7]=0: codes 0x00..0x7f output { byte23, byte01 }
    code[7]=1: codes 0x80..0xff output { byte23, byte01 }

For one 4-pixel group, MAME's x offsets use bit 0 for pixel 0:

    byte01 = { pl0_px3, pl0_px2, pl0_px1, pl0_px0,
               pl1_px3, pl1_px2, pl1_px1, pl1_px0 }

    byte23 = { pl2_px3, pl2_px2, pl2_px1, pl2_px0,
               pl3_px3, pl3_px2, pl3_px1, pl3_px0 }

Pixels are reconstructed as:

    pxN = { pl3_pxN, pl2_pxN, pl1_pxN, pl0_pxN }

PCB address order inside the selected ROM pair:

    addr[0] = v0
    addr[1] = v1
    addr[2] = v2
    addr[3] = h0
    addr[4] = h1
    addr[5] = v3

MAME flattens the four ROMs into one gfx1 region:

    gfx1 + 0x0000: byte01 for codes 0x00..0x7f
    gfx1 + 0x2000: byte01 for codes 0x80..0xff
    gfx1 + 0x4000: byte23 for codes 0x00..0x7f
    gfx1 + 0x6000: byte23 for codes 0x80..0xff

Core ROM layout:
mame2mra repacks MAME order with sequence=[0,2,1,3], width=16 so matching
bytes become adjacent:

    word16 = { byte23, byte01 }

mem.yaml uses gfx_sort: hhvvvx so adjacent horizontal groups of the same row
share one 32-bit SDRAM word:

    rom_data = { byte23_g1, byte01_g1, byte23_g0, byte01_g0 }

jtframe_objdraw requests graphics as:

    draw_rom_addr = { code, half, ysub }

The core maps that request to sorted SDRAM as:

    rom_addr = { code, ysub, half }

and swizzles the returned word into:

    pxl_data = { pl3[7:0], pl2[7:0], pl1[7:0], pl0[7:0] }
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
`elsif MZONE_OBJ_PXL_WATCH
reg [15:0] frame_cnt;
`elsif MZONE_OBJ_ROM_WATCH
reg [15:0] frame_cnt;
`endif
reg [ 9:0] scan_obj;
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
reg        dr_hflip, dr_vflip;
reg [ 3:0] dr_ysub;
wire       busy;
wire       scan_start = pxl_cen && hdump == OBJ_ARM;
wire       vblk_start = !LVBL && lvbl_l;
wire       dma_copy = pxl_cen && dma_hcnt[1:0]==2'd0 && dma_addr != DMA_COPY_BYTES;
wire       dma_we = dma_en && dma_wr;
wire [7:0] scan_dout;
wire       dbg_dma_window     /* verilator public_flat */;
wire       dbg_dma_copy       /* verilator public_flat */;
wire       dbg_dma_we         /* verilator public_flat */;
wire [8:0] ysum   = {1'b0,vdump[7:0]} + {1'b0,ypos};
wire       inzone = ysum[7:4] == 4'hf;
wire [3:0] ysub   = ysum[3:0] ^ {4{attr[7]}};
wire [7:0] xpos_raw_eff = sub_cnt==4'd8 ? scan_dout : raw_xpos;
wire [8:0] xpos   = {1'b0,xpos_raw_eff};
wire [1:0] scan_byte = sub_cnt[3] ? 2'd3 : sub_cnt[2:1];
wire [9:0] scan_addr = { scan_obj[7:0], scan_byte };
wire [9:0] scan_acc_next = {1'b0,scan_acc} + (OBJ_SCAN_LAST+10'd1);
wire       scan_acc_step = scan_acc_next >= {1'b0,HCOUNTS};
/*
  code = object graphics code
  half = 0 -> pixels 0..7 of the 16-pixel row
  half = 1 -> pixels 8..15 of the 16-pixel row
  ysub = row 0..15 inside the object
*/
wire [12:0] draw_rom_addr;
wire        draw_rom_cs;
wire [ 7:0] draw_pxl;
wire [ 3:0] lut_pxl;
wire        draw_hs = hdump == 9'd0;
wire [8:0]  draw_hdump = hdump;
wire        obj_visible = hdump < 9'd288;
// jtframe_draw handles horizontal flip internally: hflip=1 makes it request
// the second 8-pixel half first and shift pixels in the opposite direction.
// Do not also invert the ROM half here. The Konami 083-style hardware exposes
// a PCB flip control/polarity, but this signal is converted at the jtframe
// interface boundary into jtframe's logical draw-direction input.
wire        mem_half = draw_rom_addr[4];
wire [31:0] pxl_rom  = rom_data;
wire [31:0] pxl_data = {
    pxl_rom[24], pxl_rom[25], pxl_rom[26], pxl_rom[27],
    pxl_rom[ 8], pxl_rom[ 9], pxl_rom[10], pxl_rom[11],
    pxl_rom[28], pxl_rom[29], pxl_rom[30], pxl_rom[31],
    pxl_rom[12], pxl_rom[13], pxl_rom[14], pxl_rom[15],
    pxl_rom[16], pxl_rom[17], pxl_rom[18], pxl_rom[19],
    pxl_rom[ 0], pxl_rom[ 1], pxl_rom[ 2], pxl_rom[ 3],
    pxl_rom[20], pxl_rom[21], pxl_rom[22], pxl_rom[23],
    pxl_rom[ 4], pxl_rom[ 5], pxl_rom[ 6], pxl_rom[ 7]
};

assign dbg_dma_window     = dma_en;
assign dbg_dma_copy       = dma_copy;
assign dbg_dma_we         = dma_we;
assign rom_addr           = { draw_rom_addr[12:5], draw_rom_addr[3:0], mem_half };
assign rom_cs             = draw_rom_cs;

always @(posedge clk) begin
    lhbl_l <= LHBL;
    lvbl_l <= LVBL;
    if( rst ) begin
        scan_obj    <= 10'd0;
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
        dr_vflip    <= 1'b0;
        dr_ysub     <= 4'd0;
        raw_xpos    <= 8'd0;
        scan_en     <= 1'b0;
        lvbl_l    <= 1'b0;
`ifdef MZONE_OBJ_WATCH
        frame_cnt <= 16'd0;
`elsif MZONE_OBJ_DMA_WATCH
        frame_cnt <= 16'd0;
`elsif MZONE_OBJ_PXL_WATCH
        frame_cnt <= 16'd0;
`elsif MZONE_OBJ_ROM_WATCH
        frame_cnt <= 16'd0;
`endif
    end else begin
`ifdef MZONE_OBJ_WATCH
        if( LVBL && !lvbl_l ) frame_cnt <= frame_cnt + 16'd1;
`elsif MZONE_OBJ_DMA_WATCH
        if( LVBL && !lvbl_l ) frame_cnt <= frame_cnt + 16'd1;
`elsif MZONE_OBJ_PXL_WATCH
        if( LVBL && !lvbl_l ) frame_cnt <= frame_cnt + 16'd1;
`elsif MZONE_OBJ_ROM_WATCH
        if( LVBL && !lvbl_l ) frame_cnt <= frame_cnt + 16'd1;
`endif
        scan_cen <= 1'b0;
        if( busy ) draw <= 1'b0;
        if( vblk_start ) begin
            sub_cnt <= 4'd0;
            draw <= 1'b0;
            scan_en <= 1'b0;
            scan_done <= 1'b0;
            scan_hcnt <= 9'd0;
            scan_acc <= 9'd0;
        end else if( scan_start ) begin
            scan_obj  <= 10'd0;
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
                sub_cnt   <= 4'd1;
            end else if( sub_cnt!=4'd0 && !scan_done ) begin
                case( sub_cnt )
                    4'd1: begin
                        sub_cnt <= 4'd2;
                    end
                    4'd2: begin
                        attr      <= scan_dout;
                        sub_cnt   <= 4'd3;
                    end
                    4'd3: begin
                        sub_cnt <= 4'd4;
                    end
                    4'd4: begin
                        ypos      <= scan_dout;
                        sub_cnt   <= 4'd5;
                    end
                    4'd5: begin
                        sub_cnt <= 4'd6;
                    end
                    4'd6: begin
                        code      <= scan_dout;
                        sub_cnt   <= 4'd7;
                    end
                    4'd7: begin
                        sub_cnt <= 4'd8;
                    end
                    default: begin
                        raw_xpos <= scan_dout;
                        if( inzone && busy ) begin
                            sub_cnt   <= 4'd8;
                        end else begin
                            if( inzone ) begin
                                dr_code      <= code;
                                dr_xpos      <= flip ? xpos - 9'd11 : xpos + 9'd32;
                                dr_pal       <= attr[3:0];
                                // MAME/PCB polarity: bit 6 clear means flip X.
                                dr_hflip     <= ~attr[6];
                                dr_vflip     <= attr[7];
                                dr_ysub      <= ysub;
                                draw <= 1'b1;
`ifdef MZONE_OBJ_WATCH
                                if( frame_cnt >= `MZONE_OBJ_WATCH_FROM && frame_cnt <= `MZONE_OBJ_WATCH_TO )
                                    $display("MZONE_OBJ frame=%0d line=%0d base=%03x attr=%02x ypos=%02x code=%02x xpos=%02x ysum=%03x ysub=%x hflip=%b vflip=%b color=%x",
                                        frame_cnt, vdump[7:0], { scan_obj[7:0], 2'b00 }, attr, ypos, code, scan_dout,
                                        ysum, ysub, ~attr[6], attr[7], attr[3:0]);
`endif
                            end
                            if( scan_obj==OBJ_SCAN_LAST ) begin
                                scan_done <= 1'b1;
                                scan_en   <= 1'b0;
                                sub_cnt   <= 4'd0;
`ifdef MZONE_OBJ_SCAN_WATCH
                                $display("MZONE_OBJ_SCAN_DONE vdump=%0d hdump=%0d scan_obj=%0d obj_addr=%0d scan_addr=%0d scan_hcnt=%0d",
                                    vdump, hdump, scan_obj, { scan_obj[7:0], 2'b00 }, { scan_obj[7:0], 2'b11 }, scan_hcnt);
`endif
                            end else begin
                                scan_obj  <= scan_obj + 10'd1;
                                sub_cnt   <= 4'd0;
                            end
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

jtframe_objdraw #(
    .CW       (  8 ),
    .PW       (  8 ),
    .LATCH    (  1 ),
    .ALPHA    (  0 ),
    .KEEP_OLD (  1 )
) u_draw(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .pxl_cen    ( pxl_cen       ),
    .hs         ( draw_hs       ),
    .flip       ( 1'b0          ),
    .hdump      ( draw_hdump    ),

    .draw       ( draw          ),
    .busy       ( busy          ),
    .code       ( dr_code       ),
    .xpos       ( dr_xpos       ),
    .ysub       ( dr_ysub       ),
    .hzoom      ( 6'd0          ),
    .hz_keep    ( 1'b0          ),

    .hflip      ( dr_hflip      ),
    .vflip      ( dr_vflip      ),
    .pal        ( dr_pal        ),

    .rom_addr   ( draw_rom_addr ),
    .rom_cs     ( draw_rom_cs   ),
    .rom_ok     ( rom_ok        ),
    .rom_data   ( pxl_data      ),

    .pxl        ( draw_pxl      )
);

jtframe_prom #(
    .DW     ( 4 ),
    .AW     ( 8 ),
    .ASYNC  ( 1 )
) u_obj_lut(
    .clk    ( clk       ),
    .cen    ( pxl_cen   ),
    .data   ( prog_data ),
    .wr_addr( prog_addr ),
    .we     ( prog_en   ),
    .rd_addr( draw_pxl  ),
    .q      ( lut_pxl   )
);

`ifdef MZONE_NOOBJ
assign pxl    = 4'd0;
assign pxl_en = 1'b0;
`else
assign pxl_en = pxl_cen && obj_visible && lut_pxl != 4'd0;
assign pxl    = pxl_en ? lut_pxl : 4'd0;
`endif

`ifdef MZONE_OBJ_PXL_WATCH
always @(posedge clk) begin
    if( pxl_cen &&
        frame_cnt >= `MZONE_OBJ_PXL_WATCH_FROM &&
        frame_cnt <= `MZONE_OBJ_PXL_WATCH_TO &&
        hdump >= `MZONE_OBJ_PXL_X0 && hdump <= `MZONE_OBJ_PXL_X1 &&
        vdump >= `MZONE_OBJ_PXL_Y0 && vdump <= `MZONE_OBJ_PXL_Y1 ) begin
        $display("MZONE_OBJ_PXL frame=%0d x=%0d y=%0d draw_x=%0d visible=%b draw_pxl=%02x lut=%x pxl_en=%b pxl=%x",
            frame_cnt, hdump, vdump, draw_hdump, obj_visible,
            draw_pxl, lut_pxl, pxl_en, pxl);
    end
end
`endif

`ifdef MZONE_OBJ_ROM_WATCH
always @(posedge clk) begin
    if( rom_ok && draw_rom_cs &&
        frame_cnt >= `MZONE_OBJ_ROM_WATCH_FROM &&
        frame_cnt <= `MZONE_OBJ_ROM_WATCH_TO &&
        draw_rom_addr[12:5] == 8'haa &&
        draw_rom_addr[3:0] == `MZONE_OBJ_ROM_WATCH_ROW ) begin
        $display("MZONE_OBJ_ROM frame=%0d req=%03x code=%02x half=%0d row=%x addr=%04x raw=%08x pxl_data=%08x hflip=%b",
            frame_cnt, draw_rom_addr, draw_rom_addr[12:5], draw_rom_addr[4],
            draw_rom_addr[3:0], rom_addr, rom_data, pxl_data, dr_hflip);
    end
end
`endif

endmodule
