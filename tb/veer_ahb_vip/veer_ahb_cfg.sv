// =============================================================================
// VIP: veer_ahb_cfg
// File: veer_ahb_cfg.sv
//
// Description:
//   Configuration object for the veer_ahb VIP.  Holds the virtual interface
//   handle and any per-test knobs.  Passed from tb_top → test → agent via
//   uvm_config_db — the agent and its sub-components never reference the
//   interface hierarchy directly.
// =============================================================================
`timescale 1ns/1ps

class veer_ahb_cfg extends uvm_object;

    `uvm_object_utils(veer_ahb_cfg)

    // Virtual interface handle — set by tb_top, retrieved by the test,
    // injected into agent sub-components through the cfg object.
    virtual veer_ahb_if vif;

    // When 1, the monitor emits UVM_HIGH verbosity for every captured beat.
    bit enable_beat_log = 1;

    // When 1, the monitor runs basic AHB-Lite protocol assertions inline.
    bit enable_protocol_check = 1;

    function new(string name = "veer_ahb_cfg");
        super.new(name);
    endfunction

endclass : veer_ahb_cfg
