// =============================================================================
// VIP: uart_serial_base_seq
// File: uart_serial_base_seq.sv
//
// Description:
//   Sequence library for the uart_serial VIP.
//   Provides basic sequences for active stimulus transmission, string emission,
//   and negative error injection.
// =============================================================================
`timescale 1ns/1ps

// Base sequence
class uart_serial_base_seq extends uvm_sequence #(uart_serial_seq_item);

    `uvm_object_utils(uart_serial_base_seq)

    function new(string name = "uart_serial_base_seq");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info(get_type_name(), "Executing uart_serial_base_seq", UVM_HIGH)
    endtask

endclass : uart_serial_base_seq


// Single directed byte sequence
class uart_transmit_byte_seq extends uart_serial_base_seq;

    `uvm_object_utils(uart_transmit_byte_seq)

    rand bit [7:0] send_byte;

    function new(string name = "uart_transmit_byte_seq");
        super.new(name);
    endfunction

    virtual task body();
        uart_serial_seq_item item;
        item = uart_serial_seq_item::type_id::create("item");
        start_item(item);
        if (!item.randomize() with {
            data                 == local::send_byte;
            inject_framing_error == 1'b0;
            inject_parity_error  == 1'b0;
        }) begin
            `uvm_fatal(get_type_name(), "Randomization failed in uart_transmit_byte_seq")
        end
        finish_item(item);
    endtask

endclass : uart_transmit_byte_seq


// String transmission sequence
class uart_transmit_string_seq extends uart_serial_base_seq;

    `uvm_object_utils(uart_transmit_string_seq)

    string send_str = "UART\n";

    function new(string name = "uart_transmit_string_seq");
        super.new(name);
    endfunction

    virtual task body();
        uart_serial_seq_item item;
        for (int i = 0; i < send_str.len(); i++) begin
            item = uart_serial_seq_item::type_id::create($sformatf("item_%0d", i));
            start_item(item);
            item.data = byte'(send_str[i]);
            item.inject_framing_error = 1'b0;
            item.inject_parity_error  = 1'b0;
            finish_item(item);
        end
    endtask

endclass : uart_transmit_string_seq


// Deliberate framing error injection sequence (Test 11 support)
class uart_inject_framing_err_seq extends uart_serial_base_seq;

    `uvm_object_utils(uart_inject_framing_err_seq)

    rand bit [7:0] send_byte;

    function new(string name = "uart_inject_framing_err_seq");
        super.new(name);
        send_byte = 8'hA5;
    endfunction

    virtual task body();
        uart_serial_seq_item item;
        item = uart_serial_seq_item::type_id::create("item_err");
        start_item(item);
        item.data = send_byte;
        item.inject_framing_error = 1'b1; // Missing stop bit (driven low)
        item.inject_parity_error  = 1'b0;
        finish_item(item);
    endtask

endclass : uart_inject_framing_err_seq
