`timescale 1ns / 1ps
`default_nettype none

// ============================================================================
// Project: RISC-V Network Telemetry SoC
// Module : uart_axi_slave
// Desc   : Full-AXI4 slave wrapper around the AXI4-Lite UART IP
//          (axi_uart_top). Mirrors rtl/aes/aes_axi_slave.v structure so the
//          UART can sit on M02 (0x1000_0000/4KB) of axi_interconnect_wrap_2x8
//          exactly like AES sits on M06.
//
//          Outer interface is full AXI4 (AWLEN/AWSIZE/AWBURST/... + WLAST,
//          BID/BRESP/BVALID, ARLEN/... + RID/RDATA/RRESP/RLAST) with 8-bit ID,
//          matching aes_axi_slave. Inner IP is AXI4-Lite (5-bit addr, 12-bit
//          ID, no burst/len). The wrapper absorbs burst fields (single-beat
//          only, like the AES wrapper) and translates:
//
//            outer AWID[7:0]  -> inner AWID[11:0] = {4'b0, outer}
//            outer AWADDR[4:0]-> inner AWADDR[4:0] (M02 window already decoded
//                               by the interconnect; low bits select regs)
//            outer WDATA/WSTRB-> inner WDATA/WSTRB (WSTRB passed through;
//                               IP ignores it, always consumes full word;
//                               THR uses low byte)
//            inner BID[11:0]  -> outer BID[7:0] = inner[7:0]
//            (same for AR/R path)
//
//          Clocks: fixed_clk_i = axi_aclk_i = clk (single-clock SoC).
//          Reset : axi_aresetn_i = ~rst (rst is active-high like AES).
//          UART  : uart_rx_i should be tied to 1'b1 for TX-only operation
//                  (architecture: UART TX-only, no UART interrupt).
//                  uart_irq is the IP read_interrupt_o (RX-data interrupt),
//                  expected 0 in TX-only use; exposed for debug/Verdi.
//
// Register map (offsets from UART_BASE = 0x1000_0000, word-aligned):
//
//   Offset  Access  Name   Description
//   0x00    R/W*    THR/   THR (WO, TX data low byte, DLAB=0) /
//                   RBR     RBR (RO, RX data low byte, DLAB=0)
//   0x04    R/W     IER     IRQ enable (bit0); write always ACKs.
//                           NOTE: reads of IER are NOT supported by the IP
//                           read FSM (it only serves RBR+LSR); the wrapper
//                           returns 0/OKAY directly for such offsets to
//                           avoid hanging the bus.
//   0x08    R/W     BAUD    Baud divisor (effective when DLAB=1). Write always
//                           ACKs. Reads bypassed to 0 (see above).
//   0x0C    R/W     LCR     Line control (bit7 DLAB, bit2 stop, bit3 parity
//                           en, bit4 parity mode). Write always ACKs. Reads
//                           bypassed to 0.
//   0x14    R       LSR     Line status: bit0 DATA_READY, bit5 THRE, bit6 TEMT.
//                           The only status read supported by the IP.
//
//   All other offsets: writes ACK with OKAY (IP default); reads return
//   0/OKAY directly from the wrapper (IP would hang, so we never forward).
//
//   Absolute addresses: 0x1000_0000 + offset (e.g. THR = 0x1000_0000,
//   LSR = 0x1000_0014).
// ============================================================================

module uart_axi_slave #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter STRB_WIDTH = DATA_WIDTH / 8,
    parameter ID_WIDTH   = 8
)(
    input  wire                     clk,
    input  wire                     rst,

    // ------------------------------------------------------------
    // AXI write address channel (full AXI, like aes_axi_slave)
    // ------------------------------------------------------------
    input  wire [ID_WIDTH-1:0]      s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire [7:0]               s_axi_awlen,
    input  wire [2:0]               s_axi_awsize,
    input  wire [1:0]               s_axi_awburst,
    input  wire                     s_axi_awlock,
    input  wire [3:0]               s_axi_awcache,
    input  wire [2:0]               s_axi_awprot,
    input  wire [3:0]               s_axi_awqos,
    input  wire                     s_axi_awuser,
    input  wire                     s_axi_awvalid,
    output wire                     s_axi_awready,

    // ------------------------------------------------------------
    // AXI write data channel
    // ------------------------------------------------------------
    input  wire [DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire [STRB_WIDTH-1:0]    s_axi_wstrb,
    input  wire                     s_axi_wlast,
    input  wire                     s_axi_wuser,
    input  wire                     s_axi_wvalid,
    output wire                     s_axi_wready,

    // ------------------------------------------------------------
    // AXI write response channel
    // ------------------------------------------------------------
    output wire [ID_WIDTH-1:0]      s_axi_bid,
    output wire [1:0]               s_axi_bresp,
    output wire                     s_axi_buser,
    output wire                     s_axi_bvalid,
    input  wire                     s_axi_bready,

    // ------------------------------------------------------------
    // AXI read address channel
    // ------------------------------------------------------------
    input  wire [ID_WIDTH-1:0]      s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire [7:0]               s_axi_arlen,
    input  wire [2:0]               s_axi_arsize,
    input  wire [1:0]               s_axi_arburst,
    input  wire                     s_axi_arlock,
    input  wire [3:0]               s_axi_arcache,
    input  wire [2:0]               s_axi_arprot,
    input  wire [3:0]               s_axi_arqos,
    input  wire                     s_axi_aruser,
    input  wire                     s_axi_arvalid,
    output wire                     s_axi_arready,

    // ------------------------------------------------------------
    // AXI read response channel
    // ------------------------------------------------------------
    output wire [ID_WIDTH-1:0]      s_axi_rid,
    output wire [DATA_WIDTH-1:0]    s_axi_rdata,
    output wire [1:0]               s_axi_rresp,
    output wire                     s_axi_rlast,
    output wire                     s_axi_ruser,
    output wire                     s_axi_rvalid,
    input  wire                     s_axi_rready,

    // ------------------------------------------------------------
    // UART pins
    // ------------------------------------------------------------
    output wire                     uart_tx_o,
    input  wire                     uart_rx_i,
    output wire                     uart_irq
);

    // ============================================================
    // Address map
    // ============================================================
    localparam [ADDR_WIDTH-1:0] UART_BASE = 32'h1000_0000;

    // Word offsets inside the 4KB window (low 5 bits select the IP reg).
    // IP decodes axi_addr[4:2]: 0=RBR/THR, 1=IER, 2=BAUD, 3=LCR, 5=LSR.
    localparam [4:0] OFF_THR_RBR = 5'h00; // 0x00
    localparam [4:0] OFF_IER     = 5'h04; // 0x04
    localparam [4:0] OFF_BAUD    = 5'h08; // 0x08
    localparam [4:0] OFF_LCR     = 5'h0C; // 0x0C
    localparam [4:0] OFF_LSR     = 5'h14; // 0x14

    // IP only serves RBR(0) and LSR(5) on the read path. All other read
    // offsets are completed locally with 0/OKAY so the bus never hangs.
    function automatic logic is_ip_read_offset(input [4:0] off);
        begin
            // off[4:2] == 0 (RBR/THR) or == 5 (LSR)
            is_ip_read_offset = (off[4:2] == 3'd0) || (off[4:2] == 3'd5);
        end
    endfunction

    // ============================================================
    // Outer AXI handshake state (same style as aes_axi_slave)
    // ============================================================
    reg                    aw_pending;
    reg [ID_WIDTH-1:0]     awid_reg;
    reg [ADDR_WIDTH-1:0]   awaddr_reg;

    reg                    w_pending;
    reg [DATA_WIDTH-1:0]   wdata_reg;
    reg [STRB_WIDTH-1:0]   wstrb_reg;

    reg                    bvalid_reg;
    reg [ID_WIDTH-1:0]     bid_reg;
    reg [1:0]              bresp_reg;

    reg                    rvalid_reg;
    reg [ID_WIDTH-1:0]     rid_reg;
    reg [DATA_WIDTH-1:0]   rdata_reg;
    reg [1:0]              rresp_reg;

    // Inner FSM activity flags (declared early: used by ready assigns).
    reg                    wr_active;
    reg                    rd_active;

    wire aw_handshake;
    wire w_handshake;

    assign s_axi_awready = !aw_pending && !bvalid_reg && !wr_active;
    assign s_axi_wready  = !w_pending  && !bvalid_reg && !wr_active;

    assign aw_handshake = s_axi_awvalid && s_axi_awready;
    assign w_handshake  = s_axi_wvalid  && s_axi_wready;

    assign s_axi_bvalid = bvalid_reg;
    assign s_axi_bid    = bid_reg;
    assign s_axi_bresp  = bresp_reg;
    assign s_axi_buser  = 1'b0;

    // Read addr ready: block new AR while a read response is pending or an
    // inner read transaction is active.
    assign s_axi_arready = !rvalid_reg && !rd_active;

    assign s_axi_rvalid = rvalid_reg;
    assign s_axi_rid    = rid_reg;
    assign s_axi_rdata  = rdata_reg;
    assign s_axi_rresp  = rresp_reg;
    assign s_axi_rlast  = rvalid_reg;
    assign s_axi_ruser  = 1'b0;

    wire write_complete =
        (aw_pending || aw_handshake) &&
        (w_pending  || w_handshake);

    wire [ADDR_WIDTH-1:0] write_addr =
        aw_pending ? awaddr_reg : s_axi_awaddr;

    wire [31:0] write_data =
        w_pending ? wdata_reg : s_axi_wdata;

    wire [3:0] write_strb =
        w_pending ? wstrb_reg : s_axi_wstrb;

    wire [ID_WIDTH-1:0] write_id =
        aw_pending ? awid_reg : s_axi_awid;

    // ============================================================
    // Inner AXI-Lite signals toward axi_uart_top (12-bit ID, 5-bit addr)
    // ============================================================
    wire axi_aresetn;
    assign axi_aresetn = ~rst;

    reg  [11:0] inner_awid;
    reg  [4:0]  inner_awaddr;
    reg         inner_awvalid;
    reg  [31:0] inner_wdata;
    reg  [3:0]  inner_wstrb;
    reg         inner_wvalid;
    reg         inner_bready;
    wire        inner_awready;
    wire        inner_wready;
    wire [11:0] inner_bid;
    wire [1:0]  inner_bresp;
    wire        inner_bvalid;

    reg  [11:0] inner_arid;
    reg  [4:0]  inner_araddr;
    reg         inner_arvalid;
    reg         inner_rready;
    wire        inner_arready;
    wire [11:0] inner_rid;
    wire [31:0] inner_rdata;
    wire [1:0]  inner_rresp;
    wire        inner_rvalid;

    wire inner_read_interrupt;
    wire inner_uart_tx;

    assign uart_tx_o = inner_uart_tx;
    assign uart_irq  = inner_read_interrupt;

    axi_uart_top u_uart (
        .fixed_clk_i      (clk),
        .axi_aclk_i       (clk),
        .axi_aresetn_i    (axi_aresetn),

        .axi_awid_i       (inner_awid),
        .axi_awaddr_i     (inner_awaddr),
        .axi_awvalid_i    (inner_awvalid),
        .axi_awready_o    (inner_awready),

        .axi_wdata_i      (inner_wdata),
        .axi_wstrb_i      (inner_wstrb),
        .axi_wvalid_i     (inner_wvalid),
        .axi_wready_o     (inner_wready),

        .axi_bid_o        (inner_bid),
        .axi_bresp_o      (inner_bresp),
        .axi_bvalid_o     (inner_bvalid),
        .axi_bready_i     (inner_bready),

        .axi_arid_i       (inner_arid),
        .axi_araddr_i     (inner_araddr),
        .axi_arvalid_i    (inner_arvalid),
        .axi_arready_o    (inner_arready),

        .axi_rid_o        (inner_rid),
        .axi_rdata_o      (inner_rdata),
        .axi_rresp_o      (inner_rresp),
        .axi_rvalid_o     (inner_rvalid),
        .axi_rready_i     (inner_rready),

        .read_interrupt_o (inner_read_interrupt),
        .uart_rx_i        (uart_rx_i),
        .uart_tx_o        (inner_uart_tx)
    );

    // ============================================================
    // Inner write FSM: forwards one buffered outer write to the IP.
    // ============================================================
    localparam [1:0] W_IDLE      = 2'd0;
    localparam [1:0] W_WAIT_RDY  = 2'd1; // VALIDs asserted, wait READYs+BVALID
    localparam [1:0] W_ACK_IP    = 2'd2; // BREADY asserted, wait BVALID clear

    reg [1:0] wstate;
    reg [4:0] wr_off;
    reg [7:0] wr_id;

    // ============================================================
    // Inner read FSM
    // ============================================================
    localparam [1:0] R_IDLE      = 2'd0;
    localparam [1:0] R_WAIT_RDY  = 2'd1; // ARVALID asserted, wait ARREADY
    localparam [1:0] R_WAIT_R    = 2'd2; // wait RVALID
    localparam [1:0] R_ACK_IP    = 2'd3; // RREADY asserted, wait RVALID clear

    reg [1:0] rstate;
    reg [4:0] rd_off;
    reg [7:0] rd_id;
    reg       rd_bypass; // 1 = complete locally with 0 (unsupported offset)
    reg [31:0] rd_bypass_data;

    // ============================================================
    // Main sequential logic
    // ============================================================
    always @(posedge clk) begin
        if (rst) begin
            aw_pending  <= 1'b0;
            awid_reg    <= {ID_WIDTH{1'b0}};
            awaddr_reg  <= {ADDR_WIDTH{1'b0}};
            w_pending   <= 1'b0;
            wdata_reg   <= 32'h0000_0000;
            wstrb_reg   <= 4'h0;
            bvalid_reg  <= 1'b0;
            bid_reg     <= {ID_WIDTH{1'b0}};
            bresp_reg   <= 2'b00;
            rvalid_reg  <= 1'b0;
            rid_reg     <= {ID_WIDTH{1'b0}};
            rdata_reg   <= 32'h0000_0000;
            rresp_reg   <= 2'b00;

            inner_awid    <= 12'h000;
            inner_awaddr  <= 5'h00;
            inner_awvalid <= 1'b0;
            inner_wdata   <= 32'h0000_0000;
            inner_wstrb   <= 4'hF;
            inner_wvalid  <= 1'b0;
            inner_bready  <= 1'b0;
            wstate        <= W_IDLE;
            wr_active     <= 1'b0;
            wr_off        <= 5'h00;
            wr_id         <= 8'h00;

            inner_arid    <= 12'h000;
            inner_araddr  <= 5'h00;
            inner_arvalid <= 1'b0;
            inner_rready  <= 1'b0;
            rstate        <= R_IDLE;
            rd_active     <= 1'b0;
            rd_off        <= 5'h00;
            rd_id         <= 8'h00;
            rd_bypass     <= 1'b0;
            rd_bypass_data<= 32'h0000_0000;
        end else begin
            // ----------------------------------------------------
            // Capture outer AW / W (independent channels, like AES)
            // ----------------------------------------------------
            if (aw_handshake) begin
                aw_pending <= 1'b1;
                awid_reg   <= s_axi_awid;
                awaddr_reg <= s_axi_awaddr;
            end
            if (w_handshake) begin
                w_pending <= 1'b1;
                wdata_reg <= s_axi_wdata;
                wstrb_reg <= s_axi_wstrb;
            end

            // ----------------------------------------------------
            // Hand an outer write to the inner FSM once both halves
            // have arrived and the inner path is free.
            // ----------------------------------------------------
            if (write_complete && !wr_active && (wstate == W_IDLE)) begin
                aw_pending <= 1'b0;
                w_pending  <= 1'b0;
                wr_active  <= 1'b1;
                wr_off     <= write_addr[4:0];
                wr_id      <= write_id;
                inner_awid    <= {4'b0000, write_id};
                inner_awaddr  <= write_addr[4:0];
                inner_wdata   <= write_data;
                inner_wstrb   <= write_strb;
                inner_awvalid <= 1'b1;
                inner_wvalid  <= 1'b1;
                inner_bready  <= 1'b0;
                wstate        <= W_WAIT_RDY;
            end

            // ----------------------------------------------------
            // Inner write FSM
            // ----------------------------------------------------
            case (wstate)
                W_IDLE: begin
                    // idle; issue happens above
                end
                W_WAIT_RDY: begin
                    // IP asserts AWREADY/WREADY/BVALID together one cycle
                    // after VALIDs. Hold VALIDs until READYs seen.
                    if (inner_awready && inner_wready) begin
                        inner_awvalid <= 1'b0;
                        inner_wvalid  <= 1'b0;
                        // BVALID should already be up; if not, keep
                        // waiting with VALIDs low (IP has latched).
                        if (inner_bvalid) begin
                            bid_reg    <= wr_id;
                            bresp_reg  <= inner_bresp;
                            inner_bready <= 1'b1;
                            wstate     <= W_ACK_IP;
                        end else begin
                            // READYs without BVALID yet (should not
                            // happen with this IP, but stay safe).
                            wstate <= W_ACK_IP;
                            inner_bready <= 1'b1;
                        end
                    end else if (inner_bvalid) begin
                        // BVALID early (same cycle as READYs in this IP).
                        inner_awvalid <= 1'b0;
                        inner_wvalid  <= 1'b0;
                        bid_reg    <= wr_id;
                        bresp_reg  <= inner_bresp;
                        inner_bready <= 1'b1;
                        wstate     <= W_ACK_IP;
                    end
                end
                W_ACK_IP: begin
                    // Capture response in case we entered without it.
                    bid_reg   <= wr_id;
                    if (inner_bvalid)
                        bresp_reg <= inner_bresp;
                    // Wait for IP to drop BVALID after seeing BREADY.
                    if (!inner_bvalid) begin
                        inner_bready <= 1'b0;
                        wr_active    <= 1'b0;
                        bvalid_reg   <= 1'b1;
                        wstate       <= W_IDLE;
                    end
                end
                default: begin
                    wstate <= W_IDLE;
                end
            endcase

            // Outer B handshake
            if (bvalid_reg && s_axi_bready)
                bvalid_reg <= 1'b0;

            // ----------------------------------------------------
            // Outer AR capture -> inner read FSM (or local bypass)
            // ----------------------------------------------------
            if (s_axi_arvalid && s_axi_arready) begin
                rid_reg <= s_axi_arid; // pre-latch; final set on completion
                if (is_ip_read_offset(s_axi_araddr[4:0])) begin
                    rd_active   <= 1'b1;
                    rd_bypass   <= 1'b0;
                    rd_off      <= s_axi_araddr[4:0];
                    rd_id       <= s_axi_arid;
                    inner_arid    <= {4'b0000, s_axi_arid};
                    inner_araddr  <= s_axi_araddr[4:0];
                    inner_arvalid <= 1'b1;
                    inner_rready  <= 1'b0;
                    rstate        <= R_WAIT_RDY;
                end else begin
                    // Unsupported offset: answer locally, never touch IP.
                    rd_active      <= 1'b1;
                    rd_bypass      <= 1'b1;
                    rd_off         <= s_axi_araddr[4:0];
                    rd_id          <= s_axi_arid;
                    rd_bypass_data <= 32'h0000_0000;
                    rstate         <= R_ACK_IP; // reuse as "complete next cycle"
                    inner_arvalid  <= 1'b0;
                    inner_rready   <= 1'b0;
                end
            end

            // ----------------------------------------------------
            // Inner read FSM
            // ----------------------------------------------------
            case (rstate)
                R_IDLE: begin
                end
                R_WAIT_RDY: begin
                    if (inner_arready) begin
                        inner_arvalid <= 1'b0;
                        rstate        <= R_WAIT_R;
                    end
                end
                R_WAIT_R: begin
                    if (inner_rvalid) begin
                        rid_reg      <= rd_id;
                        rdata_reg    <= inner_rdata;
                        rresp_reg    <= inner_rresp;
                        inner_rready <= 1'b1;
                        rstate       <= R_ACK_IP;
                    end
                end
                R_ACK_IP: begin
                    if (rd_bypass) begin
                        // Local completion, no IP handshake.
                        rid_reg    <= rd_id;
                        rdata_reg  <= rd_bypass_data;
                        rresp_reg  <= 2'b00;
                        rd_active  <= 1'b0;
                        rd_bypass  <= 1'b0;
                        rvalid_reg <= 1'b1;
                        rstate     <= R_IDLE;
                    end else if (!inner_rvalid) begin
                        inner_rready <= 1'b0;
                        rd_active    <= 1'b0;
                        rvalid_reg   <= 1'b1;
                        rstate       <= R_IDLE;
                    end
                end
                default: rstate <= R_IDLE;
            endcase

            // Outer R handshake
            if (rvalid_reg && s_axi_rready)
                rvalid_reg <= 1'b0;
        end
    end

endmodule

`default_nettype wire
