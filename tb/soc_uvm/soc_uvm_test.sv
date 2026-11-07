// ============================================================================
// File: tb/soc_uvm/soc_uvm_test.sv
// Description: UVM Test for C Firmware execution on VeeR EL2 SoC.
//              Monitors physical UART transmission, checks DMEM mailbox,
//              and validates end-to-end execution.
// ============================================================================

`ifndef SOC_UVM_TEST_SV
`define SOC_UVM_TEST_SV

class soc_c_firmware_test extends uvm_test;
    `uvm_component_utils(soc_c_firmware_test)

    soc_uvm_env     m_env;
    uart_serial_cfg m_uart_cfg;

    function new(string name = "soc_c_firmware_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info(get_type_name(), "Building soc_c_firmware_test...", UVM_LOW)

        m_uart_cfg = uart_serial_cfg::type_id::create("m_uart_cfg");

        // Retrieve virtual interface placed by tb_top
        if (!uvm_config_db #(virtual uart_serial_if)::get(this, "", "vif", m_uart_cfg.vif)) begin
            `uvm_fatal(get_type_name(),
                "virtual uart_serial_if not found in config_db — check soc_uvm_tb_top")
        end

        m_uart_cfg.is_active = UVM_PASSIVE; // Pure passive monitoring on SoC UART TX
        // C firmware sets UART_BAUD_SIM = 8 (yielding 90ns bit period @ 100MHz)
        m_uart_cfg.nominal_baud = (1.0e9 / 90.0); // 11.11 MHz simulation baud
        m_uart_cfg.auto_calibrate_baud = 1;
        m_uart_cfg.fixed_bit_period = 90ns;
        m_uart_cfg.baud_tolerance_pct = 5.0;
        m_uart_cfg.enable_baud_check = 1;
        m_uart_cfg.enable_coverage = 1;

        // Pass UART config to m_env
        uvm_config_db#(uart_serial_cfg)::set(this, "m_env*", "cfg", m_uart_cfg);

        m_env = soc_uvm_env::type_id::create("m_env", this);
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        // Expect key tokens in UART transcript
        m_env.m_uart_env.sb.expected_string_q.push_back("SUITE_BEGIN");
        m_env.m_uart_env.sb.expected_string_q.push_back("PASS");
        m_env.m_uart_env.sb.expected_string_q.push_back("SUITE_END");
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        `uvm_info(get_type_name(), "soc_c_firmware_test running: VeeR EL2 executing C firmware...", UVM_LOW)

        // Wait for firmware execution and UART transmission
        // In full suite with 14 tests, execution takes ~2.4 ms (2,400,000 ns).
        // Wait 3.5 ms for suite to complete, then drop objection cleanly.
        #3_500_000ns;

        `uvm_info(get_type_name(), "soc_c_firmware_test run phase complete.", UVM_LOW)
        phase.drop_objection(this);
    endtask

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info(get_type_name(), "=================================================", UVM_LOW)
        `uvm_info(get_type_name(), "          SOC C FIRMWARE UVM TEST SUMMARY        ", UVM_LOW)
        `uvm_info(get_type_name(), $sformatf(" UART Total Bytes Received: %0d", m_env.m_uart_env.sb.m_byte_count), UVM_LOW)
        `uvm_info(get_type_name(), $sformatf(" UART Pass Matches:         %0d", m_env.m_uart_env.sb.m_pass_count), UVM_LOW)
        `uvm_info(get_type_name(), $sformatf(" UART Fail Mismatches:     %0d", m_env.m_uart_env.sb.m_fail_count), UVM_LOW)
        `uvm_info(get_type_name(), $sformatf(" UART Framing Errors:      %0d", m_env.m_uart_env.sb.m_framing_error_count), UVM_LOW)
        `uvm_info(get_type_name(), $sformatf(" UART Timing Deviations:   %0d", m_env.m_uart_env.sb.m_timing_error_count), UVM_LOW)
        `uvm_info(get_type_name(), "=================================================", UVM_LOW)

        if (m_env.m_uart_env.sb.m_fail_count == 0 &&
            m_env.m_uart_env.sb.m_framing_error_count == 0 &&
            m_env.m_uart_env.sb.m_timing_error_count == 0 &&
            m_env.m_uart_env.sb.m_byte_count > 0) begin
            `uvm_info(get_type_name(), "TEST PASSED: VeeR C firmware executed and UART verified!", UVM_NONE)
        end else begin
            `uvm_error(get_type_name(), "TEST FAILED: UART scoreboard errors observed or no bytes received.")
        end
    endfunction

endclass: soc_c_firmware_test

`endif // SOC_UVM_TEST_SV
