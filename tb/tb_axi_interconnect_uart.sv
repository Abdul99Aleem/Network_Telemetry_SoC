`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// Project: RISC-V Network Telemetry SoC
// TB     : tb_axi_interconnect_uart (single master via axi_uart_wrapper)
// Desc   : Mirrors tb/tb_axi_interconnect_aes.sv but targets UART on M02
//          (0x1000_0000). Proves M02 address decode + UART register access
//          through the full 2x8 AXI interconnect, then verifies real TX bytes
//          on uart_tx_o at the programmed divisor.
//
// DUT    : axi_uart_wrapper (interconnect + uart_axi_slave on M02)
// ============================================================================

module tb_axi_interconnect_uart;

    localparam DATA_WIDTH = 32;
    localparam ADDR_WIDTH = 32;
    localparam STRB_WIDTH = 4;
    localparam ID_WIDTH   = 8;

    localparam UART_BASE  = 32'h1000_0000;
    localparam ADDR_THR   = UART_BASE + 32'h00;
    localparam ADDR_RBR   = UART_BASE + 32'h00;
    localparam ADDR_IER   = UART_BASE + 32'h04;
    localparam ADDR_BAUD  = UART_BASE + 32'h08;
    localparam ADDR_LCR   = UART_BASE + 32'h0C;
    localparam ADDR_LSR   = UART_BASE + 32'h14;

    localparam integer BAUD_DIV = 8;
    localparam integer CLK_PERIOD_NS = 10;
    localparam integer BIT_PERIOD_NS = (BAUD_DIV + 1) * CLK_PERIOD_NS;

    reg clk;
    reg rst;

    // ------------------------------------------------------------------
    // AXI master interface: S00 of the 2x8 interconnect
    // ------------------------------------------------------------------
    reg  [ID_WIDTH-1:0]   s00_axi_awid;
    reg  [ADDR_WIDTH-1:0] s00_axi_awaddr;
    reg  [7:0]            s00_axi_awlen;
    reg  [2:0]            s00_axi_awsize;
    reg  [1:0]            s00_axi_awburst;
    reg                    s00_axi_awlock;
    reg  [3:0]            s00_axi_awcache;
    reg  [2:0]            s00_axi_awprot;
    reg  [3:0]            s00_axi_awqos;
    reg  [0:0]            s00_axi_awuser;
    reg                    s00_axi_awvalid;
    wire                   s00_axi_awready;

    reg  [DATA_WIDTH-1:0] s00_axi_wdata;
    reg  [STRB_WIDTH-1:0] s00_axi_wstrb;
    reg                    s00_axi_wlast;
    reg  [0:0]            s00_axi_wuser;
    reg                    s00_axi_wvalid;
    wire                   s00_axi_wready;

    wire [ID_WIDTH-1:0]   s00_axi_bid;
    wire [1:0]            s00_axi_bresp;
    wire [0:0]            s00_axi_buser;
    wire                   s00_axi_bvalid;
    reg                    s00_axi_bready;

    reg  [ID_WIDTH-1:0]   s00_axi_arid;
    reg  [ADDR_WIDTH-1:0] s00_axi_araddr;
    reg  [7:0]            s00_axi_arlen;
    reg  [2:0]            s00_axi_arsize;
    reg  [1:0]            s00_axi_arburst;
    reg                    s00_axi_arlock;
    reg  [3:0]            s00_axi_arcache;
    reg  [2:0]            s00_axi_arprot;
    reg  [3:0]            s00_axi_arqos;
    reg  [0:0]            s00_axi_aruser;
    reg                    s00_axi_arvalid;
    wire                   s00_axi_arready;

    wire [ID_WIDTH-1:0]   s00_axi_rid;
    wire [DATA_WIDTH-1:0] s00_axi_rdata;
    wire [1:0]            s00_axi_rresp;
    wire                   s00_axi_rlast;
    wire [0:0]            s00_axi_ruser;
    wire                   s00_axi_rvalid;
    reg                    s00_axi_rready;

    wire uart_tx_o;
    wire uart_irq;
    reg  uart_rx_i;

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    axi_uart_wrapper #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .STRB_WIDTH(STRB_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),

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
        .uart_tx_o(uart_tx_o),
        .uart_rx_i(uart_rx_i),
        .uart_irq(uart_irq)
    );

    // ------------------------------------------------------------------
    // Clock
    // ------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS/2) clk = ~clk;
    end

    // ------------------------------------------------------------------
    // AXI single-beat write (same style as tb_axi_interconnect_aes:
    // AW and W treated as independent channels).
    // ------------------------------------------------------------------
    task automatic axi_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);

            s00_axi_awid    <= 8'h01;
            s00_axi_awaddr  <= addr;
            s00_axi_awlen   <= 8'h00;
            s00_axi_awsize  <= 3'b010;
            s00_axi_awburst <= 2'b01;
            s00_axi_awlock  <= 1'b0;
            s00_axi_awcache <= 4'b0000;
            s00_axi_awprot  <= 3'b000;
            s00_axi_awqos   <= 4'b0000;
            s00_axi_awuser  <= 1'b0;
            s00_axi_awvalid <= 1'b1;

            s00_axi_wdata   <= data;
            s00_axi_wstrb   <= 4'b1111;
            s00_axi_wlast   <= 1'b1;
            s00_axi_wuser   <= 1'b0;
            s00_axi_wvalid  <= 1'b1;
            s00_axi_bready  <= 1'b0;

            // AW handshake
            while (!s00_axi_awready)
                @(posedge clk);
            @(posedge clk);
            s00_axi_awvalid <= 1'b0;

            // W handshake
            while (!s00_axi_wready)
                @(posedge clk);
            @(posedge clk);
            s00_axi_wvalid <= 1'b0;

            // B response
            s00_axi_bready <= 1'b1;
            while (!s00_axi_bvalid)
                @(posedge clk);

            if (s00_axi_bresp !== 2'b00) begin
                $display("ERROR: write BRESP=%b addr=%08h", s00_axi_bresp, addr);
                $fatal;
            end

            @(posedge clk);
            s00_axi_bready <= 1'b0;

            $display("WRITE  %08h <= %08h", addr, data);
        end
    endtask

    // ------------------------------------------------------------------
    // AXI single-beat read
    // ------------------------------------------------------------------
    task automatic axi_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            @(posedge clk);

            s00_axi_arid    <= 8'h02;
            s00_axi_araddr  <= addr;
            s00_axi_arlen   <= 8'h00;
            s00_axi_arsize  <= 3'b010;
            s00_axi_arburst <= 2'b01;
            s00_axi_arlock  <= 1'b0;
            s00_axi_arcache <= 4'b0000;
            s00_axi_arprot  <= 3'b000;
            s00_axi_arqos   <= 4'b0000;
            s00_axi_aruser  <= 1'b0;
            s00_axi_arvalid <= 1'b1;
            s00_axi_rready  <= 1'b0;

            while (!s00_axi_arready)
                @(posedge clk);
            @(posedge clk);
            s00_axi_arvalid <= 1'b0;

            s00_axi_rready <= 1'b1;
            while (!s00_axi_rvalid)
                @(posedge clk);

            data = s00_axi_rdata;

            if (s00_axi_rresp !== 2'b00) begin
                $display("ERROR: read RRESP=%b addr=%08h", s00_axi_rresp, addr);
                $fatal;
            end

            @(posedge clk);
            s00_axi_rready <= 1'b0;

            $display("READ   %08h => %08h", addr, data);
        end
    endtask

    // ------------------------------------------------------------
    // UART RX monitor (8N1 at programmed divisor)
    // ------------------------------------------------------------
    task automatic uart_recv_byte(output [7:0] data);
        integer b;
        begin
            fork
                begin
                    @(negedge uart_tx_o);
                end
                begin
                    repeat (30000) @(posedge clk);
                    $display("ERROR: UART start-bit timeout");
                    $fatal;
                end
            join_any
            disable fork;
            #(BIT_PERIOD_NS * 1.5 * 1000);
            for (b = 0; b < 8; b = b + 1) begin
                data[b] = uart_tx_o;
                #(BIT_PERIOD_NS * 1000);
            end
            if (uart_tx_o !== 1'b1) begin
                $display("ERROR: UART stop bit not high");
                $fatal;
            end
            #(BIT_PERIOD_NS * 1000);
            $display("UART RX byte = %02h", data);
        end
    endtask

    reg [31:0] lsr;
    reg [7:0]  rx0, rx1, rx2;

    // ------------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------------
    initial begin
        s00_axi_awid    = 0;
        s00_axi_awaddr  = 0;
        s00_axi_awlen   = 0;
        s00_axi_awsize  = 0;
        s00_axi_awburst = 0;
        s00_axi_awlock  = 0;
        s00_axi_awcache = 0;
        s00_axi_awprot  = 0;
        s00_axi_awqos   = 0;
        s00_axi_awuser  = 0;
        s00_axi_awvalid = 0;
        s00_axi_wdata   = 0;
        s00_axi_wstrb   = 0;
        s00_axi_wlast   = 0;
        s00_axi_wuser   = 0;
        s00_axi_wvalid  = 0;
        s00_axi_bready  = 0;
        s00_axi_arid    = 0;
        s00_axi_araddr  = 0;
        s00_axi_arlen   = 0;
        s00_axi_arsize  = 0;
        s00_axi_arburst = 0;
        s00_axi_arlock  = 0;
        s00_axi_arcache = 0;
        s00_axi_arprot  = 0;
        s00_axi_arqos   = 0;
        s00_axi_aruser  = 0;
        s00_axi_arvalid = 0;
        s00_axi_rready  = 0;
        uart_rx_i = 1'b1;

        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        $display("");
        $display("===============================================");
        $display(" AXI INTERCONNECT -> UART INTEGRATION TEST");
        $display(" UART BASE = %08h (M02)", UART_BASE);
        $display(" DATA WIDTH = %0d", DATA_WIDTH);
        $display("===============================================");

        // [1] M02 decode: LSR read + TX idle.
        $display("\n[1] UART M02 routing + reset state");
        if (uart_tx_o !== 1'b1) begin
            $display("ERROR: uart_tx not idle high after reset");
            $fatal;
        end
        axi_read(ADDR_LSR, lsr);
        if (lsr[6] !== 1'b1 || lsr[5] !== 1'b1) begin
            $display("ERROR: LSR reset expected THRE=TEMT=1, got %08h", lsr);
            $fatal;
        end
        $display("M02 ROUTING + LSR RESET PASS (LSR=%08h)", lsr);

        // [2] Configure through the interconnect.
        $display("\n[2] UART config through interconnect");
        axi_write(ADDR_LCR, 32'h0000_0083);
        axi_write(ADDR_BAUD, BAUD_DIV);
        axi_write(ADDR_LCR, 32'h0000_0003);
        axi_write(ADDR_IER, 32'h0000_0000);
        if (uart_irq !== 1'b0) begin
            $display("ERROR: uart_irq should be 0, got %b", uart_irq);
            $fatal;
        end
        $display("CONFIG PASS");

        // [3] TX bytes through the interconnect.
        $display("\n[3] UART TX bytes through interconnect");
        axi_write(ADDR_THR, 32'h0000_0055);
        uart_recv_byte(rx0);
        if (rx0 !== 8'h55) begin
            $display("ERROR: byte0 expected 55 got %02h", rx0);
            $fatal;
        end
        $display("TX 0x55 PASS");

        axi_write(ADDR_THR, 32'h0000_0041);
        uart_recv_byte(rx1);
        if (rx1 !== 8'h41) begin
            $display("ERROR: byte1 expected 41 got %02h", rx1);
            $fatal;
        end
        $display("TX 0x41 PASS");

        axi_write(ADDR_THR, 32'h0000_005A);
        uart_recv_byte(rx2);
        if (rx2 !== 8'h5A) begin
            $display("ERROR: byte2 expected 5A got %02h", rx2);
            $fatal;
        end
        $display("TX 0x5A PASS");

        // [4] Post-TX LSR.
        axi_read(ADDR_LSR, lsr);
        if (lsr[6] !== 1'b1 || lsr[5] !== 1'b1) begin
            $display("ERROR: LSR post-TX expected THRE=TEMT=1, got %08h", lsr);
            $fatal;
        end
        $display("LSR POST-TX (%08h) PASS", lsr);

        $display("");
        $display("===============================================");
        $display(" AXI INTERCONNECT -> UART INTEGRATION: PASS");
        $display("===============================================");
        $finish;
    end

    // FSDB dump for Verdi (AES single-TB lacked this; UART adds it).
    initial begin
        $fsdbDumpfile("uart_axi_interconnect.fsdb");
        $fsdbDumpvars(0, tb_axi_interconnect_uart);
        $fsdbDumpMDA();
    end

endmodule

`default_nettype wire
