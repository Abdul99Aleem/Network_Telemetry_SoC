// =============================================================================
// VIP: uart_serial_env
// File: uart_serial_env.sv
//
// Description:
//   Top-level UVM environment for the uart_serial VIP.
//   Instantiates the agent, scoreboard, and optional coverage subscriber.
// =============================================================================
`timescale 1ns/1ps

class uart_serial_env extends uvm_env;

    `uvm_component_utils(uart_serial_env)

    uart_serial_agent                   agent;
    uart_serial_scoreboard              sb;
    uart_serial_coverage_subscriber     cov;
    uart_serial_cfg                     cfg;

    function new(string name = "uart_serial_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Retrieve cfg to inspect feature enables
        if (!uvm_config_db #(uart_serial_cfg)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal(get_type_name(), "uart_serial_cfg not found in config_db")
        end

        // Pass cfg to agent
        uvm_config_db #(uart_serial_cfg)::set(this, "agent", "cfg", cfg);

        agent = uart_serial_agent::type_id::create("agent", this);
        sb    = uart_serial_scoreboard::type_id::create("sb", this);
        sb.cfg = cfg;

        if (cfg.enable_coverage) begin
            cov = uart_serial_coverage_subscriber::type_id::create("cov", this);
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        // Connect agent analysis port to scoreboard
        agent.ap.connect(sb.m_analysis_imp);

        // Connect agent analysis port to coverage subscriber
        if (cfg.enable_coverage && cov != null) begin
            agent.ap.connect(cov.analysis_export);
        end
    endfunction

endclass : uart_serial_env
