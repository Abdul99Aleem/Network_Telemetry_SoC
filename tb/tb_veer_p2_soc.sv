// ============================================================================
// Project: RISC-V Network Telemetry SoC — Phase 2
// TB     : tb_veer_p2_soc (TB2)
// Desc   : VeeR EL2 executes the P2 program THROUGH the project fabric:
//          reset -> fetch from project IMEM (0x0000_0000) -> execute ->
//          LSU sb/lw/sw to project DMEM (0x0001_0000) -> deterministic PASS.
//
// DUT    : veer_wrapper (VeeR, locked submodule, referenced read-only) +
//          soc_top (project fabric + IMEM + DMEM + default slave) +
//          behavioral ICCM/DCCM/ICache SRAMs (same pattern as VeeR tb_top).
// Config : snapshots/p2_soc, reset_vec = 0x00000000 (SoC boots from IMEM).
// PASS   : DMEM[2]==0xFF with DMEM[0]=='P', DMEM[1]=='2',
//          DMEM[4..7]==0x00003250 (CPU read-back word).
// ============================================================================
`timescale 1ns / 1ps

module tb_veer_p2_soc
#(
    `include "el2_param.vh"
);

    reg core_clk = 0;
    always #5 core_clk = ~core_clk;

    reg rst_l = 1;
    reg porst_l = 1;

    reg [31:0] reset_vector = `RV_RESET_VEC;
    reg [31:0] nmi_vector = 32'hee000000;
    reg [31:1] jtag_id;
    reg        nmi_assert_int = 0;
    wire       nmi_int;
    assign nmi_int = 1'b0;

    // ---- VeeR AHB masters ----
    wire [31:0] ic_haddr;  wire [2:0] ic_hburst; wire ic_hmastlock;
    wire [3:0]  ic_hprot;  wire [2:0] ic_hsize;  wire [1:0] ic_htrans;
    wire        ic_hwrite; wire [63:0] ic_hrdata; wire ic_hready, ic_hresp;

    wire [31:0] lsu_haddr; wire [2:0] lsu_hburst; wire lsu_hmastlock;
    wire [3:0]  lsu_hprot; wire [2:0] lsu_hsize; wire [1:0] lsu_htrans;
    wire        lsu_hwrite; wire [63:0] lsu_hwdata, lsu_hrdata;
    wire        lsu_hready, lsu_hresp;

    // ---- SB debug master (unused, tied to IDLE downstream) ----
    wire [31:0] sb_haddr;  wire [2:0] sb_hburst; wire sb_hmastlock;
    wire [3:0]  sb_hprot;  wire [2:0] sb_hsize;  wire [1:0] sb_htrans = 2'b00;
    wire        sb_hwrite; wire [63:0] sb_hwdata, sb_hrdata;
    wire        sb_hready = 1'b1, sb_hresp = 1'b0;

    // ---- DMA slave (unused) ----
    wire [31:0] dma_haddr = 0; wire [2:0] dma_hburst = 0;
    wire dma_hmastlock = 0; wire [3:0] dma_hprot = 0; wire [2:0] dma_hsize = 0;
    wire [1:0] dma_htrans = 0; wire dma_hwrite = 0; wire [63:0] dma_hwdata = 0;
    wire [63:0] dma_hrdata; wire dma_hresp;
    wire dma_hsel = 0, dma_hready_out = 1;

    // ---- trace ----
    wire [31:0] trace_rv_i_insn_ip, trace_rv_i_address_ip;
    wire trace_rv_i_valid_ip, trace_rv_i_exception_ip;
    wire [4:0] trace_rv_i_ecause_ip;
    wire trace_rv_i_interrupt_ip;
    wire [31:0] trace_rv_i_tval_ip;

    // ---- halt/run/debug ----
    reg i_cpu_halt_req = 0, i_cpu_run_req = 0;
    reg mpc_debug_halt_req = 0, mpc_debug_run_req = 0;
    wire o_cpu_halt_ack, o_cpu_halt_status, o_cpu_run_ack, o_debug_mode_status;
    wire mpc_debug_halt_ack, mpc_debug_run_ack;
    wire debug_brkpt_status;
    wire jtag_tdo;

    // ---- tightly-coupled SRAM export (clk driven by the core) ----
    el2_mem_if el2_mem_export ();

    wire rst_l_combined;
    assign rst_l_combined = rst_l;

    // ================= VeeR =================
    veer_wrapper rvtop_wrapper (
        .rst_l(rst_l_combined),
        .dbg_rst_l(porst_l),
        .clk(core_clk),
        .rst_vec(reset_vector[31:1]),
        .nmi_int(nmi_int),
        .nmi_vec(nmi_vector[31:1]),
        .jtag_id(jtag_id[31:1]),

        .haddr(ic_haddr), .hburst(ic_hburst), .hmastlock(ic_hmastlock),
        .hprot(ic_hprot), .hsize(ic_hsize), .htrans(ic_htrans),
        .hwrite(ic_hwrite),
        .hrdata(ic_hrdata), .hready(ic_hready), .hresp(ic_hresp),

        .sb_haddr(sb_haddr), .sb_hburst(sb_hburst), .sb_hmastlock(sb_hmastlock),
        .sb_hprot(sb_hprot), .sb_hsize(sb_hsize), .sb_htrans(sb_htrans),
        .sb_hwrite(sb_hwrite), .sb_hwdata(sb_hwdata),
        .sb_hrdata(sb_hrdata), .sb_hready(sb_hready), .sb_hresp(sb_hresp),

        .lsu_haddr(lsu_haddr), .lsu_hburst(lsu_hburst),
        .lsu_hmastlock(lsu_hmastlock), .lsu_hprot(lsu_hprot),
        .lsu_hsize(lsu_hsize), .lsu_htrans(lsu_htrans),
        .lsu_hwrite(lsu_hwrite), .lsu_hwdata(lsu_hwdata),
        .lsu_hrdata(lsu_hrdata), .lsu_hready(lsu_hready), .lsu_hresp(lsu_hresp),

        .dma_haddr(dma_haddr), .dma_hburst(dma_hburst),
        .dma_hmastlock(dma_hmastlock), .dma_hprot(dma_hprot),
        .dma_hsize(dma_hsize), .dma_htrans(dma_htrans),
        .dma_hwrite(dma_hwrite), .dma_hwdata(dma_hwdata),
        .dma_hrdata(dma_hrdata), .dma_hresp(dma_hresp),
        .dma_hsel(dma_hsel), .dma_hreadyin(dma_hready_out),
        .dma_hreadyout(dma_hready_out),

        .timer_int(1'b0),
        .extintsrc_req(31'b0),

        .lsu_bus_clk_en(1'b1),
        .ifu_bus_clk_en(1'b1),
        .dbg_bus_clk_en(1'b1),
        .dma_bus_clk_en(1'b1),

        .trace_rv_i_insn_ip(trace_rv_i_insn_ip),
        .trace_rv_i_address_ip(trace_rv_i_address_ip),
        .trace_rv_i_valid_ip(trace_rv_i_valid_ip),
        .trace_rv_i_exception_ip(trace_rv_i_exception_ip),
        .trace_rv_i_ecause_ip(trace_rv_i_ecause_ip),
        .trace_rv_i_interrupt_ip(trace_rv_i_interrupt_ip),
        .trace_rv_i_tval_ip(trace_rv_i_tval_ip),

        .jtag_tck(1'b0), .jtag_tms(1'b0), .jtag_tdi(1'b0),
        .jtag_trst_n(1'b1), .jtag_tdo(jtag_tdo), .jtag_tdoEn(),

        .mpc_debug_halt_ack(mpc_debug_halt_ack),
        .mpc_debug_halt_req(mpc_debug_halt_req),
        .mpc_debug_run_ack(mpc_debug_run_ack),
        .mpc_debug_run_req(mpc_debug_run_req),
        .mpc_reset_run_req(1'b1),
        .debug_brkpt_status(debug_brkpt_status),

        .i_cpu_halt_req(i_cpu_halt_req),
        .o_cpu_halt_ack(o_cpu_halt_ack),
        .o_cpu_halt_status(o_cpu_halt_status),
        .i_cpu_run_req(i_cpu_run_req),
        .o_debug_mode_status(o_debug_mode_status),
        .o_cpu_run_ack(o_cpu_run_ack),

        .dec_tlu_perfcnt0(), .dec_tlu_perfcnt1(),
        .dec_tlu_perfcnt2(), .dec_tlu_perfcnt3(),

        .mem_clk(el2_mem_export.clk),
        .iccm_clken(el2_mem_export.iccm_clken),
        .iccm_wren_bank(el2_mem_export.iccm_wren_bank),
        .iccm_addr_bank(el2_mem_export.iccm_addr_bank),
        .iccm_bank_wr_data(el2_mem_export.iccm_bank_wr_data),
        .iccm_bank_wr_ecc(el2_mem_export.iccm_bank_wr_ecc),
        .iccm_bank_dout(el2_mem_export.iccm_bank_dout),
        .iccm_bank_ecc(el2_mem_export.iccm_bank_ecc),
        .dccm_clken(el2_mem_export.dccm_clken),
        .dccm_wren_bank(el2_mem_export.dccm_wren_bank),
        .dccm_addr_bank(el2_mem_export.dccm_addr_bank),
        .dccm_wr_data_bank(el2_mem_export.dccm_wr_data_bank),
        .dccm_wr_ecc_bank(el2_mem_export.dccm_wr_ecc_bank),
        .dccm_bank_dout(el2_mem_export.dccm_bank_dout),
        .dccm_bank_ecc(el2_mem_export.dccm_bank_ecc),

        .ic_tag_clken_final(el2_mem_export.ic_tag_clken_final),
        .ic_tag_wren_q(el2_mem_export.ic_tag_wren_q),
        .ic_tag_wren_biten_vec(el2_mem_export.ic_tag_wren_biten_vec),
        .ic_tag_wr_data(el2_mem_export.ic_tag_wr_data),
        .ic_rw_addr_q(el2_mem_export.ic_rw_addr_q),
        .ic_tag_data_raw_packed_pre(el2_mem_export.ic_tag_data_raw_packed_pre),
        .ic_tag_data_raw_pre(el2_mem_export.ic_tag_data_raw_pre),
        .ic_b_sb_wren(el2_mem_export.ic_b_sb_wren),
        .ic_b_sb_bit_en_vec(el2_mem_export.ic_b_sb_bit_en_vec),
        .ic_sb_wr_data(el2_mem_export.ic_sb_wr_data),
        .ic_rw_addr_bank_q(el2_mem_export.ic_rw_addr_bank_q),
        .wb_packeddout_pre(el2_mem_export.wb_packeddout_pre),
        .ic_bank_way_clken_final(el2_mem_export.ic_bank_way_clken_final),
        .ic_bank_way_clken_final_up(el2_mem_export.ic_bank_way_clken_final_up),
        .wb_dout_pre_up(el2_mem_export.wb_dout_pre_up),

        .iccm_ecc_single_error(), .iccm_ecc_double_error(),
        .dccm_ecc_single_error(), .dccm_ecc_double_error(),
        .dccm_write_readback_error(),

        .soft_int(1'b0), .core_id('0),
        .scan_mode(1'b0), .mbist_mode(1'b0),

        .dmi_core_enable(1'b0), .dmi_uncore_enable(),
        .dmi_uncore_en(), .dmi_uncore_wr_en(), .dmi_uncore_addr(),
        .dmi_uncore_wdata(), .dmi_uncore_rdata(), .dmi_active()
    );

    // ================= project SoC fabric + memories =================
    soc_top #(.IMEM_HEX("p2_prog.hex"), .DMEM_HEX("")) u_soc (
        .clk(core_clk), .reset_n(rst_l_combined),
        .ifu_haddr(ic_haddr), .ifu_hburst(ic_hburst),
        .ifu_hmastlock(ic_hmastlock), .ifu_hprot(ic_hprot),
        .ifu_hsize(ic_hsize), .ifu_htrans(ic_htrans),
        .ifu_hwrite(ic_hwrite),
        .ifu_hrdata(ic_hrdata), .ifu_hready(ic_hready), .ifu_hresp(ic_hresp),
        .lsu_haddr(lsu_haddr), .lsu_hburst(lsu_hburst),
        .lsu_hmastlock(lsu_hmastlock), .lsu_hprot(lsu_hprot),
        .lsu_hsize(lsu_hsize), .lsu_htrans(lsu_htrans),
        .lsu_hwrite(lsu_hwrite), .lsu_hwdata(lsu_hwdata),
        .lsu_hrdata(lsu_hrdata), .lsu_hready(lsu_hready), .lsu_hresp(lsu_hresp)
    );

    // ================= tightly-coupled SRAMs (VeeR tb_top pattern) =================
    wire [3:0][38:0] dccm_bank_fdout;
    wire [3:0][38:0] dccm_wr_fdata_bank;
    wire [3:0][38:0] iccm_bank_fdout;
    wire [3:0][38:0] iccm_bank_wr_fdata;

    genvar i;
    generate
        for (i = 0; i < 4; i++) begin : dccm_loop
            assign dccm_wr_fdata_bank[i] = {el2_mem_export.dccm_wr_ecc_bank[i],
                                            el2_mem_export.dccm_wr_data_bank[i]};
            assign el2_mem_export.dccm_bank_dout[i] = dccm_bank_fdout[i][31:0];
            assign el2_mem_export.dccm_bank_ecc[i]  = dccm_bank_fdout[i][38:32];
            ram_4096x39 dccm_bank (
                .ME(el2_mem_export.dccm_clken[i]),
                .CLK(el2_mem_export.clk),
                .WE(el2_mem_export.dccm_wren_bank[i]),
                .ADR(el2_mem_export.dccm_addr_bank[i]),
                .D(dccm_wr_fdata_bank[i]),
                .Q(dccm_bank_fdout[i]),
                .ROP(),
                .TEST1(1'b0), .RME(1'b0), .RM(4'b0000), .LS(1'b0),
                .DS(1'b0), .SD(1'b0), .TEST_RNM(1'b0), .BC1(1'b0), .BC2(1'b0));
        end
        for (i = 0; i < 4; i++) begin : iccm_loop
            assign iccm_bank_wr_fdata[i] = {el2_mem_export.iccm_bank_wr_ecc[i],
                                            el2_mem_export.iccm_bank_wr_data[i]};
            assign el2_mem_export.iccm_bank_dout[i] = iccm_bank_fdout[i][31:0];
            assign el2_mem_export.iccm_bank_ecc[i]  = iccm_bank_fdout[i][38:32];
            ram_4096x39 iccm_bank (
                .CLK(el2_mem_export.clk),
                .ME(el2_mem_export.iccm_clken[i]),
                .WE(el2_mem_export.iccm_wren_bank[i]),
                .ADR(el2_mem_export.iccm_addr_bank[i]),
                .D(iccm_bank_wr_fdata[i]),
                .Q(iccm_bank_fdout[i]),
                .ROP(),
                .TEST1(1'b0), .RME(1'b0), .RM(4'b0000), .LS(1'b0),
                .DS(1'b0), .SD(1'b0), .TEST_RNM(1'b0), .BC1(1'b0), .BC2(1'b0));
        end
    endgenerate

    // ICache (p2_soc: WAYPACK=1, ECC=1, 2 ways, data 512x142 packed, tag 128x52)
    `include "icache_macros.svh"
    `EL2_TIE_OFF_NON_PACKED
    generate
        for (i = 0; i < 2; i++) begin : icache_banks
            `EL2_PACKED_IC_DATA_SRAM(512,142,71,i)
        end
    endgenerate
    `EL2_IC_TAG_PACKED_SRAM(128,52)

    // ================= reset + halt/run + PASS monitor =================
    initial begin
        $fsdbDumpfile("p2_veer_soc.fsdb");
        $fsdbDumpvars(0, tb_veer_p2_soc);

        jtag_id[31:28] = 4'b1;
        jtag_id[27:12] = '0;
        jtag_id[11:1]  = 11'h45;

        rst_l = 1'b1;
        rst_l = #5 1'b0;
        rst_l = #25 1'b1;
        porst_l = 1'b1;
        porst_l = #1 1'b0;
        porst_l = #10 1'b1;

        $display("[%0t] halting CPU and waiting for ack", $time);
        i_cpu_halt_req = #5 1'b1;
        wait (o_cpu_halt_ack == 1);
        i_cpu_halt_req = 1'b0;
        wait (o_cpu_halt_status == 1'b1);
        i_cpu_run_req = 1'b1;
        wait (o_cpu_run_ack == 1'b1);
        i_cpu_run_req = 1'b0;
        wait (o_cpu_halt_status == 1'b0);

        mpc_debug_halt_req = 1'b1;
        wait (mpc_debug_halt_ack == 1'b1);
        mpc_debug_halt_req = 1'b0;
        wait (o_debug_mode_status == 1'b1);
        mpc_debug_run_req = 1'b1;
        wait (mpc_debug_run_ack == 1'b1);
        mpc_debug_run_req = 1'b0;
        wait (o_debug_mode_status == 1'b0);
        $display("[%0t] CPU running, reset_vec=0x%h", $time, reset_vector);
    end

    // PASS monitor: DMEM[2]==0xFF with expected record contents.
    reg done = 0;
    always @(posedge core_clk) begin
        if (rst_l && !done && u_soc.u_dmem.mem[2] === 8'hFF) begin
            done <= 1'b1;
            if (u_soc.u_dmem.mem[0] === 8'h50 &&
                u_soc.u_dmem.mem[1] === 8'h32 &&
                u_soc.u_dmem.mem[4] === 8'h50 &&
                u_soc.u_dmem.mem[5] === 8'h32 &&
                u_soc.u_dmem.mem[6] === 8'h00 &&
                u_soc.u_dmem.mem[7] === 8'h00) begin
                $display("[%0t] P2_TB2_RESULT: PASS (P2 program ran through project fabric)", $time);
            end else begin
                $display("[%0t] P2_TB2_RESULT: FAIL (bad DMEM contents %h %h %h %h %h %h)",
                         $time, u_soc.u_dmem.mem[0], u_soc.u_dmem.mem[1],
                         u_soc.u_dmem.mem[4], u_soc.u_dmem.mem[5],
                         u_soc.u_dmem.mem[6], u_soc.u_dmem.mem[7]);
            end
            #100;
            $finish;
        end
    end

    initial begin
        #2000000;
        $display("[%0t] P2_TB2_RESULT: TIMEOUT FAIL", $time);
        $finish;
    end

endmodule
