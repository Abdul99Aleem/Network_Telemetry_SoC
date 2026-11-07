// =============================================================================
// VIP: uart_serial_seq_item
// File: uart_serial_seq_item.sv
//
// Description:
//   Sequence item representing a UART transmission or reception frame,
//   capturing both logical data bits and physical/timing characteristics.
// =============================================================================
`timescale 1ns/1ps

typedef enum bit [1:0] {
    PARITY_NONE = 2'b00,
    PARITY_EVEN = 2'b01,
    PARITY_ODD  = 2'b10
} uart_parity_e;

typedef enum bit [1:0] {
    STOP_1   = 2'b00,
    STOP_1_5 = 2'b01,
    STOP_2   = 2'b10
} uart_stop_bits_e;

class uart_serial_seq_item extends uvm_sequence_item;

    `uvm_object_utils(uart_serial_seq_item)

    // Data payload
    rand bit [7:0]          data;

    // Protocol configuration
    rand uart_parity_e      parity_type;
    rand uart_stop_bits_e   stop_bits;
    rand int unsigned       data_bits;

    // Error injection controls (for active driver)
    rand bit                inject_framing_error;
    rand bit                inject_parity_error;
    rand bit                inject_start_bit_error;

    // Detected frame attributes (populated by monitor)
    bit                     framing_error;
    bit                     parity_error;
    bit                     start_bit_error;
    bit                     irq_state;

    // Timing measurements
    realtime                frame_start_time;
    realtime                frame_end_time;
    realtime                measured_bit_period;
    real                    calculated_baud_rate;

    constraint default_cfg_c {
        soft parity_type            == PARITY_NONE;
        soft stop_bits              == STOP_1;
        soft data_bits              == 8;
        soft inject_framing_error   == 1'b0;
        soft inject_parity_error    == 1'b0;
        soft inject_start_bit_error == 1'b0;
    }

    function new(string name = "uart_serial_seq_item");
        super.new(name);
        data_bits   = 8;
        parity_type = PARITY_NONE;
        stop_bits   = STOP_1;
    endfunction

    virtual function void do_copy(uvm_object rhs);
        uart_serial_seq_item rhs_;
        if (!$cast(rhs_, rhs)) begin
            `uvm_fatal(get_type_name(), "Cast failed in do_copy()")
            return;
        end
        super.do_copy(rhs);
        this.data                   = rhs_.data;
        this.parity_type            = rhs_.parity_type;
        this.stop_bits              = rhs_.stop_bits;
        this.data_bits              = rhs_.data_bits;
        this.inject_framing_error   = rhs_.inject_framing_error;
        this.inject_parity_error    = rhs_.inject_parity_error;
        this.inject_start_bit_error = rhs_.inject_start_bit_error;
        this.framing_error          = rhs_.framing_error;
        this.parity_error           = rhs_.parity_error;
        this.start_bit_error        = rhs_.start_bit_error;
        this.irq_state              = rhs_.irq_state;
        this.frame_start_time       = rhs_.frame_start_time;
        this.frame_end_time         = rhs_.frame_end_time;
        this.measured_bit_period    = rhs_.measured_bit_period;
        this.calculated_baud_rate   = rhs_.calculated_baud_rate;
    endfunction

    virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        uart_serial_seq_item rhs_;
        if (!$cast(rhs_, rhs)) return 0;
        return (super.do_compare(rhs, comparer) &&
                (this.data          === rhs_.data) &&
                (this.framing_error === rhs_.framing_error) &&
                (this.parity_error  === rhs_.parity_error));
    endfunction

    virtual function string convert2string();
        string s;
        byte c = byte'(data);
        string ch_str = (c >= 8'h20 && c <= 8'h7E) ? $sformatf("'%c'", c) : "<non-printable>";
        s = $sformatf("data=0x%02h (%s) period=%0.2fns baud=%0.1f framing_err=%b irq=%b",
                      data, ch_str, measured_bit_period, calculated_baud_rate,
                      framing_error, irq_state);
        return s;
    endfunction

endclass : uart_serial_seq_item
