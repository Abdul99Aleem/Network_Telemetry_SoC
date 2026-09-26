`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// Project: RISC-V Network Telemetry SoC
// TB     : tb_uart_axi_slave (direct, no interconnect)
// Desc   : Mirrors tb_aes_axi_slave.sv but for UART. Drives uart_axi_slave
//          directly with single-beat AXI writes/reads, configures the UART
//          (DLAB -> divisor 8 -> 8N1), transmits bytes via THR, and verifies
//          them by sampling uart_tx_o at the programmed baud rate.
//
//          UART_BASE = 0x1000_0000. Only RBR(0x00)/LSR(0x14) reads are
//          forwarded to the IP; other read offsets return 0 locally (see
//          uart_axi_slave.v). TB therefore only reads LSR (+RBR empty).
// ============================================================================

module tb_uart_axi_slave;

localparam DATA_WIDTH = 32;
localparam ADDR_WIDTH = 32;
localparam STRB_WIDTH = 4;
localparam ID_WIDTH   = 8;

localparam UART_BASE  = 32'h1000_0000;
localparam ADDR_THR   = UART_BASE + 32'h00; // WO (low byte), RBR on read
localparam ADDR_RBR   = UART_BASE + 32'h00;
localparam ADDR_IER   = UART_BASE + 32'h04;
localparam ADDR_BAUD  = UART_BASE + 32'h08;
localparam ADDR_LCR   = UART_BASE + 32'h0C;
localparam ADDR_LSR   = UART_BASE + 32'h14;

localparam integer BAUD_DIV = 8;
localparam integer CLK_PERIOD_NS = 10;
localparam integer BIT_PERIOD_NS = (BAUD_DIV + 1) * CLK_PERIOD_NS; // ~90ns

reg clk;
reg rst;

initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD_NS/2) clk = ~clk;
end

// ------------------------------------------------------------
// AXI signals (same pinout as aes_axi_slave)
// ------------------------------------------------------------
reg [ID_WIDTH-1:0]   s_axi_awid;
reg [ADDR_WIDTH-1:0] s_axi_awaddr;
reg [7:0]            s_axi_awlen;
reg [2:0]            s_axi_awsize;
reg [1:0]            s_axi_awburst;
reg                  s_axi_awlock;
reg [3:0]            s_axi_awcache;
reg [2:0]            s_axi_awprot;
reg [3:0]            s_axi_awqos;
reg                  s_axi_awuser;
reg                  s_axi_awvalid;
wire                 s_axi_awready;

reg [DATA_WIDTH-1:0] s_axi_wdata;
reg [STRB_WIDTH-1:0] s_axi_wstrb;
reg                  s_axi_wlast;
reg                  s_axi_wuser;
reg                  s_axi_wvalid;
wire                 s_axi_wready;

wire [ID_WIDTH-1:0]  s_axi_bid;
wire [1:0]           s_axi_bresp;
wire                 s_axi_buser;
wire                 s_axi_bvalid;
reg                  s_axi_bready;

reg [ID_WIDTH-1:0]   s_axi_arid;
reg [ADDR_WIDTH-1:0] s_axi_araddr;
reg [7:0]            s_axi_arlen;
reg [2:0]            s_axi_arsize;
reg [1:0]            s_axi_arburst;
reg                  s_axi_arlock;
reg [3:0]            s_axi_arcache;
reg [2:0]            s_axi_arprot;
reg [3:0]            s_axi_arqos;
reg                  s_axi_aruser;
reg                  s_axi_arvalid;
wire                 s_axi_arready;

wire [ID_WIDTH-1:0]   s_axi_rid;
wire [DATA_WIDTH-1:0] s_axi_rdata;
wire [1:0]            s_axi_rresp;
wire                  s_axi_rlast;
wire                  s_axi_ruser;
wire                  s_axi_rvalid;
reg                   s_axi_rready;

wire uart_tx_o;
wire uart_irq;
reg  uart_rx_i;

uart_axi_slave dut (
    .clk          (clk),
    .rst          (rst),
    .s_axi_awid   (s_axi_awid),
    .s_axi_awaddr (s_axi_awaddr),
    .s_axi_awlen  (s_axi_awlen),
    .s_axi_awsize (s_axi_awsize),
    .s_axi_awburst(s_axi_awburst),
    .s_axi_awlock (s_axi_awlock),
    .s_axi_awcache(s_axi_awcache),
    .s_axi_awprot (s_axi_awprot),
    .s_axi_awqos  (s_axi_awqos),
    .s_axi_awuser (s_axi_awuser),
    .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready),
    .s_axi_wdata  (s_axi_wdata),
    .s_axi_wstrb  (s_axi_wstrb),
    .s_axi_wlast  (s_axi_wlast),
    .s_axi_wuser  (s_axi_wuser),
    .s_axi_wvalid (s_axi_wvalid),
    .s_axi_wready (s_axi_wready),
    .s_axi_bid    (s_axi_bid),
    .s_axi_bresp  (s_axi_bresp),
    .s_axi_buser  (s_axi_buser),
    .s_axi_bvalid (s_axi_bvalid),
    .s_axi_bready (s_axi_bready),
    .s_axi_arid   (s_axi_arid),
    .s_axi_araddr (s_axi_araddr),
    .s_axi_arlen  (s_axi_arlen),
    .s_axi_arsize (s_axi_arsize),
    .s_axi_arburst(s_axi_arburst),
    .s_axi_arlock (s_axi_arlock),
    .s_axi_arcache(s_axi_arcache),
    .s_axi_arprot (s_axi_arprot),
    .s_axi_arqos  (s_axi_arqos),
    .s_axi_aruser (s_axi_aruser),
    .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready),
    .s_axi_rid    (s_axi_rid),
    .s_axi_rdata  (s_axi_rdata),
    .s_axi_rresp  (s_axi_rresp),
    .s_axi_rlast  (s_axi_rlast),
    .s_axi_ruser  (s_axi_ruser),
    .s_axi_rvalid (s_axi_rvalid),
    .s_axi_rready (s_axi_rready),
    .uart_tx_o    (uart_tx_o),
    .uart_rx_i    (uart_rx_i),
    .uart_irq     (uart_irq)
);

// ------------------------------------------------------------
// AXI tasks (same style as tb_aes_axi_slave: AW+W together)
// ------------------------------------------------------------
task axi_write;
    input [31:0] addr;
    input [31:0] data;
    begin
        @(posedge clk);
        s_axi_awid    <= 8'h01;
        s_axi_awaddr  <= addr;
        s_axi_awlen   <= 8'h00;
        s_axi_awsize  <= 3'b010;
        s_axi_awburst <= 2'b01;
        s_axi_awlock  <= 1'b0;
        s_axi_awcache <= 4'b0000;
        s_axi_awprot  <= 3'b000;
        s_axi_awqos   <= 4'b0000;
        s_axi_awuser  <= 1'b0;
        s_axi_awvalid <= 1'b1;
        s_axi_wdata   <= data;
        s_axi_wstrb   <= 4'b1111;
        s_axi_wlast   <= 1'b1;
        s_axi_wuser   <= 1'b0;
        s_axi_wvalid  <= 1'b1;
        while (!(s_axi_awready && s_axi_wready))
            @(posedge clk);
        @(posedge clk);
        s_axi_awvalid <= 1'b0;
        s_axi_wvalid  <= 1'b0;
        s_axi_bready  <= 1'b1;
        while (!s_axi_bvalid)
            @(posedge clk);
        if (s_axi_bresp !== 2'b00) begin
            $display("ERROR: write BRESP=%b addr=%08h", s_axi_bresp, addr);
            $fatal;
        end
        @(posedge clk);
        s_axi_bready <= 1'b0;
        $display("AXI WRITE  ADDR=%08h DATA=%08h", addr, data);
    end
endtask

task axi_read;
    input  [31:0] addr;
    output [31:0] data;
    begin
        @(posedge clk);
        s_axi_arid    <= 8'h02;
        s_axi_araddr  <= addr;
        s_axi_arlen   <= 8'h00;
        s_axi_arsize  <= 3'b010;
        s_axi_arburst <= 2'b01;
        s_axi_arlock  <= 1'b0;
        s_axi_arcache <= 4'b0000;
        s_axi_arprot  <= 3'b000;
        s_axi_arqos   <= 4'b0000;
        s_axi_aruser  <= 1'b0;
        s_axi_arvalid <= 1'b1;
        while (!s_axi_arready)
            @(posedge clk);
        @(posedge clk);
        s_axi_arvalid <= 1'b0;
        s_axi_rready  <= 1'b1;
        while (!s_axi_rvalid)
            @(posedge clk);
        data = s_axi_rdata;
        if (s_axi_rresp !== 2'b00) begin
            $display("ERROR: read RRESP=%b addr=%08h", s_axi_rresp, addr);
            $fatal;
        end
        @(posedge clk);
        s_axi_rready <= 1'b0;
        $display("AXI READ   ADDR=%08h DATA=%08h", addr, data);
    end
endtask

// ------------------------------------------------------------
// UART RX monitor: waits for start bit, samples 8N1 at BIT_PERIOD.
// ------------------------------------------------------------
task automatic uart_recv_byte(output [7:0] data);
    integer b;
    begin
        // Wait for start bit (TX idle high -> low), timeout 20000 cycles.
        fork
            begin
                @(negedge uart_tx_o);
            end
            begin
                repeat (20000) @(posedge clk);
                $display("ERROR: UART start-bit timeout");
                $fatal;
            end
        join_any
        disable fork;
        // Mid-bit sampling: 1.5 BITs to bit0 centre.
        #(BIT_PERIOD_NS * 1.5 * 1000);
        for (b = 0; b < 8; b = b + 1) begin
            data[b] = uart_tx_o;
            #(BIT_PERIOD_NS * 1000);
        end
        // Stop bit should be high.
        if (uart_tx_o !== 1'b1) begin
            $display("ERROR: UART stop bit not high (got %b)", uart_tx_o);
            $fatal;
        end
        // Wait one more BIT so next start is clean.
        #(BIT_PERIOD_NS * 1000);
        $display("UART RX byte = %02h (%s)", data,
                 (data >= 32 && data < 127) ? "printable" : "non-print");
    end
endtask

reg [31:0] lsr;
reg [7:0]  rx0, rx1;

initial begin
    s_axi_awid=0; s_axi_awaddr=0; s_axi_awlen=0; s_axi_awsize=0;
    s_axi_awburst=0; s_axi_awlock=0; s_axi_awcache=0; s_axi_awprot=0;
    s_axi_awqos=0; s_axi_awuser=0; s_axi_awvalid=0;
    s_axi_wdata=0; s_axi_wstrb=0; s_axi_wlast=0; s_axi_wuser=0; s_axi_wvalid=0;
    s_axi_bready=0;
    s_axi_arid=0; s_axi_araddr=0; s_axi_arlen=0; s_axi_arsize=0;
    s_axi_arburst=0; s_axi_arlock=0; s_axi_arcache=0; s_axi_arprot=0;
    s_axi_arqos=0; s_axi_aruser=0; s_axi_arvalid=0;
    s_axi_rready=0;
    uart_rx_i = 1'b1; // TX-only: RX idle high

    rst = 1'b1;
    repeat (5) @(posedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);

    $display("");
    $display("===============================================");
    $display(" UART AXI SLAVE DIRECT TEST (no interconnect)");
    $display(" UART BASE = %08h, BAUD_DIV = %0d", UART_BASE, BAUD_DIV);
    $display("===============================================");

    // [1] TX idle + LSR reset state (THRE=1, TEMT=1).
    if (uart_tx_o !== 1'b1) begin
        $display("ERROR: uart_tx not idle high after reset");
        $fatal;
    end
    $display("TX IDLE HIGH PASS");
    axi_read(ADDR_LSR, lsr);
    if (lsr[6] !== 1'b1 || lsr[5] !== 1'b1) begin
        $display("ERROR: LSR reset expected THRE=TEMT=1, got %08h", lsr);
        $fatal;
    end
    $display("LSR RESET (0x%08h) PASS", lsr);

    // [2] Configure baud + 8N1.
    axi_write(ADDR_LCR, 32'h0000_0083); // DLAB=1
    axi_write(ADDR_BAUD, BAUD_DIV);
    axi_write(ADDR_LCR, 32'h0000_0003); // DLAB=0, 8N1
    axi_write(ADDR_IER, 32'h0000_0000); // TX-only: no RX interrupt
    $display("UART CONFIG PASS");

    if (uart_irq !== 1'b0) begin
        $display("ERROR: uart_irq should be 0 in TX-only use, got %b", uart_irq);
        $fatal;
    end
    $display("IRQ QUIET PASS");

    // [3] Transmit 0x55, expect exact loopback via TX monitor.
    axi_write(ADDR_THR, 32'h0000_0055);
    uart_recv_byte(rx0);
    if (rx0 !== 8'h55) begin
        $display("ERROR: byte0 expected 55 got %02h", rx0);
        $fatal;
    end
    $display("TX BYTE 0x55 PASS");

    // [4] Transmit 'A' (0x41).
    axi_write(ADDR_THR, 32'h0000_0041);
    uart_recv_byte(rx1);
    if (rx1 !== 8'h41) begin
        $display("ERROR: byte1 expected 41 got %02h", rx1);
        $fatal;
    end
    $display("TX BYTE 0x41 PASS");

    // [5] LSR still shows THRE/TEMT after bytes drain.
    repeat (20) @(posedge clk);
    axi_read(ADDR_LSR, lsr);
    if (lsr[6] !== 1'b1 || lsr[5] !== 1'b1) begin
        $display("ERROR: LSR after TX expected THRE=TEMT=1, got %08h", lsr);
        $fatal;
    end
    $display("LSR POST-TX (0x%08h) PASS", lsr);

    $display("");
    $display("===============================================");
    $display(" UART AXI SLAVE DIRECT: PASS");
    $display("===============================================");
    $finish;
end

// FSDB dump (like tb_aes_axi_slave: aes_axi_slave.fsdb).
initial begin
    $fsdbDumpfile("uart_axi_slave.fsdb");
    $fsdbDumpvars(0, tb_uart_axi_slave);
    $fsdbDumpMDA();
end

endmodule

`default_nettype wire
