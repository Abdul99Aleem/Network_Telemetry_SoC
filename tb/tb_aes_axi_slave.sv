`timescale 1ns/1ps

module tb_aes_axi_slave;

// ============================================================
// Parameters
// ============================================================

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

// ============================================================
// Clock / reset
// ============================================================

reg clk;
reg rst;

initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
end

// ============================================================
// AXI WRITE ADDRESS CHANNEL
// ============================================================

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

// ============================================================
// AXI WRITE DATA CHANNEL
// ============================================================

reg [DATA_WIDTH-1:0] s_axi_wdata;
reg [STRB_WIDTH-1:0] s_axi_wstrb;
reg                  s_axi_wlast;
reg                  s_axi_wuser;
reg                  s_axi_wvalid;
wire                 s_axi_wready;

// ============================================================
// AXI WRITE RESPONSE CHANNEL
// ============================================================

wire [ID_WIDTH-1:0]  s_axi_bid;
wire [1:0]           s_axi_bresp;
wire                 s_axi_buser;
wire                 s_axi_bvalid;
reg                  s_axi_bready;

// ============================================================
// AXI READ ADDRESS CHANNEL
// ============================================================

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

// ============================================================
// AXI READ RESPONSE CHANNEL
// ============================================================

wire [ID_WIDTH-1:0]   s_axi_rid;
wire [DATA_WIDTH-1:0] s_axi_rdata;
wire [1:0]            s_axi_rresp;
wire                  s_axi_rlast;
wire                  s_axi_ruser;
wire                  s_axi_rvalid;
reg                   s_axi_rready;

wire aes_irq;

// ============================================================
// DUT
// ============================================================

aes_axi_slave dut (
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

    .aes_irq      (aes_irq)
);

// ============================================================
// AXI WRITE TASK
// ============================================================

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
            $display("ERROR: AXI write response = %b", s_axi_bresp);
            $fatal;
        end

        @(posedge clk);

        s_axi_bready <= 1'b0;

        $display(
            "AXI WRITE  ADDR=%08h DATA=%08h",
            addr,
            data
        );

    end
endtask

// ============================================================
// AXI READ TASK
// ============================================================

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
            $display("ERROR: AXI read response = %b", s_axi_rresp);
            $fatal;
        end

        @(posedge clk);

        s_axi_rready <= 1'b0;

        $display(
            "AXI READ   ADDR=%08h DATA=%08h",
            addr,
            data
        );

    end
endtask

// ============================================================
// Test
// ============================================================

reg [31:0] read_value;

initial begin

    // --------------------------------------------------------
    // Initial AXI values
    // --------------------------------------------------------

    s_axi_awid    = 0;
    s_axi_awaddr  = 0;
    s_axi_awlen   = 0;
    s_axi_awsize  = 0;
    s_axi_awburst = 0;
    s_axi_awlock  = 0;
    s_axi_awcache = 0;
    s_axi_awprot  = 0;
    s_axi_awqos   = 0;
    s_axi_awuser  = 0;
    s_axi_awvalid = 0;

    s_axi_wdata   = 0;
    s_axi_wstrb   = 0;
    s_axi_wlast   = 0;
    s_axi_wuser   = 0;
    s_axi_wvalid  = 0;

    s_axi_bready  = 0;

    s_axi_arid    = 0;
    s_axi_araddr  = 0;
    s_axi_arlen   = 0;
    s_axi_arsize  = 0;
    s_axi_arburst = 0;
    s_axi_arlock  = 0;
    s_axi_arcache = 0;
    s_axi_arprot  = 0;
    s_axi_arqos   = 0;
    s_axi_aruser  = 0;
    s_axi_arvalid = 0;

    s_axi_rready  = 0;

    // --------------------------------------------------------
    // AES core reset is active LOW
    // --------------------------------------------------------

    rst = 1'b1;

    repeat (5)
        @(posedge clk);

    rst = 1'b0;

    repeat (2)
        @(posedge clk);

    $display("");
    $display("==============================================");
    $display(" AES AXI SLAVE TEST");
    $display("==============================================");
    $display("");

    // --------------------------------------------------------
    // AES-128 known-answer test
    //
    // Key:
    // 000102030405060708090a0b0c0d0e0f
    //
    // Plaintext:
    // 00112233445566778899aabbccddeeff
    //
    // Expected ciphertext:
    // 69c4e0d86a7b0430d8cdb78070b4c55a
    // --------------------------------------------------------

    $display("Loading AES key...");

    axi_write(ADDR_KEY0, 32'h0c0d0e0f);
    axi_write(ADDR_KEY1, 32'h08090a0b);
    axi_write(ADDR_KEY2, 32'h04050607);
    axi_write(ADDR_KEY3, 32'h00010203);

    $display("");
    $display("Loading plaintext...");

    axi_write(ADDR_DATA0, 32'hccddeeff);
    axi_write(ADDR_DATA1, 32'h8899aabb);
    axi_write(ADDR_DATA2, 32'h44556677);
    axi_write(ADDR_DATA3, 32'h00112233);

    // --------------------------------------------------------
    // Verify written registers
    // --------------------------------------------------------

    $display("");
    $display("Checking KEY/DATA registers...");

    axi_read(ADDR_KEY0, read_value);
    if (read_value !== 32'h0c0d0e0f) $fatal;

    axi_read(ADDR_KEY1, read_value);
    if (read_value !== 32'h08090a0b) $fatal;

    axi_read(ADDR_KEY2, read_value);
    if (read_value !== 32'h04050607) $fatal;

    axi_read(ADDR_KEY3, read_value);
    if (read_value !== 32'h00010203) $fatal;

    axi_read(ADDR_DATA0, read_value);
    if (read_value !== 32'hccddeeff) $fatal;

    axi_read(ADDR_DATA1, read_value);
    if (read_value !== 32'h8899aabb) $fatal;

    axi_read(ADDR_DATA2, read_value);
    if (read_value !== 32'h44556677) $fatal;

    axi_read(ADDR_DATA3, read_value);
    if (read_value !== 32'h00112233) $fatal;

    $display("Register readback PASS");

    // --------------------------------------------------------
    // Start AES
    // --------------------------------------------------------

    $display("");
    $display("Starting AES...");

    axi_write(ADDR_CONTROL, 32'h0000_0001);

    // --------------------------------------------------------
    // Verify BUSY
    // --------------------------------------------------------

    axi_read(ADDR_STATUS, read_value);

    if (read_value[0] !== 1'b1) begin
        $display("ERROR: BUSY was not asserted");
        $fatal;
    end

    $display("BUSY asserted");

    


    // --------------------------------------------------------
    // Wait for DONE
    // --------------------------------------------------------

    $display("Waiting for AES completion...");

    begin : wait_for_done
        integer timeout;

        timeout = 0;

        while (timeout < 100) begin

            axi_read(ADDR_STATUS, read_value);

            if (read_value[1]) begin
                $display("DONE asserted");
                disable wait_for_done;
            end

            timeout = timeout + 1;

        end

        if (timeout >= 100) begin
            $display("ERROR: AES timeout");
            $fatal;
        end
    end




    // --------------------------------------------------------
    // Check interrupt
    // --------------------------------------------------------

    if (aes_irq !== 1'b1) begin
        $display("ERROR: AES IRQ not asserted");
        $fatal;
    end

    $display("AES IRQ asserted");

    // --------------------------------------------------------
    // Read result
    // --------------------------------------------------------

    $display("");
    $display("Reading AES result...");

    axi_read(ADDR_RESULT0, read_value);
    if (read_value !== 32'h70b4c55a) begin
        $display(
            "ERROR RESULT0: expected 70b4c55a got %08h",
            read_value
        );
        $fatal;
    end

    axi_read(ADDR_RESULT1, read_value);
    if (read_value !== 32'hd8cdb780) begin
        $display(
            "ERROR RESULT1: expected d8cdb780 got %08h",
            read_value
        );
        $fatal;
    end

    axi_read(ADDR_RESULT2, read_value);
    if (read_value !== 32'h6a7b0430) begin
        $display(
            "ERROR RESULT2: expected 6a7b0430 got %08h",
            read_value
        );
        $fatal;
    end

    axi_read(ADDR_RESULT3, read_value);
    if (read_value !== 32'h69c4e0d8) begin
        $display(
            "ERROR RESULT3: expected 69c4e0d8 got %08h",
            read_value
        );
        $fatal;
    end

    // --------------------------------------------------------
    // Clear DONE and IRQ
    // --------------------------------------------------------

    $display("");
    $display("Clearing DONE/IRQ...");

    axi_write(ADDR_CONTROL, 32'h0000_0002);

    axi_read(ADDR_STATUS, read_value);

    if (read_value[1] !== 1'b0) begin
        $display("ERROR: DONE did not clear");
        $fatal;
    end

    if (aes_irq !== 1'b0) begin
        $display("ERROR: IRQ did not clear");
        $fatal;
    end

    // --------------------------------------------------------
    // PASS
    // --------------------------------------------------------

    $display("");
    $display("==============================================");
    $display(" AES AXI SLAVE TEST PASSED");
    $display(" Ciphertext = 69c4e0d86a7b0430d8cdb78070b4c55a");
    $display("==============================================");
    $display("");

    #100;
    $finish;

end

// ============================================================
// FSDB dump
// ============================================================

initial begin
    $fsdbDumpfile("aes_axi_slave.fsdb");
    $fsdbDumpvars(0, tb_aes_axi_slave);
    $fsdbDumpMDA();
end

endmodule

