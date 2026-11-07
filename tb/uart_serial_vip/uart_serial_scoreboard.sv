// =============================================================================
// VIP: uart_serial_scoreboard
// File: uart_serial_scoreboard.sv
//
// Description:
//   Scoreboard for the uart_serial VIP.
//   Provides two checking layers:
//     1. Exact byte-by-byte matching against an expected byte queue.
//     2. String/stream pattern verification against expected substrings
//        (e.g., "UART\n", "UART_CHECK_RESULT: PASS", "P2_TB2_RESULT: PASS").
//     3. Physical baud period tolerance validation.
// =============================================================================
`timescale 1ns/1ps

class uart_serial_scoreboard extends uvm_scoreboard;

    `uvm_component_utils(uart_serial_scoreboard)

    uvm_analysis_imp #(uart_serial_seq_item, uart_serial_scoreboard) m_analysis_imp;
    uart_serial_cfg cfg;

    // Queues for expected values
    byte   expected_byte_q[$];
    string expected_string_q[$];

    // Cumulative captured stream
    string captured_stream = "";

    // Scoreboard metrics
    int unsigned m_byte_count          = 0;
    int unsigned m_pass_count          = 0;
    int unsigned m_fail_count          = 0;
    int unsigned m_framing_error_count = 0;
    int unsigned m_timing_error_count  = 0;

    function new(string name = "uart_serial_scoreboard", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m_analysis_imp = new("m_analysis_imp", this);
        if (cfg == null) begin
            void'(uvm_config_db #(uart_serial_cfg)::get(this, "", "cfg", cfg));
        end
    endfunction

    virtual function void write(uart_serial_seq_item item);
        byte c = byte'(item.data);
        m_byte_count++;

        // Append printable character or '.' to accumulated stream
        if (c >= 8'h20 && c <= 8'h7E)
            captured_stream = {captured_stream, string'(c)};
        else if (c == 8'h0A) // newline
            captured_stream = {captured_stream, "\n"};
        else if (c == 8'h0D) // carriage return
            captured_stream = {captured_stream, "\r"};
        else
            captured_stream = {captured_stream, "."};

        // 1. Framing error tracking
        if (item.framing_error) begin
            m_framing_error_count++;
            `uvm_error(get_type_name(),
                $sformatf("[SB] Framing error recorded on byte #%0d (0x%02h)",
                          m_byte_count, item.data))
        end

        // 2. Expected byte comparison
        if (expected_byte_q.size() > 0) begin
            byte exp_byte = expected_byte_q.pop_front();
            if (c === exp_byte) begin
                m_pass_count++;
                `uvm_info(get_type_name(),
                    $sformatf("[SB MATCH] byte #%0d matched: 0x%02h ('%c')",
                              m_byte_count, c, c), UVM_HIGH)
            end else begin
                m_fail_count++;
                `uvm_error(get_type_name(),
                    $sformatf("[SB MISMATCH] byte #%0d: observed 0x%02h ('%c') != expected 0x%02h ('%c')",
                              m_byte_count, c, c, exp_byte, exp_byte))
            end
        end

        // 3. Timing / Baud tolerance check
        if (cfg != null && cfg.enable_baud_check && cfg.nominal_baud > 0.0) begin
            realtime nominal_period = cfg.get_nominal_bit_period();
            real diff = (item.measured_bit_period > nominal_period) ?
                        (item.measured_bit_period - nominal_period) :
                        (nominal_period - item.measured_bit_period);
            real diff_pct = (diff / nominal_period) * 100.0;
            if (diff_pct > cfg.baud_tolerance_pct) begin
                m_timing_error_count++;
                `uvm_warning(get_type_name(),
                    $sformatf("[SB TIMING] Measured bit period %0.2fns deviates %0.1f%% from nominal %0.2fns (> %0.1f%% tol)",
                              item.measured_bit_period, diff_pct, nominal_period, cfg.baud_tolerance_pct))
            end
        end
    endfunction

    // Helper to find substring in captured_stream
    virtual function bit contains_substring(string haystack, string needle);
        int h_len = haystack.len();
        int n_len = needle.len();
        if (n_len == 0) return 1;
        if (h_len < n_len) return 0;
        for (int i = 0; i <= h_len - n_len; i++) begin
            if (haystack.substr(i, i + n_len - 1) == needle) return 1;
        end
        return 0;
    endfunction

    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);

        // Check if all expected strings were received in the stream
        foreach (expected_string_q[i]) begin
            string target = expected_string_q[i];
            if (!contains_substring(captured_stream, target)) begin
                m_fail_count++;
                `uvm_error(get_type_name(),
                    $sformatf("[SB MISSING STRING] Expected token \"%s\" was not found in captured stream!",
                              target))
            end else begin
                `uvm_info(get_type_name(),
                    $sformatf("[SB FOUND STRING] Successfully matched expected token \"%s\"",
                              target), UVM_LOW)
            end
        end

        // Check if expected bytes remained unconsumed
        if (expected_byte_q.size() > 0) begin
            m_fail_count += expected_byte_q.size();
            `uvm_error(get_type_name(),
                $sformatf("[SB LEFTOVER] %0d expected bytes were not observed at simulation end!",
                          expected_byte_q.size()))
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info(get_type_name(),
            "============================================================", UVM_LOW)
        `uvm_info(get_type_name(),
            $sformatf("[UART_SB REPORT] bytes=%0d pass=%0d fail=%0d framing_err=%0d timing_err=%0d",
                      m_byte_count, m_pass_count, m_fail_count,
                      m_framing_error_count, m_timing_error_count), UVM_LOW)
        `uvm_info(get_type_name(),
            $sformatf("[UART_SB CAPTURE] Stream:\n\"%s\"", captured_stream), UVM_LOW)

        if (m_fail_count == 0 && m_framing_error_count == 0 && m_byte_count > 0) begin
            `uvm_info(get_type_name(), "uart_serial_scoreboard: PASS", UVM_LOW)
        end else begin
            `uvm_info(get_type_name(), "uart_serial_scoreboard: FAIL", UVM_LOW)
        end
        `uvm_info(get_type_name(),
            "============================================================", UVM_LOW)
    endfunction

endclass : uart_serial_scoreboard
