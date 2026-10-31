// =============================================================================
// VIP: veer_ahb_agent
// File: veer_ahb_agent.sv
//
// Description:
//   Composes the driver, monitor and sequencer.  Follows the standard UVM
//   pattern: driver and sequencer are only created when the agent is ACTIVE
//   (get_is_active() == UVM_ACTIVE).  The monitor is always created.
//
//   The cfg object is retrieved from config_db and forwarded to the driver
//   and monitor so they can access the virtual interface.
// =============================================================================
`timescale 1ns/1ps

class veer_ahb_agent extends uvm_agent;

    `uvm_component_utils(veer_ahb_agent)

    veer_ahb_cfg        cfg;
    veer_ahb_driver     drv;
    veer_ahb_monitor    mon;
    veer_ahb_sequencer  seqr;

    // Analysis port forwarded from monitor for external connections (env/scoreboard)
    uvm_analysis_port #(veer_ahb_seq_item) ap;

    function new(string name = "veer_ahb_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Retrieve configuration object
        if (!uvm_config_db #(veer_ahb_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal(get_type_name(), "veer_ahb_cfg not found in config_db — set it in tb_top or test")

        // Monitor is always built (active and passive)
        mon  = veer_ahb_monitor::type_id::create("mon",  this);
        mon.cfg = cfg;
        mon.vif = cfg.vif;

        // Driver + sequencer only in active mode
        if (get_is_active() == UVM_ACTIVE) begin
            drv  = veer_ahb_driver::type_id::create("drv",  this);
            seqr = veer_ahb_sequencer::type_id::create("seqr", this);
            drv.cfg = cfg;
            drv.vif = cfg.vif;
        end

        ap = new("ap", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        // Forward monitor analysis port
        mon.ap.connect(ap);
        // Connect driver to sequencer when active
        if (get_is_active() == UVM_ACTIVE)
            drv.seq_item_port.connect(seqr.seq_item_export);
    endfunction

endclass : veer_ahb_agent
