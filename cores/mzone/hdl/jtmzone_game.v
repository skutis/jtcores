/*  This file is part of JTCORES.
    JTCORES program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JTCORES program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JTCORES.  If not, see <http://www.gnu.org/licenses/>. */

module jtmzone_game(
    `include "jtframe_game_ports.inc"
);

localparam [21:0] SND_START = `SND_START;

wire [15:0] main_stub_addr;
wire        main_stub_cs;
wire        main_cpu_cen;
wire        clkq_cen;
wire        main_cpu_rnw;
wire [ 7:0] main_cpu_dout;
wire [ 8:0] video_vdump;
wire [ 8:0] video_hdump;
wire [ 8:0] video_vrender;
wire        main_scrolly_cs, main_scrollx_cs;
wire        main_vram0_cs, main_vram1_cs, main_cram0_cs, main_cram1_cs;
wire        main_vram0_we, main_vram1_we, main_cram0_we, main_cram1_we;
wire [ 9:0] main_vram_ofs;
wire [ 9:0] main_tile_addr;
wire [ 7:0] main_vram_din;
wire [ 7:0] main_vram0_dout, main_vram1_dout, main_cram0_dout, main_cram1_dout;
wire        main_objram_cs, main_shared_cs;
wire [ 9:0] main_objram_addr;
wire [ 7:0] main_objram_din;
wire [ 7:0] main_objram_dout;
wire        main_objram_we;
wire [ 9:0] obj_oram_addr;
wire [ 7:0] obj_oram_dout;
wire [ 7:0] main_scrolly, main_scrollx;
wire        main_flip, main_irq_mask, main_int;
wire        main_irq_ack, snd_irq_n;
wire        main_ba;
wire        main_bs;
wire        blank;
wire        video_pre_lvbl;
wire        h2;
wire        fix_en;
reg         blank_q;
reg         v16_q;

`ifdef MZONE_GAME_STATE_WATCH
`ifndef MZONE_GAME_STATE_WATCH_FROM
`define MZONE_GAME_STATE_WATCH_FROM 0
`endif
`ifndef MZONE_GAME_STATE_WATCH_TO
`define MZONE_GAME_STATE_WATCH_TO 16'hffff
`endif
integer game_state_frame;
reg     game_state_lvbl_l;
wire    game_state_active = game_state_frame >= `MZONE_GAME_STATE_WATCH_FROM &&
                            game_state_frame <= `MZONE_GAME_STATE_WATCH_TO;

always @(posedge clk24) begin
    if( rst24 ) begin
        game_state_frame  <= 0;
        game_state_lvbl_l <= 1'b1;
    end else begin
        game_state_lvbl_l <= LVBL;
        if( game_state_lvbl_l && !LVBL )
            game_state_frame <= game_state_frame + 1;

        if( game_state_active && main_cpu_cen && u_main.VMA && main_shared_cs &&
            (main_shared_addr == 11'h31e || main_shared_addr == 11'h31f ||
             main_shared_addr == 11'h320 || main_shared_addr == 11'h020 ||
             main_shared_addr == 11'h021) ) begin
            $display("MZONE_MAIN_SH frame=%0d pc=%04x addr=%03x rw=%b data=%02x",
                game_state_frame, u_main.u_cpu.u_sys6809.reg_pc, main_shared_addr,
                u_main.RnW, u_main.RnW ? main_shared_dout : main_shared_din);
        end

        if( game_state_active && main_objram_we && main_objram_din != 8'd0 ) begin
            $display("MZONE_OBJRAM_WR frame=%0d pc=%04x addr=%03x data=%02x",
                game_state_frame, u_main.u_cpu.u_sys6809.reg_pc,
                main_objram_addr, main_objram_din);
        end
    end
end
`endif

`ifdef MZONE_CPU_WATCH
`ifndef MZONE_CPU_WATCH_FROM
`define MZONE_CPU_WATCH_FROM 0
`endif

integer     cpu_watch_frame;
    integer     main_bus_cnt, snd_fetch_cnt, dac_fetch_cnt;
    integer     main_chg_cnt, main_x_chg_cnt, snd_chg_cnt, dac_chg_cnt;
    integer     main_irq_ack_cnt, main_irq_low_cnt, main_irq_entry_cnt, main_irq_rti_cnt, main_test_irq_cnt;
    integer     queue_rd_cnt, queue_wr_cnt, queue_nz_wr_cnt;
    integer     snd_in0_rd_cnt, snd_in1_rd_cnt, snd_in2_rd_cnt, snd_dsw_rd_cnt;
    integer     snd_sh_wr_cnt, snd_sh_nz_wr_cnt, main_sh_rd_cnt, main_sh_wr_cnt;
    integer     snd_irq_low_cnt, snd_irq_ack_cnt, snd_irq_vec_cnt, snd_irq_copy_cnt;
    integer     main_sig_repeat, snd_sig_repeat, dac_sig_repeat;
    reg         lvbl_l;
    reg  [15:0] main_last_pc, main_last_x, snd_last_addr;
    reg  [15:0] queue_wr_pc, queue_rd_pc;
    reg  [ 9:0] queue_wr_addr, queue_rd_addr;
    reg  [ 7:0] queue_wr_data, queue_rd_data;
    reg  [15:0] snd_in_pc, snd_sh_wr_pc, main_sh_pc;
    reg  [10:0] snd_sh_wr_addr;
    reg  [ 7:0] snd_in_data, snd_sh_wr_data, main_sh_data;
reg  [11:0] dac_last_addr;
    reg  [15:0] main_prev_pc, main_prev_x, snd_prev_addr;
reg  [11:0] dac_prev_addr;
reg  [31:0] main_sig, snd_sig, dac_sig;
reg  [31:0] main_sig_last, snd_sig_last, dac_sig_last;
`ifndef NOSOUND
`ifndef MZONE_FAST_SOUND
wire        watch_snd_int_n = u_snd.int_n;
wire        watch_snd_nmi_n = u_snd.snmi_n;
wire        watch_dac_irq   = u_snd.u_b4.irq_pending;
wire [ 7:0] watch_dac_status= u_snd.dac_status;
`else
wire        watch_snd_int_n = 1'b1;
wire        watch_snd_nmi_n = 1'b1;
wire        watch_dac_irq   = 1'b0;
wire [ 7:0] watch_dac_status= 8'd0;
`endif
`else
wire        watch_snd_int_n = 1'b1;
wire        watch_snd_nmi_n = 1'b1;
wire        watch_dac_irq   = 1'b0;
wire [ 7:0] watch_dac_status= 8'd0;
`endif

initial begin
    $display("MZONE CPU watch enabled");
end

always @(posedge clk24) begin
    if( rst24 ) begin
        cpu_watch_frame <= 0;
        main_bus_cnt    <= 0;
        snd_fetch_cnt   <= 0;
        dac_fetch_cnt   <= 0;
        main_last_pc    <= 16'd0;
        main_last_x     <= 16'd0;
        snd_last_addr   <= 16'd0;
        dac_last_addr   <= 12'd0;
        main_prev_pc    <= 16'd0;
        main_prev_x     <= 16'd0;
        snd_prev_addr   <= 16'd0;
        dac_prev_addr   <= 12'd0;
        main_chg_cnt    <= 0;
        main_x_chg_cnt  <= 0;
        main_irq_ack_cnt<= 0;
        main_irq_low_cnt<= 0;
        main_irq_entry_cnt <= 0;
        main_irq_rti_cnt   <= 0;
        main_test_irq_cnt  <= 0;
        queue_rd_cnt    <= 0;
        queue_wr_cnt    <= 0;
        queue_nz_wr_cnt <= 0;
        queue_wr_pc     <= 16'd0;
        queue_rd_pc     <= 16'd0;
        queue_wr_addr   <= 10'd0;
        queue_rd_addr   <= 10'd0;
        queue_wr_data   <= 8'd0;
        queue_rd_data   <= 8'd0;
        snd_in0_rd_cnt  <= 0;
        snd_in1_rd_cnt  <= 0;
        snd_in2_rd_cnt  <= 0;
        snd_dsw_rd_cnt  <= 0;
        snd_sh_wr_cnt   <= 0;
        snd_sh_nz_wr_cnt<= 0;
        main_sh_rd_cnt  <= 0;
        main_sh_wr_cnt  <= 0;
        snd_irq_low_cnt <= 0;
        snd_irq_ack_cnt <= 0;
        snd_irq_vec_cnt <= 0;
        snd_irq_copy_cnt<= 0;
        snd_in_pc       <= 16'd0;
        snd_in_data     <= 8'd0;
        snd_sh_wr_pc    <= 16'd0;
        snd_sh_wr_addr  <= 11'd0;
        snd_sh_wr_data  <= 8'd0;
        main_sh_pc      <= 16'd0;
        main_sh_data    <= 8'd0;
        snd_chg_cnt     <= 0;
        dac_chg_cnt     <= 0;
        main_sig        <= 32'd0;
        snd_sig         <= 32'd0;
        dac_sig         <= 32'd0;
        main_sig_last   <= 32'd0;
        snd_sig_last    <= 32'd0;
        dac_sig_last    <= 32'd0;
        main_sig_repeat <= 0;
        snd_sig_repeat  <= 0;
        dac_sig_repeat  <= 0;
        lvbl_l          <= 1'b1;
    end else begin
        lvbl_l <= LVBL;
        if( main_cpu_cen && u_main.VMA ) begin
            main_bus_cnt   <= main_bus_cnt + 1;
            main_last_pc   <= u_main.u_cpu.u_sys6809.reg_pc;
            main_last_x    <= u_main.u_cpu.u_sys6809.reg_x;
            main_sig       <= { main_sig[26:0], main_sig[31:27] } ^ { 16'd0, u_main.u_cpu.u_sys6809.reg_pc };
            if( u_main.u_cpu.u_sys6809.reg_pc != main_prev_pc ) begin
                main_chg_cnt   <= main_chg_cnt + 1;
                main_prev_pc   <= u_main.u_cpu.u_sys6809.reg_pc;
            end
            if( u_main.u_cpu.u_sys6809.reg_x != main_prev_x ) begin
                main_x_chg_cnt <= main_x_chg_cnt + 1;
                main_prev_x    <= u_main.u_cpu.u_sys6809.reg_x;
            end
        end
        if( main_irq_ack ) main_irq_ack_cnt <= main_irq_ack_cnt + 1;
        if( !u_main.irq_n ) main_irq_low_cnt <= main_irq_low_cnt + 1;
        if( main_cpu_cen && u_main.u_cpu.u_sys6809.reg_pc == 16'hab57 ) main_irq_entry_cnt <= main_irq_entry_cnt + 1;
        if( main_cpu_cen && u_main.u_cpu.u_sys6809.reg_pc == 16'hab80 ) main_irq_rti_cnt <= main_irq_rti_cnt + 1;
        if( main_cpu_cen && u_main.u_cpu.u_sys6809.reg_pc >= 16'hf000 && u_main.u_cpu.u_sys6809.reg_pc <= 16'hf00d )
            main_test_irq_cnt <= main_test_irq_cnt + 1;
        if( main_vram1_we && main_vram_ofs >= 10'h3bc ) begin
            queue_wr_cnt  <= queue_wr_cnt + 1;
            queue_wr_pc   <= u_main.u_cpu.u_sys6809.reg_pc;
            queue_wr_addr <= main_vram_ofs;
            queue_wr_data <= main_vram_din;
            if( main_vram_din != 8'd0 ) queue_nz_wr_cnt <= queue_nz_wr_cnt + 1;
        end
        if( main_cpu_cen && u_main.VMA && u_main.RnW && u_main.vram1_cs && u_main.A[9:0] >= 10'h3bc ) begin
            queue_rd_cnt  <= queue_rd_cnt + 1;
            queue_rd_pc   <= u_main.u_cpu.u_sys6809.reg_pc;
            queue_rd_addr <= u_main.A[9:0];
            queue_rd_data <= main_vram1_dout;
        end
        if( main_cpu_cen && u_main.VMA && main_shared_cs ) begin
            main_sh_pc   <= u_main.u_cpu.u_sys6809.reg_pc;
            main_sh_data <= u_main.RnW ? main_shared_dout : main_shared_din;
            if( u_main.RnW ) main_sh_rd_cnt <= main_sh_rd_cnt + 1;
            else             main_sh_wr_cnt <= main_sh_wr_cnt + 1;
        end
`ifndef NOSOUND
        if( !u_snd.int_n ) snd_irq_low_cnt <= snd_irq_low_cnt + 1;
        if( u_snd.irq_rst ) snd_irq_ack_cnt <= snd_irq_ack_cnt + 1;
        if( u_snd.cpu_cen && !u_snd.m1_n && !u_snd.mreq_n ) begin
            snd_fetch_cnt <= snd_fetch_cnt + 1;
            snd_last_addr <= u_snd.A;
            snd_sig       <= { snd_sig[26:0], snd_sig[31:27] } ^ { 16'd0, u_snd.A };
            if( u_snd.A != snd_prev_addr ) begin
                snd_chg_cnt   <= snd_chg_cnt + 1;
                snd_prev_addr <= u_snd.A;
            end
            if( u_snd.A == 16'h0038 ) snd_irq_vec_cnt  <= snd_irq_vec_cnt + 1;
            if( u_snd.A == 16'h0085 ) snd_irq_copy_cnt <= snd_irq_copy_cnt + 1;
        end
        if( u_snd.cpu_cen && !u_snd.mreq_n && !u_snd.rd_n ) begin
            if( u_snd.inp0_cs || u_snd.inp1_cs || u_snd.inp2_cs || u_snd.dsw1_cs || u_snd.dsw2_cs ) begin
                snd_in_pc   <= snd_last_addr;
                snd_in_data <= u_snd.cpu_din;
                if( u_snd.inp0_cs ) snd_in0_rd_cnt <= snd_in0_rd_cnt + 1;
                if( u_snd.inp1_cs ) snd_in1_rd_cnt <= snd_in1_rd_cnt + 1;
                if( u_snd.inp2_cs ) snd_in2_rd_cnt <= snd_in2_rd_cnt + 1;
                if( u_snd.dsw1_cs || u_snd.dsw2_cs ) snd_dsw_rd_cnt <= snd_dsw_rd_cnt + 1;
            end
        end
        if( u_snd.cpu_cen && snd_shared_we ) begin
            snd_sh_wr_cnt  <= snd_sh_wr_cnt + 1;
            snd_sh_wr_pc   <= snd_last_addr;
            snd_sh_wr_addr <= snd_shared_addr;
            snd_sh_wr_data <= snd_shared_dout;
            if( snd_shared_dout != 8'd0 ) snd_sh_nz_wr_cnt <= snd_sh_nz_wr_cnt + 1;
        end
`ifndef MZONE_FAST_SOUND
        if( u_snd.dac_cen && dac_cs && dac_ok ) begin
            dac_fetch_cnt <= dac_fetch_cnt + 1;
            dac_last_addr <= dac_addr;
            dac_sig       <= { dac_sig[26:0], dac_sig[31:27] } ^ { 20'd0, dac_addr };
            if( dac_addr != dac_prev_addr ) begin
                dac_chg_cnt  <= dac_chg_cnt + 1;
                dac_prev_addr <= dac_addr;
            end
        end
`endif
`endif
        if( lvbl_l && !LVBL ) begin
            if( main_sig == main_sig_last ) main_sig_repeat <= main_sig_repeat + 1;
            else begin
                main_sig_last   <= main_sig;
                main_sig_repeat <= 0;
            end
            if( snd_sig == snd_sig_last ) snd_sig_repeat <= snd_sig_repeat + 1;
            else begin
                snd_sig_last   <= snd_sig;
                snd_sig_repeat <= 0;
            end
            if( dac_sig == dac_sig_last ) dac_sig_repeat <= dac_sig_repeat + 1;
            else begin
                dac_sig_last   <= dac_sig;
                dac_sig_repeat <= 0;
            end
            if( cpu_watch_frame >= `MZONE_CPU_WATCH_FROM ) begin
            $display("MZONE_CPU frame=%0d main_bus=%0d main_chg=%0d main_pc=%04x main_x=%04x main_x_chg=%0d irq_mask=%b irq_n=%b irq_ack=%0d irq_low=%0d irq_entry=%0d irq_rti=%0d test_irq=%0d q_rd=%0d q_rd_last=%04x:%03x=%02x q_wr=%0d q_nz=%0d q_wr_last=%04x:%03x=%02x main_sh_rd=%0d main_sh_wr=%0d main_sh_last=%04x:%02x main_sig=%08x main_rep=%0d BA=%b BS=%b z80_m1=%0d z80_chg=%0d z80_pc=%04x z80_sig=%08x z80_rep=%0d z80_int_n=%b z80_nmi_n=%b snd_irq_low=%0d snd_irq_ack=%0d snd_irq_vec=%0d snd_irq_copy=%0d snd_in=%0d/%0d/%0d dsw=%0d snd_in_last=%04x:%02x snd_sh_wr=%0d snd_sh_nz=%0d snd_sh_last=%04x:%03x=%02x i8039_fetch=%0d i8039_chg=%0d i8039_pc=%03x i8039_sig=%08x i8039_rep=%0d i8039_irq=%b i8039_status=%02x",
                cpu_watch_frame,
                main_bus_cnt, main_chg_cnt, main_last_pc, main_last_x, main_x_chg_cnt,
                main_irq_mask, u_main.irq_n, main_irq_ack_cnt, main_irq_low_cnt,
                main_irq_entry_cnt, main_irq_rti_cnt, main_test_irq_cnt,
                queue_rd_cnt, queue_rd_pc, queue_rd_addr, queue_rd_data,
                queue_wr_cnt, queue_nz_wr_cnt, queue_wr_pc, queue_wr_addr, queue_wr_data,
                main_sh_rd_cnt, main_sh_wr_cnt, main_sh_pc, main_sh_data,
                main_sig, main_sig_repeat, main_ba, main_bs,
                snd_fetch_cnt, snd_chg_cnt, snd_last_addr, snd_sig, snd_sig_repeat, watch_snd_int_n, watch_snd_nmi_n,
                snd_irq_low_cnt, snd_irq_ack_cnt, snd_irq_vec_cnt, snd_irq_copy_cnt,
                snd_in0_rd_cnt, snd_in1_rd_cnt, snd_in2_rd_cnt, snd_dsw_rd_cnt, snd_in_pc, snd_in_data,
                snd_sh_wr_cnt, snd_sh_nz_wr_cnt, snd_sh_wr_pc, snd_sh_wr_addr, snd_sh_wr_data,
                dac_fetch_cnt, dac_chg_cnt, dac_last_addr, dac_sig, dac_sig_repeat, watch_dac_irq, watch_dac_status);
            end
            cpu_watch_frame <= cpu_watch_frame + 1;
            main_bus_cnt    <= 0;
            snd_fetch_cnt   <= 0;
            dac_fetch_cnt   <= 0;
            main_chg_cnt    <= 0;
            main_x_chg_cnt  <= 0;
            main_irq_ack_cnt<= 0;
            main_irq_low_cnt<= 0;
            main_irq_entry_cnt <= 0;
            main_irq_rti_cnt   <= 0;
            main_test_irq_cnt  <= 0;
            queue_rd_cnt    <= 0;
            queue_wr_cnt    <= 0;
            queue_nz_wr_cnt <= 0;
            snd_in0_rd_cnt  <= 0;
            snd_in1_rd_cnt  <= 0;
            snd_in2_rd_cnt  <= 0;
            snd_dsw_rd_cnt  <= 0;
            snd_sh_wr_cnt   <= 0;
            snd_sh_nz_wr_cnt<= 0;
            main_sh_rd_cnt  <= 0;
            main_sh_wr_cnt  <= 0;
            snd_irq_low_cnt <= 0;
            snd_irq_ack_cnt <= 0;
            snd_irq_vec_cnt <= 0;
            snd_irq_copy_cnt<= 0;
            snd_chg_cnt     <= 0;
            dac_chg_cnt     <= 0;
            main_sig        <= 32'd0;
            snd_sig         <= 32'd0;
            dac_sig         <= 32'd0;
        end
    end
end
`endif

assign dip_flip   = 0;
assign debug_view = 0;

assign main_addr   = main_stub_addr;
assign main_cs     = main_stub_cs;
assign blank       = ~blank_q;
assign main_tile_addr = main_vram_ofs;

`ifdef MZONE_MAIN_LOCAL_ROM
reg [7:0] main_local_rom[0:65535];

initial begin
    $readmemh("/tmp/mzone_main.hex", main_local_rom);
    $display("MZONE_MAIN_LOCAL_ROM loaded /tmp/mzone_main.hex");
end

wire [7:0] main_rom_data = main_local_rom[main_addr];
wire       main_rom_ok   = 1'b1;
`else
wire [7:0] main_rom_data = main_data;
wire       main_rom_ok   = main_ok;
`endif

`ifdef MZONE_SCROLL_REG_WATCH
`ifndef MZONE_SCROLL_REG_WATCH_FROM
`define MZONE_SCROLL_REG_WATCH_FROM 0
`endif
`ifndef MZONE_SCROLL_REG_WATCH_TO
`define MZONE_SCROLL_REG_WATCH_TO 65535
`endif
integer scroll_watch_frame;
reg     scroll_watch_lvbl_l;

always @(posedge clk24) begin
    if( rst24 ) begin
        scroll_watch_frame  <= 0;
        scroll_watch_lvbl_l <= 1'b1;
    end else begin
        scroll_watch_lvbl_l <= LVBL;
        if( scroll_watch_lvbl_l && !LVBL )
            scroll_watch_frame <= scroll_watch_frame + 1;
        if( main_cpu_cen && !main_cpu_rnw && (main_scrolly_cs || main_scrollx_cs) &&
            scroll_watch_frame >= `MZONE_SCROLL_REG_WATCH_FROM &&
            scroll_watch_frame <= `MZONE_SCROLL_REG_WATCH_TO ) begin
            $display("MZONE_SCROLL_REG frame=%0d hdump=%0d vdump=%0d reg=%s data=%02x held_x=%02x held_y=%02x",
                scroll_watch_frame, video_hdump, video_vdump,
                main_scrollx_cs ? "scrollx" : "scrolly",
                main_cpu_dout, main_scrollx, main_scrolly);
        end
    end
end
`endif

`ifdef MZONE_VRAM_POS_WATCH
`ifndef MZONE_VRAM_POS_WATCH_FROM
`define MZONE_VRAM_POS_WATCH_FROM 0
`endif
`ifndef MZONE_VRAM_POS_WATCH_TO
`define MZONE_VRAM_POS_WATCH_TO 65535
`endif
integer vram_pos_frame;
reg     vram_pos_lvbl_l;

always @(posedge clk24) begin
    if( rst24 ) begin
        vram_pos_frame  <= 0;
        vram_pos_lvbl_l <= 1'b1;
    end else begin
        vram_pos_lvbl_l <= LVBL;
        if( vram_pos_lvbl_l && !LVBL )
            vram_pos_frame <= vram_pos_frame + 1;
        if( vram_pos_frame >= `MZONE_VRAM_POS_WATCH_FROM &&
            vram_pos_frame <= `MZONE_VRAM_POS_WATCH_TO ) begin
            if( main_vram0_we )
                $display("MZONE_VRAM_POS frame=%0d hdump=%0d vdump=%0d ram=vram0 off=%03x data=%02x",
                    vram_pos_frame, video_hdump, video_vdump, main_vram_ofs, main_vram_din);
            if( main_cram0_we )
                $display("MZONE_VRAM_POS frame=%0d hdump=%0d vdump=%0d ram=cram0 off=%03x data=%02x",
                    vram_pos_frame, video_hdump, video_vdump, main_vram_ofs, main_vram_din);
        end
    end
end
`endif

`ifdef MZONE_MAIN_WAIT_WATCH
`ifndef MZONE_MAIN_WAIT_WATCH_FROM
`define MZONE_MAIN_WAIT_WATCH_FROM 0
`endif
`ifndef MZONE_MAIN_WAIT_WATCH_TO
`define MZONE_MAIN_WAIT_WATCH_TO 65535
`endif
integer main_wait_frame, main_wait_cycles, main_wait_reqs, main_wait_max;
integer main_wait_start;
reg     main_wait_lvbl_l, main_wait_pending;
reg     main_cs_prev;
reg [15:0] main_wait_addr;

always @(posedge clk24) begin
    if( rst24 ) begin
        main_wait_frame  <= 0;
        main_wait_cycles <= 0;
        main_wait_reqs   <= 0;
        main_wait_max    <= 0;
        main_wait_start  <= 0;
        main_wait_lvbl_l <= 1'b1;
        main_wait_pending<= 1'b0;
        main_cs_prev     <= 1'b0;
        main_wait_addr   <= 16'd0;
    end else begin
        main_wait_lvbl_l <= LVBL;
        main_cs_prev <= main_cs;

        if( main_cs && !main_rom_ok )
            main_wait_cycles <= main_wait_cycles + 1;

        if( main_cs && !main_cs_prev ) begin
            main_wait_reqs <= main_wait_reqs + 1;
            main_wait_addr <= main_addr;
            main_wait_start <= main_wait_cycles;
            main_wait_pending <= 1'b1;
        end

        if( main_wait_pending && main_rom_ok ) begin
            if( main_wait_cycles-main_wait_start > main_wait_max )
                main_wait_max <= main_wait_cycles-main_wait_start;
            if( main_wait_frame >= `MZONE_MAIN_WAIT_WATCH_FROM &&
                main_wait_frame <= `MZONE_MAIN_WAIT_WATCH_TO &&
                main_wait_cycles-main_wait_start > 0 )
                $display("MZONE_MAIN_WAIT_REQ frame=%0d hdump=%0d vdump=%0d addr=%04x wait=%0d main_ok=%b",
                    main_wait_frame, video_hdump, video_vdump, main_wait_addr,
                    main_wait_cycles-main_wait_start, main_rom_ok);
            main_wait_pending <= 1'b0;
        end

        if( main_wait_lvbl_l && !LVBL ) begin
            if( main_wait_frame >= `MZONE_MAIN_WAIT_WATCH_FROM &&
                main_wait_frame <= `MZONE_MAIN_WAIT_WATCH_TO )
                $display("MZONE_MAIN_WAIT_FRAME frame=%0d wait_cycles=%0d reqs=%0d max_wait=%0d",
                    main_wait_frame, main_wait_cycles, main_wait_reqs, main_wait_max);
            main_wait_frame  <= main_wait_frame + 1;
            main_wait_cycles <= 0;
            main_wait_reqs   <= 0;
            main_wait_max    <= 0;
        end
    end
end
`endif

`ifdef MZONE_ROM_REQ_WATCH
`ifndef MZONE_ROM_REQ_WATCH_FROM
`define MZONE_ROM_REQ_WATCH_FROM 0
`endif
`ifndef MZONE_ROM_REQ_WATCH_TO
`define MZONE_ROM_REQ_WATCH_TO 65535
`endif

reg scr_cs_l, obj_cs_l;
reg scr_pend, obj_pend;
integer gfx_cyc, scr_start, obj_start;
integer rom_watch_frame;
reg rom_watch_vs_l;
wire rom_watch_active = rom_watch_frame >= `MZONE_ROM_REQ_WATCH_FROM &&
                        rom_watch_frame <= `MZONE_ROM_REQ_WATCH_TO;

reg main_cs_l, snd_cs_l, dac_cs_l;
reg main_pend, snd_pend, dac_pend;
integer cpu_cyc, main_start, snd_start, dac_start;

always @(posedge clk) begin
    if( rst ) begin
        scr_cs_l <= 1'b0;
        obj_cs_l <= 1'b0;
        scr_pend <= 1'b0;
        obj_pend <= 1'b0;
        gfx_cyc  <= 0;
        rom_watch_frame <= 0;
        rom_watch_vs_l <= 1'b0;
    end else begin
        gfx_cyc <= gfx_cyc + 1;
        rom_watch_vs_l <= VS;
        if( VS && !rom_watch_vs_l ) rom_watch_frame <= rom_watch_frame + 1;
        scr_cs_l <= scrrom_cs;
        obj_cs_l <= objrom_cs;

        if( scrrom_cs && !scr_cs_l ) begin
            scr_pend  <= 1'b1;
            scr_start <= gfx_cyc;
            if( rom_watch_active )
                $display("MZONE_ROM_REQ port=scr cyc=%0d frame=%0d x=%0d y=%0d addr=%03x",
                    gfx_cyc, rom_watch_frame, video_hdump, video_vdump, scrrom_addr);
        end
        if( objrom_cs && !obj_cs_l ) begin
            obj_pend  <= 1'b1;
            obj_start <= gfx_cyc;
            if( rom_watch_active )
                $display("MZONE_ROM_REQ port=obj cyc=%0d frame=%0d x=%0d y=%0d addr=%04x",
                    gfx_cyc, rom_watch_frame, video_hdump, video_vdump, objrom_addr);
        end

        if( scr_pend && scrrom_ok ) begin
            if( rom_watch_active )
                $display("MZONE_ROM_OK port=scr cyc=%0d lat=%0d addr=%03x", gfx_cyc, gfx_cyc-scr_start, scrrom_addr);
            scr_pend <= 1'b0;
        end
        if( obj_pend && objrom_ok ) begin
            if( rom_watch_active )
                $display("MZONE_ROM_OK port=obj cyc=%0d lat=%0d addr=%04x", gfx_cyc, gfx_cyc-obj_start, objrom_addr);
            obj_pend <= 1'b0;
        end

        if( scr_pend && !scrrom_cs && !scrrom_ok ) begin
            if( rom_watch_active )
                $display("MZONE_ROM_DROP port=scr cyc=%0d wait=%0d addr=%03x", gfx_cyc, gfx_cyc-scr_start, scrrom_addr);
            scr_pend <= 1'b0;
        end
        if( obj_pend && !objrom_cs && !objrom_ok ) begin
            if( rom_watch_active )
                $display("MZONE_ROM_DROP port=obj cyc=%0d wait=%0d addr=%04x", gfx_cyc, gfx_cyc-obj_start, objrom_addr);
            obj_pend <= 1'b0;
        end
    end
end

always @(posedge clk24) begin
    if( rst24 ) begin
        main_cs_l <= 1'b0;
        snd_cs_l  <= 1'b0;
        dac_cs_l  <= 1'b0;
        main_pend <= 1'b0;
        snd_pend  <= 1'b0;
        dac_pend  <= 1'b0;
        cpu_cyc   <= 0;
    end else begin
        cpu_cyc <= cpu_cyc + 1;
        main_cs_l <= main_cs;
        snd_cs_l  <= snd_cs;
        dac_cs_l  <= dac_cs;

        if( main_cs && !main_cs_l ) begin
            main_pend  <= 1'b1;
            main_start <= cpu_cyc;
            if( rom_watch_active )
                $display("MZONE_ROM_REQ port=main cyc=%0d addr=%04x", cpu_cyc, main_addr);
        end
        if( snd_cs && !snd_cs_l ) begin
            snd_pend  <= 1'b1;
            snd_start <= cpu_cyc;
            if( rom_watch_active )
                $display("MZONE_ROM_REQ port=snd cyc=%0d addr=%04x", cpu_cyc, snd_addr);
        end
        if( dac_cs && !dac_cs_l ) begin
            dac_pend  <= 1'b1;
            dac_start <= cpu_cyc;
            if( rom_watch_active )
                $display("MZONE_ROM_REQ port=dac cyc=%0d addr=%03x", cpu_cyc, dac_addr);
        end

        if( main_pend && main_rom_ok ) begin
            if( rom_watch_active )
                $display("MZONE_ROM_OK port=main cyc=%0d lat=%0d addr=%04x", cpu_cyc, cpu_cyc-main_start, main_addr);
            main_pend <= 1'b0;
        end
        if( snd_pend && snd_ok ) begin
            if( rom_watch_active )
                $display("MZONE_ROM_OK port=snd cyc=%0d lat=%0d addr=%04x", cpu_cyc, cpu_cyc-snd_start, snd_addr);
            snd_pend <= 1'b0;
        end
        if( dac_pend && dac_ok ) begin
            if( rom_watch_active )
                $display("MZONE_ROM_OK port=dac cyc=%0d lat=%0d addr=%03x", cpu_cyc, cpu_cyc-dac_start, dac_addr);
            dac_pend <= 1'b0;
        end

        if( main_pend && !main_cs && !main_rom_ok ) begin
            if( rom_watch_active )
                $display("MZONE_ROM_DROP port=main cyc=%0d wait=%0d addr=%04x", cpu_cyc, cpu_cyc-main_start, main_addr);
            main_pend <= 1'b0;
        end
        if( snd_pend && !snd_cs && !snd_ok ) begin
            if( rom_watch_active )
                $display("MZONE_ROM_DROP port=snd cyc=%0d wait=%0d addr=%04x", cpu_cyc, cpu_cyc-snd_start, snd_addr);
            snd_pend <= 1'b0;
        end
        if( dac_pend && !dac_cs && !dac_ok ) begin
            if( rom_watch_active )
                $display("MZONE_ROM_DROP port=dac cyc=%0d wait=%0d addr=%03x", cpu_cyc, cpu_cyc-dac_start, dac_addr);
            dac_pend <= 1'b0;
        end
    end
end
`endif

`ifdef JTFRAME_LF_BUFFER
assign game_hdump   = video_hdump;
assign game_vrender = video_vrender[7:0];
`endif

`ifdef JTFRAME_IOCTL_RD
assign ioctl_din = 8'hff;
`endif

always @(*) begin
    post_addr = prog_addr;
end

jtmzone_main u_main(
    .rst        ( rst24          ),
    .clk        ( clk24          ),
    .cpu_clk_cen( cpu4_cen       ),
    .cpu_cen    ( main_cpu_cen   ),

    .rom_addr   ( main_stub_addr ),
    .rom_cs     ( main_stub_cs   ),
    .rom_data   ( main_rom_data  ),
    .rom_ok     ( main_rom_ok    ),

    .cpu_rnw    ( main_cpu_rnw   ),
    .cpu_dout   ( main_cpu_dout  ),

    .scrolly_cs ( main_scrolly_cs ),
    .scrollx_cs ( main_scrollx_cs ),
    .vram0_cs   ( main_vram0_cs   ),
    .vram1_cs   ( main_vram1_cs   ),
    .cram0_cs   ( main_cram0_cs   ),
    .cram1_cs   ( main_cram1_cs   ),
    .objram_cs  ( main_objram_cs  ),
    .shared_cs  ( main_shared_cs  ),
    .shared_addr( main_shared_addr ),
    .shared_dout( main_shared_din  ),
    .shared_we  ( main_shared_we   ),
    .shared_din ( main_shared_dout ),

    .main_vram_addr( main_vram_ofs  ),
    .main_vram_din ( main_vram_din  ),
    .main_vram0_we ( main_vram0_we  ),
    .main_vram1_we ( main_vram1_we  ),
    .main_cram0_we ( main_cram0_we  ),
    .main_cram1_we ( main_cram1_we  ),
    .main_vram0_dout( main_vram0_dout ),
    .main_vram1_dout( main_vram1_dout ),
    .main_cram0_dout( main_cram0_dout ),
    .main_cram1_dout( main_cram1_dout ),
    .main_objram_addr( main_objram_addr ),
    .main_objram_din ( main_objram_din  ),
    .main_objram_we  ( main_objram_we   ),
    .main_objram_dout( main_objram_dout ),

    .scrolly    ( main_scrolly   ),
    .scrollx    ( main_scrollx   ),
    .flip       ( main_flip      ),
    .irq_mask   ( main_irq_mask  ),
    .snd_int    ( main_int       ),

    .vblank     ( LVBL           ),
    .blank      ( blank          ),
    .h2         ( h2             ),
    .dip_pause  ( dip_pause      ),
    .irq_ack    ( main_irq_ack   ),
    .BA         ( main_ba        ),
    .BS         ( main_bs        ),
    .snd_irq_n  ( snd_irq_n      ),
    .snd_dout   ( 8'hff          )
);

jtframe_dual_ram #(
    .AW ( 10 ),
    .DW ( 8  )
) u_objram(
    .clk0   ( clk24             ),
    .data0  ( main_objram_din   ),
    .addr0  ( main_objram_addr  ),
    .we0    ( main_objram_we    ),
    .q0     ( main_objram_dout  ),

    .clk1   ( clk               ),
    .data1  ( 8'd0              ),
    .addr1  ( obj_oram_addr     ),
    .we1    ( 1'b0              ),
    .q1     ( obj_oram_dout     )
);

jtmzone_snd u_snd(
    .rst        ( rst24          ),
    .clk        ( clk24          ),

    .rom_addr   ( snd_addr       ),
    .rom_cs     ( snd_cs         ),
    .rom_data   ( snd_data       ),
    .rom_ok     ( snd_ok         ),
    .dac_addr   ( dac_addr       ),
    .dac_cs     ( dac_cs         ),
    .dac_data   ( dac_data       ),
    .dac_ok     ( dac_ok         ),

    .cab_1p     ( cab_1p[1:0]    ),
    .coin       ( coin[1:0]      ),
    .joystick1  ( joystick1[5:0] ),
    .joystick2  ( joystick2[5:0] ),
    .service    ( service        ),
    .dipsw_a    ( dipsw[ 7:0]    ),
    .dipsw_b    ( dipsw[15:8]    ),
    .blank      ( LVBL           ),
    .h2         ( h2             ),
    .main_irq_ack( main_irq_ack  ),

    .shared_addr( snd_shared_addr ),
    .shared_dout( snd_shared_dout ),
    .shared_we  ( snd_shared_we   ),
    .shared_din ( snd_shared_din  ),
    .main_int   ( main_int        ),
    .main_irq_n ( snd_irq_n       ),

    .ay0a       ( ay0a           ),
    .ay0a_rcen  ( ay0a_rcen      ),
    .ay0b       ( ay0b           ),
    .ay0b_rcen  ( ay0b_rcen      ),
    .ay0c       ( ay0c           ),
    .ay0c_rcen  ( ay0c_rcen      ),
    .dac        ( dac            )
);

jtmzone_video u_video(
    .rst        ( rst            ),
    .clk        ( clk            ),
    .clk24      ( clk24          ),
    .pxl_cen    ( pxl_cen        ),
    .pxl2_cen   ( pxl2_cen       ),

    .main_tile_addr( main_tile_addr ),
    .main_vram_din ( main_vram_din  ),
    .main_cpu_rnw  ( main_cpu_rnw   ),
    .main_vram0_cs ( main_vram0_cs  ),
    .main_vram1_cs ( main_vram1_cs  ),
    .main_cram0_cs ( main_cram0_cs  ),
    .main_cram1_cs ( main_cram1_cs  ),
    .main_vram0_dout( main_vram0_dout ),
    .main_vram1_dout( main_vram1_dout ),
    .main_cram0_dout( main_cram0_dout ),
    .main_cram1_dout( main_cram1_dout ),

    .scrolly    ( main_scrolly   ),
    .scrollx    ( main_scrollx   ),
    .flip       ( main_flip      ),
    .prog_data  ( prog_data      ),
    .prog_addr  ( prog_addr      ),
    .prom_we    ( prom_we        ),

    .fixrom_addr( fixrom_addr      ),
    .fixrom_cs  ( fixrom_cs        ),
    .fixrom_data( fixrom_data      ),
    .fixrom_ok  ( fixrom_ok        ),

    .scrrom_addr( scrrom_addr      ),
    .scrrom_cs  ( scrrom_cs        ),
    .scrrom_data( scrrom_data      ),
    .scrrom_ok  ( scrrom_ok        ),
    .oram_addr ( obj_oram_addr     ),
    .oram_dout ( obj_oram_dout     ),
    .obj_addr   ( objrom_addr      ),
    .obj_cs     ( objrom_cs        ),
    .obj_data   ( objrom_data      ),
    .obj_ok     ( objrom_ok        ),

    .HS         ( HS             ),
    .VS         ( VS             ),
    .LHBL       ( LHBL           ),
    .LVBL       ( LVBL           ),
    .pre_LVBL   ( video_pre_lvbl ),
    .red        ( red            ),
    .green      ( green          ),
    .blue       ( blue           ),

    .clkq_cen   ( clkq_cen       ),
    .h2         ( h2             ),
    .fix_en     ( fix_en         ),
    .hdump      ( video_hdump    ),
    .vdump      ( video_vdump    ),
    .vrender    ( video_vrender  )
);

always @(posedge clk) begin
    if( rst ) begin
        v16_q   <= 1'b0;
        blank_q <= 1'b1;
    end else if( pxl_cen ) begin
        // Schematic BLANK latch: G6B LS74, clocked by V16 and loaded from
        // ~(V32 & V64 & V128) on the V16 rising edge.
        if( !v16_q && video_vdump[4] ) begin
            blank_q <= ~(video_vdump[5] & video_vdump[6] & video_vdump[7]);
        end
        v16_q <= video_vdump[4];
    end
end

endmodule
