verdiSetActWin -dock widgetDock_<Message>
simSetSimulator "-vcssv" -exec "simv" -args
debImport "-dbdir" "simv.daidir"
debLoadSimResult /home/student/Documents/honours_project/run/aes_axi_slave.fsdb
wvCreateWindow
wvGetSignalOpen -win $_nWave2
wvGetSignalSetScope -win $_nWave2 "/tb_aes_axi_slave"
wvSetPosition -win $_nWave2 {("G1" 10)}
wvSetPosition -win $_nWave2 {("G1" 10)}
wvAddSignal -win $_nWave2 -clear
wvAddSignal -win $_nWave2 -group {"G1" \
{/tb_aes_axi_slave/s_axi_awaddr\[31:0\]} \
{/tb_aes_axi_slave/s_axi_awready} \
{/tb_aes_axi_slave/s_axi_awvalid} \
{/tb_aes_axi_slave/s_axi_bready} \
{/tb_aes_axi_slave/s_axi_bresp\[1:0\]} \
{/tb_aes_axi_slave/s_axi_bvalid} \
{/tb_aes_axi_slave/s_axi_wdata\[31:0\]} \
{/tb_aes_axi_slave/s_axi_wready} \
{/tb_aes_axi_slave/s_axi_wstrb\[3:0\]} \
{/tb_aes_axi_slave/s_axi_wvalid} \
}
wvAddSignal -win $_nWave2 -group {"G2" \
}
wvSelectSignal -win $_nWave2 {( "G1" 1 2 3 4 5 6 7 8 9 10 )} 
wvSetPosition -win $_nWave2 {("G1" 10)}
wvSetPosition -win $_nWave2 {("G1" 10)}
wvSetPosition -win $_nWave2 {("G1" 10)}
wvAddSignal -win $_nWave2 -clear
wvAddSignal -win $_nWave2 -group {"G1" \
{/tb_aes_axi_slave/s_axi_awaddr\[31:0\]} \
{/tb_aes_axi_slave/s_axi_awready} \
{/tb_aes_axi_slave/s_axi_awvalid} \
{/tb_aes_axi_slave/s_axi_bready} \
{/tb_aes_axi_slave/s_axi_bresp\[1:0\]} \
{/tb_aes_axi_slave/s_axi_bvalid} \
{/tb_aes_axi_slave/s_axi_wdata\[31:0\]} \
{/tb_aes_axi_slave/s_axi_wready} \
{/tb_aes_axi_slave/s_axi_wstrb\[3:0\]} \
{/tb_aes_axi_slave/s_axi_wvalid} \
}
wvAddSignal -win $_nWave2 -group {"G2" \
}
wvSelectSignal -win $_nWave2 {( "G1" 1 2 3 4 5 6 7 8 9 10 )} 
wvSetPosition -win $_nWave2 {("G1" 10)}
wvGetSignalClose -win $_nWave2
wvZoomAll -win $_nWave2
wvZoomAll -win $_nWave2
wvSetCursor -win $_nWave2 693728.092368 -snap {("G2" 0)}
debExit
