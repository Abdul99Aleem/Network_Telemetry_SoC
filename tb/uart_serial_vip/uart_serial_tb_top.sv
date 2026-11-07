// =============================================================================
// VIP: uart_serial_tb_top
// File: uart_serial_tb_top.sv
//
// Description:
//   Top-level UVM testbench module for the uart_serial VIP.
//   Instantiates:
//     - 100 MHz clock generator (10 ns period)
//     - uart_serial_if interface
//     - soc_top DUT
//     - Loopback multiplexer (for unit driver/monitor testing)
//     - AHB-Lite LSU bus stimulus generator (for end-to-end SoC UART TX tests)
//     - Sets virtual interface in uvm_config_db and executes run_test()
// =============================================================================
`timescale 1ns/1ps

module uart_serial_tb_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import uart_serial_pkg::*;

    // -------------------------------------------------------------------------
    // 100 MHz Clock Generator (10 ns period)
    // -------------------------------------------------------------------------
    logic clk;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // VIP Interface Instantiation
    // -------------------------------------------------------------------------
    uart_serial_if vif (.clk(clk));

    // -------------------------------------------------------------------------
    // AHB-Lite LSU Wires for Driving soc_top
    // -------------------------------------------------------------------------
    logic [31:0] lsu_haddr;
    logic [2:0]  lsu_hburst;
    logic        lsu_hmastlock;
    logic [3:0]  lsu_hprot;
    logic [2:0]  lsu_hsize;
    logic [1:0]  lsu_htrans;
    logic        lsu_hwrite;
    logic [63:0] lsu_hwdata;
    wire  [63:0] lsu_hrdata;
    wire         lsu_hready;
    wire         lsu_hresp;

    // -------------------------------------------------------------------------
    // IFU AHB-Lite Wires (Tied to IDLE)
    // -------------------------------------------------------------------------
    wire [31:0] ifu_haddr     = 32'h0;
    wire [2:0]  ifu_hburst    = 3'b000;
    wire        ifu_hmastlock = 1'b0;
    wire [3:0]  ifu_hprot     = 4'b0011;
    wire [2:0]  ifu_hsize     = 3'b010;
    wire [1:0]  ifu_htrans    = 2'b00;  // IDLE
    wire        ifu_hwrite    = 1'b0;
    wire [63:0] ifu_hrdata;
    wire        ifu_hready;
    wire        ifu_hresp;

    // -------------------------------------------------------------------------
    // DUT Ports
    // -------------------------------------------------------------------------
    wire dut_uart_tx;
    wire dut_uart_irq;
    wire dut_aes_irq;

    soc_top #(
        .IMEM_HEX(""),
        .DMEM_HEX("")
    ) u_dut (
        .clk          (clk),
        .reset_n      (vif.reset_n),

        // IFU port (idle)
        .ifu_haddr    (ifu_haddr),
        .ifu_hburst   (ifu_hburst),
        .ifu_hmastlock(ifu_hmastlock),
        .ifu_hprot    (ifu_hprot),
        .ifu_hsize    (ifu_hsize),
        .ifu_htrans   (ifu_htrans),
        .ifu_hwrite   (ifu_hwrite),
        .ifu_hrdata   (ifu_hrdata),
        .ifu_hready   (ifu_hready),
        .ifu_hresp    (ifu_hresp),

        // LSU port (driven by TB stimulus)
        .lsu_haddr    (lsu_haddr),
        .lsu_hburst   (lsu_hburst),
        .lsu_hmastlock(lsu_hmastlock),
        .lsu_hprot    (lsu_hprot),
        .lsu_hsize    (lsu_hsize),
        .lsu_htrans   (lsu_htrans),
        .lsu_hwrite   (lsu_hwrite),
        .lsu_hwdata   (lsu_hwdata),
        .lsu_hrdata   (lsu_hrdata),
        .lsu_hready   (lsu_hready),
        .lsu_hresp    (lsu_hresp),

        // UART & Interrupt ports
        .uart_tx_o    (dut_uart_tx),
        .uart_irq_o   (dut_uart_irq),
        .aes_irq_o    (dut_aes_irq)
    );

    // -------------------------------------------------------------------------
    // Loopback / SoC Selection Logic
    // -------------------------------------------------------------------------
    bit is_loopback = 0;
    initial begin
        if ($test$plusargs("loopback")) is_loopback = 1;
    end

    // Connect monitored signals to VIP interface
    assign vif.uart_tx_o  = is_loopback ? vif.uart_rx_i : dut_uart_tx;
    assign vif.uart_irq_o = is_loopback ? 1'b0          : dut_uart_irq;

    // -------------------------------------------------------------------------
    // AHB-Lite Master Stimulus Helper for SoC Integration
    // -------------------------------------------------------------------------
    task automatic ahb_write_lsu(input [31:0] addr, input [63:0] data);
        @(posedge clk);
        while (!lsu_hready) @(posedge clk);
        lsu_haddr     <= addr;
        lsu_htrans    <= 2'b10; // NONSEQ
        lsu_hwrite    <= 1'b1;  // WRITE
        lsu_hsize     <= 3'b010; // 32-bit WORD
        lsu_hburst    <= 3'b000;
        lsu_hprot     <= 4'b0011;
        lsu_hmastlock <= 1'b0;

        @(posedge clk);
        while (!lsu_hready) @(posedge clk);
        lsu_htrans    <= 2'b00; // IDLE
        lsu_hwdata    <= data;

        @(posedge clk);
        while (!lsu_hready) @(posedge clk);
    endtask

    // SoC Stimulus Process (runs when not in loopback mode)
    initial begin
        // Initialize LSU bus
        lsu_haddr     = '0;
        lsu_htrans    = 2'b00;
        lsu_hwrite    = 1'b0;
        lsu_hsize     = 3'b010;
        lsu_hburst    = 3'b000;
        lsu_hprot     = 4'b0011;
        lsu_hmastlock = 1'b0;
        lsu_hwdata    = '0;

        // Wait for reset release
        wait (vif.reset_n === 1'b1);
        repeat (20) @(posedge clk);

        if (!is_loopback) begin
            $display("[%0t ns] [TB_TOP] Starting AHB-Lite write of 'UART\\n' to UART THR (0x1000_0000)...", $time);

            // Write 'U' (0x55)
            ahb_write_lsu(32'h1000_0000, 64'h0000_0000_0000_0055);
            // Delay for UART serialization (~869 cycles per byte at 115200 baud)
            repeat (1000) @(posedge clk);

            // Write 'A' (0x41)
            ahb_write_lsu(32'h1000_0000, 64'h0000_0000_0000_0041);
            repeat (1000) @(posedge clk);

            // Write 'R' (0x52)
            ahb_write_lsu(32'h1000_0000, 64'h0000_0000_0000_0052);
            repeat (1000) @(posedge clk);

            // Write 'T' (0x54)
            ahb_write_lsu(32'h1000_0000, 64'h0000_0000_0000_0054);
            repeat (1000) @(posedge clk);

            // Write '\n' (0x0A)
            ahb_write_lsu(32'h1000_0000, 64'h0000_0000_0000_000A);
            repeat (1000) @(posedge clk);

            $display("[%0t ns] [TB_TOP] Completed AHB-Lite writes to UART THR.", $time);
        end
    end

    // -------------------------------------------------------------------------
    // Verdi FSDB Waveform Dumping (enabled via +wave or +fsdb plusarg)
    // -------------------------------------------------------------------------
    initial begin
        if ($test$plusargs("wave") || $test$plusargs("fsdb")) begin
            $fsdbDumpfile("uart_uvm.fsdb");
            $fsdbDumpvars(0, uart_serial_tb_top);
            $fsdbDumpMDA();
            $display("[TB_TOP] FSDB: enabled (+wave) -> uart_uvm.fsdb");
        end else begin
            $display("[TB_TOP] FSDB: disabled (pass +wave to enable)");
        end
    end

    // -------------------------------------------------------------------------
    // Set virtual interface in config_db and launch test
    // -------------------------------------------------------------------------
    initial begin
        uvm_config_db #(virtual uart_serial_if)::set(null, "uvm_test_top", "vif", vif);
        run_test("uart_soc_tx_test");
    end

endmodule : uart_serial_tb_top
