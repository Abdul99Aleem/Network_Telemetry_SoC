// =============================================================================
// VIP: uart_serial_test
// File: uart_serial_test.sv
//
// Description:
//   Test library for the uart_serial VIP.
//   Includes base test, unit-level loopback test (validating driver + monitor),
//   framing error test (Test 11), and SoC-driven integration test (Tests 10 & 15).
// =============================================================================
`timescale 1ns/1ps

// Base test
class uart_serial_base_test extends uvm_test;

    `uvm_component_utils(uart_serial_base_test)

    uart_serial_env env;
    uart_serial_cfg cfg;

    function new(string name = "uart_serial_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        cfg = uart_serial_cfg::type_id::create("cfg");

        // Retrieve virtual interface placed by tb_top
        if (!uvm_config_db #(virtual uart_serial_if)::get(this, "", "vif", cfg.vif)) begin
            `uvm_fatal(get_type_name(),
                "virtual uart_serial_if not found in config_db — check tb_top")
        end

        // Default: PASSIVE monitor mode on soc_top pins
        cfg.is_active           = UVM_PASSIVE;
        cfg.auto_calibrate_baud = 1;
        cfg.nominal_baud        = 115200.0;
        cfg.fixed_bit_period    = 8690ns;
        cfg.enable_baud_check   = 1;
        cfg.enable_irq_check    = 1;
        cfg.enable_coverage     = 1;

        // Publish cfg for env and subcomponents
        uvm_config_db #(uart_serial_cfg)::set(this, "env*", "cfg", cfg);

        env = uart_serial_env::type_id::create("env", this);
    endfunction

    virtual task reset_phase(uvm_phase phase);
        super.reset_phase(phase);
        phase.raise_objection(this);
        cfg.vif.reset_n = 1'b0;
        repeat (10) @(posedge cfg.vif.clk);
        cfg.vif.reset_n = 1'b1;
        repeat (5) @(posedge cfg.vif.clk);
        phase.drop_objection(this);
    endtask

endclass : uart_serial_base_test


// Unit loopback test: verifies VIP driver, monitor, and scoreboard standalone
class uart_unit_loopback_test extends uart_serial_base_test;

    `uvm_component_utils(uart_unit_loopback_test)

    function new(string name = "uart_unit_loopback_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // Active mode: driver will generate serial frames
        cfg.is_active           = UVM_ACTIVE;
        cfg.nominal_baud        = 115200.0;
        cfg.fixed_bit_period    = 8690ns;
        cfg.auto_calibrate_baud = 1;
    endfunction

    virtual task main_phase(uvm_phase phase);
        uart_transmit_string_seq seq;
        phase.raise_objection(this);

        // Pre-load expected string into scoreboard
        env.sb.expected_string_q.push_back("UART\n");

        seq = uart_transmit_string_seq::type_id::create("seq");
        seq.send_str = "UART\n";
        seq.start(env.agent.seqr);

        // Allow trailing stop bit to settle
        #(cfg.fixed_bit_period * 4);

        phase.drop_objection(this);
    endtask

endclass : uart_unit_loopback_test


// Test 10: SoC-driven UART transmission test
class uart_soc_tx_test extends uart_serial_base_test;

    `uvm_component_utils(uart_soc_tx_test)

    function new(string name = "uart_soc_tx_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        cfg.is_active           = UVM_PASSIVE;
        cfg.auto_calibrate_baud = 1;
        cfg.nominal_baud        = 115200.0;
        cfg.fixed_bit_period    = 8690ns;
    endfunction

    virtual task main_phase(uvm_phase phase);
        phase.raise_objection(this);

        // Expect "UART\n" payload from Phase-3 / Test-10 image
        env.sb.expected_string_q.push_back("UART\n");

        // Wait until scoreboard receives at least 5 bytes or timeout (1 ms)
        fork
            begin
                wait (env.sb.m_byte_count >= 5);
                #(cfg.fixed_bit_period * 2);
            end
            begin
                #1000us;
                `uvm_error(get_type_name(), "Timeout waiting for UART bytes from soc_top!")
            end
        join_any

        phase.drop_objection(this);
    endtask

endclass : uart_soc_tx_test


// Test 11: Deliberate framing error injection test
class uart_framing_error_test extends uart_serial_base_test;

    `uvm_component_utils(uart_framing_error_test)

    function new(string name = "uart_framing_error_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        cfg.is_active            = UVM_ACTIVE;
        cfg.enable_framing_check = 0; // Don't fail the run on the deliberate error
    endfunction

    virtual task main_phase(uvm_phase phase);
        uart_inject_framing_err_seq seq;
        phase.raise_objection(this);

        seq = uart_inject_framing_err_seq::type_id::create("seq");
        seq.send_byte = 8'hA5;
        seq.start(env.agent.seqr);

        #(cfg.fixed_bit_period * 3);

        if (env.sb.m_framing_error_count == 1) begin
            `uvm_info(get_type_name(),
                "PASS: Deliberate framing error was successfully detected by monitor & scoreboard",
                UVM_LOW)
        end else begin
            `uvm_error(get_type_name(),
                $sformatf("FAIL: Expected 1 framing error, observed %0d",
                          env.sb.m_framing_error_count))
        end

        phase.drop_objection(this);
    endtask

endclass : uart_framing_error_test
