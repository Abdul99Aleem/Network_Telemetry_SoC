// =============================================================================
// VIP: veer_ahb_pkg
// File: veer_ahb_pkg.sv
//
// Description:
//   Package that includes all VIP source files in compilation dependency
//   order.  Import this package (and the interface file separately, which
//   cannot be inside a package) in the filelist.
// =============================================================================
`timescale 1ns/1ps

package veer_ahb_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Types first (enums used by seq_item and all other classes)
    `include "veer_ahb_seq_item.sv"

    // Configuration object (needed by agent, driver, monitor)
    `include "veer_ahb_cfg.sv"

    // Sequencer (needed by driver and agent)
    `include "veer_ahb_sequencer.sv"

    // Driver and monitor (need seq_item + cfg)
    `include "veer_ahb_driver.sv"
    `include "veer_ahb_monitor.sv"

    // Agent (needs driver + monitor + sequencer + cfg)
    `include "veer_ahb_agent.sv"

    // Scoreboard (needs seq_item)
    `include "veer_ahb_scoreboard.sv"

    // Environment (needs agent + scoreboard)
    `include "veer_ahb_env.sv"

    // Sequences (need seq_item)
    `include "veer_ahb_base_seq.sv"

    // Test (needs env + cfg + seq)
    `include "veer_ahb_test.sv"

endpackage : veer_ahb_pkg
