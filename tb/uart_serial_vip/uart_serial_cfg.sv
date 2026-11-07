// =============================================================================
// VIP: uart_serial_cfg
// File: uart_serial_cfg.sv
//
// Description:
//   Configuration object for the uart_serial VIP.
//   Decouples component logic from physical interface and encapsulates all
//   timing parameters, protocol options, error checks, and verification knobs.
// =============================================================================
`timescale 1ns/1ps

class uart_serial_cfg extends uvm_object;

    `uvm_object_utils(uart_serial_cfg)

    // Virtual interface handle
    virtual uart_serial_if vif;

    // Agent operational mode (default PASSIVE for soc_top external observation)
    uvm_active_passive_enum is_active = UVM_PASSIVE;

    // Timing and baud parameters
    bit                     auto_calibrate_baud = 1;
    real                    nominal_baud        = 115200.0;
    realtime                fixed_bit_period    = 8690ns;   // 869 cycles @ 100 MHz
    real                    baud_tolerance_pct  = 5.0;      // +/- 5% tolerance

    // Frame format
    int unsigned            data_bits           = 8;
    uart_parity_e           parity_type         = PARITY_NONE;
    uart_stop_bits_e        stop_bits           = STOP_1;

    // Verification and assertion switches
    bit                     enable_framing_check   = 1;
    bit                     enable_irq_check       = 1;  // Verify irq_o == 0 in TX-only
    bit                     enable_baud_check      = 1;
    bit                     enable_scoreboard      = 1;
    bit                     enable_coverage        = 1;
    bit                     enable_char_logging    = 1;

    function new(string name = "uart_serial_cfg");
        super.new(name);
    endfunction

    // Helper: compute bit period in ns from nominal baud
    virtual function realtime get_nominal_bit_period();
        if (nominal_baud > 0.0)
            return (1.0e9 / nominal_baud) * 1ns;
        else
            return fixed_bit_period;
    endfunction

endclass : uart_serial_cfg
