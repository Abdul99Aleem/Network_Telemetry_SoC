# ============================================================================
# P1 Verdi signal script — hello_world on VeeR EL2 default_ahb (AHB-Lite)
# Launch:  verdi -ssf dump.fsdb -dbdir simv.daidir -play p1_verdi_ahb.tcl &
# Scope:   tb_top  (TOP = tb_top, see snapshots/default_ahb/common_defines.vh)
#
# NOTE: default_ahb has NO AXI master ports. IFU/LSU/SB speak 64-bit AHB-Lite
# (RV_EXT_DATAWIDTH=64). The axi_crossbar_wrap_2x1 instance in simv is a
# testbench helper only — do NOT look for AXI here. AXI lines belong to the
# Phase-3 AES work (see footer).
# ============================================================================

wvCreateWindow

# --- 1. Clock / reset: assertion, deassertion, no re-assertion --------------
wvAddSignal -win $_nWave2 -group {"1_clk_rst" \
  {/tb_top/core_clk} \
  {/tb_top/rst_l} \
  {/tb_top/porst_l} \
}

# --- 2. CPU progress: PC, instruction, commit strobe, mailbox PASS/FAIL -----
wvAddSignal -win $_nWave2 -group {"2_cpu" \
  {/tb_top/trace_rv_i_address_ip} \
  {/tb_top/trace_rv_i_insn_ip} \
  {/tb_top/trace_rv_i_valid_ip} \
  {/tb_top/mailbox_write} \
  {/tb_top/mailbox_data} \
}

# --- 3. IFU AHB-Lite master (fetch-only: NO hwrite/hwdata) ------------------
wvAddSignal -win $_nWave2 -group {"3_ifu_ahb" \
  {/tb_top/ic_haddr} \
  {/tb_top/ic_htrans} \
  {/tb_top/ic_hwrite} \
  {/tb_top/ic_hsize} \
  {/tb_top/ic_hburst} \
  {/tb_top/ic_hprot} \
  {/tb_top/ic_hrdata} \
  {/tb_top/ic_hready} \
  {/tb_top/ic_hresp} \
}

# --- 4. LSU AHB-Lite master (mailbox sb to 0xD0580000 appears here) ---------
wvAddSignal -win $_nWave2 -group {"4_lsu_ahb" \
  {/tb_top/lsu_haddr} \
  {/tb_top/lsu_htrans} \
  {/tb_top/lsu_hwrite} \
  {/tb_top/lsu_hsize} \
  {/tb_top/lsu_hburst} \
  {/tb_top/lsu_hprot} \
  {/tb_top/lsu_hwdata} \
  {/tb_top/lsu_hrdata} \
  {/tb_top/lsu_hready} \
  {/tb_top/lsu_hresp} \
}

# --- 5. Mux + backing memory (arbitration LSU>SB, wait-states, response) ----
wvAddSignal -win $_nWave2 -group {"5_mux_mem" \
  {/tb_top/mux_haddr} \
  {/tb_top/mux_htrans} \
  {/tb_top/mux_hwrite} \
  {/tb_top/mux_hsize} \
  {/tb_top/mux_hwdata} \
  {/tb_top/mux_hrdata} \
  {/tb_top/mux_hready} \
  {/tb_top/mux_hresp} \
  {/tb_top/lmem_hrdata} \
  {/tb_top/lmem_hready} \
  {/tb_top/lmem_hresp} \
}

wvSetCursor -win $_nWave2 117000
wvZoomAll -win $_nWave2

# ============================================================================
# WHAT TO VERIFY (Phase-1 exit, AHB-Lite — NOT AXI):
#  a. rst_l 1->0@5ns->1@30ns; porst_l pulse; PC starts 0x80000000 (RV_RESET_VEC)
#  b. trace_rv_i_valid_ip pulses; insn/address advance (PC progression)
#  c. ic_htrans NONSEQ(2) on fetches; ic_hrdata returns; ic_hready=1; ic_hresp=0
#  d. lsu_haddr=0xD0580000 + lsu_hwrite=1 + lsu_hwdata=char + lsu_htrans=NONSEQ
#     for each "Hello World" byte; mailbox_write=1 in TB; HRESP=0, HREADY=1
#  e. No stuck HREADY=0; no HRESP=1; exactly one slave selected per transfer
#  f. console: "Hello World from VeeR EL2" + TEST_PASSED (minstret=330 here)
#
# AXI LINES (for Phase-3 AES TBs tb_axi_interconnect_aes*, NOT this run):
#  s00/m06_axi_awvalid/awready/awaddr | wvalid/wready/wdata/wstrb |
#  bvalid/bready/bresp/bid | arvalid/arready/araddr |
#  rvalid/rready/rdata/rresp/rid/rlast + aes wrapper busy_reg/done_reg/
#  irq_reg/aes_ld/aes_key/aes_text_in/aes_text_out/aes_done + key/data/result regs
# ============================================================================
