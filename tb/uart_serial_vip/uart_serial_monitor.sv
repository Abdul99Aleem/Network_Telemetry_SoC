// =============================================================================
// VIP: uart_serial_monitor
// File: uart_serial_monitor.sv
//
// Description:
//   Continuous serial monitor and frame deserializer. Observes the physical
//   pins (uart_tx_o, uart_irq_o), auto-calibrates / measures baud timing,
//   samples bits at nominal mid-eye positions, verifies 8N1 framing and stop bits,
//   surveils the interrupt line, and broadcasts completed uart_serial_seq_item
//   transactions via its analysis port.
// =============================================================================
`timescale 1ns/1ps

class uart_serial_monitor extends uvm_monitor;

    `uvm_component_utils(uart_serial_monitor)

    virtual uart_serial_if                  vif;
    uart_serial_cfg                         cfg;
    uvm_analysis_port #(uart_serial_seq_item) ap;

    // Calibration and statistics
    bit                                     m_calibrated = 0;
    realtime                                m_calibrated_bit_period;
    int unsigned                            m_frames_observed = 0;
    int unsigned                            m_framing_error_count = 0;

    function new(string name = "uart_serial_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (cfg == null) begin
            if (!uvm_config_db #(uart_serial_cfg)::get(this, "", "cfg", cfg))
                `uvm_fatal(get_type_name(), "uart_serial_cfg not found in config_db")
        end
        vif = cfg.vif;
    endfunction

    virtual task run_phase(uvm_phase phase);
        realtime t_start;
        realtime bit_period;
        uart_serial_seq_item item;
        bit [7:0] rx_byte;
        bit rx_stop_bit;
        bit framing_err;
        bit irq_err;
        int unsigned n_data;

        // Initialize bit period
        bit_period = (cfg.nominal_baud > 0.0) ?
                     ((1.0e9 / cfg.nominal_baud) * 1ns) : cfg.fixed_bit_period;
        m_calibrated_bit_period = bit_period;

        `uvm_info(get_type_name(),
            $sformatf("UART Monitor started. Initial nominal bit period = %0.2f ns (baud %0.1f)",
                      bit_period, cfg.nominal_baud), UVM_MEDIUM)

        forever begin
            // 1. Wait for reset inactive and line idle (high)
            wait (vif.reset_n === 1'b1);
            while (vif.uart_tx_o !== 1'b1) @(posedge vif.clk);

            // 2. Wait for start bit (falling edge) while out of reset
            @(negedge vif.uart_tx_o);
            if (vif.reset_n !== 1'b1) continue; // Ignore reset glitches

            t_start = $realtime;
            framing_err = 1'b0;
            irq_err     = 1'b0;

            // 3. Auto-calibration (if enabled and not yet calibrated)
            if (cfg.auto_calibrate_baud && !m_calibrated) begin
                fork : cal_fork
                    begin
                        @(posedge vif.uart_tx_o);
                        m_calibrated_bit_period = $realtime - t_start;
                        m_calibrated = 1'b1;
                        `uvm_info(get_type_name(),
                            $sformatf("Auto-calibrated bit period = %0.2f ns (calculated baud = %0.1f)",
                                      m_calibrated_bit_period,
                                      (1.0e9 / m_calibrated_bit_period)), UVM_LOW)
                    end
                    begin
                        // Fallback timeout: if first byte bit0 is not 1, timeout after 2 bit periods
                        #(bit_period * 2.5);
                    end
                join_any
                disable cal_fork;
            end

            bit_period = m_calibrated ? m_calibrated_bit_period : cfg.get_nominal_bit_period();

            // 4. Align to center of data bit 0: (t_start + 1.5 * bit_period)
            #( (1.5 * bit_period) - ($realtime - t_start) );

            // 5. Sample 8 data bits (LSB first)
            n_data = (cfg.data_bits > 0) ? cfg.data_bits : 8;
            for (int k = 0; k < n_data; k++) begin
                rx_byte[k] = vif.uart_tx_o;
                if (vif.uart_irq_o !== 1'b0) irq_err = 1'b1;
                if (k != (n_data - 1)) #(bit_period);
            end

            // 6. Parity bit sampling (if configured)
            if (cfg.parity_type != PARITY_NONE) begin
                #(bit_period);
                // Can evaluate parity here
            end

            // 7. Stop bit sampling (center of stop bit)
            #(bit_period);
            rx_stop_bit = vif.uart_tx_o;
            if (rx_stop_bit !== 1'b1) begin
                framing_err = 1'b1;
                m_framing_error_count++;
                if (cfg.enable_framing_check) begin
                    `uvm_error(get_type_name(),
                        $sformatf("Framing error detected: stop bit is %b (expected 1'b1) after byte 0x%02h",
                                  rx_stop_bit, rx_byte))
                end
            end

            // 8. Interrupt pin assertion check
            if (cfg.enable_irq_check && (vif.uart_irq_o !== 1'b0 || irq_err)) begin
                `uvm_error(get_type_name(),
                    $sformatf("Spurious uart_irq_o asserted during TX-only operation (sampled %b)",
                              vif.uart_irq_o))
            end

            m_frames_observed++;

            // 9. Create and populate sequence item
            item = uart_serial_seq_item::type_id::create("item");
            item.data                   = rx_byte;
            item.framing_error          = framing_err;
            item.parity_error           = 1'b0;
            item.irq_state              = vif.uart_irq_o;
            item.frame_start_time       = t_start;
            item.frame_end_time         = $realtime;
            item.measured_bit_period    = bit_period;
            item.calculated_baud_rate   = (bit_period > 0.0) ? (1.0e9 / bit_period) : 0.0;

            if (cfg.enable_char_logging) begin
                byte c = byte'(rx_byte);
                string ch_str = (c >= 8'h20 && c <= 8'h7E) ? $sformatf("'%c'", c) : "<non-printable>";
                `uvm_info(get_type_name(),
                    $sformatf("Sampled byte #%0d: 0x%02h %s (bit_period=%0.1fns, baud=%0.1f)",
                              m_frames_observed, rx_byte, ch_str, bit_period, item.calculated_baud_rate),
                    UVM_MEDIUM)
            end

            // 10. Broadcast via analysis port
            ap.write(item);
        end
    endtask

endclass : uart_serial_monitor
