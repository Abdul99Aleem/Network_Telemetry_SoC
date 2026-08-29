verdiSetActWin -dock widgetDock_<Watch>
wvCreateWindow
wvSetPosition -win $_nWave2 {("G1" 0)}
wvOpenFile -win $_nWave2 \
           {/home/student/Documents/honours_contents/honours_project/run/axi_interconnect_2x8.fsdb}
verdiSetActWin -dock widgetDock_MTB_SOURCE_TAB_1
verdiSetActWin -win $_nWave2
wvGetSignalOpen -win $_nWave2
wvGetSignalSetScope -win $_nWave2 "/tb_axi_interconnect_2x8"
wvGetSignalSetScope -win $_nWave2 \
           "/tb_axi_interconnect_2x8/Unnamed_\$tb_axi_interconnect_2x8_sv_1237"
wvGetSignalSetScope -win $_nWave2 "/tb_axi_interconnect_2x8"
wvGetSignalSetScope -win $_nWave2 "/tb_axi_interconnect_2x8/dut"
wvGetSignalSetScope -win $_nWave2 "/tb_axi_interconnect_2x8"
wvGetSignalSetSignalFilter -win $_nWave2 "valid"
wvSetPosition -win $_nWave2 {("G1" 0)}
wvSetPosition -win $_nWave2 {("G1" 0)}
wvAddSignal -win $_nWave2 -clear
wvAddSignal -win $_nWave2 -group {"G1" \
}
wvSetPosition -win $_nWave2 {("G1" 0)}
wvGetSignalOpen -win $_nWave2
wvSetPosition -win $_nWave2 {("G1" 2)}
wvSetPosition -win $_nWave2 {("G1" 2)}
wvAddSignal -win $_nWave2 -clear
wvAddSignal -win $_nWave2 -group {"G1" \
{/tb_axi_interconnect_2x8/m0_arready} \
{/tb_axi_interconnect_2x8/m0_arvalid} \
}
wvAddSignal -win $_nWave2 -group {"G2" \
}
wvSelectSignal -win $_nWave2 {( "G1" 1 2 )} 
wvSetPosition -win $_nWave2 {("G1" 2)}
wvSetPosition -win $_nWave2 {("G1" 2)}
wvSetPosition -win $_nWave2 {("G1" 2)}
wvAddSignal -win $_nWave2 -clear
wvAddSignal -win $_nWave2 -group {"G1" \
{/tb_axi_interconnect_2x8/m0_arready} \
{/tb_axi_interconnect_2x8/m0_arvalid} \
}
wvAddSignal -win $_nWave2 -group {"G2" \
}
wvSelectSignal -win $_nWave2 {( "G1" 1 2 )} 
wvSetPosition -win $_nWave2 {("G1" 2)}
wvGetSignalClose -win $_nWave2
verdiDockWidgetHide -dock widgetDock_<Watch>
srcTBSetHiddenView -view WatchView
wvGetSignalOpen -win $_nWave2
wvGetSignalSetScope -win $_nWave2 "/tb_axi_interconnect_2x8"
wvGetSignalSetScope -win $_nWave2 "/tb_axi_interconnect_2x8"
wvSetPosition -win $_nWave2 {("G1" 3)}
wvSetPosition -win $_nWave2 {("G1" 3)}
wvAddSignal -win $_nWave2 -clear
wvAddSignal -win $_nWave2 -group {"G1" \
{/tb_axi_interconnect_2x8/m0_arready} \
{/tb_axi_interconnect_2x8/m0_arvalid} \
{/tb_axi_interconnect_2x8/m0_araddr\[31:0\]} \
}
wvAddSignal -win $_nWave2 -group {"G2" \
}
wvSelectSignal -win $_nWave2 {( "G1" 3 )} 
wvSetPosition -win $_nWave2 {("G1" 3)}
wvSetPosition -win $_nWave2 {("G1" 3)}
wvSetPosition -win $_nWave2 {("G1" 3)}
wvAddSignal -win $_nWave2 -clear
wvAddSignal -win $_nWave2 -group {"G1" \
{/tb_axi_interconnect_2x8/m0_arready} \
{/tb_axi_interconnect_2x8/m0_arvalid} \
{/tb_axi_interconnect_2x8/m0_araddr\[31:0\]} \
}
wvAddSignal -win $_nWave2 -group {"G2" \
}
wvSelectSignal -win $_nWave2 {( "G1" 3 )} 
wvSetPosition -win $_nWave2 {("G1" 3)}
wvGetSignalClose -win $_nWave2
verdiSetActWin -dock widgetDock_<Inst._Tree>
verdiSetActWin -win $_nWave2
wvGetSignalOpen -win $_nWave2
wvGetSignalSetScope -win $_nWave2 "/tb_axi_interconnect_2x8"
wvGetSignalSetScope -win $_nWave2 "/tb_axi_interconnect_2x8"
