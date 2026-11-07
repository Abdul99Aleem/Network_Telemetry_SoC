// =============================================================================
// VIP: uart_serial_coverage
// File: uart_serial_coverage.sv
//
// Description:
//   Dedicated functional coverage subscriber for the uart_serial VIP.
//   Collects coverage on data bytes, ASCII character ranges, framing integrity,
//   interrupt line status, and measured bit period ranges (in nanoseconds).
// =============================================================================
`timescale 1ns/1ps

class uart_serial_coverage_subscriber extends uvm_subscriber #(uart_serial_seq_item);

    `uvm_component_utils(uart_serial_coverage_subscriber)

    uart_serial_seq_item m_item;
    int unsigned         m_bit_period_ns;

    covergroup uart_frame_cg;
        option.per_instance = 1;
        option.name = "uart_frame_coverage";

        // Data byte distribution
        cp_data: coverpoint m_item.data {
            bins low_range       = {[8'h00:8'h1F]};
            bins ascii_printable = {[8'h20:8'h7E]};
            bins high_range      = {[8'h7F:8'hFF]};
            bins newline         = {8'h0A};
            bins cr              = {8'h0D};
        }

        // Framing error coverage (validates positive and negative tests)
        cp_framing_error: coverpoint m_item.framing_error {
            bins no_error = {1'b0};
            bins error    = {1'b1};
        }

        // Interrupt pin surveillance
        cp_irq: coverpoint m_item.irq_state {
            bins irq_low  = {1'b0};
            bins irq_high = {1'b1};
        }

        // Measured bit period ranges (integral nanoseconds)
        cp_bit_period: coverpoint m_bit_period_ns {
            bins fast_sim_baud   = {[50:200]};       // ~90ns simulation rate
            bins standard_115200 = {[8000:9500]};    // ~8690ns 115.2k baud
            bins other           = default;
        }

        // Cross of data and framing
        cx_data_framing: cross cp_data, cp_framing_error;
    endgroup

    function new(string name = "uart_serial_coverage_subscriber", uvm_component parent = null);
        super.new(name, parent);
        uart_frame_cg = new();
    endfunction

    virtual function void write(uart_serial_seq_item t);
        m_item = t;
        m_bit_period_ns = int'(t.measured_bit_period);
        uart_frame_cg.sample();
    endfunction

endclass : uart_serial_coverage_subscriber
