// =============================================================================
// VIP: veer_ahb_tb_top
// File: veer_ahb_tb_top.sv
//
// Description:
//   Top-level testbench module.  Instantiates:
//     - Clock generator (10 ns period = 100 MHz, matching the SoC design)
//     - veer_ahb_if (the external AHB-Lite interface to soc_top)
//     - soc_top DUT (connected through the interface)
//     - Sets virtual interface in uvm_config_db and calls run_test()
//
//   IMEM_HEX / DMEM_HEX parameters can be overridden via plusargs:
//     +IMEM_HEX=sw/build/imem.mem
//     +DMEM_HEX=sw/build/dmem.mem
// =============================================================================
`timescale 1ns/1ps

module veer_ahb_tb_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import veer_ahb_pkg::*;

    // -------------------------------------------------------------------------
    // Clock generator — 10 ns period (100 MHz)
    // -------------------------------------------------------------------------
    logic hclk;
    initial hclk = 1'b0;
    always #5 hclk = ~hclk;

    // -------------------------------------------------------------------------
    // Interface instantiation
    // -------------------------------------------------------------------------
    veer_ahb_if vif (.hclk(hclk));

    // -------------------------------------------------------------------------
    // DUT — soc_top
    // -------------------------------------------------------------------------
    parameter string IMEM_HEX = "";
    parameter string DMEM_HEX = "";

    soc_top #(
        .IMEM_HEX (IMEM_HEX),
        .DMEM_HEX (DMEM_HEX)
    ) u_dut (
        .clk          (hclk),
        .reset_n      (vif.reset_n),

        // IFU port
        .ifu_haddr    (vif.ifu_haddr),
        .ifu_hburst   (vif.ifu_hburst),
        .ifu_hmastlock(vif.ifu_hmastlock),
        .ifu_hprot    (vif.ifu_hprot),
        .ifu_hsize    (vif.ifu_hsize),
        .ifu_htrans   (vif.ifu_htrans),
        .ifu_hwrite   (vif.ifu_hwrite),
        .ifu_hrdata   (vif.ifu_hrdata),
        .ifu_hready   (vif.ifu_hready),
        .ifu_hresp    (vif.ifu_hresp),

        // LSU port
        .lsu_haddr    (vif.lsu_haddr),
        .lsu_hburst   (vif.lsu_hburst),
        .lsu_hmastlock(vif.lsu_hmastlock),
        .lsu_hprot    (vif.lsu_hprot),
        .lsu_hsize    (vif.lsu_hsize),
        .lsu_htrans   (vif.lsu_htrans),
        .lsu_hwrite   (vif.lsu_hwrite),
        .lsu_hwdata   (vif.lsu_hwdata),
        .lsu_hrdata   (vif.lsu_hrdata),
        .lsu_hready   (vif.lsu_hready),
        .lsu_hresp    (vif.lsu_hresp),

        // Peripheral outputs — observed by peripheral VIPs / monitors
        .uart_tx_o    (),    // leave open here; connect in combined tb if needed
        .uart_irq_o   (),
        .aes_irq_o    ()
    );

    // -------------------------------------------------------------------------
    // Publish virtual interface into config_db before run_test()
    // -------------------------------------------------------------------------
    initial begin
        uvm_config_db #(virtual veer_ahb_if)::set(null, "uvm_test_top", "vif", vif);
        run_test("veer_ahb_test");
    end

endmodule : veer_ahb_tb_top
