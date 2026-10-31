// =============================================================================
// VIP: veer_ahb_driver
// File: veer_ahb_driver.sv
//
// Description:
//   AHB-Lite master driver for the soc_top IFU and LSU ports.
//
//   AHB-Lite is a pipelined protocol: the address phase of transfer N+1
//   overlaps the data phase of transfer N.  This driver implements that
//   overlap using a semaphore (one key = bus ownership):
//
//     Thread T1 (and T2 if needed for back-to-back):
//       1. Acquire semaphore key — means address bus is free.
//       2. Drive address/control on the clocking-block output.
//       3. Wait for HREADY (slave may insert wait states).
//       4. Release semaphore key — address phase is done, data phase owns bus.
//       5. Drive HWDATA (for writes) or sample HRDATA (for reads).
//       6. Call item_done() to tell the sequencer this item is consumed.
//
//   Both IFU and LSU ports are driven independently.  The item's port_sel
//   field routes the beat to the correct set of interface signals.
//
//   Reset phase: drives IDLE / zero on all output signals.
// =============================================================================
`timescale 1ns/1ps

class veer_ahb_driver extends uvm_driver #(veer_ahb_seq_item);

    `uvm_component_utils(veer_ahb_driver)

    virtual veer_ahb_if vif;
    veer_ahb_cfg        cfg;
    semaphore           m_sema4;

    function new(string name = "veer_ahb_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m_sema4 = new(1);
        // vif is assigned in connect_phase from cfg (set by the agent)
    endfunction

    // -------------------------------------------------------------------------
    // reset_phase — park all outputs in a safe IDLE state
    // -------------------------------------------------------------------------
    virtual task reset_phase(uvm_phase phase);
        super.reset_phase(phase);
        phase.raise_objection(this);

        // IFU — IDLE, no transfer
        vif.cb.ifu_htrans    <= AHB_IDLE;
        vif.cb.ifu_haddr     <= '0;
        vif.cb.ifu_hburst    <= AHB_SINGLE;
        vif.cb.ifu_hsize     <= AHB_WORD;
        vif.cb.ifu_hwrite    <= AHB_READ;
        vif.cb.ifu_hprot     <= 4'b0011;   // data, privileged
        vif.cb.ifu_hmastlock <= 1'b0;

        // LSU — IDLE, no transfer
        vif.cb.lsu_htrans    <= AHB_IDLE;
        vif.cb.lsu_haddr     <= '0;
        vif.cb.lsu_hburst    <= AHB_SINGLE;
        vif.cb.lsu_hsize     <= AHB_WORD;
        vif.cb.lsu_hwrite    <= AHB_READ;
        vif.cb.lsu_hwdata    <= '0;
        vif.cb.lsu_hprot     <= 4'b0011;
        vif.cb.lsu_hmastlock <= 1'b0;

        phase.drop_objection(this);
    endtask

    // -------------------------------------------------------------------------
    // main_phase — fetch and drive items
    // -------------------------------------------------------------------------
    virtual task main_phase(uvm_phase phase);
        super.main_phase(phase);
        // Two parallel threads allow address-phase of next item to be set up
        // while the current item's data phase is still in progress.
        fork
            drive_thread("T1");
            drive_thread("T2");
        join
    endtask

    // -------------------------------------------------------------------------
    // drive_thread — one pipeline slot
    // -------------------------------------------------------------------------
    virtual task automatic drive_thread(string tag);
        veer_ahb_seq_item item;
        forever begin
            // ---- ADDRESS PHASE ----
            m_sema4.get(1);
            seq_item_port.get_next_item(item);

            `uvm_info(get_type_name(),
                $sformatf("[%s] ADDR_PHASE: %s", tag, item.convert2string()),
                UVM_HIGH)

            // Wait until the slave is ready to accept a new address phase
            while (!get_hready(item.port_sel)) @(vif.cb);

            drive_addr_phase(item);

            // Wait for address phase to be accepted (HREADY=1 + NONSEQ beat)
            @(vif.cb);
            // Insert IDLE after address to be safe with single-beat transactions
            drive_idle(item.port_sel);
            m_sema4.put(1);

            // ---- DATA PHASE ----
            // Wait for HREADY — slave may insert wait states during data phase
            while (!get_hready(item.port_sel)) @(vif.cb);

            if (item.hwrite == AHB_WRITE) begin
                drive_wdata(item);
            end else begin
                item.hrdata = get_hrdata(item.port_sel);
            end
            item.hresp = get_hresp(item.port_sel);

            `uvm_info(get_type_name(),
                $sformatf("[%s] DATA_PHASE done: %s", tag, item.convert2string()),
                UVM_HIGH)

            seq_item_port.item_done();
        end
    endtask

    // -------------------------------------------------------------------------
    // Helper: drive address/control signals for one beat
    // -------------------------------------------------------------------------
    task automatic drive_addr_phase(veer_ahb_seq_item item);
        if (item.port_sel == PORT_IFU) begin
            vif.cb.ifu_haddr     <= item.haddr;
            vif.cb.ifu_htrans    <= item.htrans;
            vif.cb.ifu_hsize     <= item.hsize;
            vif.cb.ifu_hburst    <= item.hburst;
            vif.cb.ifu_hwrite    <= AHB_READ;    // IFU is always read
            vif.cb.ifu_hprot     <= item.hprot;
            vif.cb.ifu_hmastlock <= item.hmastlock;
        end else begin
            vif.cb.lsu_haddr     <= item.haddr;
            vif.cb.lsu_htrans    <= item.htrans;
            vif.cb.lsu_hsize     <= item.hsize;
            vif.cb.lsu_hburst    <= item.hburst;
            vif.cb.lsu_hwrite    <= item.hwrite;
            vif.cb.lsu_hprot     <= item.hprot;
            vif.cb.lsu_hmastlock <= item.hmastlock;
        end
    endtask

    // -------------------------------------------------------------------------
    // Helper: drive IDLE on chosen port (between beats)
    // -------------------------------------------------------------------------
    task automatic drive_idle(e_port_sel_t port);
        if (port == PORT_IFU)
            vif.cb.ifu_htrans <= AHB_IDLE;
        else
            vif.cb.lsu_htrans <= AHB_IDLE;
    endtask

    // -------------------------------------------------------------------------
    // Helper: drive HWDATA on LSU write
    // -------------------------------------------------------------------------
    task automatic drive_wdata(veer_ahb_seq_item item);
        if (item.port_sel == PORT_LSU)
            vif.cb.lsu_hwdata <= item.hwdata;
    endtask

    // -------------------------------------------------------------------------
    // Helper: sample HREADY from chosen port
    // -------------------------------------------------------------------------
    function automatic bit get_hready(e_port_sel_t port);
        return (port == PORT_IFU) ? vif.cb.ifu_hready : vif.cb.lsu_hready;
    endfunction

    // -------------------------------------------------------------------------
    // Helper: sample HRDATA from chosen port
    // -------------------------------------------------------------------------
    function automatic bit [63:0] get_hrdata(e_port_sel_t port);
        return (port == PORT_IFU) ? vif.cb.ifu_hrdata : vif.cb.lsu_hrdata;
    endfunction

    // -------------------------------------------------------------------------
    // Helper: sample HRESP from chosen port
    // -------------------------------------------------------------------------
    function automatic bit get_hresp(e_port_sel_t port);
        return (port == PORT_IFU) ? vif.cb.ifu_hresp : vif.cb.lsu_hresp;
    endfunction

endclass : veer_ahb_driver
