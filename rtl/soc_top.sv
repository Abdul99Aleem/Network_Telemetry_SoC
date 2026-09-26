// ============================================================================
// Project: RISC-V Network Telemetry SoC
// Module : soc_top
// Desc   : SoC top: AHB-Lite fabric + IMEM + DMEM + UART + default slave.
//          VeeR IFU/LSU masters attach directly. The UART sits at
//          0x1000_0000/4KB (v3 §9, §10.1) behind ahb_to_axi_bridge,
//          which converts the 64-bit AHB-Lite peripheral port into the
//          32-bit full-AXI4 port that uart_axi_slave expects.
//          Remaining peripheral regions (Timer/GPIO/NET/AES/CRC) decode to
//          the default ERROR slave (v3 §9 map reserved).
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
    output wire        lsu_hresp,

    // ---- UART pins (TX-only per v3 §10.1) ----
    output wire        uart_tx_o,
    output wire        uart_irq_o
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

    wire uart_hsel, uart_hwrite, uart_hreadyout, uart_hresp;
    wire [31:0] uart_haddr; wire [2:0] uart_hburst, uart_hsize;
    wire uart_hmastlock; wire [3:0] uart_hprot; wire [1:0] uart_htrans;
    wire [63:0] uart_hwdata, uart_hrdata;

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
        .def_hreadyout(def_hreadyout), .def_hresp(def_hresp),
        .uart_hsel(uart_hsel), .uart_haddr(uart_haddr),
        .uart_hburst(uart_hburst), .uart_hmastlock(uart_hmastlock),
        .uart_hprot(uart_hprot), .uart_hsize(uart_hsize),
        .uart_htrans(uart_htrans), .uart_hwrite(uart_hwrite),
        .uart_hwdata(uart_hwdata),
        .uart_hrdata(uart_hrdata),
        .uart_hreadyout(uart_hreadyout), .uart_hresp(uart_hresp)
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

    // ---- AHB-Lite -> AXI4 bridge + UART (0x1000_0000 / 4KB) ----
    localparam UART_ID_WIDTH = 8;

    wire [UART_ID_WIDTH-1:0] awid, bid, arid, rid;
    wire [31:0] awaddr, wdata, araddr, rdata;
    wire [7:0]  awlen, arlen;
    wire [2:0]  awsize, arsize;
    wire [1:0]  awburst, arburst, bresp, rresp;
    wire        awlock, wlast, arlock, rlast;
    wire [3:0]  awcache, wstrb, arcache;
    wire [2:0]  awprot, arprot;
    wire [3:0]  awqos, arqos;
    wire        awuser, wuser, buser, aruser, ruser;
    wire        awvalid, awready, wvalid, wready, bvalid, bready;
    wire        arvalid, arready, rvalid, rready;

    ahb_to_axi_bridge #(.ID_WIDTH(UART_ID_WIDTH)) u_ahb2axi (
        .hclk(clk), .hreset_n(reset_n),
        .hsel(uart_hsel), .haddr(uart_haddr), .hburst(uart_hburst),
        .hmastlock(uart_hmastlock), .hprot(uart_hprot),
        .hsize(uart_hsize), .htrans(uart_htrans), .hwrite(uart_hwrite),
        .hwdata(uart_hwdata), .hrdata(uart_hrdata),
        .hreadyout(uart_hreadyout), .hresp(uart_hresp),

        .m_axi_awid(awid), .m_axi_awaddr(awaddr), .m_axi_awlen(awlen),
        .m_axi_awsize(awsize), .m_axi_awburst(awburst),
        .m_axi_awlock(awlock), .m_axi_awcache(awcache),
        .m_axi_awprot(awprot), .m_axi_awqos(awqos), .m_axi_awuser(awuser),
        .m_axi_awvalid(awvalid), .m_axi_awready(awready),

        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
        .m_axi_wuser(wuser), .m_axi_wvalid(wvalid), .m_axi_wready(wready),

        .m_axi_bid(bid), .m_axi_bresp(bresp), .m_axi_bvalid(bvalid),
        .m_axi_bready(bready),

        .m_axi_arid(arid), .m_axi_araddr(araddr), .m_axi_arlen(arlen),
        .m_axi_arsize(arsize), .m_axi_arburst(arburst),
        .m_axi_arlock(arlock), .m_axi_arcache(arcache),
        .m_axi_arprot(arprot), .m_axi_arqos(arqos), .m_axi_aruser(aruser),
        .m_axi_arvalid(arvalid), .m_axi_arready(arready),

        .m_axi_rid(rid), .m_axi_rdata(rdata), .m_axi_rresp(rresp),
        .m_axi_rlast(rlast), .m_axi_ruser(ruser),
        .m_axi_rvalid(rvalid), .m_axi_rready(rready)
    );

    uart_axi_slave #(.ID_WIDTH(UART_ID_WIDTH)) u_uart (
        .clk(clk), .rst(~reset_n),

        .s_axi_awid(awid), .s_axi_awaddr(awaddr), .s_axi_awlen(awlen),
        .s_axi_awsize(awsize), .s_axi_awburst(awburst),
        .s_axi_awlock(awlock), .s_axi_awcache(awcache),
        .s_axi_awprot(awprot), .s_axi_awqos(awqos), .s_axi_awuser(awuser),
        .s_axi_awvalid(awvalid), .s_axi_awready(awready),

        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wlast(wlast),
        .s_axi_wuser(wuser), .s_axi_wvalid(wvalid), .s_axi_wready(wready),

        .s_axi_bid(bid), .s_axi_bresp(bresp), .s_axi_buser(buser),
        .s_axi_bvalid(bvalid), .s_axi_bready(bready),

        .s_axi_arid(arid), .s_axi_araddr(araddr), .s_axi_arlen(arlen),
        .s_axi_arsize(arsize), .s_axi_arburst(arburst),
        .s_axi_arlock(arlock), .s_axi_arcache(arcache),
        .s_axi_arprot(arprot), .s_axi_arqos(arqos), .s_axi_aruser(aruser),
        .s_axi_arvalid(arvalid), .s_axi_arready(arready),

        .s_axi_rid(rid), .s_axi_rdata(rdata), .s_axi_rresp(rresp),
        .s_axi_rlast(rlast), .s_axi_ruser(ruser),
        .s_axi_rvalid(rvalid), .s_axi_rready(rready),

        .uart_tx_o(uart_tx_o), .uart_rx_i(1'b1), .uart_irq(uart_irq_o)
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
