// =============================================================================
// VIP: veer_ahb_sequencer
// File: veer_ahb_sequencer.sv
// =============================================================================
`timescale 1ns/1ps

class veer_ahb_sequencer extends uvm_sequencer #(veer_ahb_seq_item);
    `uvm_component_utils(veer_ahb_sequencer)
    function new(string name = "veer_ahb_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass : veer_ahb_sequencer
