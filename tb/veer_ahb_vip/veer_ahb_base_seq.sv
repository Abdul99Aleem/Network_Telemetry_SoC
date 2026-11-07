// =============================================================================
// VIP: veer_ahb_base_seq
// File: veer_ahb_base_seq.sv
//
// Description:
//   Base sequence.  Sends a configurable number of randomised AHB beats.
//   Extend this class and override body() for directed or constrained tests.
// =============================================================================
`timescale 1ns/1ps

class veer_ahb_base_seq extends uvm_sequence #(veer_ahb_seq_item);

    `uvm_object_utils(veer_ahb_base_seq)

    int unsigned num_beats = 10;

    function new(string name = "veer_ahb_base_seq");
        super.new(name);
    endfunction

    virtual task body();
        veer_ahb_seq_item item;
        `uvm_info(get_type_name(),
            $sformatf("Starting base sequence: %0d beats", num_beats), UVM_MEDIUM)
        repeat (num_beats) begin
            item = veer_ahb_seq_item::type_id::create("item");
            start_item(item);
            if (!item.randomize())
                `uvm_fatal(get_type_name(), "Randomization failed")
            finish_item(item);
        end
        `uvm_info(get_type_name(), "Base sequence complete", UVM_MEDIUM)
    endtask

endclass : veer_ahb_base_seq
