/*  This file is part of JTCORES.
    JTCORES program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version. */

module jtmzone_main(
    input             rst,
    input             clk,
    input             cpu_clk_cen,
    output            cpu_cen,

    output     [15:0] rom_addr,
    output reg        rom_cs,
    input      [ 7:0] rom_data,
    input             rom_ok,

    output            cpu_rnw,
    output     [ 7:0] cpu_dout,

    output reg        scrolly_cs,
    output reg        scrollx_cs,
    output reg        vram0_cs,
    output reg        vram1_cs,
    output reg        cram0_cs,
    output reg        cram1_cs,
    output reg        objram_cs,
    output reg        shared_cs,

    output     [10:0] shared_addr,
    output     [ 7:0] shared_dout,
    output            shared_we,
    input      [ 7:0] shared_din,

    output     [ 9:0] main_vram_addr,
    output     [ 7:0] main_vram_din,
    output            main_vram0_we,
    output            main_vram1_we,
    output            main_cram0_we,
    output            main_cram1_we,
    input      [ 7:0] main_vram0_dout,
    input      [ 7:0] main_vram1_dout,
    input      [ 7:0] main_cram0_dout,
    input      [ 7:0] main_cram1_dout,

    output     [ 9:0] main_objram_addr,
    output     [ 7:0] main_objram_din,
    output            main_objram_we,
    input      [ 7:0] main_objram_dout,

    output reg [ 7:0] scrolly,
    output reg [ 7:0] scrollx,
    output            flip,
    output            irq_mask,
    output            snd_int,
    output            irq_ack,
    output            BA,
    output            BS,

    input             blank,
    input             vblank,
    input             h2,
    input             dip_pause,
    input             snd_irq_n,
    input      [ 7:0] snd_dout
);

reg  [ 7:0] cpu_din;
reg         b_a13_coin2;
reg         b_a13_coin1;
reg         b_a13_flip;
reg         b_a13_int;
reg         b_a13_intst;
reg         scroll_pend, scroll_pend_x;
reg  [ 7:0] scroll_pend_data;
wire [15:0] A;
wire        RnW, VMA;
wire        intst       = b_a13_intst;
reg         irq_n;
wire        firq_n;
wire        main_mbs = BS;
reg         vblank_l;

`ifdef MZONE_VRAM_WRITE_WATCH
`ifndef MZONE_VRAM_WRITE_WATCH_FROM
`define MZONE_VRAM_WRITE_WATCH_FROM 0
`endif
integer     vram_watch_frame;
reg         vram_watch_vblank_l;
`endif

wire        ram_cs        = scrolly_cs | scrollx_cs | vram0_cs | vram1_cs |
                            cram0_cs | cram1_cs | objram_cs | shared_cs;
wire        cpu_bus_cen   = cpu_cen;
wire        ram_we        = ram_cs && !RnW && cpu_bus_cen;
wire        scroll_cs     = scrolly_cs | scrollx_cs;

// Schematic-equivalent active-low decode terms. B_B7 decodes the main CPU
// address space using A15..A11, so each select covers a 2 KB block.
// B_A13 is the addressable latch inside the first block.
wire        n_main_latch = ~(VMA && A[15:3]  == 13'h000);
wire        n_watchdog   = ~(VMA && A[15:11] == 5'h01);
wire        n_scrolly    = ~(VMA && A[15:11] == 5'h02);
wire        n_scrollx    = ~(VMA && A[15:11] == 5'h03);
wire        n_vram       = ~(VMA && A[15:11] == 5'h04);
wire        n_cram       = ~(VMA && A[15:11] == 5'h05);
wire        n_vram0      = ~(~n_vram && !A[10]);
wire        n_vram1      = ~(~n_vram &&  A[10]);
wire        n_cram0      = ~(~n_cram && !A[10]);
wire        n_cram1      = ~(~n_cram &&  A[10]);
wire        n_objram     = ~(VMA && A[15:11] == 5'h06);
wire        n_shared     = ~(VMA && A[15:11] == 5'h07);

assign rom_addr = A;
assign cpu_rnw  = RnW;
assign shared_addr = A[10:0];
assign shared_dout = cpu_dout;
assign shared_we   = ram_we && shared_cs;
assign main_vram_addr = A[9:0];
assign main_vram_din  = cpu_dout;
assign main_objram_addr = A[9:0];
assign main_objram_din  = cpu_dout;
assign main_objram_we   = ram_we && objram_cs;
assign main_vram0_we  = ram_we && vram0_cs;
assign main_vram1_we  = ram_we && vram1_cs;
assign main_cram0_we  = ram_we && cram0_cs;
assign main_cram1_we  = ram_we && cram1_cs;
`ifdef MZONE_FORCE_FLIP
assign flip      = 1'b1;
`else
assign flip      = b_a13_flip;
`endif
assign irq_mask  = intst;
assign snd_int   = b_a13_int;

always @(posedge clk) begin
    vblank_l <= vblank;
    if( rst ) begin
        irq_n    <= 1'b1;
        vblank_l <= 1'b1;
    end else begin
        if( !intst || irq_ack ) irq_n <= 1'b1;
        else if( vblank_l && !vblank ) irq_n <= 1'b0;
    end
end

`ifdef MZONE_VRAM_WRITE_WATCH
always @(posedge clk) begin
    if( rst ) begin
        vram_watch_frame    <= 0;
        vram_watch_vblank_l <= 1'b1;
    end else begin
        vram_watch_vblank_l <= vblank;
        if( vram_watch_vblank_l && !vblank )
            vram_watch_frame <= vram_watch_frame + 1;
        if( ram_we && vram_watch_frame >= `MZONE_VRAM_WRITE_WATCH_FROM ) begin
            if( vram0_cs ) $display("MZONE_VRAM_WR frame=%0d addr=%04x ram=vram0 off=%03x data=%02x", vram_watch_frame, A, A[9:0], cpu_dout);
            if( vram1_cs ) $display("MZONE_VRAM_WR frame=%0d addr=%04x ram=vram1 off=%03x data=%02x", vram_watch_frame, A, A[9:0], cpu_dout);
            if( cram0_cs ) $display("MZONE_VRAM_WR frame=%0d addr=%04x ram=cram0 off=%03x data=%02x", vram_watch_frame, A, A[9:0], cpu_dout);
            if( cram1_cs ) $display("MZONE_VRAM_WR frame=%0d addr=%04x ram=cram1 off=%03x data=%02x", vram_watch_frame, A, A[9:0], cpu_dout);
        end
    end
end
`endif

// B_C1B on the schematic: ~FIRQ is clocked by ~INTMAIN and released by ~MBS.
// Use qn so jtframe_ff reset leaves the active-low FIRQ inactive.
jtframe_ff u_nfirq(
    .rst      ( rst         ),
    .clk      ( clk         ),
    .cen      ( 1'b1        ),
    .din      ( 1'b1        ),
    .q        (             ),
    .qn       ( firq_n      ),
    .set      ( 1'b0        ),
    .clr      ( main_mbs    ),
    .sigedge  ( snd_irq_n   )
);

always @(*) begin
    rom_cs     = 0;
    scrolly_cs = 0;
    scrollx_cs = 0;
    vram0_cs   = 0;
    vram1_cs   = 0;
    cram0_cs   = 0;
    cram1_cs   = 0;
    objram_cs  = 0;
    shared_cs  = 0;

    if( !n_scrolly ) scrolly_cs = 1;
    if( !n_scrollx ) scrollx_cs = 1;
    if( !n_vram0   ) vram0_cs   = 1;
    if( !n_vram1   ) vram1_cs   = 1;
    if( !n_cram0   ) cram0_cs   = 1;
    if( !n_cram1   ) cram1_cs   = 1;
    if( !n_objram  ) objram_cs  = 1;
    if( !n_shared  ) shared_cs  = 1;

    if( VMA && A[15:14] != 0 ) rom_cs = RnW;
end

always @(*) begin
    cpu_din = 8'hff;
    if( rom_cs ) begin
        cpu_din = rom_data;
    end else if( vram0_cs ) begin
        cpu_din = main_vram0_dout;
    end else if( vram1_cs ) begin
        cpu_din = main_vram1_dout;
    end else if( cram0_cs ) begin
        cpu_din = main_cram0_dout;
    end else if( cram1_cs ) begin
        cpu_din = main_cram1_dout;
    end else if( objram_cs ) begin
        cpu_din = main_objram_dout;
    end else if( shared_cs ) begin
        cpu_din = shared_din;
    end
end

always @(posedge clk) begin
    if( rst ) begin
        scrolly       <= 0;
        scrollx       <= 0;
        b_a13_coin2   <= 1'b0;
        b_a13_coin1   <= 1'b0;
        b_a13_flip    <= 1'b0;
        b_a13_int     <= 1'b0;
        b_a13_intst   <= 1'b0;
        scroll_pend   <= 1'b0;
        scroll_pend_x <= 1'b0;
        scroll_pend_data <= 8'd0;
    end else begin
        if( ram_we && scroll_cs ) begin
            if( !h2 ) begin
                if( scrolly_cs ) scrolly <= cpu_dout;
                if( scrollx_cs ) scrollx <= cpu_dout;
                scroll_pend <= 1'b0;
            end else begin
                scroll_pend      <= 1'b1;
                scroll_pend_x    <= scrollx_cs;
                scroll_pend_data <= cpu_dout;
            end
        end else if( scroll_pend && !h2 ) begin
            if( scroll_pend_x ) scrollx <= scroll_pend_data;
            else                scrolly <= scroll_pend_data;
            scroll_pend <= 1'b0;
        end
        if( !n_main_latch && !RnW && cpu_bus_cen ) begin
            // B_A13 is a 74LS259 addressable latch. Only the schematic nets
            // currently used by the core are modeled here.
            case( A[2:0] )
                3'd0: b_a13_coin2 <= cpu_dout[0];
                3'd1: b_a13_coin1 <= cpu_dout[0];
                3'd3: b_a13_int   <= cpu_dout[0];
                3'd5: b_a13_flip  <= cpu_dout[0];
                3'd7: b_a13_intst  <= cpu_dout[0];
                default: ;
            endcase
        end
    end
end

jtframe_sys6809 #(
    .RAM_AW     ( 0 ),
    .KONAMI     ( 1 ),
    .RECOVERY   ( 1 ),
    .CENDIV     ( 1 )
) u_cpu(
    .rstn       ( ~rst      ),
    .clk        ( clk       ),
    .cen        ( cpu_clk_cen ),
    .cpu_cen    ( cpu_cen   ),

    .nIRQ       ( irq_n     ),
    .nFIRQ      ( firq_n    ),
    .nNMI       ( 1'b1      ),
    .irq_ack    ( irq_ack   ),
    .BA         ( BA        ),
    .BS         ( BS        ),
    .bus_busy   ( 1'b0      ),

    .A          ( A         ),
    .RnW        ( RnW       ),
    .VMA        ( VMA       ),
    .ram_cs     ( 1'b0      ),
    .rom_cs     ( rom_cs    ),
    .rom_ok     ( rom_ok    ),
    .ram_dout   (           ),
    .cpu_dout   ( cpu_dout  ),
    .cpu_din    ( cpu_din   )
);

endmodule
