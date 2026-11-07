// ============================================================================
// File: tb/soc_uvm/soc_uvm_pkg.sv
// Description: UVM Package for SoC Level Verification.
// ============================================================================

`ifndef SOC_UVM_PKG_SV
`define SOC_UVM_PKG_SV

`include "uvm_macros.svh"

package soc_uvm_pkg;
    import uvm_pkg::*;
    import uart_serial_pkg::*;

    `include "soc_uvm_env.sv"
    `include "soc_uvm_test.sv"

endpackage: soc_uvm_pkg

`endif // SOC_UVM_PKG_SV
