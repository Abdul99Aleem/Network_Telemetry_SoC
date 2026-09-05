// ============================================================================
// Project: RISC-V Network Telemetry SoC — Phase 2
// Module : ahb_interconnect
// Desc   : 2-master (IFU, LSU) x 3-slave (IMEM, DMEM, DEFAULT-ERROR)
//          AHB-Lite fabric. LSU has fixed priority over IFU (v3 arch §11.8).
//          64-bit data to match the VeeR AHB interface (v3 §2.3).
//
// Address map (v3 §9, Phase-2 scope = memories; all other regions decode
// to the DEFAULT error slave and are added as slaves in later phases):
//   IMEM  0x0000_0000 - 0x0000_7FFF  (32 KB)
//   DMEM  0x0001_0000 - 0x0001_7FFF  (32 KB)
//
// Protocol notes:
// - Address-phase arbitration (combinational on HTRANS), data-phase
//   ownership follows the registered address-phase owner.
// - The idle (non-owner) master sees HREADY=1/HRESP=0/HRDATA=0.
// - Exactly one HSEL is asserted per NONSEQ/SEQ transfer.
// ============================================================================
`timescale 1ns / 1ps
`default_nettype none

module ahb_interconnect #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64
) (
    input  wire                     hclk,
    input  wire                     hreset_n,

    // ---- IFU master (fetch-only: no HWDATA) ----
    input  wire [ADDR_WIDTH-1:0]    ifu_haddr,
    input  wire [2:0]               ifu_hburst,
    input  wire                     ifu_hmastlock,
    input  wire [3:0]               ifu_hprot,
    input  wire [2:0]               ifu_hsize,
    input  wire [1:0]               ifu_htrans,
    input  wire                     ifu_hwrite,
    output wire [DATA_WIDTH-1:0]    ifu_hrdata,
    output wire                     ifu_hready,
    output wire                     ifu_hresp,

    // ---- LSU master ----
    input  wire [ADDR_WIDTH-1:0]    lsu_haddr,
    input  wire [2:0]               lsu_hburst,
    input  wire                     lsu_hmastlock,
    input  wire [3:0]               lsu_hprot,
    input  wire [2:0]               lsu_hsize,
    input  wire [1:0]               lsu_htrans,
    input  wire                     lsu_hwrite,
    input  wire [DATA_WIDTH-1:0]    lsu_hwdata,
    output wire [DATA_WIDTH-1:0]    lsu_hrdata,
    output wire                     lsu_hready,
    output wire                     lsu_hresp,

    // ---- IMEM slave ----
    output wire                     imem_hsel,
    output wire [ADDR_WIDTH-1:0]    imem_haddr,
    output wire [2:0]               imem_hburst,
    output wire                     imem_hmastlock,
    output wire [3:0]               imem_hprot,
    output wire [2:0]               imem_hsize,
    output wire [1:0]               imem_htrans,
    output wire                     imem_hwrite,
    output wire [DATA_WIDTH-1:0]    imem_hwdata,
    input  wire [DATA_WIDTH-1:0]    imem_hrdata,
    input  wire                     imem_hreadyout,
    input  wire                     imem_hresp,

    // ---- DMEM slave ----
    output wire                     dmem_hsel,
    output wire [ADDR_WIDTH-1:0]    dmem_haddr,
    output wire [2:0]               dmem_hburst,
    output wire                     dmem_hmastlock,
    output wire [3:0]               dmem_hprot,
    output wire [2:0]               dmem_hsize,
    output wire [1:0]               dmem_htrans,
    output wire                     dmem_hwrite,
    output wire [DATA_WIDTH-1:0]    dmem_hwdata,
    input  wire [DATA_WIDTH-1:0]    dmem_hrdata,
    input  wire                     dmem_hreadyout,
    input  wire                     dmem_hresp,

    // ---- DEFAULT (error) slave ----
    output wire                     def_hsel,
    output wire [ADDR_WIDTH-1:0]    def_haddr,
    output wire [2:0]               def_hburst,
    output wire                     def_hmastlock,
    output wire [3:0]               def_hprot,
    output wire [2:0]               def_hsize,
    output wire [1:0]               def_htrans,
    output wire                     def_hwrite,
    output wire [DATA_WIDTH-1:0]    def_hwdata,
    input  wire [DATA_WIDTH-1:0]    def_hrdata,
    input  wire                     def_hreadyout,
    input  wire                     def_hresp
);

    localparam [1:0] HTRANS_IDLE   = 2'b00;
    localparam [1:0] HTRANS_NONSEQ = 2'b10;
    localparam [1:0] HTRANS_SEQ    = 2'b11;

    // ----------------------------------------------------------------
    // Address-phase arbitration: LSU wins over IFU (fixed priority).
    // addr_is_lsu = 1 -> LSU owns the address phase.
    // ----------------------------------------------------------------
    wire lsu_active = (lsu_htrans != HTRANS_IDLE);
    wire addr_is_lsu = lsu_active;

    wire [ADDR_WIDTH-1:0] mux_haddr     = addr_is_lsu ? lsu_haddr     : ifu_haddr;
    wire [2:0]            mux_hburst    = addr_is_lsu ? lsu_hburst    : ifu_hburst;
    wire                  mux_hmastlock = addr_is_lsu ? lsu_hmastlock : ifu_hmastlock;
    wire [3:0]            mux_hprot     = addr_is_lsu ? lsu_hprot     : ifu_hprot;
    wire [2:0]            mux_hsize     = addr_is_lsu ? lsu_hsize     : ifu_hsize;
    wire [1:0]            mux_htrans    = addr_is_lsu ? lsu_htrans    : ifu_htrans;
    wire                  mux_hwrite    = addr_is_lsu ? lsu_hwrite    : ifu_hwrite;
    wire [DATA_WIDTH-1:0] mux_hwdata    = lsu_hwdata; // IFU never writes

    wire                  mux_active    = (mux_htrans != HTRANS_IDLE);

    // ----------------------------------------------------------------
    // Address decode (Phase-2: IMEM + DMEM; everything else -> default).
    // ----------------------------------------------------------------
    wire imem_match = (mux_haddr[31:15] == 17'h0000); // 0x0000_0000/32K
    wire dmem_match = (mux_haddr[31:15] == 17'h0002); // 0x0001_0000/32K

    wire sel_imem = mux_active && imem_match;
    wire sel_dmem = mux_active && !imem_match && dmem_match;
    wire sel_def  = mux_active && !imem_match && !dmem_match;

    assign imem_hsel = sel_imem;
    assign dmem_hsel = sel_dmem;
    assign def_hsel  = sel_def;

    assign imem_haddr = mux_haddr; assign imem_hburst = mux_hburst;
    assign imem_hmastlock = mux_hmastlock; assign imem_hprot = mux_hprot;
    assign imem_hsize = mux_hsize; assign imem_htrans = mux_htrans;
    assign imem_hwrite = mux_hwrite; assign imem_hwdata = mux_hwdata;

    assign dmem_haddr = mux_haddr; assign dmem_hburst = mux_hburst;
    assign dmem_hmastlock = mux_hmastlock; assign dmem_hprot = mux_hprot;
    assign dmem_hsize = mux_hsize; assign dmem_htrans = mux_htrans;
    assign dmem_hwrite = mux_hwrite; assign dmem_hwdata = mux_hwdata;

    assign def_haddr = mux_haddr; assign def_hburst = mux_hburst;
    assign def_hmastlock = mux_hmastlock; assign def_hprot = mux_hprot;
    assign def_hsize = mux_hsize; assign def_htrans = mux_htrans;
    assign def_hwrite = mux_hwrite; assign def_hwdata = mux_hwdata;

    // ----------------------------------------------------------------
    // Data-phase ownership: registered address-phase owner + slave.
    // Sampled when the data phase completes (slave HREADYOUT = 1).
    // Encoding: 2'b00 none/idle, 2'b01 IMEM, 2'b10 DMEM, 2'b11 DEFAULT.
    // ----------------------------------------------------------------
    reg        data_is_lsu;
    reg [1:0]  data_sel;

    wire [1:0] addr_sel = sel_imem ? 2'b01 : (sel_dmem ? 2'b10 : (sel_def ? 2'b11 : 2'b00));

    wire [DATA_WIDTH-1:0] mux_hrdata;
    wire                  mux_hreadyout;
    wire                  mux_hresp;

    assign mux_hrdata    = (data_sel == 2'b01) ? imem_hrdata :
                           (data_sel == 2'b10) ? dmem_hrdata : def_hrdata;
    assign mux_hreadyout = (data_sel == 2'b01) ? imem_hreadyout :
                           (data_sel == 2'b10) ? dmem_hreadyout : def_hreadyout;
    assign mux_hresp     = (data_sel == 2'b01) ? imem_hresp :
                           (data_sel == 2'b10) ? dmem_hresp : def_hresp;

    always @(posedge hclk or negedge hreset_n) begin
        if (!hreset_n) begin
            data_is_lsu <= 1'b0;
            data_sel    <= 2'b00;
        end else if (mux_hreadyout) begin
            // Previous data phase completed: adopt current address phase.
            data_is_lsu <= addr_is_lsu;
            data_sel    <= addr_sel;
        end
    end

    // ----------------------------------------------------------------
    // Response steering to masters.
    // ----------------------------------------------------------------
    assign ifu_hrdata = (!data_is_lsu) ? mux_hrdata : {DATA_WIDTH{1'b0}};
    assign ifu_hready = (!data_is_lsu) ? mux_hreadyout : 1'b1;
    assign ifu_hresp  = (!data_is_lsu) ? mux_hresp : 1'b0;

    assign lsu_hrdata = (data_is_lsu) ? mux_hrdata : {DATA_WIDTH{1'b0}};
    assign lsu_hready = (data_is_lsu) ? mux_hreadyout : 1'b1;
    assign lsu_hresp  = (data_is_lsu) ? mux_hresp : 1'b0;

endmodule

`default_nettype wire
