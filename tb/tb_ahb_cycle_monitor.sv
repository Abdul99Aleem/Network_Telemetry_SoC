// ============================================================================
// Project: RISC-V Network Telemetry SoC
// File   : tb/tb_ahb_cycle_monitor.sv
// Desc   : Additive AHB-Lite read/write cycle monitor (plan §5.2).
//
//          WHY THIS EXISTS SEPARATELY
//          Spec §22 fw0 requires the *existing* tb_veer_p2_soc monitor
//          (tb/tb_veer_p2_soc.sv:300) to fire with zero changes, while spec
//          §14/§16 L6 wants its own unambiguous terminal token proving read
//          AND write cycles actually happened on the fabric. This module adds
//          the second token without touching the first.
//
//          SAMPLING RULE — address phase, not data phase
//          An address phase is ACCEPTED in cycle t iff
//              HTRANS != IDLE   &&   HREADY == 1
//          sampled on posedge clk while rst_n is high. The values read in the
//          active region of posedge are the ones the slaves sample at that
//          same edge (both masters' HTRANS/HREADY settle through NBA from the
//          previous edge).
//
//          DO NOT pair hsel with hreadyout on the same cycle: hsel is an
//          address-phase signal, hreadyout completes the *data* phase.
//          doc/Phase2_AHB_Fabric_Completion_Record.md §4.1 and §4.3 record
//          two bugs of exactly that class ("BFM sampled AHB responses a cycle
//          early"), so the rule above is the one that is known-correct here.
//
//          ADDRESS DECODE mirrors rtl/ahb/ahb_interconnect.sv:142-144
//              addr[31:15] == 17'h0000 -> IMEM   0x0000_0000 / 32 KB
//              addr[31:15] == 17'h0002 -> DMEM   0x0001_0000 / 32 KB
//              addr[31:12] == 20'h10000 -> UART  0x1000_0000 / 4 KB
//              anything else           -> DEFAULT ERROR slave
//
//          OUTPUT (once, on completion or watchdog):
//            [TB] AHB_CYCLES imem_rd=.. imem_wr=.. dmem_rd=.. dmem_wr=..
//                               uart_rd=.. uart_wr=.. def=.. bus_err=..
//            [TB] AHB_RW_MONITOR: PASS|FAIL ...
//
//          PASS iff  imem_rd >= N_IMEM_RD
//                 && dmem_rd >= N_DMEM_RD
//                 && dmem_wr >= N_DMEM_WR
//                 && bus_err == 0
//                 && def     == 0        (no transfer hit the ERROR slave)
//
//          imem_wr is a CANARY: under image decision D11 the .bss VMA lives
//          in DMEM, so nothing ever stores into IMEM. Any non-zero value means
//          a stray write is reaching code memory.
// ============================================================================
`timescale 1ns / 1ps

module tb_ahb_cycle_monitor #(
    parameter int N_IMEM_RD = 8,
    parameter int N_DMEM_RD = 16,
    parameter int N_DMEM_WR = 16,
    // Must fire BEFORE tb_veer_p2_soc's own #2000000 watchdog so the cycle
    // summary is still in the log when the testbench gives up.
    parameter int WATCHDOG_NS = 1_900_000
) (
    input wire        clk,
    input wire        rst_n,
    input wire        stop,          // connected to the TB 'done' flag

    // ---- IFU master (fetch-only: never writes) ----
    input wire [31:0] ic_haddr,
    input wire [1:0]  ic_htrans,
    input wire        ic_hwrite,
    input wire        ic_hready,
    input wire        ic_hresp,

    // ---- LSU master (reads and writes) ----
    input wire [31:0] lsu_haddr,
    input wire [1:0]  lsu_htrans,
    input wire        lsu_hwrite,
    input wire        lsu_hready,
    input wire        lsu_hresp
);

    localparam logic [1:0] HTRANS_IDLE = 2'b00;

    // ---------------------------------------------------------------- counters
    int unsigned imem_rd, imem_wr;
    int unsigned dmem_rd, dmem_wr;
    int unsigned uart_rd, uart_wr;
    int unsigned def_sel;
    int unsigned bus_err;
    int unsigned ifu_bad;      // IFU fetch aimed outside IMEM
    int unsigned cycles;       // accepted address phases of any kind

    reg          reported = 1'b0;   // 4-state regs default to X; `if (!X)` is
    reg          stop_d   = 1'b0;   // never true, which silently disables both
                                    // the counting block and the watchdog.
                                    // Must be initialised explicitly.

    // ------------------------------------------------------------- addr decode
    function automatic bit is_imem(input logic [31:0] a);
        return (a[31:15] == 17'h0000);
    endfunction

    function automatic bit is_dmem(input logic [31:0] a);
        return (a[31:15] == 17'h0002);
    endfunction

    function automatic bit is_uart(input logic [31:0] a);
        return (a[31:12] == 20'h10000);
    endfunction

    // ----------------------------------------------------------------- report
    task automatic report(input string reason);
        int unsigned fail_count;
        bit pass;
        pass = (imem_rd >= N_IMEM_RD) &&
               (dmem_rd >= N_DMEM_RD) &&
               (dmem_wr >= N_DMEM_WR) &&
               (bus_err == 0) &&
               (def_sel == 0);

        $display("[TB] AHB_CYCLES imem_rd=%0d imem_wr=%0d dmem_rd=%0d dmem_wr=%0d",
                 imem_rd, imem_wr, dmem_rd, dmem_wr);
        $display("[TB] AHB_CYCLES uart_rd=%0d uart_wr=%0d def=%0d bus_err=%0d ifu_offtarget=%0d",
                 uart_rd, uart_wr, def_sel, bus_err, ifu_bad);

        if (pass) begin
            $display("[TB] AHB_RW_MONITOR: PASS (%s; thresholds imem_rd>=%0d dmem_rd>=%0d dmem_wr>=%0d bus_err==0 def==0)",
                     reason, N_IMEM_RD, N_DMEM_RD, N_DMEM_WR);
        end else begin
            fail_count = 0;
            if (imem_rd < N_IMEM_RD) begin
                $display("[TB]   FAIL reason: imem_rd=%0d < %0d", imem_rd, N_IMEM_RD);
                fail_count++;
            end
            if (dmem_rd < N_DMEM_RD) begin
                $display("[TB]   FAIL reason: dmem_rd=%0d < %0d", dmem_rd, N_DMEM_RD);
                fail_count++;
            end
            if (dmem_wr < N_DMEM_WR) begin
                $display("[TB]   FAIL reason: dmem_wr=%0d < %0d", dmem_wr, N_DMEM_WR);
                fail_count++;
            end
            if (bus_err != 0) begin
                $display("[TB]   FAIL reason: bus_err=%0d (HRESP asserted)", bus_err);
                fail_count++;
            end
            if (def_sel != 0) begin
                $display("[TB]   FAIL reason: %0d transfer(s) hit the default ERROR slave", def_sel);
                fail_count++;
            end
            $display("[TB] AHB_RW_MONITOR: FAIL (%s, %0d condition(s))", reason, fail_count);
        end
    endtask

    // ------------------------------------------------------------ counting
    // Sampled in the active region of posedge clk: the values presented for
    // this edge are the ones the fabric's slaves latch at this edge.
    always @(posedge clk) begin
        if (!rst_n) begin
            imem_rd  <= 0; imem_wr <= 0;
            dmem_rd  <= 0; dmem_wr <= 0;
            uart_rd  <= 0; uart_wr <= 0;
            def_sel  <= 0; bus_err <= 0;
            ifu_bad  <= 0; cycles  <= 0;
            stop_d   <= 1'b0;
        end else if (!reported) begin
            stop_d <= stop;

            // ---- bus errors are per-cycle, independent of address phase ----
            if (ic_hresp || lsu_hresp) begin
                bus_err <= bus_err + 1;
                $display("[TB] %0t AHB_BUS_ERROR: ic_hresp=%0b lsu_hresp=%0b addr=ic:0x%08h lsu:0x%08h",
                         $time, ic_hresp, lsu_hresp, ic_haddr, lsu_haddr);
            end

            // ---- IFU: address phase accepted ----
            if (ic_htrans != HTRANS_IDLE && ic_hready) begin
                cycles <= cycles + 1;
                if (is_imem(ic_haddr)) begin
                    imem_rd <= imem_rd + 1;       // IFU never writes
                    if (ic_hwrite) $display("[TB] %0t IFU write to IMEM?! addr=0x%08h", $time, ic_haddr);
                end else begin
                    ifu_bad <= ifu_bad + 1;
                    $display("[TB] %0t IFU fetch off-target: addr=0x%08h (expected IMEM 0x0000_0000)",
                             $time, ic_haddr);
                end
            end

            // ---- LSU: address phase accepted ----
            if (lsu_htrans != HTRANS_IDLE && lsu_hready) begin
                cycles <= cycles + 1;
                if (is_imem(lsu_haddr)) begin
                    if (lsu_hwrite) imem_wr <= imem_wr + 1;   // canary: expected 0
                    else            imem_rd <= imem_rd + 1;   // .data LMA read during copy
                end else if (is_dmem(lsu_haddr)) begin
                    if (lsu_hwrite) dmem_wr <= dmem_wr + 1;
                    else            dmem_rd <= dmem_rd + 1;
                end else if (is_uart(lsu_haddr)) begin
                    if (lsu_hwrite) uart_wr <= uart_wr + 1;
                    else            uart_rd <= uart_rd + 1;
                end else begin
                    def_sel <= def_sel + 1;
                    $display("[TB] %0t DEFAULT slave claimed: lsu addr=0x%08h hwrite=%0b",
                             $time, lsu_haddr, lsu_hwrite);
                end
            end

            // ---- completion: the mailbox trigger byte has been written ----
            if (stop && !stop_d) begin
                reported = 1'b1;                 // blocking: halts further counting
                report("mailbox reached");
            end
        end
    end

    // ------------------------------------------------------------- watchdog
    // Runs ahead of tb_veer_p2_soc's own #2000000 timeout so the cycle
    // summary is always in the log, pass or fail.
    initial begin
        #(WATCHDOG_NS);
        if (!reported) begin
            reported = 1'b1;
            report("watchdog timeout");
        end
    end

endmodule
