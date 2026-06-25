/*  This file is part of JTCORES.
    JTCORES program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version. */

module jtmzone_fix(
    input               rst,
    input               clk,
    input               clk24,
    input               pxl_cen,

    input        [ 9:0] cpu_addr,
    input        [ 7:0] cpu_dout,
    input               cpu_rnw,
    input               vram_cs,
    input               cram_cs,
    output       [ 7:0] vram_dout,
    output       [ 7:0] cram_dout,

    input        [ 8:0] hdump,
    input        [ 8:0] vdump,
    input               flip,

    input        [ 3:0] prog_data,
    input        [ 7:0] prog_addr,
    input               prog_en,

    output reg   [11:0] rom_addr,
    output reg          rom_cs,
    input        [31:0] rom_data,
    input               rom_ok,

    output       [ 3:0] pxl,
    output              fix_src,
    output              fix_sel,
    output              fix_en
);

localparam [8:0] HVISIBLE       = 9'd288;
localparam [8:0] HTOTAL         = 9'd384;
localparam [8:0] FIX_WIDTH      = 9'd48;
localparam [8:0] FIX_FLIP_START = HVISIBLE-FIX_WIDTH;
localparam [8:0] FIX_FLIP_SHIFT = 9'd7;
localparam [8:0] FIX_FLIP_SRC_START = FIX_FLIP_START-FIX_FLIP_SHIFT;
localparam [8:0] FIX_FLIP_SRC_END   = FIX_FLIP_SRC_START+9'd111;
localparam [8:0] FIX_FLIP_VIS_START = FIX_FLIP_SRC_START+9'd8;
localparam       FIX_SEL_DLY    = 5;
localparam       FIX_SEL_DLY_FLIP = 4;
localparam       FIX_PRIO_DLY   = 5;
localparam       FIX_PRIO_DLY_FLIP = 4;
localparam [2:0] RD_PHASE       = 3'd7;
localparam [2:0] FETCH_PHASE    = 3'd0;
localparam [2:0] LOAD_PHASE     = 3'd4;

reg  [31:0] pxl_data;
reg  [ 9:0] ram_addr;
reg  [ 3:0] pal_msb, cur_pal;
reg         hflip, cur_hf;
wire [ 7:0] vram, cram;
wire        vram_we = vram_cs & ~cpu_rnw;
wire        cram_we = cram_cs & ~cpu_rnw;
wire [ 9:0] eff_addr = cpu_addr;

assign      fix_src = fix_src_at(hdump, flip);
wire        fix_vis = fix_vis_at(hdump, flip);
wire        fix_sel_dly, fix_sel_dly_flip;
wire        fix_prio_dly, fix_prio_dly_flip;
wire [ 8:0] hdump_next = hdump == HTOTAL-9'd1 ? 9'd0 : hdump + 9'd1;
wire [ 7:0] h_eff = pcb_hcnt(hdump, flip);
wire [ 7:0] v_eff = pcb_vcnt(vdump, flip);
wire [ 7:0] h_eff_next = pcb_hcnt(hdump_next, flip);
wire [31:0] rom_decoded_row;
wire [11:0] tile_addr = { cram[7], vram, v_eff[2:0] ^ {3{cram[5]}} };
wire        read_tile = h_eff[2:0] == RD_PHASE;
wire        load_tile = h_eff[2:0] == LOAD_PHASE;
wire        fetch_tile = h_eff[2:0] == FETCH_PHASE;

wire [ 3:0] pxl_raw = cur_hf ? pxl_data[3:0] : pxl_data[31:28];
wire [ 3:0] color_raw = cur_pal;
wire [ 7:0] pal_addr = { color_raw, pxl_raw[0], pxl_raw[1], pxl_raw[2], pxl_raw[3] };

`ifdef MZONE_ROM_MISS_WATCH_FIX
reg [15:0] miss_frame;
reg        miss_lvbl_l;
reg        rom_req_pending;
reg        rom_req_ready;
reg [11:0] rom_req_addr;
reg [ 8:0] rom_req_hdump;
reg [ 8:0] rom_req_vdump;
reg [ 7:0] rom_req_heff;
reg [ 7:0] rom_req_veff;
wire       miss_lvbl = vdump >= 9'd16 && vdump < 9'd240;
wire       rom_req_match = rom_ok && rom_addr == rom_req_addr;
wire       rom_ready_now = rom_req_ready || rom_req_match;
`endif

assign rom_decoded_row = decode_row(rom_data);

jtframe_sh #(.W(1),.L(FIX_PRIO_DLY)) u_fix_prio_dly(
    .clk    ( clk          ),
    .clk_en ( pxl_cen      ),
    .din    ( fix_vis      ),
    .drop   ( fix_prio_dly )
);

jtframe_sh #(.W(1),.L(FIX_PRIO_DLY_FLIP)) u_fix_prio_dly_flip(
    .clk    ( clk               ),
    .clk_en ( pxl_cen           ),
    .din    ( fix_vis           ),
    .drop   ( fix_prio_dly_flip )
);

jtframe_sh #(.W(1),.L(FIX_SEL_DLY)) u_fix_sel_dly(
    .clk    ( clk          ),
    .clk_en ( pxl_cen      ),
    .din    ( fix_vis      ),
    .drop   ( fix_sel_dly  )
);

jtframe_sh #(.W(1),.L(FIX_SEL_DLY_FLIP)) u_fix_sel_dly_flip(
    .clk    ( clk               ),
    .clk_en ( pxl_cen           ),
    .din    ( fix_vis           ),
    .drop   ( fix_sel_dly_flip  )
);

assign fix_sel = flip ? fix_sel_dly_flip : fix_sel_dly;
assign fix_en  = flip ? fix_prio_dly_flip : fix_prio_dly;

function [31:0] decode_row;
    input [31:0] data;
begin
    decode_row = {
        { data[4],  data[5],  data[6],  data[7]  },
        { data[0],  data[1],  data[2],  data[3]  },
        { data[12], data[13], data[14], data[15] },
        { data[8],  data[9],  data[10], data[11] },
        { data[20], data[21], data[22], data[23] },
        { data[16], data[17], data[18], data[19] },
        { data[28], data[29], data[30], data[31] },
        { data[24], data[25], data[26], data[27] }
    };
end
endfunction

function [7:0] pcb_vcnt;
    input [8:0] v;
    input       f;
    reg   [7:0] vn;
begin
    vn = v[8] ? v[7:0] - 8'd8 : v[7:0];
    pcb_vcnt = f ? ~vn : vn;
end
endfunction

function [7:0] pcb_hcnt;
    input [8:0] h;
    input       f;
    reg   [8:0] hn;
begin
    if( f ) begin
        hn = 9'd047 - (h - FIX_FLIP_SRC_START);
    end else begin
        hn = h < FIX_WIDTH ? h : h - 9'd128;
    end
    pcb_hcnt = hn[7:0];
end
endfunction

function fix_src_at;
    input [8:0] h;
    input       f;
begin
    fix_src_at = f ? h >= FIX_FLIP_SRC_START && h <= FIX_FLIP_SRC_END :
                     h >= HVISIBLE || h < FIX_WIDTH;
end
endfunction

function fix_vis_at;
    input [8:0] h;
    input       f;
begin
    fix_vis_at = f ? h >= FIX_FLIP_VIS_START && h < FIX_FLIP_VIS_START+FIX_WIDTH :
                     fix_src_at(h, f);
end
endfunction

always @(posedge clk) begin
    if( rst ) begin
        rom_addr <= 12'd0;
        rom_cs <= 1'b0;
        ram_addr <= 10'd0;
        pxl_data <= 32'd0;
        pal_msb <= 4'd0;
        cur_pal <= 4'd0;
        hflip <= 1'b0;
        cur_hf <= 1'b0;
`ifdef MZONE_ROM_MISS_WATCH_FIX
        miss_frame      <= 16'd0;
        miss_lvbl_l     <= 1'b0;
        rom_req_pending <= 1'b0;
        rom_req_ready   <= 1'b0;
        rom_req_addr    <= 12'd0;
        rom_req_hdump   <= 9'd0;
        rom_req_vdump   <= 9'd0;
        rom_req_heff    <= 8'd0;
        rom_req_veff    <= 8'd0;
`endif
    end else if( pxl_cen ) begin
`ifdef MZONE_ROM_MISS_WATCH_FIX
        miss_lvbl_l <= miss_lvbl;
        if( !miss_lvbl_l && miss_lvbl )
            miss_frame <= miss_frame + 16'd1;
        if( rom_req_match )
            rom_req_ready <= 1'b1;
`endif
        if( read_tile )
            ram_addr <= { v_eff[7:3], h_eff_next[7:3] };

        if( fetch_tile ) begin
            rom_addr <= tile_addr;
            rom_cs   <= fix_src;
            pal_msb  <= cram[3:0];
            hflip    <= cram[6] ^ flip;
`ifdef MZONE_ROM_MISS_WATCH_FIX
            if( fix_src ) begin
                if( rom_req_pending && !rom_ready_now )
                    $display("MZONE_ROM_MISS_OVERWRITE layer=fix frame=%0d req_hdump=%0d req_vdump=%0d req_heff=%02x req_veff=%02x req_addr=%03x new_hdump=%0d new_vdump=%0d new_heff=%02x new_veff=%02x new_addr=%03x",
                        miss_frame, rom_req_hdump, rom_req_vdump, rom_req_heff, rom_req_veff, rom_req_addr,
                        hdump, vdump, h_eff, v_eff, tile_addr);
                rom_req_pending <= 1'b1;
                rom_req_ready   <= 1'b0;
                rom_req_addr    <= tile_addr;
                rom_req_hdump   <= hdump;
                rom_req_vdump   <= vdump;
                rom_req_heff    <= h_eff;
                rom_req_veff    <= v_eff;
            end
`endif
        end else begin
            rom_cs <= 1'b0;
        end

        if( load_tile ) begin
`ifdef MZONE_ROM_MISS_WATCH_FIX
            if( fix_src && rom_req_pending && !rom_ready_now )
                $display("MZONE_ROM_MISS layer=fix frame=%0d load_hdump=%0d load_vdump=%0d load_heff=%02x load_veff=%02x req_hdump=%0d req_vdump=%0d req_heff=%02x req_veff=%02x req_addr=%03x cur_addr=%03x rom_ok=%b rom_data=%08x",
                    miss_frame, hdump, vdump, h_eff, v_eff,
                    rom_req_hdump, rom_req_vdump, rom_req_heff, rom_req_veff,
                    rom_req_addr, rom_addr, rom_ok, rom_data);
            if( fix_src )
                rom_req_pending <= 1'b0;
`endif
            pxl_data <= rom_decoded_row;
            cur_pal  <= pal_msb;
            cur_hf   <= hflip;
        end else begin
            pxl_data <= cur_hf ? pxl_data >> 4 : pxl_data << 4;
        end
    end
end

jtframe_dual_ram #(
    .AW ( 10 ),
    .DW ( 8  )
) u_vram(
    .clk0   ( clk           ),
    .data0  ( 8'd0          ),
    .addr0  ( ram_addr      ),
    .we0    ( 1'b0          ),
    .q0     ( vram          ),

    .clk1   ( clk24         ),
    .data1  ( cpu_dout      ),
    .addr1  ( eff_addr      ),
    .we1    ( vram_we       ),
    .q1     ( vram_dout     )
);

jtframe_dual_ram #(
    .AW ( 10 ),
    .DW ( 8  )
) u_cram(
    .clk0   ( clk           ),
    .data0  ( 8'd0          ),
    .addr0  ( ram_addr      ),
    .we0    ( 1'b0          ),
    .q0     ( cram          ),

    .clk1   ( clk24         ),
    .data1  ( cpu_dout      ),
    .addr1  ( eff_addr      ),
    .we1    ( cram_we       ),
    .q1     ( cram_dout     )
);

jtframe_prom #(
    .DW ( 4 ),
    .AW ( 8 ),
    .ASYNC( 1 )
) u_palette(
    .clk    ( clk              ),
    .cen    ( pxl_cen          ),
    .data   ( prog_data        ),
    .wr_addr( prog_addr        ),
    .we     ( prog_en          ),
    .rd_addr( pal_addr         ),
    .q      ( pxl              )
);

endmodule
