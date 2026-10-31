// =============================================================================
// VIP: veer_ahb_env
// File: veer_ahb_env.sv
//
// Description:
//   Top-level UVM environment.  Instantiates the agent and scoreboard,
//   connects the agent's analysis port to the scoreboard's analysis imp.
// =============================================================================
`timescale 1ns/1ps

class veer_ahb_env extends uvm_env;

    `uvm_component_utils(veer_ahb_env)

    veer_ahb_agent      agent;
    veer_ahb_scoreboard sb;

    function new(string name = "veer_ahb_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = veer_ahb_agent::type_id::create("agent", this);
        sb    = veer_ahb_scoreboard::type_id::create("sb",    this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.ap.connect(sb.m_analysis_imp);
    endfunction

endclass : veer_ahb_env
