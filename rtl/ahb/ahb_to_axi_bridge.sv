// ============================================================================
// Project: RISC-V Network Telemetry SoC
// Module : ahb_to_axi_bridge
// Desc   : AHB-Lite slave -> AXI4 master bridge, single outstanding,
//          single-beat (AWLEN/ARLEN = 0). Connects one AHB peripheral
//          region of the project fabric to one AXI4 IP.
//
//          Used by soc_top to attach the UART AXI slave (0x1000_0000/4KB)
//          to the 64-bit AHB-Lite fabric. Architecture doc v3 §2.4 defines
//          the peripheral-side AHB subset; §11.10 requires 32-bit
//          word-aligned register accesses.
//
// Width    : AHB data is 64 bits (v3 §2.3), AXI data is 32 bits. The bridge
//            selects the addressed 32-bit lane of the 64-bit AHB bus:
//              HADDR[2]==0 -> hwdata[31:0] / hrdata[31:0]
//              HADDR[2]==1 -> hwdata[63:32] / hrdata[63:32]
//            WSTRB is derived from HSIZE + HADDR[2:0] byte lanes, exactly
//            like ahb_sram, so sb/sh/sw all map onto the right AXI strobes.
//
//            HSIZE==3 (64-bit beat) is split into TWO back-to-back 32-bit
//            AXI accesses at HADDR and HADDR+4, then merged:
//              read  -> hrdata = {word(HADDR+4), word(HADDR)}
//              write -> WDATA[31:0]/WSTRB[3:0] first, then [63:32]/[7:4]
//            VeeR EL2 marks MMIO regions as non-side-effect in MRAC by
//            default, so its load unit issues a full 64-bit read aligned
//            down to the 8-byte boundary and selects the sub-word itself.
//            The bridge must therefore always be able to return BOTH
//            32-bit halves of a 64-bit AHB read.
//
// Protocol  :
//  - Address phase is accepted whenever HREADYOUT is high (S_IDLE, or the
//    second cycle of an AHB ERROR response).
//  - HREADYOUT is held low for the whole AXI transaction, so HWDATA stays
//    stable for the duration of the AHB data phase (AHB-Lite requirement).
//  - HWDATA is latched in the FIRST data-phase cycle (S_LAUNCH), which is
//    the first cycle in which the master guarantees it valid.
//  - A non-OKAY AXI BRESP/RRESP becomes a standard two-cycle AHB ERROR
//    response (S_ERR1 HREADY=0/HRESP=1, then S_ERR2 HREADY=1/HRESP=1).
//    Note: with the current slaves (uart_axi_slave, ahb devices) this path
//    is unreachable -- both always answer OKAY -- but it is implemented so
//    the bridge never silently swallows an error.
//  - HBURST is ignored: each AHB beat is translated to its own single-beat
//    AXI transaction, which is what a SEQ/NONSEQ peripheral access needs.
// ============================================================================
`timescale 1ns / 1ps
`default_nettype none

module ahb_to_axi_bridge #(
    parameter ID_WIDTH = 8
) (
    input  wire                 hclk,
    input  wire                 hreset_n,

    // ---- AHB-Lite slave port (64-bit) ----
    input  wire                 hsel,
    input  wire [31:0]          haddr,
    input  wire [2:0]           hburst,
    input  wire                 hmastlock,
    input  wire [3:0]           hprot,
    input  wire [2:0]           hsize,
    input  wire [1:0]           htrans,
    input  wire                 hwrite,
    input  wire [63:0]          hwdata,
    output wire [63:0]          hrdata,
    output wire                 hreadyout,
    output wire                 hresp,

    // ---- AXI4 master port (32-bit, single beat) ----
    output wire [ID_WIDTH-1:0]  m_axi_awid,
    output wire [31:0]          m_axi_awaddr,
    output wire [7:0]           m_axi_awlen,
    output wire [2:0]           m_axi_awsize,
    output wire [1:0]           m_axi_awburst,
    output wire                 m_axi_awlock,
    output wire [3:0]           m_axi_awcache,
    output wire [2:0]           m_axi_awprot,
    output wire [3:0]           m_axi_awqos,
    output wire                 m_axi_awuser,
    output wire                 m_axi_awvalid,
    input  wire                 m_axi_awready,

    output wire [31:0]          m_axi_wdata,
    output wire [3:0]           m_axi_wstrb,
    output wire                 m_axi_wlast,
    output wire                 m_axi_wuser,
    output wire                 m_axi_wvalid,
    input  wire                 m_axi_wready,

    input  wire [ID_WIDTH-1:0]  m_axi_bid,
    input  wire [1:0]           m_axi_bresp,
    input  wire                 m_axi_bvalid,
    output wire                 m_axi_bready,

    output wire [ID_WIDTH-1:0]  m_axi_arid,
    output wire [31:0]          m_axi_araddr,
    output wire [7:0]           m_axi_arlen,
    output wire [2:0]           m_axi_arsize,
    output wire [1:0]           m_axi_arburst,
    output wire                 m_axi_arlock,
    output wire [3:0]           m_axi_arcache,
    output wire [2:0]           m_axi_arprot,
    output wire [3:0]           m_axi_arqos,
    output wire                 m_axi_aruser,
    output wire                 m_axi_arvalid,
    input  wire                 m_axi_arready,

    input  wire [ID_WIDTH-1:0]  m_axi_rid,
    input  wire [31:0]          m_axi_rdata,
    input  wire [1:0]           m_axi_rresp,
    input  wire                 m_axi_rlast,
    input  wire                 m_axi_ruser,
    input  wire                 m_axi_rvalid,
    output wire                 m_axi_rready
);

    localparam [1:0] HTRANS_IDLE = 2'b00;

    localparam [2:0] S_IDLE   = 3'd0; // HREADYOUT=1, accept address phase
    localparam [2:0] S_LAUNCH = 3'd1; // first data-phase cycle, latch HWDATA
    localparam [2:0] S_WR     = 3'd2; // AW/W handshakes
    localparam [2:0] S_WR_B   = 3'd3; // wait BVALID
    localparam [2:0] S_RD     = 3'd4; // AR handshake
    localparam [2:0] S_RD_R   = 3'd5; // wait RVALID
    localparam [2:0] S_ERR1   = 3'd6; // AHB ERROR, HREADY=0
    localparam [2:0] S_ERR2   = 3'd7; // AHB ERROR, HREADY=1

    reg [2:0]       state;
    reg [31:0]      a_q;
    reg [2:0]       size_q;
    reg             write_q;
    reg [31:0]      wdata_q;
    reg [3:0]       wstrb_q;
    reg [31:0]      wdata_alt_q;
    reg [3:0]       wstrb_alt_q;
    reg [31:0]      rdata_q;
    reg [31:0]      rdata_hi_q;
    reg             rd_second_q;
    reg             wr_second_q;
    reg             awvalid_q, wvalid_q, bready_q, arvalid_q, rready_q;

    // A 64-bit AHB beat is carried out as two 32-bit AXI accesses.
    wire        wide64   = (size_q == 3'b011);
    wire [31:0] aw_addr  = a_q + (wr_second_q ? 32'd4 : 32'd0);
    wire [31:0] ar_addr  = a_q + (rd_second_q ? 32'd4 : 32'd0);
    // AXI SIZE never exceeds 2 (32-bit) on the 32-bit AXI port.
    wire [2:0]  axi_size = wide64 ? 3'b010 : size_q;

    // ---------------------------------------------------------------
    // AHB byte lanes for a 64-bit bus (same encoding as ahb_sram).
    // ---------------------------------------------------------------
    function automatic [7:0] ahb_lanes;
        input [2:0] size;
        input [2:0] addr_lo;
        begin
            case (size)
                3'b000: ahb_lanes = 8'h01 << addr_lo;                 // byte
                3'b001: ahb_lanes = 8'h03 << {addr_lo[2:1], 1'b0};    // half
                3'b010: ahb_lanes = 8'h0F << {addr_lo[2], 3'b000};    // word
                default: ahb_lanes = 8'hFF;                           // 64b+
            endcase
        end
    endfunction

    wire [7:0] lanes_now = ahb_lanes(size_q, a_q[2:0]);
    wire       lane_hi   = a_q[2]; // which 32-bit half of the 64-bit bus

    // ---------------------------------------------------------------
    // AHB response
    // ---------------------------------------------------------------
    assign hreadyout = (state == S_IDLE) || (state == S_ERR2);
    assign hresp     = (state == S_ERR1) || (state == S_ERR2);

    // 32-bit AXI read data is placed back in the lane it came from.
    // A 64-bit beat returns both halves, low word first.
    assign hrdata = wide64    ? {rdata_hi_q, rdata_q}
                  : lane_hi   ? {rdata_q, 32'h0000_0000}
                              : {32'h0000_0000, rdata_q};

    wire accept = hreadyout && hsel && (htrans != HTRANS_IDLE);

    // ---------------------------------------------------------------
    // AXI master outputs
    // ---------------------------------------------------------------
    assign m_axi_awid    = {ID_WIDTH{1'b0}};
    assign m_axi_awaddr  = aw_addr;
    assign m_axi_awlen   = 8'h00;
    assign m_axi_awsize  = axi_size;
    assign m_axi_awburst = 2'b01; // INCR
    assign m_axi_awlock  = 1'b0;
    assign m_axi_awcache = 4'b0000;
    assign m_axi_awprot  = 3'b000;
    assign m_axi_awqos   = 4'b0000;
    assign m_axi_awuser  = 1'b0;
    assign m_axi_awvalid = awvalid_q;

    assign m_axi_wdata   = wdata_q;
    assign m_axi_wstrb   = wstrb_q;
    assign m_axi_wlast   = 1'b1;
    assign m_axi_wuser   = 1'b0;
    assign m_axi_wvalid  = wvalid_q;

    assign m_axi_bready  = bready_q;

    assign m_axi_arid    = {ID_WIDTH{1'b0}};
    assign m_axi_araddr  = ar_addr;
    assign m_axi_arlen   = 8'h00;
    assign m_axi_arsize  = axi_size;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arlock  = 1'b0;
    assign m_axi_arcache = 4'b0000;
    assign m_axi_arprot  = 3'b000;
    assign m_axi_arqos   = 4'b0000;
    assign m_axi_aruser  = 1'b0;
    assign m_axi_arvalid = arvalid_q;

    assign m_axi_rready  = rready_q;

    // ---------------------------------------------------------------
    // FSM
    // ---------------------------------------------------------------
    always @(posedge hclk or negedge hreset_n) begin
        if (!hreset_n) begin
            state     <= S_IDLE;
            a_q       <= 32'h0;
            size_q    <= 3'b000;
            write_q   <= 1'b0;
            wdata_q   <= 32'h0;
            wstrb_q   <= 4'h0;
            wdata_alt_q <= 32'h0;
            wstrb_alt_q <= 4'h0;
            rdata_q   <= 32'h0;
            rdata_hi_q <= 32'h0;
            rd_second_q <= 1'b0;
            wr_second_q <= 1'b0;
            awvalid_q <= 1'b0;
            wvalid_q  <= 1'b0;
            bready_q  <= 1'b0;
            arvalid_q <= 1'b0;
            rready_q  <= 1'b0;
        end else begin
            case (state)
                // ----------------------------------------------------
                S_IDLE, S_ERR2: begin
                    if (accept) begin
                        a_q     <= haddr;
                        size_q  <= hsize;
                        write_q <= hwrite;
                        state   <= S_LAUNCH;
                    end
                end

                // ----------------------------------------------------
                // First data-phase cycle: HWDATA is valid here for the
                // first time, so latch the addressed 32-bit slice.
                // lanes_now already picks the right half of the 64-bit
                // bus, so WSTRB is simply that half.
                S_LAUNCH: begin
                    wdata_q     <= lane_hi ? hwdata[63:32] : hwdata[31:0];
                    wstrb_q     <= lane_hi ? lanes_now[7:4] : lanes_now[3:0];
                    wdata_alt_q <= lane_hi ? hwdata[31:0]  : hwdata[63:32];
                    wstrb_alt_q <= lane_hi ? lanes_now[3:0] : lanes_now[7:4];
                    rdata_q     <= 32'h0;
                    rdata_hi_q  <= 32'h0;
                    if (write_q) begin
                        wr_second_q <= 1'b0;
                        awvalid_q <= 1'b1;
                        wvalid_q  <= 1'b1;
                        state     <= S_WR;
                    end else begin
                        rd_second_q <= 1'b0;
                        arvalid_q <= 1'b1;
                        state     <= S_RD;
                    end
                end

                // ----------------------------------------------------
                S_WR: begin
                    if (awvalid_q && m_axi_awready) awvalid_q <= 1'b0;
                    if (wvalid_q  && m_axi_wready)  wvalid_q  <= 1'b0;
                    if ((awvalid_q == 1'b0 || m_axi_awready) &&
                        (wvalid_q  == 1'b0 || m_axi_wready)) begin
                        bready_q <= 1'b1;
                        state    <= S_WR_B;
                    end
                end

                S_WR_B: begin
                    if (bready_q && m_axi_bvalid) begin
                        bready_q <= 1'b0;
                        if (m_axi_bresp != 2'b00) begin
                            state <= S_ERR1;
                        end else if (wide64 && !wr_second_q) begin
                            // second half of a 64-bit AHB write
                            wr_second_q <= 1'b1;
                            wdata_q     <= wdata_alt_q;
                            wstrb_q     <= wstrb_alt_q;
                            awvalid_q   <= 1'b1;
                            wvalid_q    <= 1'b1;
                            state       <= S_WR;
                        end else begin
                            state <= S_IDLE;
                        end
                    end
                end

                // ----------------------------------------------------
                S_RD: begin
                    if (arvalid_q && m_axi_arready) begin
                        arvalid_q <= 1'b0;
                        rready_q  <= 1'b1;
                        state     <= S_RD_R;
                    end
                end

                S_RD_R: begin
                    if (rready_q && m_axi_rvalid) begin
                        rready_q <= 1'b0;
                        if (m_axi_rresp != 2'b00) begin
                            state <= S_ERR1;
                        end else if (wide64 && !rd_second_q) begin
                            // first half of a 64-bit AHB read captured
                            rdata_q     <= m_axi_rdata;
                            rd_second_q <= 1'b1;
                            arvalid_q   <= 1'b1;
                            state       <= S_RD;
                        end else begin
                            if (wide64) rdata_hi_q <= m_axi_rdata;
                            else        rdata_q    <= m_axi_rdata;
                            state <= S_IDLE;
                        end
                    end
                end

                // ----------------------------------------------------
                S_ERR1: state <= S_ERR2;

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
