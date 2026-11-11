## Basys3 · top_debug (B-17).
set_property -dict { PACKAGE_PIN W5  IOSTANDARD LVCMOS33 } [get_ports i_clk100]
create_clock -period 10.000 -name sys_clk_pin [get_ports i_clk100]
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports i_btn_reset]
set_property -dict { PACKAGE_PIN B18 IOSTANDARD LVCMOS33 } [get_ports i_rx]
set_property -dict { PACKAGE_PIN A18 IOSTANDARD LVCMOS33 } [get_ports o_tx]

## LEDs LD0..LD15
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports {o_led[0]}]
set_property -dict { PACKAGE_PIN E19 IOSTANDARD LVCMOS33 } [get_ports {o_led[1]}]
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports {o_led[2]}]
set_property -dict { PACKAGE_PIN V19 IOSTANDARD LVCMOS33 } [get_ports {o_led[3]}]
set_property -dict { PACKAGE_PIN W18 IOSTANDARD LVCMOS33 } [get_ports {o_led[4]}]
set_property -dict { PACKAGE_PIN U15 IOSTANDARD LVCMOS33 } [get_ports {o_led[5]}]
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports {o_led[6]}]
set_property -dict { PACKAGE_PIN V14 IOSTANDARD LVCMOS33 } [get_ports {o_led[7]}]
set_property -dict { PACKAGE_PIN V13 IOSTANDARD LVCMOS33 } [get_ports {o_led[8]}]
set_property -dict { PACKAGE_PIN V3  IOSTANDARD LVCMOS33 } [get_ports {o_led[9]}]
set_property -dict { PACKAGE_PIN W3  IOSTANDARD LVCMOS33 } [get_ports {o_led[10]}]
set_property -dict { PACKAGE_PIN U3  IOSTANDARD LVCMOS33 } [get_ports {o_led[11]}]
set_property -dict { PACKAGE_PIN P3  IOSTANDARD LVCMOS33 } [get_ports {o_led[12]}]
set_property -dict { PACKAGE_PIN N3  IOSTANDARD LVCMOS33 } [get_ports {o_led[13]}]
set_property -dict { PACKAGE_PIN P1  IOSTANDARD LVCMOS33 } [get_ports {o_led[14]}]
set_property -dict { PACKAGE_PIN L1  IOSTANDARD LVCMOS33 } [get_ports {o_led[15]}]

## Entradas asíncronas: van a sincronizadores de 2 FF (ASYNC_REG en el RTL).
set_false_path -from [get_ports {i_btn_reset i_rx}]
set_false_path -to   [get_ports {o_tx o_led[*]}]

set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
