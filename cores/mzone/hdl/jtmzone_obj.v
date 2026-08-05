/*  This file is part of JTCORES.
    JTCORES program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version. */

module jtmzone_obj(
    input               rst,
    input               clk,
    input               pxl_cen,

    input               LVBL,
    input               HS,
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

    output       [ 3:0] pxl
);

/*
On real Megazone PCB:

Object rendering:
Object render RAM is scanned from byte A=0..143 once per line. The scan
starts at HCNT=40 and completes before the next HCNT=40. The 144 bytes are
36 object entries, four bytes each.

Object DMA:
DMA arms when VBLK goes active, starts one pixel count after HSYNC goes
active, and lasts for 240*4+1 HCNTs. The object RAM and object render RAM
address go from 0 to 240 in that time.


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

Core ROM layout without jtframe gfx_sort:
mame2mra repacks MAME order with sequence=[0,2,1,3], width=16 so matching
bytes from the selected ROM pair become adjacent:

    word16 = { byte23, byte01 }

The download address mapper transposes the packed within-tile address so each
32-bit SDRAM word contains two adjacent four-pixel groups for one row.  The
custom object drawer reads words as:

    rom_addr = { code, ysub[3], half, ysub[2:0] }

where half selects the left or right eight-pixel half.  Each response contains
two adjacent four-pixel groups in its lower and upper 16-bit lanes:

    pixels 0..3 = rom_data[15:0]
    pixels 4..7 = rom_data[31:16]

Thus one response supplies eight horizontal pixels and a 16-pixel sprite row
needs two requests, like Road Fighter.  Pixels are decoded from byte01/byte23
and written to a one-line object buffer.
*/
localparam [8:0] OBJ_START       = 9'd40;
localparam [8:0] OBJ_ARM         = OBJ_START - 9'd1;
localparam [9:0] OBJ_SCAN_LAST   = 10'd35;
localparam [9:0] OBJ_ENTRY_BYTES = 10'd4;
localparam [9:0] DMA_COPY_BYTES  = 10'd240;
localparam [9:0] DMA_HCOUNTS     = DMA_COPY_BYTES*10'd4 + 10'd1;

reg        lvbl_l, hs_l;
reg [ 9:0] scan_obj;
reg [ 2:0] scan_st;
reg        scan_last;
reg        cen2, scan_start_x;
reg [ 7:0] attr, ypos, code;
reg [ 9:0] dma_addr;
reg [ 7:0] dma_din;
reg        dma_en, dma_start_wait, dma_hs_wait, dma_wr;
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
wire       hs_start = HS && !hs_l;
wire       dma_copy = pxl_cen && dma_hcnt[1:0]==2'd0 && dma_addr != DMA_COPY_BYTES;
wire       dma_we = dma_en && dma_wr;
wire [7:0] scan_dout;
wire [7:0] draw_vdump = vdump[7:0] + 8'd1;
wire [8:0] ysum   = {1'b0,draw_vdump} + {1'b0,ypos};
wire       inzone = ysum[7:4] == 4'hf;
wire [3:0] ysub   = ysum[3:0] ^ {4{attr[7] ^ flip}};
wire [1:0] scan_byte = scan_st==3'd1 ? 2'd0 :
                       scan_st==3'd2 ? 2'd1 :
                       scan_st==3'd3 ? 2'd2 : 2'd3;
wire [9:0] scan_addr = { scan_obj[7:0], scan_byte };
// Kicker-style object drawer. It reads the raw PCB/MRA object layout directly:
// one 32-bit SDRAM word contains two 16-bit {byte23,byte01} groups. The drawer
// writes decoded pixels into a one-line object buffer.

always @(posedge clk) begin
    lvbl_l <= LVBL;
    hs_l   <= HS;
    cen2   <= ~cen2;
    if( scan_start ) scan_start_x <= 1'b1;
    else if( cen2 )  scan_start_x <= 1'b0;
    if( rst ) begin
        scan_obj    <= 10'd0;
        scan_st     <= 3'd0;
        scan_last   <= 1'b0;
        cen2        <= 1'b0;
        scan_start_x<= 1'b0;
        draw        <= 1'b0;
        dr_code     <= 8'd0;
        dr_xpos     <= 9'd0;
        dr_pal      <= 4'd0;
        dr_hflip    <= 1'b0;
        dr_vflip    <= 1'b0;
        dr_ysub     <= 4'd0;
        lvbl_l    <= 1'b0;
        hs_l      <= 1'b0;
    end else begin
        if( vblk_start ) begin
            scan_st <= 3'd0;
            draw    <= 1'b0;
        end else if( cen2 ) begin
            draw <= 1'b0;
            case( scan_st )
                3'd0: if( scan_start_x ) begin
                    scan_obj <= OBJ_SCAN_LAST;
                    scan_st  <= 3'd1;
                end
                3'd1: if( !busy ) begin
                    attr    <= scan_dout;
                    scan_st <= 3'd2;
                end
                3'd2: begin
                    ypos    <= scan_dout;
                    scan_st <= 3'd3;
                end
                3'd3: begin
                    code     <= scan_dout;
                    scan_st  <= 3'd4;
                end
                3'd4: begin
                    dr_code      <= code;
                    // Resolve global horizontal flip before the shared-style
                    // drawer.  224 = 239-(16-1), accounting for the active
                    // 0..239 span and the 16-pixel sprite width.
                    dr_xpos      <= {1'b0, flip ? 8'd224-scan_dout : scan_dout};
                    dr_pal       <= attr[3:0];
                    // MAME and the 083 shifter behavior show this attribute
                    // bit is active-low for horizontal flip.
                    dr_hflip     <= (~attr[6]) ^ flip;
                    dr_vflip     <= attr[7] ^ flip;
                    dr_ysub      <= ysub;
                    draw         <= inzone;
                    scan_last    <= scan_obj==10'd0;
                    if( scan_obj!=10'd0 ) scan_obj <= scan_obj-10'd1;
                    scan_st <= 3'd5;
                end
                3'd5: scan_st <= scan_last ? 3'd0 : 3'd1;
                default: scan_st <= 3'd0;
            endcase
        end
    end
end

always @(posedge clk) begin
    if( rst ) begin
        oram_addr <= 10'd0;
        dma_addr  <= 10'd0;
        dma_din   <= 8'd0;
        dma_en    <= 1'b0;
        dma_start_wait <= 1'b0;
        dma_hs_wait <= 1'b0;
        dma_wr    <= 1'b0;
        dma_hcnt  <= 10'd0;
    end else begin
        if( vblk_start ) begin
            dma_start_wait <= 1'b1;
            dma_hs_wait <= 1'b0;
            dma_en    <= 1'b0;
            dma_wr    <= 1'b0;
            dma_hcnt  <= 10'd0;
            oram_addr <= 10'd0;
            dma_addr  <= 10'd0;
            dma_din   <= 8'd0;
        end else if( dma_start_wait && hs_start ) begin
            dma_start_wait <= 1'b0;
            dma_hs_wait <= 1'b1;
        end else if( dma_hs_wait && pxl_cen ) begin
            dma_hs_wait <= 1'b0;
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
    .rst        ( rst           ),
    .clk        ( clk           ),
    .pxl_cen    ( pxl_cen       ),
    .cen2       ( cen2          ),
    .HS         ( HS            ),
    .hdump      ( hdump         ),
    .vdump      ( vdump         ),
    .flip       ( flip          ),

    .draw       ( draw          ),
    .busy       ( busy          ),

    .code       ( dr_code       ),
    .xpos       ( dr_xpos       ),
    .pal        ( dr_pal        ),
    .hflip      ( dr_hflip      ),
    .ysub       ( dr_ysub       ),

    .prog_data  ( prog_data     ),
    .prog_addr  ( prog_addr     ),
    .prog_en    ( prog_en       ),

    .rom_addr   ( rom_addr      ),
    .rom_cs     ( rom_cs        ),
    .rom_ok     ( rom_ok        ),
    .rom_data   ( rom_data      ),

    .pxl        ( pxl           )
);

endmodule
