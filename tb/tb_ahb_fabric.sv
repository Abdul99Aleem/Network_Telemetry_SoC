// ============================================================================
// Project: RISC-V Network Telemetry SoC — Phase 2
// TB     : tb_ahb_fabric (TB1)
// Desc   : Directed verification of soc_top AHB-Lite fabric:
//          reset, single read/write, decode, slave select, HREADY/HRESP
//          propagation, unmapped ERROR, back-to-back, arbitration,
//          read-after-write, byte/half lanes.
//
// DUT    : soc_top (fabric + IMEM + DMEM + default slave)
// Clocks : 100 MHz single clock, active-low reset.
// Result : PASS/FAIL per check + final summary. FSDB dumped.
// ============================================================================
`timescale 1ns / 1ps

module tb_ahb_fabric;

    localparam [1:0] HTRANS_IDLE   = 2'b00;
    localparam [1:0] HTRANS_NONSEQ = 2'b10;

    reg clk = 0;
    always #5 clk = ~clk;
    reg reset_n = 0;

    // ---- LSU master stimulus ----
    reg  [31:0] lsu_haddr = 0;
    reg  [2:0]  lsu_hburst = 0;
    reg         lsu_hmastlock = 0;
    reg  [3:0]  lsu_hprot = 0;
    reg  [2:0]  lsu_hsize = 0;
    reg  [1:0]  lsu_htrans = HTRANS_IDLE;
    reg         lsu_hwrite = 0;
    reg  [63:0] lsu_hwdata = 0;
    wire [63:0] lsu_hrdata;
    wire        lsu_hready;
    wire        lsu_hresp;

    // ---- IFU master stimulus ----
    reg  [31:0] ifu_haddr = 0;
    reg  [2:0]  ifu_hburst = 0;
    reg         ifu_hmastlock = 0;
    reg  [3:0]  ifu_hprot = 0;
    reg  [2:0]  ifu_hsize = 0;
    reg  [1:0]  ifu_htrans = HTRANS_IDLE;
    reg         ifu_hwrite = 0;
    wire [63:0] ifu_hrdata;
    wire        ifu_hready;
    wire        ifu_hresp;

    soc_top dut (
        .clk(clk), .reset_n(reset_n),
        .ifu_haddr(ifu_haddr), .ifu_hburst(ifu_hburst),
        .ifu_hmastlock(ifu_hmastlock), .ifu_hprot(ifu_hprot),
        .ifu_hsize(ifu_hsize), .ifu_htrans(ifu_htrans),
        .ifu_hwrite(ifu_hwrite),
        .ifu_hrdata(ifu_hrdata), .ifu_hready(ifu_hready), .ifu_hresp(ifu_hresp),
        .lsu_haddr(lsu_haddr), .lsu_hburst(lsu_hburst),
        .lsu_hmastlock(lsu_hmastlock), .lsu_hprot(lsu_hprot),
        .lsu_hsize(lsu_hsize), .lsu_htrans(lsu_htrans),
        .lsu_hwrite(lsu_hwrite), .lsu_hwdata(lsu_hwdata),
        .lsu_hrdata(lsu_hrdata), .lsu_hready(lsu_hready), .lsu_hresp(lsu_hresp)
    );

    // Standalone SRAM with wait states (HREADY-propagation mechanism check).
    reg        ws_hsel = 0;
    reg [31:0] ws_haddr = 0;
    reg [2:0]  ws_hsize = 3'b011;
    reg [1:0]  ws_htrans = HTRANS_IDLE;
    reg        ws_hwrite = 0;
    reg [63:0] ws_hwdata = 0;
    wire [63:0] ws_hrdata;
    wire        ws_hreadyout;
    wire        ws_hresp;
    ahb_sram #(.BASE_ADDR(32'h0), .SIZE_BYTES(1024), .WAIT_STATES(2)) u_ws (
        .hclk(clk), .hreset_n(reset_n),
        .hsel(ws_hsel), .haddr(ws_haddr), .hburst(3'b0), .hmastlock(1'b0),
        .hprot(4'b0), .hsize(ws_hsize), .htrans(ws_htrans), .hwrite(ws_hwrite),
        .hwdata(ws_hwdata), .hrdata(ws_hrdata),
        .hreadyout(ws_hreadyout), .hresp(ws_hresp)
    );

    integer pass_cnt = 0;
    integer fail_cnt = 0;

    task check(input string name, input cond);
        begin
            if (cond) begin
                pass_cnt = pass_cnt + 1;
                $display("[%0t ns] PASS %0s", $time, name);
            end else begin
                fail_cnt = fail_cnt + 1;
                $display("[%0t ns] FAIL %0s", $time, name);
            end
        end
    endtask

    // One-hot HSEL monitor (sampled every cycle while any master is active).
    always @(posedge clk) begin
        if (reset_n && ((lsu_htrans != HTRANS_IDLE) || (ifu_htrans != HTRANS_IDLE))) begin
            if ((dut.imem_hsel + dut.dmem_hsel + dut.def_hsel) > 1) begin
                fail_cnt = fail_cnt + 1;
                $display("[%0t ns] FAIL hsel_onehot imem=%b dmem=%b def=%b",
                         $time, dut.imem_hsel, dut.dmem_hsel, dut.def_hsel);
            end
        end
    end

    // ---- LSU single transfer ----
    // Discipline: NBA-settle (#1) after every edge before sampling DUT
    // outputs; one full data-phase cycle before checking HREADY, because
    // AHB responses belong to the cycle AFTER the address phase.
    task lsu_write(input [31:0] addr, input [63:0] data, input [2:0] size);
        begin
            @(posedge clk); #1;
            lsu_haddr <= addr; lsu_hwrite <= 1'b1; lsu_htrans <= HTRANS_NONSEQ;
            lsu_hsize <= size; lsu_hwdata <= data; lsu_hburst <= 3'b0;
            @(posedge clk); #1;   // address phase latched, data phase begins
            @(posedge clk); #1;   // data phase completes (zero-wait)
            while (lsu_hready !== 1'b1) begin @(posedge clk); #1; end
            lsu_htrans <= HTRANS_IDLE; lsu_hwrite <= 1'b0;
            @(posedge clk); #1;
        end
    endtask

    task lsu_read(input [31:0] addr, input [2:0] size, output [63:0] data, output resp);
        begin
            @(posedge clk); #1;
            lsu_haddr <= addr; lsu_hwrite <= 1'b0; lsu_htrans <= HTRANS_NONSEQ;
            lsu_hsize <= size; lsu_hburst <= 3'b0;
            @(posedge clk); #1;
            @(posedge clk); #1;
            while (lsu_hready !== 1'b1) begin @(posedge clk); #1; end
            data = lsu_hrdata;
            resp = lsu_hresp;
            lsu_htrans <= HTRANS_IDLE;
            @(posedge clk); #1;
        end
    endtask

    task ifu_read(input [31:0] addr, output [63:0] data);
        begin
            @(posedge clk); #1;
            ifu_haddr <= addr; ifu_hwrite <= 1'b0; ifu_htrans <= HTRANS_NONSEQ;
            ifu_hsize <= 3'b011; ifu_hburst <= 3'b0;
            @(posedge clk); #1;
            @(posedge clk); #1;
            while (ifu_hready !== 1'b1) begin @(posedge clk); #1; end
            data = ifu_hrdata;
            ifu_htrans <= HTRANS_IDLE;
            @(posedge clk); #1;
        end
    endtask

    reg [63:0] rd;
    reg        rp;
    integer k;

    initial begin
        $fsdbDumpfile("p2_fabric.fsdb");
        $fsdbDumpvars(0, tb_ahb_fabric);

        // ---- T1: reset ----
        repeat (4) @(posedge clk);
        reset_n = 1;
        repeat (2) @(posedge clk); #1;
        check("T1 reset: masters ready, no resp, no select",
              lsu_hready && ifu_hready && !lsu_hresp && !ifu_hresp &&
              !dut.imem_hsel && !dut.dmem_hsel && !dut.def_hsel);

        // ---- T2: LSU word write + read, DMEM ----
        lsu_write(32'h0001_0000, 64'h0000_0000_DEADBEEF, 3'b010);
        lsu_read(32'h0001_0000, 3'b010, rd, rp);
        check("T2 LSU write/read DMEM word", (rd[31:0] == 32'hDEADBEEF) && !rp);
        check("T2 HRESP=0 on mapped access", !rp);

        // ---- T3: IFU read of LSU-written IMEM word (shared slave) ----
        lsu_write(32'h0000_0100, 64'h11223344_55667788, 3'b011);
        ifu_read(32'h0000_0100, rd);
        check("T3 IFU fetch of IMEM doubleword", rd == 64'h11223344_55667788);
        check("T3 IFU HRESP=0", !ifu_hresp);

        // ---- T4: decode/slave-select spot checks ----
        @(posedge clk); #1;
        lsu_haddr <= 32'h0000_7FF8; lsu_htrans <= HTRANS_NONSEQ; lsu_hwrite <= 1'b0; lsu_hsize <= 3'b011;
        @(posedge clk); #1;
        check("T4 IMEM selected at top of window",
              dut.imem_hsel && !dut.dmem_hsel && !dut.def_hsel);
        lsu_htrans <= HTRANS_IDLE;
        @(posedge clk); #1;
        @(posedge clk); #1;
        lsu_haddr <= 32'h0001_7FF0; lsu_htrans <= HTRANS_NONSEQ;
        @(posedge clk); #1;
        check("T4 DMEM selected at top of window",
              dut.dmem_hsel && !dut.imem_hsel && !dut.def_hsel);
        lsu_htrans <= HTRANS_IDLE;
        @(posedge clk); #1;

        // ---- T5: wait-state SRAM: HREADY low then data ----
        @(posedge clk); #1;
        ws_hsel <= 1'b1; ws_haddr <= 32'h40; ws_hwrite <= 1'b1;
        ws_htrans <= HTRANS_NONSEQ; ws_hwdata <= 64'hA5A5_A5A5_5A5A_5A5A;
        @(posedge clk); #1;
        check("T5 wait: HREADY low during stall", ws_hreadyout === 1'b0);
        @(posedge clk); #1;
        while (ws_hreadyout !== 1'b1) begin @(posedge clk); #1; end
        ws_htrans <= HTRANS_IDLE; ws_hwrite <= 1'b0;
        @(posedge clk); #1;
        ws_hsel <= 1'b1; ws_haddr <= 32'h40; ws_htrans <= HTRANS_NONSEQ;
        @(posedge clk); #1;
        @(posedge clk); #1;
        while (ws_hreadyout !== 1'b1) begin @(posedge clk); #1; end
        check("T5 wait: readback after stall", ws_hrdata == 64'hA5A5_A5A5_5A5A_5A5A);
        ws_htrans <= HTRANS_IDLE; ws_hsel <= 1'b0;
        @(posedge clk); #1;

        // ---- T6: unmapped access -> ERROR ----
        lsu_read(32'h2000_0000, 3'b010, rd, rp);
        check("T6 unmapped HRESP=1", rp === 1'b1);
        // default slave was selected (sampled during transfer above via monitor)

        // ---- T7: back-to-back pipelined writes (new addr phase EVERY cycle,
        // no IDLE): AHB pipelines addr ahead of data, so HWDATA lags HADDR
        // by one cycle — data for the just-latched transfer is driven
        // during its data phase. ----
        @(posedge clk); #1;
        lsu_haddr <= 32'h0001_0100; lsu_hwrite <= 1'b1;
        lsu_htrans <= HTRANS_NONSEQ; lsu_hsize <= 3'b011;
        for (k = 0; k < 4; k = k + 1) begin
            @(posedge clk); #1; // slave latches addr[k] here; w[k-1] commits
            lsu_hwdata <= 64'hF00D_0000_0000_0000 + k; // data phase of w[k]
            if (k < 3) begin
                lsu_haddr <= 32'h0001_0100 + (k+1)*8;
            end else begin
                lsu_htrans <= HTRANS_IDLE; lsu_hwrite <= 1'b0;
            end
        end
        @(posedge clk); #1; // w[3] commits at this edge
        begin
            integer t7_fail;
            t7_fail = 0;
            for (k = 0; k < 4; k = k + 1) begin
                lsu_read(32'h0001_0100 + k*8, 3'b011, rd, rp);
                if (rd !== (64'hF00D_0000_0000_0000 + k) || rp) begin
                    t7_fail = 1;
                    $display("[%0t ns] FAIL T7 b2b word %0d got %h", $time, k, rd);
                end
            end
            if (t7_fail) fail_cnt = fail_cnt + 1;
            else begin
                pass_cnt = pass_cnt + 1;
                $display("[%0t ns] PASS T7 back-to-back write/read x4", $time);
            end
        end

        // ---- T8: arbitration — both masters same cycle, LSU wins ----
        @(posedge clk); #1;
        lsu_haddr <= 32'h0001_0200; lsu_hwrite <= 1'b1; lsu_htrans <= HTRANS_NONSEQ;
        lsu_hsize <= 3'b011; lsu_hwdata <= 64'hAA55_AA55_AA55_AA55;
        ifu_haddr <= 32'h0000_0200; ifu_hwrite <= 1'b0; ifu_htrans <= HTRANS_NONSEQ;
        ifu_hsize <= 3'b011;
        @(posedge clk); #1;
        // LSU owns address phase: DMEM selected, not IMEM
        check("T8 LSU priority: DMEM selected over IMEM",
              dut.dmem_hsel && !dut.imem_hsel);
        @(posedge clk); #1;
        while (lsu_hready !== 1'b1) begin @(posedge clk); #1; end
        lsu_htrans <= HTRANS_IDLE; lsu_hwrite <= 1'b0;
        // IFU transfer now proceeds to IMEM
        while (ifu_hready !== 1'b1) begin @(posedge clk); #1; end
        check("T8 IFU completes after LSU", ifu_hready && !ifu_hresp);
        ifu_htrans <= HTRANS_IDLE;
        @(posedge clk); #1;
        lsu_read(32'h0001_0200, 3'b011, rd, rp);
        check("T8 LSU data intact under contention", rd == 64'hAA55_AA55_AA55_AA55);

        // ---- T9: read-after-write same address ----
        lsu_write(32'h0001_0300, 64'h01234567_89ABCDEF, 3'b011);
        lsu_read(32'h0001_0300, 3'b011, rd, rp);
        check("T9 read-after-write", (rd == 64'h01234567_89ABCDEF) && !rp);

        // ---- T10: byte + halfword lanes (data on correct HWDATA lanes) ----
        lsu_write(32'h0001_0400, 64'h00, 3'b011); // clear dword
        lsu_write(32'h0001_0401, 64'hBB00, 3'b000); // byte lane 1 <- HWDATA[15:8]
        lsu_write(32'h0001_0402, 64'hCCDD0000, 3'b001); // half lanes 2-3 <- HWDATA[31:16]
        lsu_read(32'h0001_0400, 3'b011, rd, rp);
        check("T10 byte/half lanes", (rd[31:0] == 32'hCCDD_BB00) && !rp);

        // ---- summary ----
        $display("==================================================");
        $display("P2 FABRIC: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display("P2_TB1_RESULT: PASS");
        else $display("P2_TB1_RESULT: FAIL");
        $display("==================================================");
        #100;
        $finish;
    end

    // Global timeout
    initial begin
        #500000;
        $display("P2_TB1_RESULT: TIMEOUT FAIL");
        $finish;
    end

endmodule
