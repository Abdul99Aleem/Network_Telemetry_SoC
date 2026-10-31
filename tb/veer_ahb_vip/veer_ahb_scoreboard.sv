// =============================================================================
// VIP: veer_ahb_scoreboard
// File: veer_ahb_scoreboard.sv
//
// Description:
//   Scoreboard for the veer_ahb VIP.  Receives completed beats from the
//   monitor via the analysis port.  Two checking modes:
//
//   1. Mailbox check (directed): The test populates 'expected_q' with
//      (addr, data) pairs before starting the sequence.  Each captured
//      read beat is compared against the front of the queue.
//
//   2. Pass-through log: All beats (reads and writes) are logged at
//      UVM_MEDIUM.  Extend this class and override write() to add
//      custom checks (e.g., DMEM mailbox values from the Phase 2/3 flow).
//
//   AHB response check: any beat with HRESP=1 (ERROR) increments
//   m_error_count and emits a UVM_ERROR.
// =============================================================================
`timescale 1ns/1ps

class veer_ahb_scoreboard extends uvm_scoreboard;

    `uvm_component_utils(veer_ahb_scoreboard)

    // Analysis imp — connected from agent.ap in the environment
    uvm_analysis_imp #(veer_ahb_seq_item, veer_ahb_scoreboard) m_analysis_imp;

    // Expected queue for directed checks:
    //   push_back({addr, expected_rdata}) before the sequence runs
    typedef struct { bit [31:0] addr; bit [63:0] data; } ahb_expect_t;
    ahb_expect_t expected_q[$];

    // Statistics
    int unsigned m_beat_count  = 0;
    int unsigned m_error_count = 0;
    int unsigned m_pass_count  = 0;
    int unsigned m_fail_count  = 0;

    function new(string name = "veer_ahb_scoreboard", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m_analysis_imp = new("m_analysis_imp", this);
    endfunction

    // -------------------------------------------------------------------------
    // write() — called by uvm_analysis_imp for every beat the monitor emits
    // -------------------------------------------------------------------------
    virtual function void write(veer_ahb_seq_item item);
        m_beat_count++;

        `uvm_info(get_type_name(),
            $sformatf("[SB] beat #%0d: %s", m_beat_count, item.convert2string()),
            UVM_MEDIUM)

        // --- Bus error check ---
        if (item.hresp) begin
            m_error_count++;
            `uvm_error(get_type_name(),
                $sformatf("[SB] HRESP=ERROR on addr=0x%08h (beat #%0d)",
                    item.haddr, m_beat_count))
        end

        // --- Directed expected-value check (reads only) ---
        if (item.hwrite == AHB_READ && expected_q.size() > 0) begin
            ahb_expect_t exp = expected_q.pop_front();
            if (item.haddr !== exp.addr) begin
                m_fail_count++;
                `uvm_error(get_type_name(),
                    $sformatf("[SB] addr mismatch: got 0x%08h expected 0x%08h",
                        item.haddr, exp.addr))
            end else if (item.hrdata !== exp.data) begin
                m_fail_count++;
                `uvm_error(get_type_name(),
                    $sformatf("[SB] rdata mismatch @ 0x%08h: got 0x%016h expected 0x%016h",
                        item.haddr, item.hrdata, exp.data))
            end else begin
                m_pass_count++;
                `uvm_info(get_type_name(),
                    $sformatf("[SB] PASS: addr=0x%08h rdata=0x%016h", item.haddr, item.hrdata),
                    UVM_LOW)
            end
        end
    endfunction

    // -------------------------------------------------------------------------
    // report_phase — print final tally
    // -------------------------------------------------------------------------
    virtual function void report_phase(uvm_phase phase);
        `uvm_info(get_type_name(),
            $sformatf("[SB REPORT] beats=%0d  pass=%0d  fail=%0d  bus_errors=%0d",
                m_beat_count, m_pass_count, m_fail_count, m_error_count),
            UVM_NONE)
        if (m_fail_count > 0 || m_error_count > 0)
            `uvm_error(get_type_name(), "veer_ahb_scoreboard: FAIL")
        else
            `uvm_info(get_type_name(), "veer_ahb_scoreboard: PASS", UVM_NONE)
    endfunction

endclass : veer_ahb_scoreboard
