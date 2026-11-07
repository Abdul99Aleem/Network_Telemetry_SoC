// =============================================================================
// VIP: uart_serial_pkg
// File: uart_serial_pkg.sv
//
// Description:
//   Top-level SystemVerilog package for the uart_serial VIP.
//   Includes all VIP classes in compilation order.
// =============================================================================
`timescale 1ns/1ps

package uart_serial_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // 1. Transaction Item
    `include "uart_serial_seq_item.sv"

    // 2. Configuration Object
    `include "uart_serial_cfg.sv"

    // 3. Sequencer
    `include "uart_serial_sequencer.sv"

    // 4. Driver & Monitor
    `include "uart_serial_driver.sv"
    `include "uart_serial_monitor.sv"

    // 5. Scoreboard & Coverage Subscriber
    `include "uart_serial_scoreboard.sv"
    `include "uart_serial_coverage.sv"

    // 6. Agent
    `include "uart_serial_agent.sv"

    // 7. Environment
    `include "uart_serial_env.sv"

    // 8. Sequence Library
    `include "uart_serial_base_seq.sv"

    // 9. Test Library
    `include "uart_serial_test.sv"

endpackage : uart_serial_pkg
