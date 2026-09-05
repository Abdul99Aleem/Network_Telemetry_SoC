`timescale 1ns / 1ps
`default_nettype none

module aes_axi_slave #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter STRB_WIDTH = DATA_WIDTH / 8,
    parameter ID_WIDTH   = 8
)(
    input  wire                     clk,
    input  wire                     rst,

    // ------------------------------------------------------------
    // AXI write address channel
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
    // AES interrupt
    // ------------------------------------------------------------
    output wire                     aes_irq
);

    // ============================================================
    // Address map
    // ============================================================

    localparam [ADDR_WIDTH-1:0] AES_BASE = 32'h1000_4000;

    localparam [5:0] ADDR_CONTROL = 6'h00;
    localparam [5:0] ADDR_STATUS  = 6'h04;

    localparam [5:0] ADDR_KEY0    = 6'h08;
    localparam [5:0] ADDR_KEY1    = 6'h0c;
    localparam [5:0] ADDR_KEY2    = 6'h10;
    localparam [5:0] ADDR_KEY3    = 6'h14;

    localparam [5:0] ADDR_DATA0   = 6'h18;
    localparam [5:0] ADDR_DATA1   = 6'h1c;
    localparam [5:0] ADDR_DATA2   = 6'h20;
    localparam [5:0] ADDR_DATA3   = 6'h24;

    localparam [5:0] ADDR_RESULT0 = 6'h28;
    localparam [5:0] ADDR_RESULT1 = 6'h2c;
    localparam [5:0] ADDR_RESULT2 = 6'h30;
    localparam [5:0] ADDR_RESULT3 = 6'h34;

    // ============================================================
    // AXI write channel state
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

    wire aw_handshake;
    wire w_handshake;

    assign s_axi_awready = !aw_pending && !bvalid_reg;
    assign s_axi_wready  = !w_pending && !bvalid_reg;

    assign aw_handshake = s_axi_awvalid && s_axi_awready;
    assign w_handshake  = s_axi_wvalid  && s_axi_wready;

    assign s_axi_bvalid = bvalid_reg;
    assign s_axi_bid    = bid_reg;
    assign s_axi_bresp  = bresp_reg;
    assign s_axi_buser  = 1'b0;

    // ============================================================
    // AXI read channel state
    // ============================================================

    reg                    rvalid_reg;
    reg [ID_WIDTH-1:0]     rid_reg;
    reg [DATA_WIDTH-1:0]   rdata_reg;
    reg [1:0]              rresp_reg;

    assign s_axi_arready = !rvalid_reg;

    assign s_axi_rvalid = rvalid_reg;
    assign s_axi_rid    = rid_reg;
    assign s_axi_rdata  = rdata_reg;
    assign s_axi_rresp  = rresp_reg;
    assign s_axi_rlast  = rvalid_reg;
    assign s_axi_ruser  = 1'b0;

    // ============================================================
    // AES registers
    // ============================================================

    reg [31:0] key0_reg;
    reg [31:0] key1_reg;
    reg [31:0] key2_reg;
    reg [31:0] key3_reg;

    reg [31:0] data0_reg;
    reg [31:0] data1_reg;
    reg [31:0] data2_reg;
    reg [31:0] data3_reg;

    reg [31:0] result0_reg;
    reg [31:0] result1_reg;
    reg [31:0] result2_reg;
    reg [31:0] result3_reg;

    reg        busy_reg;
    reg        done_reg;
    reg        irq_reg;

    reg        aes_ld;

    wire [127:0] aes_key;
    wire [127:0] aes_text_in;
    wire [127:0] aes_text_out;
    wire         aes_done;

    /*
     * Word ordering:
     *
     * KEY0  = key[31:0]
     * KEY1  = key[63:32]
     * KEY2  = key[95:64]
     * KEY3  = key[127:96]
     *
     * Therefore:
     *
     * key = {KEY3, KEY2, KEY1, KEY0}
     */
    assign aes_key = {
        key3_reg,
        key2_reg,
        key1_reg,
        key0_reg
    };

    assign aes_text_in = {
        data3_reg,
        data2_reg,
        data1_reg,
        data0_reg
    };

    assign aes_irq = irq_reg;

    // ============================================================
    // AES core
    // ============================================================

    aes_cipher_top aes_core_inst (
        .clk      (clk),
        .rst      (!rst),
        .ld       (aes_ld),
        .done     (aes_done),
        .key      (aes_key),
        .text_in  (aes_text_in),
        .text_out (aes_text_out)
    );

    // ============================================================
    // Byte write-enable helper
    // ============================================================

    function [31:0] apply_wstrb;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0]  strb;

        integer k;

        begin
            apply_wstrb = old_value;

            for (k = 0; k < 4; k = k + 1) begin
                if (strb[k])
                    apply_wstrb[k*8 +: 8] =
                        new_value[k*8 +: 8];
            end
        end
    endfunction

    // ============================================================
    // Effective write transaction
    //
    // AXI AW and W are independent channels.  The transaction
    // commits once both have arrived.
    // ============================================================

    wire write_complete =
        (aw_pending || aw_handshake) &&
        (w_pending  || w_handshake);

    wire [ADDR_WIDTH-1:0] write_addr =
        aw_pending ? awaddr_reg : s_axi_awaddr;

    wire [31:0] write_data =
        w_pending ? wdata_reg : s_axi_wdata;

    wire [3:0] write_strb =
        w_pending ? wstrb_reg : s_axi_wstrb;

    wire [5:0] write_offset =
        write_addr[5:0];

    // ============================================================
    // Read data mux
    // ============================================================

    reg [31:0] read_data;

    always @* begin
        read_data = 32'h0000_0000;

        case (s_axi_araddr[5:0])

            ADDR_CONTROL:
                read_data = 32'h0000_0000;

            ADDR_STATUS: begin
                read_data = 32'h0000_0000;
                read_data[0] = busy_reg;
                read_data[1] = done_reg;
            end

            ADDR_KEY0:
                read_data = key0_reg;

            ADDR_KEY1:
                read_data = key1_reg;

            ADDR_KEY2:
                read_data = key2_reg;

            ADDR_KEY3:
                read_data = key3_reg;

            ADDR_DATA0:
                read_data = data0_reg;

            ADDR_DATA1:
                read_data = data1_reg;

            ADDR_DATA2:
                read_data = data2_reg;

            ADDR_DATA3:
                read_data = data3_reg;

            ADDR_RESULT0:
                read_data = result0_reg;

            ADDR_RESULT1:
                read_data = result1_reg;

            ADDR_RESULT2:
                read_data = result2_reg;

            ADDR_RESULT3:
                read_data = result3_reg;

            default:
                read_data = 32'h0000_0000;

        endcase
    end

    // ============================================================
    // Main sequential logic
    // ============================================================

    always @(posedge clk) begin

        if (rst) begin

            aw_pending <= 1'b0;
            awid_reg   <= {ID_WIDTH{1'b0}};
            awaddr_reg <= {ADDR_WIDTH{1'b0}};

            w_pending  <= 1'b0;
            wdata_reg  <= 32'h0000_0000;
            wstrb_reg  <= 4'h0;

            bvalid_reg <= 1'b0;
            bid_reg    <= {ID_WIDTH{1'b0}};
            bresp_reg  <= 2'b00;

            rvalid_reg <= 1'b0;
            rid_reg    <= {ID_WIDTH{1'b0}};
            rdata_reg  <= 32'h0000_0000;
            rresp_reg  <= 2'b00;

            key0_reg <= 32'h0;
            key1_reg <= 32'h0;
            key2_reg <= 32'h0;
            key3_reg <= 32'h0;

            data0_reg <= 32'h0;
            data1_reg <= 32'h0;
            data2_reg <= 32'h0;
            data3_reg <= 32'h0;

            result0_reg <= 32'h0;
            result1_reg <= 32'h0;
            result2_reg <= 32'h0;
            result3_reg <= 32'h0;

            busy_reg <= 1'b0;
            done_reg <= 1'b0;
            irq_reg  <= 1'b0;

            aes_ld <= 1'b0;

        end else begin

            // ----------------------------------------------------
            // Default: AES load is a one-cycle pulse
            // ----------------------------------------------------

            aes_ld <= 1'b0;

            // ----------------------------------------------------
            // Capture AXI AW
            // ----------------------------------------------------

            if (aw_handshake) begin
                aw_pending <= 1'b1;
                awid_reg   <= s_axi_awid;
                awaddr_reg <= s_axi_awaddr;
            end

            // ----------------------------------------------------
            // Capture AXI W
            // ----------------------------------------------------

            if (w_handshake) begin
                w_pending <= 1'b1;
                wdata_reg <= s_axi_wdata;
                wstrb_reg <= s_axi_wstrb;
            end

            // ----------------------------------------------------
            // Complete AXI write transaction
            // ----------------------------------------------------

            if (write_complete) begin

                aw_pending <= 1'b0;
                w_pending  <= 1'b0;

                bid_reg    <= aw_pending ? awid_reg : s_axi_awid;
                bresp_reg  <= 2'b00;       // OKAY
                bvalid_reg <= 1'b1;

                // ------------------------------------------------
                // Register decode
                // ------------------------------------------------

                case (write_offset)

                    ADDR_CONTROL: begin

                        // CONTROL[0] = START
                        if (write_strb[0] && write_data[0]) begin

                            if (!busy_reg) begin
                                aes_ld   <= 1'b1;
                                busy_reg <= 1'b1;
                                done_reg <= 1'b0;
                                irq_reg  <= 1'b0;
                            end

                        end

                        // CONTROL[1] = CLEAR DONE / IRQ
                        if (write_strb[0] && write_data[1]) begin
                            done_reg <= 1'b0;
                            irq_reg  <= 1'b0;
                        end

                    end

                    ADDR_KEY0:
                        key0_reg <= apply_wstrb(
                            key0_reg,
                            write_data,
                            write_strb
                        );

                    ADDR_KEY1:
                        key1_reg <= apply_wstrb(
                            key1_reg,
                            write_data,
                            write_strb
                        );

                    ADDR_KEY2:
                        key2_reg <= apply_wstrb(
                            key2_reg,
                            write_data,
                            write_strb
                        );

                    ADDR_KEY3:
                        key3_reg <= apply_wstrb(
                            key3_reg,
                            write_data,
                            write_strb
                        );

                    ADDR_DATA0:
                        data0_reg <= apply_wstrb(
                            data0_reg,
                            write_data,
                            write_strb
                        );

                    ADDR_DATA1:
                        data1_reg <= apply_wstrb(
                            data1_reg,
                            write_data,
                            write_strb
                        );

                    ADDR_DATA2:
                        data2_reg <= apply_wstrb(
                            data2_reg,
                            write_data,
                            write_strb
                        );

                    ADDR_DATA3:
                        data3_reg <= apply_wstrb(
                            data3_reg,
                            write_data,
                            write_strb
                        );

                    default: begin
                    end

                endcase

            end

            // ----------------------------------------------------
            // AXI B response handshake
            // ----------------------------------------------------

            if (bvalid_reg && s_axi_bready)
                bvalid_reg <= 1'b0;

            // ----------------------------------------------------
            // AES completion
            // ----------------------------------------------------

            if (aes_done) begin

                busy_reg <= 1'b0;
                done_reg <= 1'b1;
                irq_reg  <= 1'b1;

                result0_reg <= aes_text_out[31:0];
                result1_reg <= aes_text_out[63:32];
                result2_reg <= aes_text_out[95:64];
                result3_reg <= aes_text_out[127:96];

            end

            // ----------------------------------------------------
            // AXI read transaction
            // ----------------------------------------------------

            if (s_axi_arvalid && s_axi_arready) begin

                rid_reg    <= s_axi_arid;
                rdata_reg  <= read_data;
                rresp_reg  <= 2'b00;       // OKAY
                rvalid_reg <= 1'b1;

            end

            // ----------------------------------------------------
            // AXI R response handshake
            // ----------------------------------------------------

            if (rvalid_reg && s_axi_rready)
                rvalid_reg <= 1'b0;

        end

    end

endmodule

`default_nettype wire
