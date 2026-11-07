// =============================================================================
// VIP: uart_serial_sequencer
// File: uart_serial_sequencer.sv
//
// Description:
//   Standard UVM sequencer parameterized on uart_serial_seq_item.
// =============================================================================
`timescale 1ns/1ps

class uart_serial_sequencer extends uvm_sequencer #(uart_serial_seq_item);

    `uvm_component_utils(uart_serial_sequencer)

    function new(string name = "uart_serial_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

endclass : uart_serial_sequencer
