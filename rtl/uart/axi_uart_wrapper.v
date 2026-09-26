`timescale 1ns / 1ps
`default_nettype none

// ============================================================================
// Project: RISC-V Network Telemetry SoC
// Module : axi_uart_wrapper
// Desc   : AXI 2x8 interconnect + UART slave on M02 (0x1000_0000/4KB).
//          Mirrors rtl/aes/axi_aes_wrapper.v (which puts AES on M06) so UART
//          integrates to the AXI fabric exactly like AES.
//
//          S00 is the external AXI master (testbench / CPU path). S01 is tied
//          off. M02 routes to uart_axi_slave; M00/M01/M03-M07 response inputs
//          are tied to 0 (unmapped for this isolated test; TB only targets
//          M02, same as the AES wrapper only targets M06).
//
//          UART pins: uart_tx_o (to SoC top), uart_rx_i (tie 1'b1 for TX-only),
//          uart_irq (IP read interrupt; expected 0 in TX-only use).
// ============================================================================

module axi_uart_wrapper #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter STRB_WIDTH = DATA_WIDTH/8,
    parameter ID_WIDTH   = 8,
    parameter AWUSER_WIDTH = 1,
    parameter WUSER_WIDTH  = 1,
    parameter BUSER_WIDTH  = 1,
    parameter ARUSER_WIDTH = 1,
    parameter RUSER_WIDTH  = 1
)(
    input wire clk,
    input wire rst,

    // ============================================================
    // AXI S00 input
    // ============================================================

    input wire [ID_WIDTH-1:0] s00_axi_awid,
    input wire [ADDR_WIDTH-1:0] s00_axi_awaddr,
    input wire [7:0] s00_axi_awlen,
    input wire [2:0] s00_axi_awsize,
    input wire [1:0] s00_axi_awburst,
    input wire s00_axi_awlock,
    input wire [3:0] s00_axi_awcache,
    input wire [2:0] s00_axi_awprot,
    input wire [3:0] s00_axi_awqos,
    input wire [AWUSER_WIDTH-1:0] s00_axi_awuser,
    input wire s00_axi_awvalid,
    output wire s00_axi_awready,

    input wire [DATA_WIDTH-1:0] s00_axi_wdata,
    input wire [STRB_WIDTH-1:0] s00_axi_wstrb,
    input wire s00_axi_wlast,
    input wire [WUSER_WIDTH-1:0] s00_axi_wuser,
    input wire s00_axi_wvalid,
    output wire s00_axi_wready,

    output wire [ID_WIDTH-1:0] s00_axi_bid,
    output wire [1:0] s00_axi_bresp,
    output wire [BUSER_WIDTH-1:0] s00_axi_buser,
    output wire s00_axi_bvalid,
    input wire s00_axi_bready,

    input wire [ID_WIDTH-1:0] s00_axi_arid,
    input wire [ADDR_WIDTH-1:0] s00_axi_araddr,
    input wire [7:0] s00_axi_arlen,
    input wire [2:0] s00_axi_arsize,
    input wire [1:0] s00_axi_arburst,
    input wire s00_axi_arlock,
    input wire [3:0] s00_axi_arcache,
    input wire [2:0] s00_axi_arprot,
    input wire [3:0] s00_axi_arqos,
    input wire [ARUSER_WIDTH-1:0] s00_axi_aruser,
    input wire s00_axi_arvalid,
    output wire s00_axi_arready,

    output wire [ID_WIDTH-1:0] s00_axi_rid,
    output wire [DATA_WIDTH-1:0] s00_axi_rdata,
    output wire [1:0] s00_axi_rresp,
    output wire s00_axi_rlast,
    output wire [RUSER_WIDTH-1:0] s00_axi_ruser,
    output wire s00_axi_rvalid,
    input wire s00_axi_rready,

    output wire uart_tx_o,
    input  wire uart_rx_i,
    output wire uart_irq
);

    // ============================================================
    // Internal M02 AXI connection
    // ============================================================

    wire [ID_WIDTH-1:0] m02_axi_awid;
    wire [ADDR_WIDTH-1:0] m02_axi_awaddr;
    wire [7:0] m02_axi_awlen;
    wire [2:0] m02_axi_awsize;
    wire [1:0] m02_axi_awburst;
    wire m02_axi_awlock;
    wire [3:0] m02_axi_awcache;
    wire [2:0] m02_axi_awprot;
    wire [3:0] m02_axi_awqos;
    wire [3:0] m02_axi_awregion;
    wire [AWUSER_WIDTH-1:0] m02_axi_awuser;
    wire m02_axi_awvalid;
    wire m02_axi_awready;

    wire [DATA_WIDTH-1:0] m02_axi_wdata;
    wire [STRB_WIDTH-1:0] m02_axi_wstrb;
    wire m02_axi_wlast;
    wire [WUSER_WIDTH-1:0] m02_axi_wuser;
    wire m02_axi_wvalid;
    wire m02_axi_wready;

    wire [ID_WIDTH-1:0] m02_axi_bid;
    wire [1:0] m02_axi_bresp;
    wire [BUSER_WIDTH-1:0] m02_axi_buser;
    wire m02_axi_bvalid;
    wire m02_axi_bready;

    wire [ID_WIDTH-1:0] m02_axi_arid;
    wire [ADDR_WIDTH-1:0] m02_axi_araddr;
    wire [7:0] m02_axi_arlen;
    wire [2:0] m02_axi_arsize;
    wire [1:0] m02_axi_arburst;
    wire m02_axi_arlock;
    wire [3:0] m02_axi_arcache;
    wire [2:0] m02_axi_arprot;
    wire [3:0] m02_axi_arqos;
    wire [3:0] m02_axi_arregion;
    wire [ARUSER_WIDTH-1:0] m02_axi_aruser;
    wire m02_axi_arvalid;
    wire m02_axi_arready;

    wire [ID_WIDTH-1:0] m02_axi_rid;
    wire [DATA_WIDTH-1:0] m02_axi_rdata;
    wire [1:0] m02_axi_rresp;
    wire m02_axi_rlast;
    wire [RUSER_WIDTH-1:0] m02_axi_ruser;
    wire m02_axi_rvalid;
    wire m02_axi_rready;

    // ============================================================
    // AXI 2x8 interconnect
    // ============================================================

    axi_interconnect_wrap_2x8 #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .STRB_WIDTH(STRB_WIDTH),
        .ID_WIDTH(ID_WIDTH),

        .M02_BASE_ADDR(32'h1000_0000),
        .M02_ADDR_WIDTH({1{32'd12}})
    ) interconnect_inst (

        .clk(clk),
        .rst(rst),

        // --------------------------------------------------------
        // S00
        // --------------------------------------------------------

        .s00_axi_awid(s00_axi_awid),
        .s00_axi_awaddr(s00_axi_awaddr),
        .s00_axi_awlen(s00_axi_awlen),
        .s00_axi_awsize(s00_axi_awsize),
        .s00_axi_awburst(s00_axi_awburst),
        .s00_axi_awlock(s00_axi_awlock),
        .s00_axi_awcache(s00_axi_awcache),
        .s00_axi_awprot(s00_axi_awprot),
        .s00_axi_awqos(s00_axi_awqos),
        .s00_axi_awuser(s00_axi_awuser),
        .s00_axi_awvalid(s00_axi_awvalid),
        .s00_axi_awready(s00_axi_awready),

        .s00_axi_wdata(s00_axi_wdata),
        .s00_axi_wstrb(s00_axi_wstrb),
        .s00_axi_wlast(s00_axi_wlast),
        .s00_axi_wuser(s00_axi_wuser),
        .s00_axi_wvalid(s00_axi_wvalid),
        .s00_axi_wready(s00_axi_wready),

        .s00_axi_bid(s00_axi_bid),
        .s00_axi_bresp(s00_axi_bresp),
        .s00_axi_buser(s00_axi_buser),
        .s00_axi_bvalid(s00_axi_bvalid),
        .s00_axi_bready(s00_axi_bready),

        .s00_axi_arid(s00_axi_arid),
        .s00_axi_araddr(s00_axi_araddr),
        .s00_axi_arlen(s00_axi_arlen),
        .s00_axi_arsize(s00_axi_arsize),
        .s00_axi_arburst(s00_axi_arburst),
        .s00_axi_arlock(s00_axi_arlock),
        .s00_axi_arcache(s00_axi_arcache),
        .s00_axi_arprot(s00_axi_arprot),
        .s00_axi_arqos(s00_axi_arqos),
        .s00_axi_aruser(s00_axi_aruser),
        .s00_axi_arvalid(s00_axi_arvalid),
        .s00_axi_arready(s00_axi_arready),

        .s00_axi_rid(s00_axi_rid),
        .s00_axi_rdata(s00_axi_rdata),
        .s00_axi_rresp(s00_axi_rresp),
        .s00_axi_rlast(s00_axi_rlast),
        .s00_axi_ruser(s00_axi_ruser),
        .s00_axi_rvalid(s00_axi_rvalid),
        .s00_axi_rready(s00_axi_rready),

        // --------------------------------------------------------
        // S01 unused
        // --------------------------------------------------------

        .s01_axi_awid(0),
        .s01_axi_awaddr(0),
        .s01_axi_awlen(0),
        .s01_axi_awsize(0),
        .s01_axi_awburst(0),
        .s01_axi_awlock(0),
        .s01_axi_awcache(0),
        .s01_axi_awprot(0),
        .s01_axi_awqos(0),
        .s01_axi_awuser(0),
        .s01_axi_awvalid(0),

        .s01_axi_wdata(0),
        .s01_axi_wstrb(0),
        .s01_axi_wlast(0),
        .s01_axi_wuser(0),
        .s01_axi_wvalid(0),

        .s01_axi_bready(0),

        .s01_axi_arid(0),
        .s01_axi_araddr(0),
        .s01_axi_arlen(0),
        .s01_axi_arsize(0),
        .s01_axi_arburst(0),
        .s01_axi_arlock(0),
        .s01_axi_arcache(0),
        .s01_axi_arprot(0),
        .s01_axi_arqos(0),
        .s01_axi_aruser(0),
        .s01_axi_arvalid(0),
        .s01_axi_rready(0),

        // --------------------------------------------------------
        // M00/M01 unused response inputs
        // --------------------------------------------------------

        .m00_axi_awready(0),
        .m00_axi_wready(0),
        .m00_axi_bid(0),
        .m00_axi_bresp(0),
        .m00_axi_buser(0),
        .m00_axi_bvalid(0),
        .m00_axi_arready(0),
        .m00_axi_rid(0),
        .m00_axi_rdata(0),
        .m00_axi_rresp(0),
        .m00_axi_rlast(0),
        .m00_axi_ruser(0),
        .m00_axi_rvalid(0),

        .m01_axi_awready(0),
        .m01_axi_wready(0),
        .m01_axi_bid(0),
        .m01_axi_bresp(0),
        .m01_axi_buser(0),
        .m01_axi_bvalid(0),
        .m01_axi_arready(0),
        .m01_axi_rid(0),
        .m01_axi_rdata(0),
        .m01_axi_rresp(0),
        .m01_axi_rlast(0),
        .m01_axi_ruser(0),
        .m01_axi_rvalid(0),

        // --------------------------------------------------------
        // M02 -> UART
        // --------------------------------------------------------

        .m02_axi_awid(m02_axi_awid),
        .m02_axi_awaddr(m02_axi_awaddr),
        .m02_axi_awlen(m02_axi_awlen),
        .m02_axi_awsize(m02_axi_awsize),
        .m02_axi_awburst(m02_axi_awburst),
        .m02_axi_awlock(m02_axi_awlock),
        .m02_axi_awcache(m02_axi_awcache),
        .m02_axi_awprot(m02_axi_awprot),
        .m02_axi_awqos(m02_axi_awqos),
        .m02_axi_awregion(m02_axi_awregion),
        .m02_axi_awuser(m02_axi_awuser),
        .m02_axi_awvalid(m02_axi_awvalid),
        .m02_axi_awready(m02_axi_awready),

        .m02_axi_wdata(m02_axi_wdata),
        .m02_axi_wstrb(m02_axi_wstrb),
        .m02_axi_wlast(m02_axi_wlast),
        .m02_axi_wuser(m02_axi_wuser),
        .m02_axi_wvalid(m02_axi_wvalid),
        .m02_axi_wready(m02_axi_wready),

        .m02_axi_bid(m02_axi_bid),
        .m02_axi_bresp(m02_axi_bresp),
        .m02_axi_buser(m02_axi_buser),
        .m02_axi_bvalid(m02_axi_bvalid),
        .m02_axi_bready(m02_axi_bready),

        .m02_axi_arid(m02_axi_arid),
        .m02_axi_araddr(m02_axi_araddr),
        .m02_axi_arlen(m02_axi_arlen),
        .m02_axi_arsize(m02_axi_arsize),
        .m02_axi_arburst(m02_axi_arburst),
        .m02_axi_arlock(m02_axi_arlock),
        .m02_axi_arcache(m02_axi_arcache),
        .m02_axi_arprot(m02_axi_arprot),
        .m02_axi_arqos(m02_axi_arqos),
        .m02_axi_arregion(m02_axi_arregion),
        .m02_axi_aruser(m02_axi_aruser),
        .m02_axi_arvalid(m02_axi_arvalid),
        .m02_axi_arready(m02_axi_arready),

        .m02_axi_rid(m02_axi_rid),
        .m02_axi_rdata(m02_axi_rdata),
        .m02_axi_rresp(m02_axi_rresp),
        .m02_axi_rlast(m02_axi_rlast),
        .m02_axi_ruser(m02_axi_ruser),
        .m02_axi_rvalid(m02_axi_rvalid),
        .m02_axi_rready(m02_axi_rready),

        // --------------------------------------------------------
        // M03-M07 unused response inputs
        // --------------------------------------------------------

        .m03_axi_awready(0),
        .m03_axi_wready(0),
        .m03_axi_bid(0),
        .m03_axi_bresp(0),
        .m03_axi_buser(0),
        .m03_axi_bvalid(0),
        .m03_axi_arready(0),
        .m03_axi_rid(0),
        .m03_axi_rdata(0),
        .m03_axi_rresp(0),
        .m03_axi_rlast(0),
        .m03_axi_ruser(0),
        .m03_axi_rvalid(0),

        .m04_axi_awready(0),
        .m04_axi_wready(0),
        .m04_axi_bid(0),
        .m04_axi_bresp(0),
        .m04_axi_buser(0),
        .m04_axi_bvalid(0),
        .m04_axi_arready(0),
        .m04_axi_rid(0),
        .m04_axi_rdata(0),
        .m04_axi_rresp(0),
        .m04_axi_rlast(0),
        .m04_axi_ruser(0),
        .m04_axi_rvalid(0),

        .m05_axi_awready(0),
        .m05_axi_wready(0),
        .m05_axi_bid(0),
        .m05_axi_bresp(0),
        .m05_axi_buser(0),
        .m05_axi_bvalid(0),
        .m05_axi_arready(0),
        .m05_axi_rid(0),
        .m05_axi_rdata(0),
        .m05_axi_rresp(0),
        .m05_axi_rlast(0),
        .m05_axi_ruser(0),
        .m05_axi_rvalid(0),

        .m06_axi_awready(0),
        .m06_axi_wready(0),
        .m06_axi_bid(0),
        .m06_axi_bresp(0),
        .m06_axi_buser(0),
        .m06_axi_bvalid(0),
        .m06_axi_arready(0),
        .m06_axi_rid(0),
        .m06_axi_rdata(0),
        .m06_axi_rresp(0),
        .m06_axi_rlast(0),
        .m06_axi_ruser(0),
        .m06_axi_rvalid(0),

        .m07_axi_awready(0),
        .m07_axi_wready(0),
        .m07_axi_bid(0),
        .m07_axi_bresp(0),
        .m07_axi_buser(0),
        .m07_axi_bvalid(0),
        .m07_axi_arready(0),
        .m07_axi_rid(0),
        .m07_axi_rdata(0),
        .m07_axi_rresp(0),
        .m07_axi_rlast(0),
        .m07_axi_ruser(0),
        .m07_axi_rvalid(0)
    );

    // ============================================================
    // UART AXI slave
    // ============================================================

    uart_axi_slave #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .STRB_WIDTH(STRB_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    ) uart_inst (
        .clk(clk),
        .rst(rst),

        .s_axi_awid(m02_axi_awid),
        .s_axi_awaddr(m02_axi_awaddr),
        .s_axi_awlen(m02_axi_awlen),
        .s_axi_awsize(m02_axi_awsize),
        .s_axi_awburst(m02_axi_awburst),
        .s_axi_awlock(m02_axi_awlock),
        .s_axi_awcache(m02_axi_awcache),
        .s_axi_awprot(m02_axi_awprot),
        .s_axi_awqos(m02_axi_awqos),
        .s_axi_awuser(m02_axi_awuser),
        .s_axi_awvalid(m02_axi_awvalid),
        .s_axi_awready(m02_axi_awready),

        .s_axi_wdata(m02_axi_wdata),
        .s_axi_wstrb(m02_axi_wstrb),
        .s_axi_wlast(m02_axi_wlast),
        .s_axi_wuser(m02_axi_wuser),
        .s_axi_wvalid(m02_axi_wvalid),
        .s_axi_wready(m02_axi_wready),

        .s_axi_bid(m02_axi_bid),
        .s_axi_bresp(m02_axi_bresp),
        .s_axi_buser(m02_axi_buser),
        .s_axi_bvalid(m02_axi_bvalid),
        .s_axi_bready(m02_axi_bready),

        .s_axi_arid(m02_axi_arid),
        .s_axi_araddr(m02_axi_araddr),
        .s_axi_arlen(m02_axi_arlen),
        .s_axi_arsize(m02_axi_arsize),
        .s_axi_arburst(m02_axi_arburst),
        .s_axi_arlock(m02_axi_arlock),
        .s_axi_arcache(m02_axi_arcache),
        .s_axi_arprot(m02_axi_arprot),
        .s_axi_arqos(m02_axi_arqos),
        .s_axi_aruser(m02_axi_aruser),
        .s_axi_arvalid(m02_axi_arvalid),
        .s_axi_arready(m02_axi_arready),

        .s_axi_rid(m02_axi_rid),
        .s_axi_rdata(m02_axi_rdata),
        .s_axi_rresp(m02_axi_rresp),
        .s_axi_rlast(m02_axi_rlast),
        .s_axi_ruser(m02_axi_ruser),
        .s_axi_rvalid(m02_axi_rvalid),
        .s_axi_rready(m02_axi_rready),

        .uart_tx_o(uart_tx_o),
        .uart_rx_i(uart_rx_i),
        .uart_irq(uart_irq)
    );

endmodule

`default_nettype wire
