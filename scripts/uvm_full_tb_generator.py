#!/usr/bin/env python3
"""
UVM Testbench Generator
Usage:
  python uvm_full_tb_generator.py <vip_name> <signals.csv>

CSV format:
signal_name,direction,width
clk,input,1
rst_n,input,1
addr,input,32
rdata,output,32
"""

import csv
import os
import sys

if len(sys.argv) != 3:
    print('Usage: python uvm_full_tb_generator.py <vip_name> <signals.csv>')
    sys.exit(1)

VIP = sys.argv[1].lower()
CSV_FILE = sys.argv[2]

CLK_NAMES = ['clk', 'clock']
RST_NAMES = ['rst', 'rst_n', 'reset', 'reset_n']


def read_signals(csv_file):
    sigs = []
    with open(csv_file) as f:
        for row in csv.reader(f):
            if len(row) < 3:
                continue
            sigs.append({
                'name': row[0].strip(),
                'dir': row[1].strip().lower(),
                'width': int(row[2])
            })
    return sigs


def sv_type(width):
    return 'bit' if width == 1 else f'bit [{width-1}:0]'


def transaction(signals):
    s = f'class {VIP}_item extends uvm_sequence_item;\n\n'
    for sig in signals:
        if sig['name'] not in CLK_NAMES + RST_NAMES:
            rand = 'rand ' if sig['dir'] == 'input' else ''
            s += f'  {rand}{sv_type(sig["width"])} {sig["name"]};\n'
    s += f"\n  `uvm_object_utils({VIP}_item)\n\n"
    s += f"  function new(string name=\"{VIP}_item\"); super.new(name); endfunction\n"
    s += 'endclass\n'
    return s


def sequencer():
    return f'class {VIP}_sequencer extends uvm_sequencer #({VIP}_item);\n`uvm_component_utils({VIP}_sequencer)\nfunction new(string n,uvm_component p);super.new(n,p);endfunction\nendclass\n'


def driver():
    return f'class {VIP}_driver extends uvm_driver #({VIP}_item);\nvirtual {VIP}_if vif;\n`uvm_component_utils({VIP}_driver)\nfunction new(string n,uvm_component p);super.new(n,p);endfunction\ntask run_phase(uvm_phase phase); forever begin seq_item_port.get_next_item(req); @(posedge vif.clk); seq_item_port.item_done(); end endtask\nendclass\n'


def monitor():
    return f'class {VIP}_monitor extends uvm_monitor;\nvirtual {VIP}_if vif;\nuvm_analysis_port #({VIP}_item) ap;\n`uvm_component_utils({VIP}_monitor)\nfunction new(string n,uvm_component p); super.new(n,p); ap=new("ap",this); endfunction\nendclass\n'


def agent():
    return f'class {VIP}_agent extends uvm_agent;\n{VIP}_driver drv; {VIP}_monitor mon; {VIP}_sequencer seqr;\n`uvm_component_utils({VIP}_agent)\nfunction new(string n,uvm_component p);super.new(n,p);endfunction\nfunction void build_phase(uvm_phase phase); drv={VIP}_driver::type_id::create("drv",this); mon={VIP}_monitor::type_id::create("mon",this); seqr={VIP}_sequencer::type_id::create("seqr",this); endfunction\nfunction void connect_phase(uvm_phase phase); drv.seq_item_port.connect(seqr.seq_item_export); endfunction\nendclass\n'


def scoreboard():
    return f'class {VIP}_scoreboard extends uvm_scoreboard;\n`uvm_component_utils({VIP}_scoreboard)\nfunction new(string n,uvm_component p);super.new(n,p);endfunction\nendclass\n'


def env():
    return f'class {VIP}_env extends uvm_env;\n{VIP}_agent agent; {VIP}_scoreboard sb;\n`uvm_component_utils({VIP}_env)\nfunction new(string n,uvm_component p);super.new(n,p);endfunction\nfunction void build_phase(uvm_phase phase); agent={VIP}_agent::type_id::create("agent",this); sb={VIP}_scoreboard::type_id::create("sb",this); endfunction\nendclass\n'


def test():
    return f'class {VIP}_test extends uvm_test;\n{VIP}_env env;\n`uvm_component_utils({VIP}_test)\nfunction new(string n,uvm_component p);super.new(n,p);endfunction\nfunction void build_phase(uvm_phase phase); env={VIP}_env::type_id::create("env",this); endfunction\nendclass\n'


def interface(signals):
    s=f'interface {VIP}_if;\n'
    for sig in signals:
        if sig['width']==1:
            s+=f'logic {sig["name"]};\n'
        else:
            s+=f'logic [{sig["width"]-1}:0] {sig["name"]};\n'
    s+='endinterface\n'
    return s


def package():
    return f'package {VIP}_pkg;\nimport uvm_pkg::*;\n`include "uvm_macros.svh"\n`include "{VIP}_item.sv"\n`include "{VIP}_sequencer.sv"\n`include "{VIP}_driver.sv"\n`include "{VIP}_monitor.sv"\n`include "{VIP}_agent.sv"\n`include "{VIP}_scoreboard.sv"\n`include "{VIP}_env.sv"\n`include "{VIP}_test.sv"\nendpackage\n'


def tb_top():
    return f'module tb_top;\nimport uvm_pkg::*; import {VIP}_pkg::*;\n{VIP}_if vif();\ninitial run_test("{VIP}_test");\nendmodule\n'

signals = read_signals(CSV_FILE)
outdir = f'{VIP}_uvm_tb'
os.makedirs(outdir, exist_ok=True)
files = {
f'{VIP}_if.sv': interface(signals),
f'{VIP}_item.sv': transaction(signals),
f'{VIP}_sequencer.sv': sequencer(),
f'{VIP}_driver.sv': driver(),
f'{VIP}_monitor.sv': monitor(),
f'{VIP}_agent.sv': agent(),
f'{VIP}_scoreboard.sv': scoreboard(),
f'{VIP}_env.sv': env(),
f'{VIP}_test.sv': test(),
f'{VIP}_pkg.sv': package(),
'tb_top.sv': tb_top()
}
for n,c in files.items():
    open(os.path.join(outdir,n),'w').write(c)
print('Generated:', outdir)
