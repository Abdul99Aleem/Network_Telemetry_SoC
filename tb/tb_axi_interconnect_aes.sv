`timescale 1ns/1ps
`default_nettype none

module tb_axi_interconnect_aes;

    localparam DATA_WIDTH = 32;
    localparam ADDR_WIDTH = 32;
    localparam STRB_WIDTH = 4;
    localparam ID_WIDTH   = 8;

    localparam AES_BASE   = 32'h1000_4000;

    localparam ADDR_CONTROL = AES_BASE + 32'h00;
    localparam ADDR_STATUS  = AES_BASE + 32'h04;
    localparam ADDR_KEY0    = AES_BASE + 32'h08;
    localparam ADDR_KEY1    = AES_BASE + 32'h0C;
    localparam ADDR_KEY2    = AES_BASE + 32'h10;
    localparam ADDR_KEY3    = AES_BASE + 32'h14;
    localparam ADDR_DATA0   = AES_BASE + 32'h18;
    localparam ADDR_DATA1   = AES_BASE + 32'h1C;
    localparam ADDR_DATA2   = AES_BASE + 32'h20;
    localparam ADDR_DATA3   = AES_BASE + 32'h24;
    localparam ADDR_RESULT0 = AES_BASE + 32'h28;
    localparam ADDR_RESULT1 = AES_BASE + 32'h2C;
    localparam ADDR_RESULT2 = AES_BASE + 32'h30;
    localparam ADDR_RESULT3 = AES_BASE + 32'h34;

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

    wire aes_irq;

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    axi_aes_wrapper #(
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
        .aes_irq(aes_irq)
    );

    // ------------------------------------------------------------------
    // Clock
    // ------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ------------------------------------------------------------------
    // AXI single-beat write. AW and W are treated as independent AXI
    // channels and may handshake on different cycles.
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

    task automatic check_read;
        input [31:0] addr;
        input [31:0] expected;
        reg   [31:0] actual;
        begin
            axi_read(addr, actual);
            if (actual !== expected) begin
                $display("ERROR: %08h expected %08h got %08h", addr, expected, actual);
                $fatal;
            end
        end
    endtask

    reg [31:0] status;
    reg [31:0] result0;
    reg [31:0] result1;
    reg [31:0] result2;
    reg [31:0] result3;
    integer timeout;

    // ------------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------------
    initial begin
        // AXI defaults
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

        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        $display("");
        $display("===============================================");
        $display(" AXI INTERCONNECT -> AES INTEGRATION TEST");
        $display(" AES BASE = %08h", AES_BASE);
        $display(" DATA WIDTH = %0d", DATA_WIDTH);
        $display("===============================================");
        

        // --------------------------------------------------------------
        // 1. Prove M06 address decode and AES register access.
        // --------------------------------------------------------------
        $display("\n[1] KEY/DATA register routing through M06");

        axi_write(ADDR_KEY0,  32'h0c0d0e0f);
        axi_write(ADDR_KEY1,  32'h08090a0b);
        axi_write(ADDR_KEY2,  32'h04050607);
        axi_write(ADDR_KEY3,  32'h00010203);

        axi_write(ADDR_DATA0, 32'hccddeeff);
        axi_write(ADDR_DATA1, 32'h8899aabb);
        axi_write(ADDR_DATA2, 32'h44556677);
        axi_write(ADDR_DATA3, 32'h00112233);

        check_read(ADDR_KEY0,  32'h0c0d0e0f);
        check_read(ADDR_KEY1,  32'h08090a0b);
        check_read(ADDR_KEY2,  32'h04050607);
        check_read(ADDR_KEY3,  32'h00010203);
        check_read(ADDR_DATA0, 32'hccddeeff);
        check_read(ADDR_DATA1, 32'h8899aabb);
        check_read(ADDR_DATA2, 32'h44556677);
        check_read(ADDR_DATA3, 32'h00112233);

        $display("REGISTER ROUTING PASS");

        // --------------------------------------------------------------
        // 2. Start AES through the complete AXI path.
        // --------------------------------------------------------------
        $display("\n[2] AES transaction through interconnect");

        axi_write(ADDR_CONTROL, 32'h0000_0001);
        axi_read(ADDR_STATUS, status);

        if (status[0] !== 1'b1) begin
            $display("ERROR: BUSY not asserted after START; STATUS=%08h", status);
            $fatal;
        end
        $display("BUSY ASSERTED");

        // --------------------------------------------------------------
        // 3. Wait for completion.
        // --------------------------------------------------------------
        timeout = 0;
        while (timeout < 100) begin
            axi_read(ADDR_STATUS, status);
            if (status[1] === 1'b1)
                break;
            timeout = timeout + 1;
        end

        if (status[1] !== 1'b1) begin
            $display("ERROR: AES timeout; final STATUS=%08h", status);
            $fatal;
        end

        $display("DONE ASSERTED");

        if (aes_irq !== 1'b1) begin
            $display("ERROR: AES IRQ not asserted");
            $fatal;
        end
        $display("IRQ ASSERTED");

        // --------------------------------------------------------------
        // 4. Known-answer result.
        // --------------------------------------------------------------
        $display("\n[3] AES result verification");

        axi_read(ADDR_RESULT0, result0);
        axi_read(ADDR_RESULT1, result1);
        axi_read(ADDR_RESULT2, result2);
        axi_read(ADDR_RESULT3, result3);

        if (result0 !== 32'h70b4c55a ||
            result1 !== 32'hd8cdb780 ||
            result2 !== 32'h6a7b0430 ||
            result3 !== 32'h69c4e0d8) begin
            $display("ERROR: ciphertext mismatch");
            $display(" expected = 69c4e0d8 6a7b0430 d8cdb780 70b4c55a");
            $display(" actual   = %08h %08h %08h %08h", result3, result2, result1, result0);
            $fatal;
        end

        $display("CIPHERTEXT PASS");
        $display("");
        $display("===============================================");
        $display(" AXI INTERCONNECT -> AES INTEGRATION: PASS");
        $display("===============================================");
        $finish;
    end

    // Useful integration-level waveform probes.
    // These are intentionally hierarchical so the testbench remains
    // compatible with the existing RTL without changing the DUT.

endmodule

`default_nettype wire
