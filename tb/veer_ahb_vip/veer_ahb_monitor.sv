// =============================================================================
// VIP: veer_ahb_monitor
// File: veer_ahb_monitor.sv
//
// Description:
//   Passive monitor for the soc_top IFU and LSU AHB-Lite master ports.
//   Never drives the interface.  Reconstructs completed AHB beats into
//   veer_ahb_seq_item objects and broadcasts them via the analysis port.
//
//   AHB-Lite beat reconstruction:
//     - Capture address/control on the cycle where HTRANS!=IDLE and HREADY=1
//       (address phase accepted).
//     - Capture HWDATA / HRDATA on the NEXT cycle where HREADY=1
//       (data phase complete).
//     - Build item and write to analysis port.
//
//   Two parallel threads run simultaneously: one for the IFU port and one
//   for the LSU port.  Each thread maintains its own address-phase state
//   because the DUT can drive both ports in the same clock cycle.
//
//   Optional inline protocol checks (gated by cfg.enable_protocol_check):
//     - Address must not change while HREADY=0 during the address phase.
//     - HRESP=ERROR must be followed by a two-cycle error response (v3 §2.4).
// =============================================================================
`timescale 1ns/1ps

class veer_ahb_monitor extends uvm_monitor;

    `uvm_component_utils(veer_ahb_monitor)

    virtual veer_ahb_if      vif;
    veer_ahb_cfg             cfg;
    uvm_analysis_port #(veer_ahb_seq_item) ap;

    function new(string name = "veer_ahb_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
    endfunction

    // -------------------------------------------------------------------------
    // run_phase — two parallel capture threads, one per port
    // -------------------------------------------------------------------------
    virtual task run_phase(uvm_phase phase);
        fork
            capture_port(PORT_IFU);
            capture_port(PORT_LSU);
        join
    endtask

    // -------------------------------------------------------------------------
    // capture_port — reconstruct beats for one master port
    // -------------------------------------------------------------------------
    task automatic capture_port(e_port_sel_t port);
        veer_ahb_seq_item item;
        // Saved address-phase fields (registered on accepted address cycle)
        bit [31:0]  saved_haddr;
        e_htrans_t  saved_htrans;
        e_hsize_t   saved_hsize;
        e_hburst_t  saved_hburst;
        e_hwrite_t  saved_hwrite;
        bit [3:0]   saved_hprot;
        bit         addr_phase_pending;

        addr_phase_pending = 0;

        forever begin
            @(vif.mon_cb);

            // ---------- Address phase detection ----------
            // A new beat starts when HTRANS is NONSEQ or SEQ and HREADY is 1
            if (get_htrans(port) inside {AHB_NONSEQ, AHB_SEQ} && get_hready(port)) begin

                // If there was a pending address phase, the previous data phase
                // must have completed in this same cycle — capture it first.
                if (addr_phase_pending) begin
                    item = veer_ahb_seq_item::type_id::create("item", this);
                    item.port_sel  = port;
                    item.haddr     = saved_haddr;
                    item.htrans    = saved_htrans;
                    item.hsize     = saved_hsize;
                    item.hburst    = saved_hburst;
                    item.hwrite    = saved_hwrite;
                    item.hprot     = saved_hprot;
                    // For back-to-back transfers HWDATA / HRDATA were valid this cycle
                    item.hwdata    = get_hwdata(port);
                    item.hrdata    = get_hrdata(port);
                    item.hresp     = get_hresp(port);

                    if (cfg.enable_beat_log)
                        `uvm_info(get_type_name(),
                            $sformatf("[MON %s] beat: %s", port.name(), item.convert2string()),
                            UVM_HIGH)

                    ap.write(item);
                end

                // Register new address phase
                saved_haddr  = get_haddr(port);
                saved_htrans = get_htrans(port);
                saved_hsize  = get_hsize(port);
                saved_hburst = get_hburst(port);
                saved_hwrite = get_hwrite(port);
                saved_hprot  = get_hprot(port);
                addr_phase_pending = 1;

            end
            // ---------- Data phase completion ----------
            // Data phase finishes when HREADY=1 and we have a pending beat
            else if (addr_phase_pending && get_hready(port)) begin
                item = veer_ahb_seq_item::type_id::create("item", this);
                item.port_sel  = port;
                item.haddr     = saved_haddr;
                item.htrans    = saved_htrans;
                item.hsize     = saved_hsize;
                item.hburst    = saved_hburst;
                item.hwrite    = saved_hwrite;
                item.hprot     = saved_hprot;
                item.hwdata    = get_hwdata(port);
                item.hrdata    = get_hrdata(port);
                item.hresp     = get_hresp(port);

                if (cfg.enable_beat_log)
                    `uvm_info(get_type_name(),
                        $sformatf("[MON %s] beat: %s", port.name(), item.convert2string()),
                        UVM_HIGH)

                // Protocol check: HRESP=ERROR (slave errors are a 2-cycle response)
                if (cfg.enable_protocol_check && item.hresp) begin
                    `uvm_warning(get_type_name(),
                        $sformatf("[MON %s] HRESP=ERROR on addr=0x%08h", port.name(), item.haddr))
                end

                ap.write(item);
                addr_phase_pending = 0;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Helpers: read interface signals for the selected port
    // All use the clocking block so there is no glitch risk.
    // -------------------------------------------------------------------------
    function automatic bit [31:0]  get_haddr  (e_port_sel_t p);
        return (p==PORT_IFU) ? vif.mon_cb.ifu_haddr  : vif.mon_cb.lsu_haddr;  endfunction
    function automatic e_htrans_t  get_htrans (e_port_sel_t p);
        return (p==PORT_IFU) ? e_htrans_t'(vif.mon_cb.ifu_htrans) : e_htrans_t'(vif.mon_cb.lsu_htrans); endfunction
    function automatic e_hsize_t   get_hsize  (e_port_sel_t p);
        return (p==PORT_IFU) ? e_hsize_t'(vif.mon_cb.ifu_hsize)  : e_hsize_t'(vif.mon_cb.lsu_hsize);  endfunction
    function automatic e_hburst_t  get_hburst (e_port_sel_t p);
        return (p==PORT_IFU) ? e_hburst_t'(vif.mon_cb.ifu_hburst): e_hburst_t'(vif.mon_cb.lsu_hburst); endfunction
    function automatic e_hwrite_t  get_hwrite (e_port_sel_t p);
        return (p==PORT_IFU) ? e_hwrite_t'(vif.mon_cb.ifu_hwrite): e_hwrite_t'(vif.mon_cb.lsu_hwrite); endfunction
    function automatic bit [3:0]   get_hprot  (e_port_sel_t p);
        return (p==PORT_IFU) ? vif.mon_cb.ifu_hprot  : vif.mon_cb.lsu_hprot;  endfunction
    function automatic bit         get_hready (e_port_sel_t p);
        return (p==PORT_IFU) ? vif.mon_cb.ifu_hready : vif.mon_cb.lsu_hready; endfunction
    function automatic bit         get_hresp  (e_port_sel_t p);
        return (p==PORT_IFU) ? vif.mon_cb.ifu_hresp  : vif.mon_cb.lsu_hresp;  endfunction
    function automatic bit [63:0]  get_hrdata (e_port_sel_t p);
        return (p==PORT_IFU) ? vif.mon_cb.ifu_hrdata : vif.mon_cb.lsu_hrdata; endfunction
    function automatic bit [63:0]  get_hwdata (e_port_sel_t p);
        return (p==PORT_IFU) ? 64'h0                 : vif.mon_cb.lsu_hwdata; endfunction

endclass : veer_ahb_monitor
