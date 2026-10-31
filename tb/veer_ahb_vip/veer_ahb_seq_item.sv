// =============================================================================
// VIP: veer_ahb_seq_item
// Project: RISC-V Network Telemetry SoC
// File: veer_ahb_seq_item.sv
//
// Description:
//   Sequence item representing one AHB-Lite beat on either the IFU or LSU
//   master port of soc_top.  Covers both ports in a single item — the driver
//   selects which port to drive from the 'port_sel' field.
//
//   Stimulus fields (rand): address, control, write-data.
//   Response fields (non-rand): rdata, hresp — written back by the driver
//   after the data phase completes, so a sequence can inspect the result.
//
//   Constraints reflect the SoC's actual legal traffic:
//     - IMEM (IFU): 0x0000_0000–0x0000_7FFF, read-only, word/double-word
//     - DMEM (LSU): 0x0001_0000–0x0001_7FFF, read/write
//     - UART (LSU): 0x1000_0000–0x1000_0FFF, word-aligned R/W
//     - Other:      0x1000_1000–0x1FFF_FFFF → ERROR slave (legal to send)
// =============================================================================
`timescale 1ns/1ps

// AHB-Lite type definitions (mirrors VeeR EL2 PRM signal encoding)
typedef enum bit [1:0] { AHB_IDLE=2'b00, AHB_BUSY=2'b01,
                         AHB_NONSEQ=2'b10, AHB_SEQ=2'b11 } e_htrans_t;
typedef enum bit [2:0] { AHB_BYTE=3'b000, AHB_HWORD=3'b001,
                         AHB_WORD=3'b010, AHB_DWORD=3'b011 } e_hsize_t;
typedef enum bit [2:0] { AHB_SINGLE=3'b000, AHB_INCR=3'b001,
                         AHB_WRAP4=3'b010,  AHB_INCR4=3'b011,
                         AHB_WRAP8=3'b100,  AHB_INCR8=3'b101 } e_hburst_t;
typedef enum bit       { AHB_READ=1'b0, AHB_WRITE=1'b1 } e_hwrite_t;
typedef enum bit       { PORT_IFU=1'b0, PORT_LSU=1'b1  } e_port_sel_t;

class veer_ahb_seq_item extends uvm_sequence_item;

    `uvm_object_utils_begin(veer_ahb_seq_item)
        `uvm_field_enum(e_port_sel_t, port_sel,   UVM_ALL_ON)
        `uvm_field_int (haddr,                    UVM_ALL_ON)
        `uvm_field_enum(e_htrans_t,   htrans,     UVM_ALL_ON)
        `uvm_field_enum(e_hsize_t,    hsize,      UVM_ALL_ON)
        `uvm_field_enum(e_hburst_t,   hburst,     UVM_ALL_ON)
        `uvm_field_enum(e_hwrite_t,   hwrite,     UVM_ALL_ON)
        `uvm_field_int (hprot,                    UVM_ALL_ON)
        `uvm_field_int (hmastlock,                UVM_ALL_ON)
        `uvm_field_int (hwdata,                   UVM_ALL_ON)
        `uvm_field_int (hrdata,                   UVM_ALL_ON | UVM_NOCOMPARE)
        `uvm_field_int (hresp,                    UVM_ALL_ON | UVM_NOCOMPARE)
    `uvm_object_utils_end

    // ---- Randomisable stimulus fields ----
    rand e_port_sel_t port_sel;
    rand bit [31:0]   haddr;
    rand e_htrans_t   htrans;
    rand e_hsize_t    hsize;
    rand e_hburst_t   hburst;
    rand e_hwrite_t   hwrite;
    rand bit [3:0]    hprot;
    rand bit          hmastlock;
    rand bit [63:0]   hwdata;    // 64-bit to match VeeR's 64-bit AHB data bus

    // ---- Response fields (filled in by driver) ----
    bit [63:0]        hrdata;
    bit               hresp;

    // ---- Default constraint: legal single NONSEQ word transfer ----
    constraint c_default {
        htrans    == AHB_NONSEQ;
        hsize     == AHB_WORD;
        hburst    == AHB_SINGLE;
        hmastlock == 1'b0;
    }

    // ---- IFU is fetch-only: no writes, address in IMEM ----
    constraint c_ifu_read_only {
        if (port_sel == PORT_IFU) {
            hwrite == AHB_READ;
            haddr inside {[32'h0000_0000 : 32'h0000_7FFF]};
            hsize inside {AHB_WORD, AHB_DWORD};
            haddr[1:0] == 2'b00;  // 4-byte aligned
        }
    }

    // ---- LSU can target DMEM or UART; word-aligned for UART ----
    constraint c_lsu_addr {
        if (port_sel == PORT_LSU) {
            haddr inside {
                [32'h0001_0000 : 32'h0001_7FFF],  // DMEM
                [32'h1000_0000 : 32'h1000_0FFF]   // UART
            };
        }
    }

    function new(string name = "veer_ahb_seq_item");
        super.new(name);
    endfunction

    virtual function string convert2string();
        return $sformatf("port=%s addr=0x%08h htrans=%s hsize=%s hwrite=%s hwdata=0x%016h hrdata=0x%016h hresp=%0b",
            port_sel.name(), haddr, htrans.name(), hsize.name(),
            hwrite.name(), hwdata, hrdata, hresp);
    endfunction

endclass : veer_ahb_seq_item
