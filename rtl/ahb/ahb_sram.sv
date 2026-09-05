// ============================================================================
// Project: RISC-V Network Telemetry SoC — Phase 2
// Module : ahb_sram
// Desc   : Parameterized AHB-Lite slave SRAM (IMEM/DMEM). 64-bit data to
//          match the VeeR AHB interface; 32-bit word-aligned SW accesses
//          use HSIZE + HADDR[2:0] byte lanes. Zero-wait by default with
//          optional wait-state injection for HREADY testing.
//
// Params : BASE_ADDR  - byte address of word 0 (must be SIZE-aligned)
//          SIZE_BYTES - power-of-two byte size
//          HEX_FILE   - $readmemh preload file ("": none)
//          WAIT_STATES- wait states per transfer (0 = none)
// ============================================================================
`timescale 1ns / 1ps
`default_nettype none

module ahb_sram #(
    parameter [31:0] BASE_ADDR   = 32'h0000_0000,
    parameter integer SIZE_BYTES = 32768,
    parameter HEX_FILE = "",
    parameter integer WAIT_STATES = 0
) (
    input  wire        hclk,
    input  wire        hreset_n,
    input  wire        hsel,
    input  wire [31:0] haddr,
    input  wire [2:0]  hburst,
    input  wire        hmastlock,
    input  wire [3:0]  hprot,
    input  wire [2:0]  hsize,
    input  wire [1:0]  htrans,
    input  wire        hwrite,
    input  wire [63:0] hwdata,
    output wire [63:0] hrdata,
    output wire        hreadyout,
    output wire        hresp
);

    localparam [1:0] HTRANS_IDLE = 2'b00;

    localparam integer AW = $clog2(SIZE_BYTES);

    // Byte memory: SIZE_BYTES x 8.
    reg [7:0] mem [0:SIZE_BYTES-1];

    integer i;
    initial begin
        for (i = 0; i < SIZE_BYTES; i = i + 1) mem[i] = 8'h00;
        if (HEX_FILE != "") $readmemh(HEX_FILE, mem);
    end

    // A transfer is active when selected with a non-IDLE HTRANS.
    wire active = hsel && (htrans != HTRANS_IDLE);

    // Latch address/control on the address phase (HREADY high).
    reg [31:0] addr_q;
    reg [2:0]  size_q;
    reg        write_q;
    reg        active_q;

    // Wait-state counter.
    reg [7:0]  wscnt;

    wire complete = active_q && (wscnt == 8'd0);

    assign hreadyout = !active_q || (wscnt == 8'd0);
    assign hresp     = 1'b0; // OKAY always (decode guarantees hit)

    // Byte-lane enables from latched HSIZE + HADDR[2:0].
    reg [7:0] lane_en;
    always @* begin
        lane_en = 8'h00;
        if (active_q) begin
            case (size_q)
                3'b000: lane_en[addr_q[2:0]] = 1'b1;                    // byte
                3'b001: begin                                           // half
                    lane_en[{addr_q[2:1], 1'b0}] = 1'b1;
                    lane_en[{addr_q[2:1], 1'b1}] = 1'b1;
                end
                3'b010: begin                                           // word (32b)
                    lane_en[{addr_q[2], 2'b00}] = 1'b1;
                    lane_en[{addr_q[2], 2'b01}] = 1'b1;
                    lane_en[{addr_q[2], 2'b10}] = 1'b1;
                    lane_en[{addr_q[2], 2'b11}] = 1'b1;
                end
                default: lane_en = 8'hFF;                               // 64b+
            endcase
        end
    end

    wire [AW-1:0] word_addr = {addr_q[AW-1:3], 3'b000};

    // Word base (byte-lane offset cleared) + lane index. The low address
    // bits select the lane; they must NOT also offset the base.

    // Writes complete in the data phase.
    integer b;
    always @(posedge hclk) begin
        if (complete && write_q) begin
            for (b = 0; b < 8; b = b + 1)
                if (lane_en[b]) mem[word_addr + b] <= hwdata[b*8 +: 8];
        end
    end

    // Reads are combinational (zero-wait) from the latched address.
    reg [63:0] rdata;
    always @* begin
        rdata = 64'h0;
        for (b = 0; b < 8; b = b + 1)
            rdata[b*8 +: 8] = mem[word_addr + b];
    end
    assign hrdata = rdata;

    // Address-phase latch + wait counter.
    always @(posedge hclk or negedge hreset_n) begin
        if (!hreset_n) begin
            addr_q   <= 32'h0;
            size_q   <= 3'h0;
            write_q  <= 1'b0;
            active_q <= 1'b0;
            wscnt    <= 8'd0;
        end else if (hreadyout) begin
            // Bus idle or previous transfer completed: sample new phase.
            addr_q   <= haddr;
            size_q   <= hsize;
            write_q  <= hwrite;
            active_q <= active;
            wscnt    <= active ? WAIT_STATES[7:0] : 8'd0;
        end else if (wscnt != 8'd0) begin
            wscnt <= wscnt - 8'd1;
        end
    end

endmodule

`default_nettype wire
