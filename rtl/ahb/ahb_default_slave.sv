// ============================================================================
// Project: RISC-V Network Telemetry SoC — Phase 2
// Module : ahb_default_slave
// Desc   : AHB-Lite default slave. Claims every transfer the interconnect
//          routes to it (unmapped addresses, and Phase-2 peripheral
//          regions not yet implemented as slaves) and completes them with
//          a two-cycle ERROR response (HRESP=1). Idle-high HREADYOUT.
// ============================================================================
`timescale 1ns / 1ps
`default_nettype none

module ahb_default_slave (
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

    localparam [1:0] ST_IDLE = 2'b00;
    localparam [1:0] ST_ERR1 = 2'b01; // first ERROR cycle: HREADY low
    localparam [1:0] ST_ERR2 = 2'b10; // second ERROR cycle: HREADY high

    reg [1:0] state;

    wire active = hsel && (htrans != HTRANS_IDLE);

    assign hrdata    = 64'h0;
    assign hreadyout = (state != ST_ERR1);
    assign hresp     = (state != ST_IDLE);

    always @(posedge hclk or negedge hreset_n) begin
        if (!hreset_n) begin
            state <= ST_IDLE;
        end else begin
            case (state)
                ST_IDLE: state <= active ? ST_ERR1 : ST_IDLE;
                ST_ERR1: state <= ST_ERR2;
                ST_ERR2: state <= active ? ST_ERR1 : ST_IDLE;
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
