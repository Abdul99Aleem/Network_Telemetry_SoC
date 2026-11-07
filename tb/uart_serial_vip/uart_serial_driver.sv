// =============================================================================
// VIP: uart_serial_driver
// File: uart_serial_driver.sv
//
// Description:
//   Serial transmitter driver. When the VIP is instantiated in ACTIVE mode,
//   this driver consumes uart_serial_seq_item transactions and drives
//   the physical serial stream onto vif.uart_rx_i. Supports parity calculation
//   and intentional framing/parity error injection for negative testing.
// =============================================================================
`timescale 1ns/1ps

class uart_serial_driver extends uvm_driver #(uart_serial_seq_item);

    `uvm_component_utils(uart_serial_driver)

    virtual uart_serial_if vif;
    uart_serial_cfg        cfg;

    function new(string name = "uart_serial_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (cfg == null) begin
            if (!uvm_config_db #(uart_serial_cfg)::get(this, "", "cfg", cfg))
                `uvm_fatal(get_type_name(), "uart_serial_cfg not found in config_db")
        end
        vif = cfg.vif;
    endfunction

    virtual task run_phase(uvm_phase phase);
        uart_serial_seq_item req;
        realtime bit_period;

        // Line idle level
        vif.uart_rx_i = 1'b1;

        // Wait for reset release
        wait (vif.reset_n === 1'b1);
        @(posedge vif.clk);

        forever begin
            seq_item_port.get_next_item(req);

            bit_period = (cfg.nominal_baud > 0.0) ?
                         ((1.0e9 / cfg.nominal_baud) * 1ns) : cfg.fixed_bit_period;

            drive_frame(req, bit_period);

            seq_item_port.item_done();
        end
    endtask

    virtual task drive_frame(uart_serial_seq_item item, realtime bit_period);
        bit parity_bit;
        int unsigned n_data;

        n_data = (item.data_bits > 0) ? item.data_bits : cfg.data_bits;

        // Compute parity bit
        if (cfg.parity_type == PARITY_EVEN)
            parity_bit = ^(item.data);
        else if (cfg.parity_type == PARITY_ODD)
            parity_bit = ~(^(item.data));
        else
            parity_bit = 1'b0;

        if (item.inject_parity_error)
            parity_bit = ~parity_bit;

        // 1. Start bit
        vif.uart_rx_i = item.inject_start_bit_error ? 1'b1 : 1'b0;
        #(bit_period);

        // 2. Data bits (LSB first)
        for (int k = 0; k < n_data; k++) begin
            vif.uart_rx_i = item.data[k];
            #(bit_period);
        end

        // 3. Parity bit
        if (cfg.parity_type != PARITY_NONE) begin
            vif.uart_rx_i = parity_bit;
            #(bit_period);
        end

        // 4. Stop bit(s)
        if (item.inject_framing_error)
            vif.uart_rx_i = 1'b0;  // Corrupted stop bit
        else
            vif.uart_rx_i = 1'b1;  // Valid stop bit
        #(bit_period);

        // Return to idle
        vif.uart_rx_i = 1'b1;
        #(bit_period);
    endtask

endclass : uart_serial_driver
