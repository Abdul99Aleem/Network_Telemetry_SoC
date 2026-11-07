// =============================================================================
// VIP: uart_serial_agent
// File: uart_serial_agent.sv
//
// Description:
//   Standard UVM agent encapsulating driver, sequencer, monitor, and cfg.
//   Supports both PASSIVE mode (monitor-only, for soc_top external observation)
//   and ACTIVE mode (for loopback/driver stimulus generation).
// =============================================================================
`timescale 1ns/1ps

class uart_serial_agent extends uvm_agent;

    `uvm_component_utils(uart_serial_agent)

    uart_serial_cfg                  cfg;
    uart_serial_driver               drv;
    uart_serial_sequencer            seqr;
    uart_serial_monitor              mon;
    uvm_analysis_port #(uart_serial_seq_item) ap;

    function new(string name = "uart_serial_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Retrieve configuration object
        if (!uvm_config_db #(uart_serial_cfg)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal(get_type_name(),
                "uart_serial_cfg not found in config_db — ensure test or tb_top sets it")
        end

        // Align agent active/passive state with cfg
        is_active = cfg.is_active;

        // Monitor is always created
        mon = uart_serial_monitor::type_id::create("mon", this);
        mon.cfg = cfg;
        mon.vif = cfg.vif;

        // Driver and sequencer only created in active mode
        if (get_is_active() == UVM_ACTIVE) begin
            drv  = uart_serial_driver::type_id::create("drv", this);
            seqr = uart_serial_sequencer::type_id::create("seqr", this);
            drv.cfg = cfg;
            drv.vif = cfg.vif;
        end

        ap = new("ap", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        // Forward analysis port
        mon.ap.connect(ap);

        // Connect driver to sequencer in active mode
        if (get_is_active() == UVM_ACTIVE) begin
            drv.seq_item_port.connect(seqr.seq_item_export);
        end
    endfunction

endclass : uart_serial_agent
