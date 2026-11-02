## Basys3 · top_uart_echo (B-05).
## Sin create_clock: el reloj de entrada lo restringe el XDC del Clock Wizard
## (o build_bit.tcl en modo --clk mmcm).
set_property -dict { PACKAGE_PIN W5  IOSTANDARD LVCMOS33 } [get_ports i_clk100]
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports i_btn_reset]
set_property -dict { PACKAGE_PIN B18 IOSTANDARD LVCMOS33 } [get_ports i_rx]
set_property -dict { PACKAGE_PIN A18 IOSTANDARD LVCMOS33 } [get_ports o_tx]
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports {o_led[0]}]
set_property -dict { PACKAGE_PIN E19 IOSTANDARD LVCMOS33 } [get_ports {o_led[1]}]
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports {o_led[2]}]
set_property -dict { PACKAGE_PIN V19 IOSTANDARD LVCMOS33 } [get_ports {o_led[3]}]

## Entradas asíncronas: van a sincronizadores de 2 FF (ASYNC_REG en el RTL).
set_false_path -from [get_ports {i_btn_reset i_rx}]
set_false_path -to   [get_ports {o_tx o_led[*]}]

set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
