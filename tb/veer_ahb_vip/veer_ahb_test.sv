// =============================================================================
// VIP: veer_ahb_test
// File: veer_ahb_test.sv
//
// Description:
//   Base test.  Retrieves the virtual interface from config_db, builds the
//   cfg object, injects it for the agent, and runs the base sequence.
//   Extend this class to create directed tests (e.g. boot sequence,
//   UART register write, DMEM mailbox check).
// =============================================================================
`timescale 1ns/1ps

class veer_ahb_test extends uvm_test;

    `uvm_component_utils(veer_ahb_test)

    veer_ahb_env        env;
    veer_ahb_cfg        cfg;
    veer_ahb_base_seq   seq;

    function new(string name = "veer_ahb_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Build cfg and retrieve virtual interface from tb_top
        cfg = veer_ahb_cfg::type_id::create("cfg");
        if (!uvm_config_db #(virtual veer_ahb_if)::get(this, "", "vif", cfg.vif))
            `uvm_fatal(get_type_name(),
                "veer_ahb_if not found in config_db — check tb_top uvm_config_db::set()")

        // Publish cfg so the agent's build_phase can find it
        uvm_config_db #(veer_ahb_cfg)::set(this, "env.agent", "cfg", cfg);

        env = veer_ahb_env::type_id::create("env", this);
        seq = veer_ahb_base_seq::type_id::create("seq");
    endfunction

    // Reset phase: hold reset for 5 cycles
    virtual task reset_phase(uvm_phase phase);
        super.reset_phase(phase);
        phase.raise_objection(this);
        cfg.vif.reset_n = 1'b0;
        repeat (5) @(posedge cfg.vif.hclk);
        cfg.vif.reset_n = 1'b1;
        repeat (2) @(posedge cfg.vif.hclk);
        phase.drop_objection(this);
    endtask

    // Main phase: run the sequence
    virtual task main_phase(uvm_phase phase);
        super.main_phase(phase);
        phase.raise_objection(this);
        seq.start(env.agent.seqr);
        phase.drop_objection(this);
    endtask

endclass : veer_ahb_test
