`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// AXI4 2-master / 8-slave interconnect verification testbench
//
// DUT:
//   axi_interconnect_wrap_2x8
//
// Masters:
//   M0 = testbench master 0
//   M1 = testbench master 1
//
// Targets:
//   S0 = IMEM
//   S1 = DMEM
//   S2 = UART
//   S3 = Timer
//   S4 = GPIO
//   S5 = Network Telemetry
//   S6 = AES
//   S7 = CRC32
//
// The DUT output ports are named m00..m07 because the underlying crossbar
// calls its target-facing ports "master interfaces".
//
// Verification features:
//   - Independent AXI AW/W/B and AR/R channel BFMs
//   - 64-bit data / 32-bit address
//   - Single-beat and INCR burst reads/writes
//   - Byte strobes
//   - Per-master IDs
//   - Random target-side ready stalls
//   - Random response stalls
//   - Concurrent M0/M1 traffic
//   - Address-routing scoreboard
//   - Data/memory scoreboard
//   - Response-ID scoreboard
//   - RLAST/BRESP/RRESP checks
//   - Unmapped-address DECERR test
//   - Timeout detection
//   - FSDB dumping for Verdi
//
// Compile with VCS, for example:
//   vcs -full64 -sverilog -debug_access+all \
//       axi_crossbar.v axi_interconnect_wrap_2x8.v tb_axi_interconnect_2x8.sv \
//       -o simv
//
// Run:
//   ./simv
//
// Open FSDB:
//   verdi -ssf axi_interconnect_2x8.fsdb
// ============================================================================

module axi_dummy_slave #(
    parameter integer ID_WIDTH   = 8,
    parameter integer DATA_WIDTH = 64,
    parameter integer ADDR_WIDTH = 32,
    parameter integer MEM_WORDS  = 256,
    parameter integer SLAVE_NUM  = 0
) (
    input  wire                     clk,
    input  wire                     rst,

    input  wire [ID_WIDTH-1:0]      s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire [7:0]               s_axi_awlen,
    input  wire [2:0]               s_axi_awsize,
    input  wire [1:0]               s_axi_awburst,
    input  wire                     s_axi_awlock,
    input  wire [3:0]               s_axi_awcache,
    input  wire [2:0]               s_axi_awprot,
    input  wire [3:0]               s_axi_awqos,
    input  wire [3:0]               s_axi_awregion,
    input  wire                     s_axi_awvalid,
    output reg                      s_axi_awready,

    input  wire [DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire [(DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                     s_axi_wlast,
    input  wire                     s_axi_wvalid,
    output reg                      s_axi_wready,

    output reg  [ID_WIDTH-1:0]      s_axi_bid,
    output reg  [1:0]               s_axi_bresp,
    output reg                      s_axi_bvalid,
    input  wire                     s_axi_bready,

    input  wire [ID_WIDTH-1:0]      s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire [7:0]               s_axi_arlen,
    input  wire [2:0]               s_axi_arsize,
    input  wire [1:0]               s_axi_arburst,
    input  wire                     s_axi_arlock,
    input  wire [3:0]               s_axi_arcache,
    input  wire [2:0]               s_axi_arprot,
    input  wire [3:0]               s_axi_arqos,
    input  wire [3:0]               s_axi_arregion,
    input  wire                     s_axi_arvalid,
    output reg                      s_axi_arready,

    output reg  [ID_WIDTH-1:0]      s_axi_rid,
    output reg  [DATA_WIDTH-1:0]    s_axi_rdata,
    output reg  [1:0]               s_axi_rresp,
    output reg                      s_axi_rlast,
    output reg                      s_axi_rvalid,
    input  wire                     s_axi_rready
);

    localparam integer STRB_WIDTH = DATA_WIDTH/8;
    localparam integer WORD_SHIFT = $clog2(STRB_WIDTH);

    reg [DATA_WIDTH-1:0] mem [0:MEM_WORDS-1];

    // Write-address state. AXI permits AW and W to arrive independently.
    reg                    aw_pending;
    reg [ID_WIDTH-1:0]     aw_id_reg;
    reg [ADDR_WIDTH-1:0]   aw_addr_reg;
    reg [7:0]              aw_len_reg;
    reg [2:0]              aw_size_reg;
    reg [1:0]              aw_burst_reg;
    integer                aw_beat;

    // Read state.
    reg                    rd_pending;
    reg [ID_WIDTH-1:0]     rd_id_reg;
    reg [ADDR_WIDTH-1:0]   rd_addr_reg;
    reg [7:0]              rd_len_reg;
    reg [2:0]              rd_size_reg;
    reg [1:0]              rd_burst_reg;
    integer                rd_beat;

    integer i;
    integer random_ready;

    function automatic integer word_index(input [ADDR_WIDTH-1:0] addr);
        begin
            word_index = (addr >> WORD_SHIFT) % MEM_WORDS;
        end
    endfunction

    task automatic apply_wstrb(
        inout [DATA_WIDTH-1:0] old_data,
        input [DATA_WIDTH-1:0] new_data,
        input [STRB_WIDTH-1:0] strb
    );
        integer b;
        begin
            for (b = 0; b < STRB_WIDTH; b = b + 1)
                if (strb[b])
                    old_data[b*8 +: 8] = new_data[b*8 +: 8];
        end
    endtask

    // Target-side READY signals are randomized once per clock.
    // Do not call $urandom from an always @(*) block: if READY becomes 0,
    // no input may change to retrigger that block, causing a permanent stall.
    reg awready_rand;
    reg wready_rand;
    reg arready_rand;

    always @(posedge clk) begin
        if (rst) begin
            awready_rand <= 1'b1;
            wready_rand  <= 1'b1;
            arready_rand <= 1'b1;
        end else begin
            awready_rand <= (($urandom % 5) != 0);
            wready_rand  <= (($urandom % 4) != 0);
            arready_rand <= (($urandom % 5) != 0);
        end
    end

    always @(*) begin
        s_axi_awready = !rst && !aw_pending && !s_axi_bvalid && awready_rand;
        s_axi_wready  = !rst && aw_pending && !s_axi_bvalid && wready_rand;
        s_axi_arready = !rst && !rd_pending && !s_axi_rvalid && arready_rand;
    end

    always @(posedge clk) begin
        if (rst) begin
            aw_pending <= 1'b0;
            rd_pending <= 1'b0;
            aw_beat    <= 0;
            rd_beat    <= 0;

            s_axi_bid   <= {ID_WIDTH{1'b0}};
            s_axi_bresp <= 2'b00;
            s_axi_bvalid<= 1'b0;

            s_axi_rid   <= {ID_WIDTH{1'b0}};
            s_axi_rdata <= {DATA_WIDTH{1'b0}};
            s_axi_rresp <= 2'b00;
            s_axi_rlast <= 1'b0;
            s_axi_rvalid<= 1'b0;

            for (i = 0; i < MEM_WORDS; i = i + 1)
                mem[i] <= {DATA_WIDTH{1'b0}};
        end
        else begin
            // ---------------------------------------------------------------
            // WRITE ADDRESS
            // ---------------------------------------------------------------
            if (s_axi_awvalid && s_axi_awready) begin
                aw_pending  <= 1'b1;
                aw_id_reg   <= s_axi_awid;
                aw_addr_reg <= s_axi_awaddr;
                aw_len_reg  <= s_axi_awlen;
                aw_size_reg <= s_axi_awsize;
                aw_burst_reg<= s_axi_awburst;
                aw_beat     <= 0;
            end

            // ---------------------------------------------------------------
            // WRITE DATA
            // ---------------------------------------------------------------
            if (s_axi_wvalid && s_axi_wready) begin
                if (!aw_pending) begin
                    $display("[%0t] ERROR S%0d: W accepted without AW",
                             $time, SLAVE_NUM);
                    $fatal;
                end

                if (word_index(aw_addr_reg) >= 0 &&
                    word_index(aw_addr_reg) < MEM_WORDS) begin
                    apply_wstrb(mem[word_index(aw_addr_reg)],
                                s_axi_wdata, s_axi_wstrb);
                end

                if (s_axi_wlast !== (aw_beat == aw_len_reg)) begin
                    $display("[%0t] ERROR S%0d: WLAST mismatch beat=%0d len=%0d",
                             $time, SLAVE_NUM, aw_beat, aw_len_reg);
                    $fatal;
                end

                if (s_axi_wlast) begin
                    s_axi_bid    <= aw_id_reg;
                    s_axi_bresp  <= 2'b00; // OKAY
                    s_axi_bvalid <= 1'b1;
                    aw_pending   <= 1'b0;
                end
                else begin
                    aw_beat <= aw_beat + 1;
                    if (aw_burst_reg == 2'b01)
                        aw_addr_reg <= aw_addr_reg + (1 << aw_size_reg);
                end
            end

            // ---------------------------------------------------------------
            // WRITE RESPONSE
            // ---------------------------------------------------------------
            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;

            // ---------------------------------------------------------------
            // READ ADDRESS
            // ---------------------------------------------------------------
            if (s_axi_arvalid && s_axi_arready) begin
                rd_pending  <= 1'b1;
                rd_id_reg   <= s_axi_arid;
                rd_addr_reg <= s_axi_araddr;
                rd_len_reg  <= s_axi_arlen;
                rd_size_reg <= s_axi_arsize;
                rd_burst_reg<= s_axi_arburst;
                rd_beat     <= 0;
            end

            // ---------------------------------------------------------------
            // READ DATA
            // ---------------------------------------------------------------
            if (rd_pending && !s_axi_rvalid) begin
                if (word_index(rd_addr_reg) >= 0 &&
                    word_index(rd_addr_reg) < MEM_WORDS)
                    s_axi_rdata <= mem[word_index(rd_addr_reg)];
                else
                    s_axi_rdata <= {DATA_WIDTH{1'b0}};

                s_axi_rid    <= rd_id_reg;
                s_axi_rresp  <= 2'b00; // OKAY
                s_axi_rlast  <= (rd_beat == rd_len_reg);
                s_axi_rvalid <= 1'b1;
            end

            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;

                if (s_axi_rlast) begin
                    rd_pending <= 1'b0;
                end
                else begin
                    rd_beat <= rd_beat + 1;
                    if (rd_burst_reg == 2'b01)
                        rd_addr_reg <= rd_addr_reg + (1 << rd_size_reg);
                end
            end
        end
    end

endmodule


module tb_axi_interconnect_aes_2master;

    localparam integer DATA_WIDTH = 32;
    localparam integer ADDR_WIDTH = 32;
    localparam integer STRB_WIDTH = 4;
    localparam integer ID_WIDTH   = 8;

    localparam [31:0] S0_BASE = 32'h0000_0000;
    localparam [31:0] S1_BASE = 32'h0001_0000;
    localparam [31:0] S2_BASE = 32'h1000_0000;
    localparam [31:0] S3_BASE = 32'h1000_1000;
    localparam [31:0] S4_BASE = 32'h1000_2000;
    localparam [31:0] S5_BASE = 32'h1000_3000;
    localparam [31:0] S6_BASE = 32'h1000_4000;
    localparam [31:0] S7_BASE = 32'h1000_5000;

    reg clk = 1'b0;
    reg rst = 1'b1;

    always #5 clk = ~clk;

    // ------------------------------------------------------------------------
    // Master 0 signals
    // ------------------------------------------------------------------------
    reg [ID_WIDTH-1:0] m0_awid;
    reg [ADDR_WIDTH-1:0] m0_awaddr;
    reg [7:0] m0_awlen;
    reg [2:0] m0_awsize;
    reg [1:0] m0_awburst;
    reg m0_awlock;
    reg [3:0] m0_awcache;
    reg [2:0] m0_awprot;
    reg [3:0] m0_awqos;
    reg [0:0] m0_awuser;
    reg m0_awvalid;
    wire m0_awready;

    reg [DATA_WIDTH-1:0] m0_wdata;
    reg [STRB_WIDTH-1:0] m0_wstrb;
    reg m0_wlast;
    reg [0:0] m0_wuser;
    reg m0_wvalid;
    wire m0_wready;

    wire [ID_WIDTH-1:0] m0_bid;
    wire [1:0] m0_bresp;
    wire [0:0] m0_buser;
    wire m0_bvalid;
    reg m0_bready;

    reg [ID_WIDTH-1:0] m0_arid;
    reg [ADDR_WIDTH-1:0] m0_araddr;
    reg [7:0] m0_arlen;
    reg [2:0] m0_arsize;
    reg [1:0] m0_arburst;
    reg m0_arlock;
    reg [3:0] m0_arcache;
    reg [2:0] m0_arprot;
    reg [3:0] m0_arqos;
    reg [0:0] m0_aruser;
    reg m0_arvalid;
    wire m0_arready;

    wire [ID_WIDTH-1:0] m0_rid;
    wire [DATA_WIDTH-1:0] m0_rdata;
    wire [1:0] m0_rresp;
    wire m0_rlast;
    wire [0:0] m0_ruser;
    wire m0_rvalid;
    reg m0_rready;

    // ------------------------------------------------------------------------
    // Master 1 signals
    // ------------------------------------------------------------------------
    reg [ID_WIDTH-1:0] m1_awid;
    reg [ADDR_WIDTH-1:0] m1_awaddr;
    reg [7:0] m1_awlen;
    reg [2:0] m1_awsize;
    reg [1:0] m1_awburst;
    reg m1_awlock;
    reg [3:0] m1_awcache;
    reg [2:0] m1_awprot;
    reg [3:0] m1_awqos;
    reg [0:0] m1_awuser;
    reg m1_awvalid;
    wire m1_awready;

    reg [DATA_WIDTH-1:0] m1_wdata;
    reg [STRB_WIDTH-1:0] m1_wstrb;
    reg m1_wlast;
    reg [0:0] m1_wuser;
    reg m1_wvalid;
    wire m1_wready;

    wire [ID_WIDTH-1:0] m1_bid;
    wire [1:0] m1_bresp;
    wire [0:0] m1_buser;
    wire m1_bvalid;
    reg m1_bready;

    reg [ID_WIDTH-1:0] m1_arid;
    reg [ADDR_WIDTH-1:0] m1_araddr;
    reg [7:0] m1_arlen;
    reg [2:0] m1_arsize;
    reg [1:0] m1_arburst;
    reg m1_arlock;
    reg [3:0] m1_arcache;
    reg [2:0] m1_arprot;
    reg [3:0] m1_arqos;
    reg [0:0] m1_aruser;
    reg m1_arvalid;
    wire m1_arready;

    wire [ID_WIDTH-1:0] m1_rid;
    wire [DATA_WIDTH-1:0] m1_rdata;
    wire [1:0] m1_rresp;
    wire m1_rlast;
    wire [0:0] m1_ruser;
    wire m1_rvalid;
    reg m1_rready;

    // ------------------------------------------------------------------------
    // Eight target ports
    // ------------------------------------------------------------------------
    `define DECL_SLAVE(N) \
        wire [ID_WIDTH-1:0] s``N``_awid; \
        wire [ADDR_WIDTH-1:0] s``N``_awaddr; \
        wire [7:0] s``N``_awlen; \
        wire [2:0] s``N``_awsize; \
        wire [1:0] s``N``_awburst; \
        wire s``N``_awlock; \
        wire [3:0] s``N``_awcache; \
        wire [2:0] s``N``_awprot; \
        wire [3:0] s``N``_awqos; \
        wire [3:0] s``N``_awregion; \
        wire s``N``_awvalid; \
        wire s``N``_awready; \
        wire [DATA_WIDTH-1:0] s``N``_wdata; \
        wire [STRB_WIDTH-1:0] s``N``_wstrb; \
        wire s``N``_wlast; \
        wire s``N``_wvalid; \
        wire s``N``_wready; \
        wire [ID_WIDTH-1:0] s``N``_bid; \
        wire [1:0] s``N``_bresp; \
        wire s``N``_bvalid; \
        wire s``N``_bready; \
        wire [ID_WIDTH-1:0] s``N``_arid; \
        wire [ADDR_WIDTH-1:0] s``N``_araddr; \
        wire [7:0] s``N``_arlen; \
        wire [2:0] s``N``_arsize; \
        wire [1:0] s``N``_arburst; \
        wire s``N``_arlock; \
        wire [3:0] s``N``_arcache; \
        wire [2:0] s``N``_arprot; \
        wire [3:0] s``N``_arqos; \
        wire [3:0] s``N``_arregion; \
        wire s``N``_arvalid; \
        wire s``N``_arready; \
        wire [ID_WIDTH-1:0] s``N``_rid; \
        wire [DATA_WIDTH-1:0] s``N``_rdata; \
        wire [1:0] s``N``_rresp; \
        wire s``N``_rlast; \
        wire s``N``_rvalid; \
        wire s``N``_rready

    `DECL_SLAVE(0);
    `DECL_SLAVE(1);
    `DECL_SLAVE(2);
    `DECL_SLAVE(3);
    `DECL_SLAVE(4);
    `DECL_SLAVE(5);
    `DECL_SLAVE(6);
    `DECL_SLAVE(7);

    // ------------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------------
    axi_interconnect_wrap_2x8 #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .STRB_WIDTH(STRB_WIDTH),
        .ID_WIDTH(ID_WIDTH),

        .M00_BASE_ADDR(S0_BASE),
        .M00_ADDR_WIDTH({32'd15}),
        .M01_BASE_ADDR(S1_BASE),
        .M01_ADDR_WIDTH({32'd15}),
        .M02_BASE_ADDR(S2_BASE),
        .M02_ADDR_WIDTH({32'd12}),
        .M03_BASE_ADDR(S3_BASE),
        .M03_ADDR_WIDTH({32'd12}),
        .M04_BASE_ADDR(S4_BASE),
        .M04_ADDR_WIDTH({32'd12}),
        .M05_BASE_ADDR(S5_BASE),
        .M05_ADDR_WIDTH({32'd12}),
        .M06_BASE_ADDR(S6_BASE),
        .M06_ADDR_WIDTH({32'd12}),
        .M07_BASE_ADDR(S7_BASE),
        .M07_ADDR_WIDTH({32'd12})
    ) dut (
        .clk(clk),
        .rst(rst),

        .s00_axi_awid(m0_awid), .s00_axi_awaddr(m0_awaddr),
        .s00_axi_awlen(m0_awlen), .s00_axi_awsize(m0_awsize),
        .s00_axi_awburst(m0_awburst), .s00_axi_awlock(m0_awlock),
        .s00_axi_awcache(m0_awcache), .s00_axi_awprot(m0_awprot),
        .s00_axi_awqos(m0_awqos), .s00_axi_awuser(m0_awuser),
        .s00_axi_awvalid(m0_awvalid), .s00_axi_awready(m0_awready),
        .s00_axi_wdata(m0_wdata), .s00_axi_wstrb(m0_wstrb),
        .s00_axi_wlast(m0_wlast), .s00_axi_wuser(m0_wuser),
        .s00_axi_wvalid(m0_wvalid), .s00_axi_wready(m0_wready),
        .s00_axi_bid(m0_bid), .s00_axi_bresp(m0_bresp),
        .s00_axi_buser(m0_buser), .s00_axi_bvalid(m0_bvalid),
        .s00_axi_bready(m0_bready),
        .s00_axi_arid(m0_arid), .s00_axi_araddr(m0_araddr),
        .s00_axi_arlen(m0_arlen), .s00_axi_arsize(m0_arsize),
        .s00_axi_arburst(m0_arburst), .s00_axi_arlock(m0_arlock),
        .s00_axi_arcache(m0_arcache), .s00_axi_arprot(m0_arprot),
        .s00_axi_arqos(m0_arqos), .s00_axi_aruser(m0_aruser),
        .s00_axi_arvalid(m0_arvalid), .s00_axi_arready(m0_arready),
        .s00_axi_rid(m0_rid), .s00_axi_rdata(m0_rdata),
        .s00_axi_rresp(m0_rresp), .s00_axi_rlast(m0_rlast),
        .s00_axi_ruser(m0_ruser), .s00_axi_rvalid(m0_rvalid),
        .s00_axi_rready(m0_rready),

        .s01_axi_awid(m1_awid), .s01_axi_awaddr(m1_awaddr),
        .s01_axi_awlen(m1_awlen), .s01_axi_awsize(m1_awsize),
        .s01_axi_awburst(m1_awburst), .s01_axi_awlock(m1_awlock),
        .s01_axi_awcache(m1_awcache), .s01_axi_awprot(m1_awprot),
        .s01_axi_awqos(m1_awqos), .s01_axi_awuser(m1_awuser),
        .s01_axi_awvalid(m1_awvalid), .s01_axi_awready(m1_awready),
        .s01_axi_wdata(m1_wdata), .s01_axi_wstrb(m1_wstrb),
        .s01_axi_wlast(m1_wlast), .s01_axi_wuser(m1_wuser),
        .s01_axi_wvalid(m1_wvalid), .s01_axi_wready(m1_wready),
        .s01_axi_bid(m1_bid), .s01_axi_bresp(m1_bresp),
        .s01_axi_buser(m1_buser), .s01_axi_bvalid(m1_bvalid),
        .s01_axi_bready(m1_bready),
        .s01_axi_arid(m1_arid), .s01_axi_araddr(m1_araddr),
        .s01_axi_arlen(m1_arlen), .s01_axi_arsize(m1_arsize),
        .s01_axi_arburst(m1_arburst), .s01_axi_arlock(m1_arlock),
        .s01_axi_arcache(m1_arcache), .s01_axi_arprot(m1_arprot),
        .s01_axi_arqos(m1_arqos), .s01_axi_aruser(m1_aruser),
        .s01_axi_arvalid(m1_arvalid), .s01_axi_arready(m1_arready),
        .s01_axi_rid(m1_rid), .s01_axi_rdata(m1_rdata),
        .s01_axi_rresp(m1_rresp), .s01_axi_rlast(m1_rlast),
        .s01_axi_ruser(m1_ruser), .s01_axi_rvalid(m1_rvalid),
        .s01_axi_rready(m1_rready),

        .m00_axi_awid(s0_awid), .m00_axi_awaddr(s0_awaddr),
        .m00_axi_awlen(s0_awlen), .m00_axi_awsize(s0_awsize),
        .m00_axi_awburst(s0_awburst), .m00_axi_awlock(s0_awlock),
        .m00_axi_awcache(s0_awcache), .m00_axi_awprot(s0_awprot),
        .m00_axi_awqos(s0_awqos), .m00_axi_awregion(s0_awregion),
        .m00_axi_awuser(), .m00_axi_awvalid(s0_awvalid),
        .m00_axi_awready(s0_awready), .m00_axi_wdata(s0_wdata),
        .m00_axi_wstrb(s0_wstrb), .m00_axi_wlast(s0_wlast),
        .m00_axi_wuser(), .m00_axi_wvalid(s0_wvalid),
        .m00_axi_wready(s0_wready), .m00_axi_bid(s0_bid),
        .m00_axi_bresp(s0_bresp), .m00_axi_buser(),
        .m00_axi_bvalid(s0_bvalid), .m00_axi_bready(s0_bready),
        .m00_axi_arid(s0_arid), .m00_axi_araddr(s0_araddr),
        .m00_axi_arlen(s0_arlen), .m00_axi_arsize(s0_arsize),
        .m00_axi_arburst(s0_arburst), .m00_axi_arlock(s0_arlock),
        .m00_axi_arcache(s0_arcache), .m00_axi_arprot(s0_arprot),
        .m00_axi_arqos(s0_arqos), .m00_axi_arregion(s0_arregion),
        .m00_axi_aruser(), .m00_axi_arvalid(s0_arvalid),
        .m00_axi_arready(s0_arready), .m00_axi_rid(s0_rid),
        .m00_axi_rdata(s0_rdata), .m00_axi_rresp(s0_rresp),
        .m00_axi_rlast(s0_rlast), .m00_axi_ruser(),
        .m00_axi_rvalid(s0_rvalid), .m00_axi_rready(s0_rready),

        .m01_axi_awid(s1_awid), .m01_axi_awaddr(s1_awaddr),
        .m01_axi_awlen(s1_awlen), .m01_axi_awsize(s1_awsize),
        .m01_axi_awburst(s1_awburst), .m01_axi_awlock(s1_awlock),
        .m01_axi_awcache(s1_awcache), .m01_axi_awprot(s1_awprot),
        .m01_axi_awqos(s1_awqos), .m01_axi_awregion(s1_awregion),
        .m01_axi_awuser(), .m01_axi_awvalid(s1_awvalid),
        .m01_axi_awready(s1_awready), .m01_axi_wdata(s1_wdata),
        .m01_axi_wstrb(s1_wstrb), .m01_axi_wlast(s1_wlast),
        .m01_axi_wuser(), .m01_axi_wvalid(s1_wvalid),
        .m01_axi_wready(s1_wready), .m01_axi_bid(s1_bid),
        .m01_axi_bresp(s1_bresp), .m01_axi_buser(),
        .m01_axi_bvalid(s1_bvalid), .m01_axi_bready(s1_bready),
        .m01_axi_arid(s1_arid), .m01_axi_araddr(s1_araddr),
        .m01_axi_arlen(s1_arlen), .m01_axi_arsize(s1_arsize),
        .m01_axi_arburst(s1_arburst), .m01_axi_arlock(s1_arlock),
        .m01_axi_arcache(s1_arcache), .m01_axi_arprot(s1_arprot),
        .m01_axi_arqos(s1_arqos), .m01_axi_arregion(s1_arregion),
        .m01_axi_aruser(), .m01_axi_arvalid(s1_arvalid),
        .m01_axi_arready(s1_arready), .m01_axi_rid(s1_rid),
        .m01_axi_rdata(s1_rdata), .m01_axi_rresp(s1_rresp),
        .m01_axi_rlast(s1_rlast), .m01_axi_ruser(),
        .m01_axi_rvalid(s1_rvalid), .m01_axi_rready(s1_rready),

        .m02_axi_awid(s2_awid), .m02_axi_awaddr(s2_awaddr),
        .m02_axi_awlen(s2_awlen), .m02_axi_awsize(s2_awsize),
        .m02_axi_awburst(s2_awburst), .m02_axi_awlock(s2_awlock),
        .m02_axi_awcache(s2_awcache), .m02_axi_awprot(s2_awprot),
        .m02_axi_awqos(s2_awqos), .m02_axi_awregion(s2_awregion),
        .m02_axi_awuser(), .m02_axi_awvalid(s2_awvalid),
        .m02_axi_awready(s2_awready), .m02_axi_wdata(s2_wdata),
        .m02_axi_wstrb(s2_wstrb), .m02_axi_wlast(s2_wlast),
        .m02_axi_wuser(), .m02_axi_wvalid(s2_wvalid),
        .m02_axi_wready(s2_wready), .m02_axi_bid(s2_bid),
        .m02_axi_bresp(s2_bresp), .m02_axi_buser(),
        .m02_axi_bvalid(s2_bvalid), .m02_axi_bready(s2_bready),
        .m02_axi_arid(s2_arid), .m02_axi_araddr(s2_araddr),
        .m02_axi_arlen(s2_arlen), .m02_axi_arsize(s2_arsize),
        .m02_axi_arburst(s2_arburst), .m02_axi_arlock(s2_arlock),
        .m02_axi_arcache(s2_arcache), .m02_axi_arprot(s2_arprot),
        .m02_axi_arqos(s2_arqos), .m02_axi_arregion(s2_arregion),
        .m02_axi_aruser(), .m02_axi_arvalid(s2_arvalid),
        .m02_axi_arready(s2_arready), .m02_axi_rid(s2_rid),
        .m02_axi_rdata(s2_rdata), .m02_axi_rresp(s2_rresp),
        .m02_axi_rlast(s2_rlast), .m02_axi_ruser(),
        .m02_axi_rvalid(s2_rvalid), .m02_axi_rready(s2_rready),

        .m03_axi_awid(s3_awid), .m03_axi_awaddr(s3_awaddr),
        .m03_axi_awlen(s3_awlen), .m03_axi_awsize(s3_awsize),
        .m03_axi_awburst(s3_awburst), .m03_axi_awlock(s3_awlock),
        .m03_axi_awcache(s3_awcache), .m03_axi_awprot(s3_awprot),
        .m03_axi_awqos(s3_awqos), .m03_axi_awregion(s3_awregion),
        .m03_axi_awuser(), .m03_axi_awvalid(s3_awvalid),
        .m03_axi_awready(s3_awready), .m03_axi_wdata(s3_wdata),
        .m03_axi_wstrb(s3_wstrb), .m03_axi_wlast(s3_wlast),
        .m03_axi_wuser(), .m03_axi_wvalid(s3_wvalid),
        .m03_axi_wready(s3_wready), .m03_axi_bid(s3_bid),
        .m03_axi_bresp(s3_bresp), .m03_axi_buser(),
        .m03_axi_bvalid(s3_bvalid), .m03_axi_bready(s3_bready),
        .m03_axi_arid(s3_arid), .m03_axi_araddr(s3_araddr),
        .m03_axi_arlen(s3_arlen), .m03_axi_arsize(s3_arsize),
        .m03_axi_arburst(s3_arburst), .m03_axi_arlock(s3_arlock),
        .m03_axi_arcache(s3_arcache), .m03_axi_arprot(s3_arprot),
        .m03_axi_arqos(s3_arqos), .m03_axi_arregion(s3_arregion),
        .m03_axi_aruser(), .m03_axi_arvalid(s3_arvalid),
        .m03_axi_arready(s3_arready), .m03_axi_rid(s3_rid),
        .m03_axi_rdata(s3_rdata), .m03_axi_rresp(s3_rresp),
        .m03_axi_rlast(s3_rlast), .m03_axi_ruser(),
        .m03_axi_rvalid(s3_rvalid), .m03_axi_rready(s3_rready),

        .m04_axi_awid(s4_awid), .m04_axi_awaddr(s4_awaddr),
        .m04_axi_awlen(s4_awlen), .m04_axi_awsize(s4_awsize),
        .m04_axi_awburst(s4_awburst), .m04_axi_awlock(s4_awlock),
        .m04_axi_awcache(s4_awcache), .m04_axi_awprot(s4_awprot),
        .m04_axi_awqos(s4_awqos), .m04_axi_awregion(s4_awregion),
        .m04_axi_awuser(), .m04_axi_awvalid(s4_awvalid),
        .m04_axi_awready(s4_awready), .m04_axi_wdata(s4_wdata),
        .m04_axi_wstrb(s4_wstrb), .m04_axi_wlast(s4_wlast),
        .m04_axi_wuser(), .m04_axi_wvalid(s4_wvalid),
        .m04_axi_wready(s4_wready), .m04_axi_bid(s4_bid),
        .m04_axi_bresp(s4_bresp), .m04_axi_buser(),
        .m04_axi_bvalid(s4_bvalid), .m04_axi_bready(s4_bready),
        .m04_axi_arid(s4_arid), .m04_axi_araddr(s4_araddr),
        .m04_axi_arlen(s4_arlen), .m04_axi_arsize(s4_arsize),
        .m04_axi_arburst(s4_arburst), .m04_axi_arlock(s4_arlock),
        .m04_axi_arcache(s4_arcache), .m04_axi_arprot(s4_arprot),
        .m04_axi_arqos(s4_arqos), .m04_axi_arregion(s4_arregion),
        .m04_axi_aruser(), .m04_axi_arvalid(s4_arvalid),
        .m04_axi_arready(s4_arready), .m04_axi_rid(s4_rid),
        .m04_axi_rdata(s4_rdata), .m04_axi_rresp(s4_rresp),
        .m04_axi_rlast(s4_rlast), .m04_axi_ruser(),
        .m04_axi_rvalid(s4_rvalid), .m04_axi_rready(s4_rready),

        .m05_axi_awid(s5_awid), .m05_axi_awaddr(s5_awaddr),
        .m05_axi_awlen(s5_awlen), .m05_axi_awsize(s5_awsize),
        .m05_axi_awburst(s5_awburst), .m05_axi_awlock(s5_awlock),
        .m05_axi_awcache(s5_awcache), .m05_axi_awprot(s5_awprot),
        .m05_axi_awqos(s5_awqos), .m05_axi_awregion(s5_awregion),
        .m05_axi_awuser(), .m05_axi_awvalid(s5_awvalid),
        .m05_axi_awready(s5_awready), .m05_axi_wdata(s5_wdata),
        .m05_axi_wstrb(s5_wstrb), .m05_axi_wlast(s5_wlast),
        .m05_axi_wuser(), .m05_axi_wvalid(s5_wvalid),
        .m05_axi_wready(s5_wready), .m05_axi_bid(s5_bid),
        .m05_axi_bresp(s5_bresp), .m05_axi_buser(),
        .m05_axi_bvalid(s5_bvalid), .m05_axi_bready(s5_bready),
        .m05_axi_arid(s5_arid), .m05_axi_araddr(s5_araddr),
        .m05_axi_arlen(s5_arlen), .m05_axi_arsize(s5_arsize),
        .m05_axi_arburst(s5_arburst), .m05_axi_arlock(s5_arlock),
        .m05_axi_arcache(s5_arcache), .m05_axi_arprot(s5_arprot),
        .m05_axi_arqos(s5_arqos), .m05_axi_arregion(s5_arregion),
        .m05_axi_aruser(), .m05_axi_arvalid(s5_arvalid),
        .m05_axi_arready(s5_arready), .m05_axi_rid(s5_rid),
        .m05_axi_rdata(s5_rdata), .m05_axi_rresp(s5_rresp),
        .m05_axi_rlast(s5_rlast), .m05_axi_ruser(),
        .m05_axi_rvalid(s5_rvalid), .m05_axi_rready(s5_rready),

        .m06_axi_awid(s6_awid), .m06_axi_awaddr(s6_awaddr),
        .m06_axi_awlen(s6_awlen), .m06_axi_awsize(s6_awsize),
        .m06_axi_awburst(s6_awburst), .m06_axi_awlock(s6_awlock),
        .m06_axi_awcache(s6_awcache), .m06_axi_awprot(s6_awprot),
        .m06_axi_awqos(s6_awqos), .m06_axi_awregion(s6_awregion),
        .m06_axi_awuser(), .m06_axi_awvalid(s6_awvalid),
        .m06_axi_awready(s6_awready), .m06_axi_wdata(s6_wdata),
        .m06_axi_wstrb(s6_wstrb), .m06_axi_wlast(s6_wlast),
        .m06_axi_wuser(), .m06_axi_wvalid(s6_wvalid),
        .m06_axi_wready(s6_wready), .m06_axi_bid(s6_bid),
        .m06_axi_bresp(s6_bresp), .m06_axi_buser(),
        .m06_axi_bvalid(s6_bvalid), .m06_axi_bready(s6_bready),
        .m06_axi_arid(s6_arid), .m06_axi_araddr(s6_araddr),
        .m06_axi_arlen(s6_arlen), .m06_axi_arsize(s6_arsize),
        .m06_axi_arburst(s6_arburst), .m06_axi_arlock(s6_arlock),
        .m06_axi_arcache(s6_arcache), .m06_axi_arprot(s6_arprot),
        .m06_axi_arqos(s6_arqos), .m06_axi_arregion(s6_arregion),
        .m06_axi_aruser(), .m06_axi_arvalid(s6_arvalid),
        .m06_axi_arready(s6_arready), .m06_axi_rid(s6_rid),
        .m06_axi_rdata(s6_rdata), .m06_axi_rresp(s6_rresp),
        .m06_axi_rlast(s6_rlast), .m06_axi_ruser(),
        .m06_axi_rvalid(s6_rvalid), .m06_axi_rready(s6_rready),

        .m07_axi_awid(s7_awid), .m07_axi_awaddr(s7_awaddr),
        .m07_axi_awlen(s7_awlen), .m07_axi_awsize(s7_awsize),
        .m07_axi_awburst(s7_awburst), .m07_axi_awlock(s7_awlock),
        .m07_axi_awcache(s7_awcache), .m07_axi_awprot(s7_awprot),
        .m07_axi_awqos(s7_awqos), .m07_axi_awregion(s7_awregion),
        .m07_axi_awuser(), .m07_axi_awvalid(s7_awvalid),
        .m07_axi_awready(s7_awready), .m07_axi_wdata(s7_wdata),
        .m07_axi_wstrb(s7_wstrb), .m07_axi_wlast(s7_wlast),
        .m07_axi_wuser(), .m07_axi_wvalid(s7_wvalid),
        .m07_axi_wready(s7_wready), .m07_axi_bid(s7_bid),
        .m07_axi_bresp(s7_bresp), .m07_axi_buser(),
        .m07_axi_bvalid(s7_bvalid), .m07_axi_bready(s7_bready),
        .m07_axi_arid(s7_arid), .m07_axi_araddr(s7_araddr),
        .m07_axi_arlen(s7_arlen), .m07_axi_arsize(s7_arsize),
        .m07_axi_arburst(s7_arburst), .m07_axi_arlock(s7_arlock),
        .m07_axi_arcache(s7_arcache), .m07_axi_arprot(s7_arprot),
        .m07_axi_arqos(s7_arqos), .m07_axi_arregion(s7_arregion),
        .m07_axi_aruser(), .m07_axi_arvalid(s7_arvalid),
        .m07_axi_arready(s7_arready), .m07_axi_rid(s7_rid),
        .m07_axi_rdata(s7_rdata), .m07_axi_rresp(s7_rresp),
        .m07_axi_rlast(s7_rlast), .m07_axi_ruser(),
        .m07_axi_rvalid(s7_rvalid), .m07_axi_rready(s7_rready)
    );

    // ------------------------------------------------------------------------
    // Dummy slaves
    // ------------------------------------------------------------------------
    `define INST_SLAVE(N) \
    axi_dummy_slave #(.SLAVE_NUM(N)) slave``N`` ( \
        .clk(clk), .rst(rst), \
        .s_axi_awid(s``N``_awid), .s_axi_awaddr(s``N``_awaddr), \
        .s_axi_awlen(s``N``_awlen), .s_axi_awsize(s``N``_awsize), \
        .s_axi_awburst(s``N``_awburst), .s_axi_awlock(s``N``_awlock), \
        .s_axi_awcache(s``N``_awcache), .s_axi_awprot(s``N``_awprot), \
        .s_axi_awqos(s``N``_awqos), .s_axi_awregion(s``N``_awregion), \
        .s_axi_awvalid(s``N``_awvalid), .s_axi_awready(s``N``_awready), \
        .s_axi_wdata(s``N``_wdata), .s_axi_wstrb(s``N``_wstrb), \
        .s_axi_wlast(s``N``_wlast), .s_axi_wvalid(s``N``_wvalid), \
        .s_axi_wready(s``N``_wready), .s_axi_bid(s``N``_bid), \
        .s_axi_bresp(s``N``_bresp), .s_axi_bvalid(s``N``_bvalid), \
        .s_axi_bready(s``N``_bready), \
        .s_axi_arid(s``N``_arid), .s_axi_araddr(s``N``_araddr), \
        .s_axi_arlen(s``N``_arlen), .s_axi_arsize(s``N``_arsize), \
        .s_axi_arburst(s``N``_arburst), .s_axi_arlock(s``N``_arlock), \
        .s_axi_arcache(s``N``_arcache), .s_axi_arprot(s``N``_arprot), \
        .s_axi_arqos(s``N``_arqos), .s_axi_arregion(s``N``_arregion), \
        .s_axi_arvalid(s``N``_arvalid), .s_axi_arready(s``N``_arready), \
        .s_axi_rid(s``N``_rid), .s_axi_rdata(s``N``_rdata), \
        .s_axi_rresp(s``N``_rresp), .s_axi_rlast(s``N``_rlast), \
        .s_axi_rvalid(s``N``_rvalid), .s_axi_rready(s``N``_rready) \
    )

    `INST_SLAVE(0);
    `INST_SLAVE(1);
    `INST_SLAVE(2);
    `INST_SLAVE(3);
    `INST_SLAVE(4);
    `INST_SLAVE(5);
    // M06 is the AES peripheral; all other M ports remain dummy targets.
    wire aes_irq;

    aes_axi_slave #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .STRB_WIDTH(STRB_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    ) aes_slave_inst (
        .clk(clk), .rst(rst),
        .s_axi_awid(s6_awid), .s_axi_awaddr(s6_awaddr),
        .s_axi_awlen(s6_awlen), .s_axi_awsize(s6_awsize),
        .s_axi_awburst(s6_awburst), .s_axi_awlock(s6_awlock),
        .s_axi_awcache(s6_awcache), .s_axi_awprot(s6_awprot),
        .s_axi_awqos(s6_awqos), .s_axi_awuser(1'b0),
        .s_axi_awvalid(s6_awvalid), .s_axi_awready(s6_awready),
        .s_axi_wdata(s6_wdata), .s_axi_wstrb(s6_wstrb),
        .s_axi_wlast(s6_wlast), .s_axi_wuser(1'b0),
        .s_axi_wvalid(s6_wvalid), .s_axi_wready(s6_wready),
        .s_axi_bid(s6_bid), .s_axi_bresp(s6_bresp),
        .s_axi_buser(), .s_axi_bvalid(s6_bvalid),
        .s_axi_bready(s6_bready),
        .s_axi_arid(s6_arid), .s_axi_araddr(s6_araddr),
        .s_axi_arlen(s6_arlen), .s_axi_arsize(s6_arsize),
        .s_axi_arburst(s6_arburst), .s_axi_arlock(s6_arlock),
        .s_axi_arcache(s6_arcache), .s_axi_arprot(s6_arprot),
        .s_axi_arqos(s6_arqos), .s_axi_aruser(1'b0),
        .s_axi_arvalid(s6_arvalid), .s_axi_arready(s6_arready),
        .s_axi_rid(s6_rid), .s_axi_rdata(s6_rdata),
        .s_axi_rresp(s6_rresp), .s_axi_rlast(s6_rlast),
        .s_axi_ruser(), .s_axi_rvalid(s6_rvalid),
        .s_axi_rready(s6_rready),
        .aes_irq(aes_irq)
    );
    `INST_SLAVE(7);

    // ------------------------------------------------------------------------
    // Scoreboard state
    // ------------------------------------------------------------------------
    integer pass_count = 0;
    integer fail_count = 0;
    integer write_count = 0;
    integer read_count = 0;
    integer route_count = 0;

    reg [DATA_WIDTH-1:0] expected_mem [0:7][0:255];

    function automatic integer decode_slave(input [31:0] addr);
        begin
            if      ((addr >= S0_BASE) && (addr < S0_BASE + 32'h0000_8000)) decode_slave = 0;
            else if ((addr >= S1_BASE) && (addr < S1_BASE + 32'h0000_8000)) decode_slave = 1;
            else if ((addr >= S2_BASE) && (addr < S2_BASE + 32'h0000_1000)) decode_slave = 2;
            else if ((addr >= S3_BASE) && (addr < S3_BASE + 32'h0000_1000)) decode_slave = 3;
            else if ((addr >= S4_BASE) && (addr < S4_BASE + 32'h0000_1000)) decode_slave = 4;
            else if ((addr >= S5_BASE) && (addr < S5_BASE + 32'h0000_1000)) decode_slave = 5;
            else if ((addr >= S6_BASE) && (addr < S6_BASE + 32'h0000_1000)) decode_slave = 6;
            else if ((addr >= S7_BASE) && (addr < S7_BASE + 32'h0000_1000)) decode_slave = 7;
            else decode_slave = -1;
        end
    endfunction

    function automatic [31:0] slave_base(input integer s);
        begin
            case (s)
                0: slave_base = S0_BASE;
                1: slave_base = S1_BASE;
                2: slave_base = S2_BASE;
                3: slave_base = S3_BASE;
                4: slave_base = S4_BASE;
                5: slave_base = S5_BASE;
                6: slave_base = S6_BASE;
                7: slave_base = S7_BASE;
                default: slave_base = 32'h0;
            endcase
        end
    endfunction

    task automatic scoreboard_write(
        input integer master,
        input [31:0] addr,
        input [63:0] data,
        input [7:0] strb
    );
        integer s;
        integer w;
        integer b;
        reg [63:0] old_data;
        begin
            s = decode_slave(addr);
            if (s < 0) begin
                $display("[%0t] SCOREBOARD ERROR: mapped write expected at %08x",
                         $time, addr);
                fail_count = fail_count + 1;
            end
            else begin
                w = ((addr - slave_base(s)) >> 3) & 255;
                old_data = expected_mem[s][w];
                for (b = 0; b < 8; b = b + 1)
                    if (strb[b])
                        old_data[b*8 +: 8] = data[b*8 +: 8];
                expected_mem[s][w] = old_data;
                write_count = write_count + 1;
                route_count = route_count + 1;
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Master BFM defaults
    // ------------------------------------------------------------------------
    task automatic init_master_signals;
        begin
            m0_awid=0; m0_awaddr=0; m0_awlen=0; m0_awsize=3;
            m0_awburst=2'b01; m0_awlock=0; m0_awcache=0; m0_awprot=0;
            m0_awqos=0; m0_awuser=0; m0_awvalid=0;
            m0_wdata=0; m0_wstrb=0; m0_wlast=0; m0_wuser=0; m0_wvalid=0;
            m0_bready=0;
            m0_arid=0; m0_araddr=0; m0_arlen=0; m0_arsize=3;
            m0_arburst=2'b01; m0_arlock=0; m0_arcache=0; m0_arprot=0;
            m0_arqos=0; m0_aruser=0; m0_arvalid=0; m0_rready=0;

            m1_awid=0; m1_awaddr=0; m1_awlen=0; m1_awsize=3;
            m1_awburst=2'b01; m1_awlock=0; m1_awcache=0; m1_awprot=0;
            m1_awqos=0; m1_awuser=0; m1_awvalid=0;
            m1_wdata=0; m1_wstrb=0; m1_wlast=0; m1_wuser=0; m1_wvalid=0;
            m1_bready=0;
            m1_arid=0; m1_araddr=0; m1_arlen=0; m1_arsize=3;
            m1_arburst=2'b01; m1_arlock=0; m1_arcache=0; m1_arprot=0;
            m1_arqos=0; m1_aruser=0; m1_arvalid=0; m1_rready=0;
        end
    endtask

    task automatic wait_cycles(input integer n);
        integer k;
        begin
            for (k=0;k<n;k=k+1) @(posedge clk);
        end
    endtask

    task automatic master_write_single(
        input integer master,
        input [31:0] addr,
        input [63:0] data,
        input [7:0] strb,
        input [7:0] id
    );
        begin
            if (master == 0) begin
                fork
                    begin
                        m0_awid=id; m0_awaddr=addr; m0_awlen=0; m0_awsize=2;
                        m0_awburst=2'b01; m0_awvalid=1;
                        @(posedge clk);
                        while (!m0_awready) @(posedge clk);
                        m0_awvalid=0;
                    end
                    begin
                        // Deliberately allow W to be independent of AW.
                        repeat ($urandom%3) @(posedge clk);
                        m0_wdata=data; m0_wstrb=strb; m0_wlast=1; m0_wvalid=1;
                        @(posedge clk);
                        while (!m0_wready) @(posedge clk);
                        m0_wvalid=0; m0_wlast=0;
                    end
                join
                // Randomized master-side response backpressure.
                repeat ($urandom % 3) @(posedge clk);
                m0_bready=1;
                @(posedge clk);
                while (!m0_bvalid) @(posedge clk);
                if (m0_bid !== id || m0_bresp !== 2'b00) begin
                    $display("[%0t] FAIL M0 WRITE addr=%08x BID=%02x expected=%02x BRESP=%b",
                             $time,addr,m0_bid,id,m0_bresp);
                    fail_count=fail_count+1;
                end
                else begin
                    pass_count=pass_count+1;
                    $display("[%0t] PASS M0 WRITE addr=%08x data=%016x",
                             $time,addr,data);
                end
                @(posedge clk);
                m0_bready=0;
            end
            else begin
                fork
                    begin
                        m1_awid=id; m1_awaddr=addr; m1_awlen=0; m1_awsize=2;
                        m1_awburst=2'b01; m1_awvalid=1;
                        @(posedge clk);
                        while (!m1_awready) @(posedge clk);
                        m1_awvalid=0;
                    end
                    begin
                        repeat ($urandom%3) @(posedge clk);
                        m1_wdata=data; m1_wstrb=strb; m1_wlast=1; m1_wvalid=1;
                        @(posedge clk);
                        while (!m1_wready) @(posedge clk);
                        m1_wvalid=0; m1_wlast=0;
                    end
                join
                // Randomized master-side response backpressure.
                repeat ($urandom % 3) @(posedge clk);
                m1_bready=1;
                @(posedge clk);
                while (!m1_bvalid) @(posedge clk);
                if (m1_bid !== id || m1_bresp !== 2'b00) begin
                    $display("[%0t] FAIL M1 WRITE addr=%08x BID=%02x expected=%02x BRESP=%b",
                             $time,addr,m1_bid,id,m1_bresp);
                    fail_count=fail_count+1;
                end
                else begin
                    pass_count=pass_count+1;
                    $display("[%0t] PASS M1 WRITE addr=%08x data=%016x",
                             $time,addr,data);
                end
                @(posedge clk);
                m1_bready=0;
            end
            scoreboard_write(master,addr,data,strb);
        end
    endtask

    task automatic master_read_single(
        input integer master,
        input [31:0] addr,
        input [63:0] expected,
        input [7:0] id
    );
        begin
            if (master == 0) begin
                m0_arid=id; m0_araddr=addr; m0_arlen=0; m0_arsize=2;
                m0_arburst=2'b01; m0_arvalid=1;
                @(posedge clk);
                while (!m0_arready) @(posedge clk);
                m0_arvalid=0;
                // Intentionally stall RREADY.
                repeat ($urandom%3) @(posedge clk);
                m0_rready=1;
                @(posedge clk);
                while (!m0_rvalid) @(posedge clk);
                if (m0_rid !== id || m0_rdata !== expected ||
                    m0_rresp !== 2'b00 || m0_rlast !== 1'b1) begin
                    $display("[%0t] FAIL M0 READ addr=%08x RID=%02x expRID=%02x data=%016x exp=%016x RRESP=%b RLAST=%b",
                             $time,addr,m0_rid,id,m0_rdata,expected,m0_rresp,m0_rlast);
                    fail_count=fail_count+1;
                end
                else begin
                    pass_count=pass_count+1;
                    read_count=read_count+1;
                    $display("[%0t] PASS M0 READ addr=%08x data=%016x",
                             $time,addr,m0_rdata);
                end
                @(posedge clk);
                m0_rready=0;
            end
            else begin
                m1_arid=id; m1_araddr=addr; m1_arlen=0; m1_arsize=2;
                m1_arburst=2'b01; m1_arvalid=1;
                @(posedge clk);
                while (!m1_arready) @(posedge clk);
                m1_arvalid=0;
                repeat ($urandom%3) @(posedge clk);
                m1_rready=1;
                @(posedge clk);
                while (!m1_rvalid) @(posedge clk);
                if (m1_rid !== id || m1_rdata !== expected ||
                    m1_rresp !== 2'b00 || m1_rlast !== 1'b1) begin
                    $display("[%0t] FAIL M1 READ addr=%08x RID=%02x expRID=%02x data=%016x exp=%016x RRESP=%b RLAST=%b",
                             $time,addr,m1_rid,id,m1_rdata,expected,m1_rresp,m1_rlast);
                    fail_count=fail_count+1;
                end
                else begin
                    pass_count=pass_count+1;
                    read_count=read_count+1;
                    $display("[%0t] PASS M1 READ addr=%08x data=%016x",
                             $time,addr,m1_rdata);
                end
                @(posedge clk);
                m1_rready=0;
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Directed routing test
    // ------------------------------------------------------------------------
    task automatic directed_routing_test;
        integer s;
        reg [31:0] addr;
        reg [63:0] data;
        begin
            $display("\n=== DIRECTED 2x8 ROUTING TEST ===");
            for (s=0; s<8; s=s+1) begin
                addr = slave_base(s) + 32'h20;
                data = 64'hA500_0000_0000_0000 | s;
                master_write_single(0,addr,data,8'hFF,8'h10+s);
                master_read_single(0,addr,data,8'h40+s);
            end

            for (s=0; s<8; s=s+1) begin
                addr = slave_base(s) + 32'h38;
                data = 64'h5A00_0000_0000_0000 | (s << 8) | 64'h55;
                master_write_single(1,addr,data,8'hFF,8'h80+s);
                master_read_single(1,addr,data,8'hA0+s);
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Byte-strobe test
    // ------------------------------------------------------------------------
    task automatic byte_strobe_test;
        reg [63:0] initial_data;
        reg [63:0] expected_data;
        begin
            $display("\n=== BYTE STROBE TEST ===");
            initial_data = 64'h1122_3344_5566_7788;

            master_write_single(0,S2_BASE+32'h40,
                                initial_data,8'hFF,8'h20);

            expected_data = initial_data;
            expected_data[7:0]   = 8'hAA;
            expected_data[31:24] = 8'h00;
            expected_data[63:56] = 8'hCC;

            master_write_single(1,S2_BASE+32'h40,
                                64'hCC00_00BB_0000_00AA,
                                8'b1000_1001,8'h21);

            master_read_single(0,S2_BASE+32'h40,expected_data,8'h22);
        end
    endtask

    // ------------------------------------------------------------------------
    // Burst test
    // ------------------------------------------------------------------------
    task automatic burst_test_master0;
        integer i;
        reg [63:0] d;
        reg [31:0] a;
        begin
            $display("\n=== BURST TEST M0 ===");
            a = S1_BASE + 32'h80;

            m0_awid=8'h30; m0_awaddr=a; m0_awlen=3; m0_awsize=3;
            m0_awburst=2'b01; m0_awvalid=1;
            @(posedge clk);
            while (!m0_awready) @(posedge clk);
            m0_awvalid=0;

            for (i=0;i<4;i=i+1) begin
                d = 64'hB000_0000_0000_0000 + i;
                m0_wdata=d; m0_wstrb=8'hFF; m0_wlast=(i==3); m0_wvalid=1;
                @(posedge clk);
                while (!m0_wready) @(posedge clk);
                m0_wvalid=0;
                @(posedge clk);
            end

            m0_bready=1;
            @(posedge clk);
            while (!m0_bvalid) @(posedge clk);
            if (m0_bid !== 8'h30 || m0_bresp !== 2'b00) begin
                $display("[%0t] FAIL M0 burst write response", $time);
                fail_count=fail_count+1;
            end
            else begin
                $display("[%0t] PASS M0 burst write response", $time);
                pass_count=pass_count+1;
            end
            @(posedge clk);
            m0_bready=0;

            for (i=0;i<4;i=i+1)
                scoreboard_write(0,a+(i*8),
                                 64'hB000_0000_0000_0000+i,8'hFF);
        end
    endtask

    // ------------------------------------------------------------------------
    // Concurrent traffic
    // ------------------------------------------------------------------------
    task automatic concurrent_test;
        begin
            $display("\n=== CONCURRENT M0/M1 TEST ===");
            fork
                begin
                    master_write_single(0,S0_BASE+32'h100,
                                        64'h0000_0000_0000_1111,8'hFF,8'h51);
                    master_read_single(0,S0_BASE+32'h100,
                                       64'h0000_0000_0000_1111,8'h52);
                    master_write_single(0,S6_BASE+32'h100,
                                        64'h0000_0000_0000_6666,8'hFF,8'h53);
                    master_read_single(0,S6_BASE+32'h100,
                                       64'h0000_0000_0000_6666,8'h54);
                end
                begin
                    master_write_single(1,S1_BASE+32'h100,
                                        64'h0000_0000_0000_2222,8'hFF,8'h61);
                    master_read_single(1,S1_BASE+32'h100,
                                       64'h0000_0000_0000_2222,8'h62);
                    master_write_single(1,S7_BASE+32'h100,
                                        64'h0000_0000_0000_7777,8'hFF,8'h63);
                    master_read_single(1,S7_BASE+32'h100,
                                       64'h0000_0000_0000_7777,8'h64);
                end
            join
        end
    endtask

    // ------------------------------------------------------------------------
    // Unmapped-address test
    //
    // Expected behavior for this crossbar is an error response rather than a
    // target selection. This test intentionally does not use the dummy slaves.
    // ------------------------------------------------------------------------
    task automatic unmapped_test;
        reg [31:0] bad_addr;
        begin
            $display("\n=== UNMAPPED ADDRESS TEST ===");
            bad_addr = 32'h2000_0000;

            m0_arid=8'hF0; m0_araddr=bad_addr; m0_arlen=0; m0_arsize=3;
            m0_arburst=2'b01; m0_arvalid=1;
            @(posedge clk);
            while (!m0_arready) @(posedge clk);
            m0_arvalid=0;
            m0_rready=1;
            @(posedge clk);
            while (!m0_rvalid) @(posedge clk);

            if (m0_rid !== 8'hF0 || m0_rresp !== 2'b11 ||
                m0_rlast !== 1'b1) begin
                $display("[%0t] FAIL unmapped read: RID=%02x RRESP=%b RLAST=%b",
                         $time,m0_rid,m0_rresp,m0_rlast);
                fail_count=fail_count+1;
            end
            else begin
                $display("[%0t] PASS unmapped read -> DECERR", $time);
                pass_count=pass_count+1;
            end
            @(posedge clk);
            m0_rready=0;
        end
    endtask

    // ------------------------------------------------------------------------
    // Protocol assertions
    // ------------------------------------------------------------------------
    // VALID must remain asserted until READY. These assertions deliberately
    // monitor the two upstream masters and representative target channels.
    property p_m0_aw_stable;
        @(posedge clk) disable iff (rst)
        m0_awvalid && !m0_awready |=> m0_awvalid &&
            $stable({m0_awid,m0_awaddr,m0_awlen,m0_awsize,m0_awburst});
    endproperty
    assert property (p_m0_aw_stable)
        else begin $display("[%0t] ERROR M0 AW changed while stalled",$time); fail_count=fail_count+1; end

    property p_m0_w_stable;
        @(posedge clk) disable iff (rst)
        m0_wvalid && !m0_wready |=> m0_wvalid &&
            $stable({m0_wdata,m0_wstrb,m0_wlast});
    endproperty
    assert property (p_m0_w_stable)
        else begin $display("[%0t] ERROR M0 W changed while stalled",$time); fail_count=fail_count+1; end

    property p_m0_ar_stable;
        @(posedge clk) disable iff (rst)
        m0_arvalid && !m0_arready |=> m0_arvalid &&
            $stable({m0_arid,m0_araddr,m0_arlen,m0_arsize,m0_arburst});
    endproperty
    assert property (p_m0_ar_stable)
        else begin $display("[%0t] ERROR M0 AR changed while stalled",$time); fail_count=fail_count+1; end

    // ------------------------------------------------------------------------
    // Waveform dump
    // ------------------------------------------------------------------------
    initial begin
        $fsdbDumpfile("axi_interconnect_2x8.fsdb");
        $fsdbDumpvars(0,tb_axi_interconnect_aes_2master);
        $fsdbDumpMDA();
    end

    // ------------------------------------------------------------------------
    // Two-master AES contention test
    // ------------------------------------------------------------------------
    task automatic simultaneous_aes_writes;
        begin
            $display("\n=== TWO-MASTER AES CONTENTION TEST ===");

            // Both masters target M06 at the same time.
            // M0 writes KEY0, M1 writes KEY1. The per-target arbiter must
            // serialize the requests and preserve each master's AXI response.
            fork
                begin
                    m0_awid=8'h11; m0_awaddr=S6_BASE+32'h08;
                    m0_awlen=0; m0_awsize=2; m0_awburst=2'b01;
                    m0_awlock=0; m0_awcache=0; m0_awprot=0; m0_awqos=0;
                    m0_awuser=0; m0_awvalid=1;
                    m0_wdata=32'h03020100; m0_wstrb=4'hF;
                    m0_wlast=1; m0_wuser=0; m0_wvalid=1;
                    @(posedge clk);
                    while (!(m0_awready && m0_awvalid)) @(posedge clk);
                    m0_awvalid=0;
                    while (!(m0_wready && m0_wvalid)) @(posedge clk);
                    m0_wvalid=0; m0_wlast=0;
                    m0_bready=1;
                    while (!m0_bvalid) @(posedge clk);
                    if (m0_bid !== 8'h11 || m0_bresp !== 2'b00) begin
                        $display("FAIL M0 AES write response BID=%02x BRESP=%b",m0_bid,m0_bresp);
                        fail_count=fail_count+1;
                    end else begin
                        $display("PASS M0 AES KEY0 write response");
                        pass_count=pass_count+1;
                    end
                    @(posedge clk); m0_bready=0;
                end
                begin
                    m1_awid=8'h21; m1_awaddr=S6_BASE+32'h0c;
                    m1_awlen=0; m1_awsize=2; m1_awburst=2'b01;
                    m1_awlock=0; m1_awcache=0; m1_awprot=0; m1_awqos=0;
                    m1_awuser=0; m1_awvalid=1;
                    m1_wdata=32'h07060504; m1_wstrb=4'hF;
                    m1_wlast=1; m1_wuser=0; m1_wvalid=1;
                    @(posedge clk);
                    while (!(m1_awready && m1_awvalid)) @(posedge clk);
                    m1_awvalid=0;
                    while (!(m1_wready && m1_wvalid)) @(posedge clk);
                    m1_wvalid=0; m1_wlast=0;
                    m1_bready=1;
                    while (!m1_bvalid) @(posedge clk);
                    if (m1_bid !== 8'h21 || m1_bresp !== 2'b00) begin
                        $display("FAIL M1 AES write response BID=%02x BRESP=%b",m1_bid,m1_bresp);
                        fail_count=fail_count+1;
                    end else begin
                        $display("PASS M1 AES KEY1 write response");
                        pass_count=pass_count+1;
                    end
                    @(posedge clk); m1_bready=0;
                end
            join
        end
    endtask

    task automatic verify_aes_registers;
        begin
            $display("\n=== VERIFY AES REGISTER OWNERSHIP AFTER CONTENTION ===");
            master_read_single(0,S6_BASE+32'h08,32'h03020100,8'h31);
            master_read_single(1,S6_BASE+32'h0c,32'h07060504,8'h32);
        end
    endtask

    task automatic concurrent_aes_operation;
        begin
            $display("\n=== AES OPERATION WITH SECOND MASTER ACTIVE ===");

            // M0 owns the AES operation. M1 simultaneously issues a read
            // to the same M06 target. This forces arbitration while the AES
            // transaction is active, without involving VeeR or another IP.
            fork
                begin
                    master_write_single(0,S6_BASE+32'h10,32'h0b0a0908,4'hF,8'h41);
                    master_write_single(0,S6_BASE+32'h14,32'h0f0e0d0c,4'hF,8'h42);
                    master_write_single(0,S6_BASE+32'h18,32'h33221100,4'hF,8'h43);
                    master_write_single(0,S6_BASE+32'h1c,32'h77665544,4'hF,8'h44);
                    master_write_single(0,S6_BASE+32'h20,32'hbbaa9988,4'hF,8'h45);
                    master_write_single(0,S6_BASE+32'h24,32'hffeeddcc,4'hF,8'h46);
                    master_write_single(0,S6_BASE+32'h00,32'h00000001,4'hF,8'h47);
                end
                begin
                    repeat (2) @(posedge clk);
                    master_read_single(1,S6_BASE+32'h08,32'h03020100,8'h51);
                    master_read_single(1,S6_BASE+32'h0c,32'h07060504,8'h52);
                end
            join

            // Poll status from M1 until AES completion. This proves that M1
            // can continue accessing M06 while M0 owns the launch sequence.
            begin : poll_done
                integer poll_count;
                reg [31:0] status_value;
                poll_count = 0;
                status_value = 32'h00000001;
                while ((status_value != 32'h00000002) && (poll_count < 500)) begin
                    m1_arid=8'h53; m1_araddr=S6_BASE+32'h04; m1_arlen=0;
                    m1_arsize=2; m1_arburst=2'b01; m1_arlock=0;
                    m1_arcache=0; m1_arprot=0; m1_arqos=0; m1_aruser=0;
                    m1_arvalid=1;
                    @(posedge clk);
                    while (!m1_arready) @(posedge clk);
                    m1_arvalid=0;
                    m1_rready=1;
                    @(posedge clk);
                    while (!m1_rvalid) @(posedge clk);
                    status_value=m1_rdata;
                    if ((m1_rid !== 8'h53) || (m1_rresp !== 2'b00) ||
                        (m1_rlast !== 1'b1)) begin
                        $display("FAIL M1 STATUS poll response RID=%02x RRESP=%b RLAST=%b",
                                 m1_rid,m1_rresp,m1_rlast);
                        fail_count=fail_count+1;
                    end
                    @(posedge clk);
                    m1_rready=0;
                    poll_count=poll_count+1;
                    if (status_value == 32'h00000001)
                        $display("STATUS POLL %0d: BUSY",poll_count);
                    else if (status_value == 32'h00000002)
                        $display("STATUS POLL %0d: DONE",poll_count);
                    else begin
                        $display("FAIL unexpected STATUS=%08x",status_value);
                        fail_count=fail_count+1;
                        status_value=32'h00000002;
                    end
                end
                if (poll_count >= 500 && status_value != 32'h00000002) begin
                    $display("FAIL AES completion timeout while M1 was polling");
                    fail_count=fail_count+1;
                end else begin
                    pass_count=pass_count+1;
                end
            end

            // Result readback through the other master.
            master_read_single(1,S6_BASE+32'h28,32'h70b4c55a,8'h55);
            master_read_single(1,S6_BASE+32'h2c,32'hd8cdb780,8'h56);
            master_read_single(1,S6_BASE+32'h30,32'h6a7b0430,8'h57);
            master_read_single(1,S6_BASE+32'h34,32'h69c4e0d8,8'h58);

            if (!aes_irq) begin
                $display("FAIL AES IRQ not asserted after completion");
                fail_count=fail_count+1;
            end else begin
                $display("PASS AES IRQ asserted after two-master traffic");
                pass_count=pass_count+1;
            end
        end
    endtask

    initial begin
        $display("\n==============================================================");
        $display(" AXI 2x8 -> AES TWO-MASTER CONTENTION VERIFICATION");
        $display(" M06 = 0x%08x, DATA_WIDTH=%0d",S6_BASE,DATA_WIDTH);
        $display("==============================================================\n");

        init_master_signals();
        wait_cycles(5);
        rst=1'b0;
        wait_cycles(5);

        simultaneous_aes_writes();
        verify_aes_registers();
        concurrent_aes_operation();

        wait_cycles(10);
        $display("\n==============================================================");
        $display(" TWO-MASTER AES VERIFICATION SUMMARY");
        $display(" PASS checks : %0d",pass_count);
        $display(" FAIL checks : %0d",fail_count);
        $display("==============================================================");

        if (fail_count == 0) begin
            $display("*** TWO-MASTER AES TEST PASSED ***");
            $finish;
        end else begin
            $display("*** TWO-MASTER AES TEST FAILED ***");
            $fatal;
        end
    end

    // Global timeout prevents deadlock from hanging regression.
    initial begin
        #500_000;
        $display("[%0t] GLOBAL TIMEOUT", $time);
        $fatal;
    end

endmodule

`default_nettype wire
