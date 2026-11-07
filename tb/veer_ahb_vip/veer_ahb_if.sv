// =============================================================================
// VIP: veer_ahb_if
// Project: RISC-V Network Telemetry SoC
// File: veer_ahb_if.sv
//
// Description:
//   SystemVerilog interface for the two AHB-Lite master ports that cross the
//   soc_top boundary: the VeeR IFU (fetch) port and the VeeR LSU (load/store)
//   port.  These are the ONLY AHB signals visible outside soc_top — every
//   other AHB wire (fabric↔IMEM, fabric↔DMEM, fabric↔bridge, etc.) is an
//   internal net inside soc_top and is NOT represented here.
//
//   Clocking block direction is from the testbench master's perspective:
//     output = TB drives → DUT input
//     input  = TB samples ← DUT output
//
// Source: soc_top.sv port list (v3 §2.3, §9, §11.8)
//   IFU: read-only (hwrite is always 0 from VeeR's fetch unit).
//        64-bit hrdata — the fabric returns a full 64-bit word per fetch.
//   LSU: read/write, 64-bit data width.
//        hwdata is valid in the cycle after the address phase (AHB pipelining).
// =============================================================================
`timescale 1ns/1ps

interface veer_ahb_if (input logic hclk);

    // -------------------------------------------------------------------------
    // IFU (Instruction Fetch Unit) master port
    // -------------------------------------------------------------------------
    logic [31:0] ifu_haddr;
    logic [2:0]  ifu_hburst;
    logic        ifu_hmastlock;
    logic [3:0]  ifu_hprot;
    logic [2:0]  ifu_hsize;
    logic [1:0]  ifu_htrans;
    logic        ifu_hwrite;      // always 0 from IFU; included for protocol completeness
    logic [63:0] ifu_hrdata;      // soc_top → TB (64-bit, from fabric)
    logic        ifu_hready;      // soc_top → TB
    logic        ifu_hresp;       // soc_top → TB

    // -------------------------------------------------------------------------
    // LSU (Load/Store Unit) master port
    // -------------------------------------------------------------------------
    logic [31:0] lsu_haddr;
    logic [2:0]  lsu_hburst;
    logic        lsu_hmastlock;
    logic [3:0]  lsu_hprot;
    logic [2:0]  lsu_hsize;
    logic [1:0]  lsu_htrans;
    logic        lsu_hwrite;
    logic [63:0] lsu_hwdata;      // TB → soc_top
    logic [63:0] lsu_hrdata;      // soc_top → TB (64-bit)
    logic        lsu_hready;      // soc_top → TB
    logic        lsu_hresp;       // soc_top → TB

    // -------------------------------------------------------------------------
    // Reset (active-low, matching soc_top reset_n)
    // -------------------------------------------------------------------------
    logic reset_n;

    // -------------------------------------------------------------------------
    // Clocking block for driver — synchronises driver to posedge hclk.
    //   output: TB drives these onto the DUT inputs
    //   input:  TB samples these from the DUT outputs
    // -------------------------------------------------------------------------
    clocking cb @(posedge hclk);
        // IFU address/control (TB drives)
        output ifu_haddr, ifu_hburst, ifu_hmastlock, ifu_hprot,
               ifu_hsize, ifu_htrans, ifu_hwrite;
        // IFU response (TB samples)
        input  ifu_hrdata, ifu_hready, ifu_hresp;

        // LSU address/control/data (TB drives)
        output lsu_haddr, lsu_hburst, lsu_hmastlock, lsu_hprot,
               lsu_hsize, lsu_htrans, lsu_hwrite, lsu_hwdata;
        // LSU response (TB samples)
        input  lsu_hrdata, lsu_hready, lsu_hresp;
    endclocking

    // -------------------------------------------------------------------------
    // Clocking block for monitor — all signals are inputs so monitor can sample
    // without illegal clocking-output sampling errors.
    // -------------------------------------------------------------------------
    clocking mon_cb @(posedge hclk);
        input ifu_haddr, ifu_hburst, ifu_hmastlock, ifu_hprot,
              ifu_hsize, ifu_htrans, ifu_hwrite;
        input ifu_hrdata, ifu_hready, ifu_hresp;
        input lsu_haddr, lsu_hburst, lsu_hmastlock, lsu_hprot,
              lsu_hsize, lsu_htrans, lsu_hwrite, lsu_hwdata;
        input lsu_hrdata, lsu_hready, lsu_hresp;
    endclocking

    // -------------------------------------------------------------------------
    // Modports
    // -------------------------------------------------------------------------
    modport master_mp (clocking cb, input hclk, output reset_n);
    modport passive_mp (clocking mon_cb, input hclk, reset_n,
                        input ifu_haddr, ifu_hburst, ifu_hmastlock, ifu_hprot,
                              ifu_hsize, ifu_htrans, ifu_hwrite,
                              ifu_hrdata, ifu_hready, ifu_hresp,
                              lsu_haddr, lsu_hburst, lsu_hmastlock, lsu_hprot,
                              lsu_hsize, lsu_htrans, lsu_hwrite, lsu_hwdata,
                              lsu_hrdata, lsu_hready, lsu_hresp);

endinterface : veer_ahb_if
