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
    // uart_tx_o / uart_irq_o were left dangling before Phase 2. uart_tx_o is
    // now connected so the suite's serial transcript can be decoded; the
    // driver side lives in sw/src/uart.c and the receiver in the
    // "serial receiver" section below.
    wire uart_tx;
    wire uart_irq;
    wire aes_irq;

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
        .lsu_hrdata(lsu_hrdata), .lsu_hready(lsu_hready), .lsu_hresp(lsu_hresp),
        .uart_tx_o(uart_tx), .uart_irq_o(uart_irq),
        .aes_irq_o(aes_irq)
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

    // ================= bus-watch control =================
    reg     bus_watch;        // +bus_watch
    reg     bus_done;
    integer expect_def_for_tb, expect_buserr_for_tb;
    logic [31:0] expect_addr_for_tb;
    bit     addr_ok;

// ================= reset + halt/run + PASS monitor =================
    // FSDB is opt-in via +wave. With -debug_access+all and a UART-enabled
    // suite running tens of milliseconds, an unconditional dump produces a
    // waveform far too large to be useful and slow enough to be skipped. The
    // repo rule only requires a waveform when investigating a failure, so
    // routine regressions run without one and can be re-run with +wave.
    initial begin
        if ($test$plusargs("wave")) begin
            $fsdbDumpfile("p2_veer_soc.fsdb");
            $fsdbDumpvars(0, tb_veer_p2_soc);
            $display("[TB] FSDB: enabled (+wave) -> p2_veer_soc.fsdb");
        end else begin
            $display("[TB] FSDB: disabled (pass +wave to enable)");
        end
    end

// ================= retire / exception tracker ========================
    // Phase 3 diagnostics. On a timeout the interesting question is whether the
    // core ever took the exception at all, and where it stopped retiring.
    // trace_rv_i_valid_ip pulses once per retired instruction and
    // trace_rv_i_exception_ip marks a retired exception, so these two counters
    // distinguish "handler never ran" from "handler ran but recovery failed".
    // Explicitly initialised: an uninitialised integer stays X after `+ 1`, so
    // the diagnostic would print X and prove nothing.
    integer retire_count   = 0;
    integer exc_count      = 0;
    logic [31:0] last_retire_addr = 32'h0000_0000;
    logic [4:0]  last_exc_cause   = 5'd0;

    always @(posedge core_clk) begin
        if (rst_l_combined && trace_rv_i_valid_ip) begin
            retire_count     = retire_count + 1;
            last_retire_addr = trace_rv_i_address_ip;
            if (trace_rv_i_exception_ip) begin
                exc_count     = exc_count + 1;
                last_exc_cause = trace_rv_i_ecause_ip;
            end
        end
    end

// ================= serial capture control =================
    // Declared here rather than in the receiver section below, because the
    // reset/halt-run and plusarg blocks above assign them.
    //   rx_running  capture enable, set when the CPU leaves reset
    //   corrupt_rx  +uart_corrupt rewrites the first captured byte, so the
    //               UART gate can be proven to reject a wrong payload
    //               (doc/Phase2_UART_Reporting_Record.md)
    //   expect_uart +expect_uart requires a transcript. fw0 emits none, so
    //               requiring one unconditionally would fail a proven
    //               regression.
    reg        rx_running;
    reg        corrupt_rx;
    reg        expect_uart;

// ================= reset + halt/run + PASS monitor =================
    initial begin
        corrupt_rx = $test$plusargs("uart_corrupt");
        expect_uart = $test$plusargs("expect_uart");
        bus_watch   = $test$plusargs("bus_watch");
        bus_done    = 1'b0;
        expect_def_for_tb    = 0;
        expect_buserr_for_tb = 0;
        void'($value$plusargs("expect_def=%d",    expect_def_for_tb));
        void'($value$plusargs("expect_buserr=%d", expect_buserr_for_tb));
        void'($value$plusargs("expect_def_addr=%h", expect_addr_for_tb));
        if (bus_watch)
            $display("[TB] BUS_CHECK: +bus_watch set - will terminate on the observed AHB ERROR");
        if (corrupt_rx)
            $display("[TB] UART_CHECK: +uart_corrupt set - byte 0 will be corrupted");
        if (expect_uart)
            $display("[TB] UART_CHECK: +expect_uart set - transcript will be verified");

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
        // Start serial capture as the firmware comes out of reset. Enabling it
        // here rather than at time 0 means an image that never transmits (fw0)
        // costs nothing and cannot block on a negedge that never comes.
        rx_running = 1'b1;
    end

    // ================= serial receiver (reused from tb_veer_uart_soc) ======
    // Same self-calibrating scheme as the Phase-3 bench: the bit period is
    // MEASURED from the first byte's edges, never guessed. Calibration relies
    // on the first transmitted byte having bit0 set, so that the line rises
    // exactly one bit period after the start bit's falling edge. The suite's
    // transcript opens with 'S' = 0x53, which qualifies. If that first
    // character ever changes, this calibration silently measures 2 or 3 bit
    // periods and the decode fails loudly as a byte mismatch.
    //
    // Captures a variable-length transcript (fw0 emits none), so this buffers
    // up to MAX_RX bytes and parses lines afterwards rather than comparing a
    // fixed expected sequence byte by byte.
    localparam integer MAX_RX = 2048;

    reg        calibrated = 1'b0;
    time       bit_period;
    reg [7:0]  rx_bytes [0:MAX_RX-1];
    integer    rx_count   = 0;
    integer    rx_stop_err = 0;
    // rx_running, corrupt_rx and expect_uart are declared near the reset block
    // above, because it assigns them.

    function automatic [7:0] printable(input [7:0] c);
        printable = (c >= 8'h20 && c < 8'h7F) ? c : 8'h2E; // '.'
    endfunction

    task automatic uart_rx_byte(output reg [7:0] b);
        time t0;
        integer k;
        begin
            @(negedge uart_tx);                 // start bit falling edge
            t0 = $time;
            if (!calibrated) begin
                // First byte has bit0 = 1 (see note above), so the line rises
                // after exactly one bit period. Measure, do not assume.
                @(posedge uart_tx);
                bit_period = $time - t0;
                calibrated  = 1'b1;
                // Printed with explicit %0d as well as %0t: %0t renders in ps
                // while the arithmetic is in ns, which makes the raw numbers
                // look inconsistent unless the units are stated.
                $display("[%0t ns] UART MONITOR: calibrated bit period = %0t ns (%0d ns, %0d clk)",
                         $time, bit_period, bit_period, bit_period / 10);
            end
            // align to the middle of data bit 0 = t0 + 1.5 * bit_period
            #((3 * bit_period) / 2 - ($time - t0));
            for (k = 0; k < 8; k = k + 1) begin
                b[k] = uart_tx;
                if (k != 7) #(bit_period);
            end
            #(bit_period);                       // stop bit window
            if (uart_tx !== 1'b1) begin
                $display("[%0t ns] UART MONITOR: ERROR stop bit not high after byte %0d",
                         $time, rx_count);
                rx_stop_err++;
            end
        end
    endtask

    // Continuous capture, gated by rx_running so it stops once the suite has
    // finished and the line has gone quiet.
    initial begin : rx_loop
        forever begin
            wait (rx_running && rx_count < MAX_RX);
            uart_rx_byte(rx_bytes[rx_count]);
            if (corrupt_rx && rx_count == 0)
                rx_bytes[0] = 8'h00;            // deliberate corruption
            $display("[%0t ns] UART RX[%0d] = 0x%02h '%c'", $time, rx_count,
                     rx_bytes[rx_count], printable(rx_bytes[rx_count]));
            rx_count++;
        end
    end

// ================= UART transcript verification =========================
//
// The transcript is PARSED, not string-compared against a golden copy, and
// every field is cross-checked against the DMEM result table. That makes
// "UART and DMEM agree" a checked claim instead of an assumption: if the
// firmware prints one number and stores another, this fails.
    integer uart_fail;
    reg     uart_checked;

    // DMEM table header, read once by dump_test_results and cross-checked
    // against the parsed transcript by verify_uart_transcript. Module scope so
    // both tasks see the same values.
    integer tb_ntests, tb_npass, tb_nfail;
    integer tb_ff_idx, tb_ff_code, tb_ff_got, tb_ff_want;

    function automatic bit str_is(input integer start, input integer n,
                                  input string want);
        integer p;
        begin
            str_is = 1'b0;
            if (start + n > rx_count) str_is = 1'b0;
            else begin
                str_is = 1'b1;
                for (p = 0; p < n; p = p + 1)
                    if (rx_bytes[start+p] !== want[p]) str_is = 1'b0;
            end
        end
    endfunction

    // Find a key substring anywhere in the transcript and return the index
    // just past it, or -1. Keys are unique within one transcript, so an
    // unanchored search is safe here. An earlier version required a preceding
    // newline, which silently failed for every space-separated key after the
    // first (npass=, nfail=, first_fail=, got=, want=) and reported zeros.
    function automatic integer find_kv(input integer from, input string key);
        integer p, klen;
        begin
            find_kv = -1;
            klen = key.len();
            for (p = from; p + klen <= rx_count; p = p + 1)
                if (str_is(p, klen, key)) find_kv = p + klen;
        end
    endfunction

    function automatic integer scan_dec(input integer from);
        integer p;
        integer val;
        begin
            val = 0;
            scan_dec = -1;
            if (from < 0) begin
                scan_dec = -1;
                return scan_dec;
            end
            for (p = from; p < rx_count; p = p + 1) begin
                if (rx_bytes[p] >= "0" && rx_bytes[p] <= "9")
                    val = val * 10 + (rx_bytes[p] - "0");
                else begin
                    scan_dec = val;
                    return scan_dec;
                end
            end
            scan_dec = -1;
        end
    endfunction

    function automatic integer scan_hex(input integer from);
        integer p;
        integer val;
        begin
            val = 0;
            scan_hex = -1;
            if (from < 0) begin
                scan_hex = -1;
                return scan_hex;
            end
            for (p = from; p < rx_count; p = p + 1) begin
                if      ((rx_bytes[p] >= "0") && (rx_bytes[p] <= "9"))
                    val = val * 16 + (rx_bytes[p] - "0");
                else if ((rx_bytes[p] >= "A") && (rx_bytes[p] <= "F"))
                    val = val * 16 + (rx_bytes[p] - "A" + 10);
                else if ((rx_bytes[p] >= "a") && (rx_bytes[p] <= "f"))
                    val = val * 16 + (rx_bytes[p] - "a" + 10);
                else begin
                    scan_hex = val;
                    return scan_hex;
                end
            end
            scan_hex = -1;
        end
    endfunction

    task automatic verify_uart_transcript;
        integer ntests_u, npass_u, nfail_u, ff_u, code_u;
        integer got_u, want_u;
        integer idx;
        integer line_start;
        integer tcount, pcount;
        begin
            uart_checked = 1'b1;
            uart_fail    = 0;

            if (rx_stop_err != 0) begin
                $display("[TB] UART_CHECK: FAIL - %0d stop-bit error(s)", rx_stop_err);
                uart_fail++;
            end

            if (rx_count < 12 || !str_is(0, 12, "SUITE_BEGIN\n")) begin
                $display("[TB] UART_CHECK: FAIL - missing SUITE_BEGIN (captured %0d bytes)",
                         rx_count);
                uart_fail++;
            end

            // ---- per-test lines ------------------------------------------
            tcount = 0; pcount = 0;
            line_start = 12;                       // just past SUITE_BEGIN\n
            for (idx = 0; idx < rx_count; idx = idx + 1) begin
                if (rx_bytes[idx] == 8'h0A) begin
                    // Line body is [line_start, idx), and rx_bytes[idx] is the
                    // terminating newline. Check the trailing 6 bytes only:
                    // comparing the whole span against " PASS\n" can never
                    // match, because a real line is "T0 <name> PASS\n".
                    if (idx > line_start && rx_bytes[line_start] == "T") begin
                        tcount = tcount + 1;
                        if (str_is(idx - 5, 6, " PASS\n"))
                            pcount = pcount + 1;
                    end
                    line_start = idx + 1;
                end
            end

            // ---- summary line, cross-checked against DMEM ----------------
            ntests_u = find_kv(0, "SUITE_END ntests=");
            if (ntests_u < 0) begin
                $display("[TB] UART_CHECK: FAIL - no SUITE_END summary line");
                uart_fail++;
            end else begin
                ntests_u  = scan_dec(find_kv(0, "SUITE_END ntests="));
                npass_u   = scan_dec(find_kv(0, "npass="));
                nfail_u   = scan_dec(find_kv(0, "nfail="));
                ff_u      = scan_dec(find_kv(0, "first_fail="));
                code_u    = scan_dec(find_kv(0, "code="));
                got_u     = scan_hex(find_kv(0, "got=0x"));
                want_u    = scan_hex(find_kv(0, "want=0x"));

                $display("[TB] UART_CHECK: parsed ntests=%0d npass=%0d nfail=%0d first_fail=%0d code=%0d got=0x%08x want=0x%08x",
                         ntests_u, npass_u, nfail_u, ff_u, code_u, got_u, want_u);

                // Cross-check against the DMEM table (values read below by
                // verify_against_dmem, which owns the table accessors).
                if (ntests_u !== tb_ntests) begin
                    $display("[TB] UART_CHECK: FAIL - UART ntests=%0d but DMEM ntests=%0d",
                             ntests_u, tb_ntests);
                    uart_fail++;
                end
                if (npass_u !== tb_npass) begin
                    $display("[TB] UART_CHECK: FAIL - UART npass=%0d but DMEM npass=%0d",
                             npass_u, tb_npass);
                    uart_fail++;
                end
                if (nfail_u !== tb_nfail) begin
                    $display("[TB] UART_CHECK: FAIL - UART nfail=%0d but DMEM nfail=%0d",
                             nfail_u, tb_nfail);
                    uart_fail++;
                end
                if (ff_u !== tb_ff_idx) begin
                    $display("[TB] UART_CHECK: FAIL - UART first_fail=%0d but DMEM first_fail_idx=%0d",
                             ff_u, tb_ff_idx);
                    uart_fail++;
                end
                if (code_u !== tb_ff_code) begin
                    $display("[TB] UART_CHECK: FAIL - UART code=%0d but DMEM first_fail_code=%0d",
                             code_u, tb_ff_code);
                    uart_fail++;
                end
                if (tcount !== tb_ntests) begin
                    $display("[TB] UART_CHECK: FAIL - %0d per-test line(s) but ntests=%0d",
                             tcount, tb_ntests);
                    uart_fail++;
                end
                if (pcount !== tb_npass) begin
                    $display("[TB] UART_CHECK: FAIL - %0d PASS line(s) but npass=%0d",
                             pcount, tb_npass);
                    uart_fail++;
                end
                if (got_u !== tb_ff_got || want_u !== tb_ff_want) begin
                    $display("[TB] UART_CHECK: FAIL - UART got=0x%08x want=0x%08x but DMEM got=0x%08x want=0x%08x",
                             got_u, want_u, tb_ff_got, tb_ff_want);
                    uart_fail++;
                end
            end

            if (uart_fail == 0)
                $display("[TB] UART_CHECK: PASS (%0d byte transcript, %0d test lines, UART agrees with DMEM)",
                         rx_count, tcount);
            else
                $display("[TB] UART_CHECK: FAIL (%0d condition(s), %0d byte transcript)",
                         uart_fail, rx_count);

            // Echo the transcript so the log carries the report as text, not
            // only as parsed fields. This is the human-readable evidence that
            // each test was reported individually.
            $write("[TB] UART_TRANSCRIPT_BEGIN\n");
            for (int unsigned i = 0; i < rx_count; i = i + 1) begin
                if (rx_bytes[i] == 8'h0A) $display("[TB] |%s", "");
                else                      $write("%s", printable(rx_bytes[i]));
            end
            $display("[TB] UART_TRANSCRIPT_END");
        end
    endtask
    // Reads the .results NOLOAD block the firmware runner fills in, by absolute
    // DMEM address. Mirrors sw/include/test.h:
    //   [0x00] magic 'T''E''S''T'  [0x04] ntests  [0x08] npass  [0x0C] nfail
    //   [0x10] first_fail_idx       [0x14] first_fail_code
    //   [0x18] first_fail_got       [0x1C] first_fail_want
    // then ntests entries of { const char *name; uint32 code; } = 8 bytes each.
    //
    // For a non-suite image the block is absent, so magic reads as 0 and this
    // prints one "no result table" line and returns. fw0 therefore keeps its
    // log shape apart from one extra line.
    task automatic dump_test_results;
        int unsigned magic;
        int unsigned ntests, npass, nfail, ff_idx, ff_code, ff_got, ff_want;
        int unsigned base;
        begin
            // u_dmem.mem is indexed by OFFSET from the DMEM base, not by
            // absolute address: ahb_sram.mem is SIZE_BYTES deep and
            // BASE_ADDR=0x0001_0000 is unused by the array (ahb_sram.sv:43).
            // So RESULTS_BASE 0x0001_0010 is array index 0x10. Indexing with
            // the absolute address reads out of bounds and yields X -- which is
            // exactly what happened before this was corrected.
            base   = 32'h0001_0010 - 32'h0001_0000;   // == 0x10
            magic  = {u_soc.u_dmem.mem[base+3], u_soc.u_dmem.mem[base+2],
                      u_soc.u_dmem.mem[base+1], u_soc.u_dmem.mem[base+0]};
            if (magic !== 32'h5453_4553) begin
                $display("[%0t] TEST_RESULT: none (no .results table in this image)", $time);
                // Always print the raw header words so "magic missing" is a
                // diagnosable log line rather than a dead end.
                for (int unsigned w = 0; w < 8; w++)
                    $display("[%0t] TEST_RAW[0x%04h] = %08h", $time, base + w*4,
                             {u_soc.u_dmem.mem[base+w*4+3], u_soc.u_dmem.mem[base+w*4+2],
                              u_soc.u_dmem.mem[base+w*4+1], u_soc.u_dmem.mem[base+w*4+0]});
            end else begin
                ntests  = {u_soc.u_dmem.mem[base+7], u_soc.u_dmem.mem[base+6],
                           u_soc.u_dmem.mem[base+5], u_soc.u_dmem.mem[base+4]};
                npass   = {u_soc.u_dmem.mem[base+11], u_soc.u_dmem.mem[base+10],
                           u_soc.u_dmem.mem[base+ 9], u_soc.u_dmem.mem[base+ 8]};
                nfail   = {u_soc.u_dmem.mem[base+15], u_soc.u_dmem.mem[base+14],
                           u_soc.u_dmem.mem[base+13], u_soc.u_dmem.mem[base+12]};
                ff_idx  = {u_soc.u_dmem.mem[base+19], u_soc.u_dmem.mem[base+18],
                           u_soc.u_dmem.mem[base+17], u_soc.u_dmem.mem[base+16]};
                ff_code = {u_soc.u_dmem.mem[base+23], u_soc.u_dmem.mem[base+22],
                           u_soc.u_dmem.mem[base+21], u_soc.u_dmem.mem[base+20]};
                ff_got  = {u_soc.u_dmem.mem[base+27], u_soc.u_dmem.mem[base+26],
                           u_soc.u_dmem.mem[base+25], u_soc.u_dmem.mem[base+24]};
                ff_want = {u_soc.u_dmem.mem[base+31], u_soc.u_dmem.mem[base+30],
                           u_soc.u_dmem.mem[base+29], u_soc.u_dmem.mem[base+28]};
                $display("[%0t] TEST_RESULT: ntests=%0d npass=%0d nfail=%0d",
                         $time, ntests, npass, nfail);
                $display("[%0t] TEST_RESULT: first_fail idx=%0d code=%0d got=%0h want=%0h",
                         $time, ff_idx, ff_code, ff_got, ff_want);
                for (int unsigned i = 0; i < ntests; i++) begin
                    int unsigned e = base + 32 + i*8;
                    $display("[%0t] TEST_CASE[%0d] name_ptr=0x%08h code=%0d",
                             $time, i,
                             {u_soc.u_dmem.mem[e+3], u_soc.u_dmem.mem[e+2],
                              u_soc.u_dmem.mem[e+1], u_soc.u_dmem.mem[e+0]},
                             {u_soc.u_dmem.mem[e+7], u_soc.u_dmem.mem[e+6],
                              u_soc.u_dmem.mem[e+5], u_soc.u_dmem.mem[e+4]});
                end

                // Publish for the UART cross-check.
                tb_ntests  = ntests;  tb_npass  = npass;  tb_nfail  = nfail;
                tb_ff_idx  = ff_idx;  tb_ff_code = ff_code;
                tb_ff_got  = ff_got;  tb_ff_want = ff_want;
            end
        end
    endtask

    // PASS monitor: DMEM[2]==0xFF with expected record contents.
    reg done = 0;
    always @(posedge core_clk) begin
        if (rst_l && !done && u_soc.u_dmem.mem[2] === 8'hFF) begin
            done <= 1'b1;
            $display("[%0t] MBOX[8..15] spike fields : iccm_rb=%h dccm_rb=%h",
                     $time,
                     {u_soc.u_dmem.mem[11], u_soc.u_dmem.mem[10],
                      u_soc.u_dmem.mem[ 9], u_soc.u_dmem.mem[ 8]},
                     {u_soc.u_dmem.mem[15], u_soc.u_dmem.mem[14],
                      u_soc.u_dmem.mem[13], u_soc.u_dmem.mem[12]});
            dump_test_results();
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

            // Let the serial line go quiet, then decode and check it. The
            // firmware already waited for TEMT before returning, so this only
            // has to cover the in-flight tail; the bound keeps a truncated
            // transcript from silently passing.
            rx_running = 1'b0;
            #(100 * 10 * 20);                       // <= 20 bit periods
            dump_test_results();
            if (expect_uart) begin
                verify_uart_transcript();
                if (uart_fail != 0)
                    $display("[%0t] UART_CHECK_RESULT: FAIL", $time);
                else
                    $display("[%0t] UART_CHECK_RESULT: PASS", $time);
            end else begin
                $display("[%0t] UART_CHECK_RESULT: SKIP (+expect_uart not set)", $time);
            end

            #100;
            $finish;
        end
    end

    // ================= additive AHB read/write cycle monitor (plan §5.2) ====
    // Separate module on purpose: spec §22 fw0 wants the PASS monitor above to
    // fire with ZERO changes, while spec §14/§16 L6 wants an independent token
    // proving read AND write cycles really occurred. Instantiated after `done`
    // is declared; the reset/halt/run sequence above is untouched.
    tb_ahb_cycle_monitor #(
        .N_IMEM_RD(8),
        .N_DMEM_RD(16),
        .N_DMEM_WR(16),
        // Raised for Phase 2: the UART-enabled suite transmits a ~200-byte
        // transcript at 90 ns/bit (~18 us) and runs longer than fw0. 8x the
        // fw0 budget, which fw0 itself finishes in 90.7 ms with room to spare.
        .WATCHDOG_NS(15_000_000)  // ahead of the #16000000 timeout below
    ) u_ahb_mon (
        .clk       (core_clk),
        .rst_n     (rst_l_combined),
        .stop      (done),

        .ic_haddr  (ic_haddr),
        .ic_htrans (ic_htrans),
        .ic_hwrite (ic_hwrite),
        .ic_hready (ic_hready),
        .ic_hresp  (ic_hresp),

        .lsu_haddr (lsu_haddr),
        .lsu_htrans(lsu_htrans),
        .lsu_hwrite(lsu_hwrite),
        .lsu_hready(lsu_hready),
        .lsu_hresp (lsu_hresp)
    );

// ================= bus-error watcher ==================================
    // Phase 3. The CPU cannot complete an access to unmapped space, so it never
    // reaches startup.S's mailbox write and the normal monitor above can never
    // fire. For the bus variant the termination condition is therefore the
    // FABRIC EVIDENCE itself: once the default ERROR slave has claimed the
    // expected address and the monitor counts match the declared expectations,
    // the run is complete and correct.

    always @(posedge core_clk) begin
        if (rst_l_combined && bus_watch && !bus_done) begin
            // tb_ahb_cycle_monitor exposes its counters hierarchically.
            if (u_ahb_mon.def_sel >= 1 && u_ahb_mon.bus_err >= 1) begin
                bus_done <= 1'b1;
                // Counts AND the address. A correct count from the wrong address
                // is not evidence that the intended address was exercised.
                addr_ok = (u_ahb_mon.def_addr_count == 1) &&
                          (u_ahb_mon.def_addr[0] == expect_addr_for_tb);
                if (u_ahb_mon.def_sel == expect_def_for_tb &&
                    u_ahb_mon.bus_err == expect_buserr_for_tb && addr_ok) begin
                    $display("[%0t] BUS_CHECK: PASS (fabric returned ERROR: addr=0x%08h def=%0d bus_err=%0d)",
                             $time, u_ahb_mon.def_addr[0], u_ahb_mon.def_sel,
                             u_ahb_mon.bus_err);
                    $display("[%0t] BUS_CHECK_RESULT: PASS", $time);
                    $finish;
                end else begin
                    $display("[%0t] BUS_CHECK: FAIL (addr=0x%08h want 0x%08h addr_ok=%0b; def=%0d want %0d; bus_err=%0d want %0d)",
                             $time, u_ahb_mon.def_addr[0], expect_addr_for_tb,
                             addr_ok, u_ahb_mon.def_sel, expect_def_for_tb,
                             u_ahb_mon.bus_err, expect_buserr_for_tb);
                    $display("[%0t] BUS_CHECK_RESULT: FAIL", $time);
                    $finish;
                end
            end
        end
    end

    initial begin
        #16000000;
        // Also dump the Phase-0 spike fields on timeout. A trap parks the CPU
        // before startup.S can write mbox[2], so the monitor above never fires
        // and its display is skipped — without this the values written before
        // the fault would be lost from the log.
        $display("[%0t] MBOX[8..15] spike fields : iccm_rb=%h dccm_rb=%h",
                 $time,
                 {u_soc.u_dmem.mem[11], u_soc.u_dmem.mem[10],
                  u_soc.u_dmem.mem[ 9], u_soc.u_dmem.mem[ 8]},
                 {u_soc.u_dmem.mem[15], u_soc.u_dmem.mem[14],
                  u_soc.u_dmem.mem[13], u_soc.u_dmem.mem[12]});
        dump_test_results();
        // Trap diagnostic. `entries` is the counter startup.S:trap_handler
        // increments on every entry; 0 means the handler never ran at all,
        // which points at the exception not being delivered rather than at the
        // recovery code. It lives at the linker-fixed __trapdiag address
        // (DMEM 0x0001_000C == byte offset 0x0C), so the TB can read it.
        //
        // trap_expect / saved_ra / saved_sp / resumed_ok are ordinary .bss
        // globals whose addresses depend on the layout, so the TB cannot read
        // them by index. They are NOT printed here; an earlier version read
        // bytes 0x10..0x17, which is the .results header (magic/ntests) and
        // printed those as if they were trap state. The trap path is currently
        // not exercised by any test (a bus response error does not trap on this
        // core — see sw/tests/t_bus.c), so this is diagnostic only.
        $display("[%0t] TRACEDIAG retired=%0d last_pc=0x%08h exceptions_taken=%0d last_ecause=%0d",
                 $time, retire_count, last_retire_addr, exc_count, last_exc_cause);
        $display("[%0t] TRAPDIAG entries=%0d", $time,
                 {u_soc.u_dmem.mem[15], u_soc.u_dmem.mem[14],
                  u_soc.u_dmem.mem[13], u_soc.u_dmem.mem[12]});
        $display("[%0t] P2_TB2_RESULT: TIMEOUT FAIL", $time);
        $finish;
    end

endmodule
