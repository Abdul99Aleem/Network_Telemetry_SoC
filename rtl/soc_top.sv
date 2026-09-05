// ============================================================================
// Project: RISC-V Network Telemetry SoC — Phase 2
// Module : soc_top
// Desc   : Phase-2 SoC top: AHB-Lite fabric + IMEM + DMEM + default slave.
//          VeeR IFU/LSU masters attach directly. Peripheral regions
//          (UART/Timer/GPIO/NET/AES/CRC) decode to the default ERROR slave
//          until their slaves land in later phases (v3 §9 map reserved).
//
//          IMEM_HEX preloads IMEM via $readmemh ("" = zero-filled).
//          DMEM is zero-filled (CPU/stack Init in software).
// ============================================================================
`timescale 1ns / 1ps
`default_nettype none

module soc_top #(
    parameter IMEM_HEX = "",
    parameter DMEM_HEX = ""
) (
    input  wire        clk,
    input  wire        reset_n,

    // ---- VeeR IFU master ----
    input  wire [31:0] ifu_haddr,
    input  wire [2:0]  ifu_hburst,
    input  wire        ifu_hmastlock,
    input  wire [3:0]  ifu_hprot,
    input  wire [2:0]  ifu_hsize,
    input  wire [1:0]  ifu_htrans,
    input  wire        ifu_hwrite,
    output wire [63:0] ifu_hrdata,
    output wire        ifu_hready,
    output wire        ifu_hresp,

    // ---- VeeR LSU master ----
    input  wire [31:0] lsu_haddr,
    input  wire [2:0]  lsu_hburst,
    input  wire        lsu_hmastlock,
    input  wire [3:0]  lsu_hprot,
    input  wire [2:0]  lsu_hsize,
    input  wire [1:0]  lsu_htrans,
    input  wire        lsu_hwrite,
    input  wire [63:0] lsu_hwdata,
    output wire [63:0] lsu_hrdata,
    output wire        lsu_hready,
    output wire        lsu_hresp
);

    // ---- fabric -> slave wires ----
    wire imem_hsel, imem_hwrite, imem_hreadyout, imem_hresp;
    wire [31:0] imem_haddr; wire [2:0] imem_hburst, imem_hsize;
    wire imem_hmastlock; wire [3:0] imem_hprot; wire [1:0] imem_htrans;
    wire [63:0] imem_hwdata, imem_hrdata;

    wire dmem_hsel, dmem_hwrite, dmem_hreadyout, dmem_hresp;
    wire [31:0] dmem_haddr; wire [2:0] dmem_hburst, dmem_hsize;
    wire dmem_hmastlock; wire [3:0] dmem_hprot; wire [1:0] dmem_htrans;
    wire [63:0] dmem_hwdata, dmem_hrdata;

    wire def_hsel, def_hwrite, def_hreadyout, def_hresp;
    wire [31:0] def_haddr; wire [2:0] def_hburst, def_hsize;
    wire def_hmastlock; wire [3:0] def_hprot; wire [1:0] def_htrans;
    wire [63:0] def_hwdata, def_hrdata;

    ahb_interconnect u_fabric (
        .hclk(clk), .hreset_n(reset_n),
        .ifu_haddr(ifu_haddr), .ifu_hburst(ifu_hburst),
        .ifu_hmastlock(ifu_hmastlock), .ifu_hprot(ifu_hprot),
        .ifu_hsize(ifu_hsize), .ifu_htrans(ifu_htrans),
        .ifu_hwrite(ifu_hwrite),
        .ifu_hrdata(ifu_hrdata), .ifu_hready(ifu_hready), .ifu_hresp(ifu_hresp),
        .lsu_haddr(lsu_haddr), .lsu_hburst(lsu_hburst),
        .lsu_hmastlock(lsu_hmastlock), .lsu_hprot(lsu_hprot),
        .lsu_hsize(lsu_hsize), .lsu_htrans(lsu_htrans),
        .lsu_hwrite(lsu_hwrite), .lsu_hwdata(lsu_hwdata),
        .lsu_hrdata(lsu_hrdata), .lsu_hready(lsu_hready), .lsu_hresp(lsu_hresp),
        .imem_hsel(imem_hsel), .imem_haddr(imem_haddr),
        .imem_hburst(imem_hburst), .imem_hmastlock(imem_hmastlock),
        .imem_hprot(imem_hprot), .imem_hsize(imem_hsize),
        .imem_htrans(imem_htrans), .imem_hwrite(imem_hwrite),
        .imem_hwdata(imem_hwdata),
        .imem_hrdata(imem_hrdata),
        .imem_hreadyout(imem_hreadyout), .imem_hresp(imem_hresp),
        .dmem_hsel(dmem_hsel), .dmem_haddr(dmem_haddr),
        .dmem_hburst(dmem_hburst), .dmem_hmastlock(dmem_hmastlock),
        .dmem_hprot(dmem_hprot), .dmem_hsize(dmem_hsize),
        .dmem_htrans(dmem_htrans), .dmem_hwrite(dmem_hwrite),
        .dmem_hwdata(dmem_hwdata),
        .dmem_hrdata(dmem_hrdata),
        .dmem_hreadyout(dmem_hreadyout), .dmem_hresp(dmem_hresp),
        .def_hsel(def_hsel), .def_haddr(def_haddr),
        .def_hburst(def_hburst), .def_hmastlock(def_hmastlock),
        .def_hprot(def_hprot), .def_hsize(def_hsize),
        .def_htrans(def_htrans), .def_hwrite(def_hwrite),
        .def_hwdata(def_hwdata),
        .def_hrdata(def_hrdata),
        .def_hreadyout(def_hreadyout), .def_hresp(def_hresp)
    );

    // IMEM: 0x0000_0000 - 0x0000_7FFF (32 KB)
    ahb_sram #(
        .BASE_ADDR(32'h0000_0000), .SIZE_BYTES(32768), .HEX_FILE(IMEM_HEX)
    ) u_imem (
        .hclk(clk), .hreset_n(reset_n),
        .hsel(imem_hsel), .haddr(imem_haddr), .hburst(imem_hburst),
        .hmastlock(imem_hmastlock), .hprot(imem_hprot), .hsize(imem_hsize),
        .htrans(imem_htrans), .hwrite(imem_hwrite), .hwdata(imem_hwdata),
        .hrdata(imem_hrdata), .hreadyout(imem_hreadyout), .hresp(imem_hresp)
    );

    // DMEM: 0x0001_0000 - 0x0001_7FFF (32 KB)
    ahb_sram #(
        .BASE_ADDR(32'h0001_0000), .SIZE_BYTES(32768), .HEX_FILE(DMEM_HEX)
    ) u_dmem (
        .hclk(clk), .hreset_n(reset_n),
        .hsel(dmem_hsel), .haddr(dmem_haddr), .hburst(dmem_hburst),
        .hmastlock(dmem_hmastlock), .hprot(dmem_hprot), .hsize(dmem_hsize),
        .htrans(dmem_htrans), .hwrite(dmem_hwrite), .hwdata(dmem_hwdata),
        .hrdata(dmem_hrdata), .hreadyout(dmem_hreadyout), .hresp(dmem_hresp)
    );

    ahb_default_slave u_default (
        .hclk(clk), .hreset_n(reset_n),
        .hsel(def_hsel), .haddr(def_haddr), .hburst(def_hburst),
        .hmastlock(def_hmastlock), .hprot(def_hprot), .hsize(def_hsize),
        .htrans(def_htrans), .hwrite(def_hwrite), .hwdata(def_hwdata),
        .hrdata(def_hrdata), .hreadyout(def_hreadyout), .hresp(def_hresp)
    );

endmodule

`default_nettype wire
