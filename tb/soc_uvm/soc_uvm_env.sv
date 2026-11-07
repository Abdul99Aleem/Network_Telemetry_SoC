// ============================================================================
// File: tb/soc_uvm/soc_uvm_env.sv
// Description: UVM Environment for SoC Level Verification.
//              Reuses the complete uart_serial_env component.
// ============================================================================

`ifndef SOC_UVM_ENV_SV
`define SOC_UVM_ENV_SV

class soc_uvm_env extends uvm_env;
    `uvm_component_utils(soc_uvm_env)

    uart_serial_env m_uart_env;
    uart_serial_cfg m_uart_cfg;

    function new(string name = "soc_uvm_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info(get_type_name(), "Building soc_uvm_env...", UVM_MEDIUM)

        if (!uvm_config_db#(uart_serial_cfg)::get(this, "", "cfg", m_uart_cfg)) begin
            `uvm_info(get_type_name(), "soc_uvm_env: creating default uart_serial_cfg", UVM_MEDIUM)
            m_uart_cfg = uart_serial_cfg::type_id::create("m_uart_cfg");
            m_uart_cfg.is_active = UVM_PASSIVE;
            m_uart_cfg.nominal_baud = 115200.0;
            m_uart_cfg.auto_calibrate_baud = 1;
            m_uart_cfg.fixed_bit_period = 8690ns;
            m_uart_cfg.baud_tolerance_pct = 5.0;
            m_uart_cfg.enable_coverage = 1;
        end

        // Pass config down to m_uart_env
        uvm_config_db#(uart_serial_cfg)::set(this, "m_uart_env*", "cfg", m_uart_cfg);

        m_uart_env = uart_serial_env::type_id::create("m_uart_env", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        `uvm_info(get_type_name(), "Connecting soc_uvm_env...", UVM_MEDIUM)
    endfunction

endclass: soc_uvm_env

`endif // SOC_UVM_ENV_SV
