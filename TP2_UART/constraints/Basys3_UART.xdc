## Restricciones para Digilent Basys 3, TOP uart_top.
## Dispositivo configurado en TP1: xc7a35ticpg236-1L.
## Reloj, boton central y LD0..LD8 conservan los pines de TP1.
## Pines UART y LEDs adicionales verificados con el archivo oficial:
## https://github.com/Digilent/digilent-xdc/blob/master/Basys-3-Master.xdc

## Reloj onboard de 100 MHz (periodo = 10 ns).
set_property -dict { PACKAGE_PIN W5 IOSTANDARD LVCMOS33 } [get_ports i_clock]
create_clock -add -name sys_clk_pin -period 10.000 -waveform {0.000 5.000} [get_ports i_clock]

## Reset activo en alto: boton central btnC.
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports i_reset]

## Puente USB-UART onboard (conector micro-USB J4, PROG).
## Direcciones desde la FPGA: B18 recibe de la PC, A18 transmite a la PC.
set_property -dict { PACKAGE_PIN B18 IOSTANDARD LVCMOS33 } [get_ports i_rx]
set_property -dict { PACKAGE_PIN A18 IOSTANDARD LVCMOS33 } [get_ports o_tx]

## LD0..LD7 muestran el ultimo resultado cargado en la interfaz TX.
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports {o_leds[0]}]
set_property -dict { PACKAGE_PIN E19 IOSTANDARD LVCMOS33 } [get_ports {o_leds[1]}]
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports {o_leds[2]}]
set_property -dict { PACKAGE_PIN V19 IOSTANDARD LVCMOS33 } [get_ports {o_leds[3]}]
set_property -dict { PACKAGE_PIN W18 IOSTANDARD LVCMOS33 } [get_ports {o_leds[4]}]
set_property -dict { PACKAGE_PIN U15 IOSTANDARD LVCMOS33 } [get_ports {o_leds[5]}]
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports {o_leds[6]}]
set_property -dict { PACKAGE_PIN V14 IOSTANDARD LVCMOS33 } [get_ports {o_leds[7]}]

## LD8: reset sincronizado; LD9: TX ocupado; LD10: error retenido hasta reset.
set_property -dict { PACKAGE_PIN V13 IOSTANDARD LVCMOS33 } [get_ports o_reset_led]
set_property -dict { PACKAGE_PIN V3 IOSTANDARD LVCMOS33 } [get_ports o_tx_busy_led]
set_property -dict { PACKAGE_PIN W3 IOSTANDARD LVCMOS33 } [get_ports o_error_led]

## Marcar los dos registros de sincronizacion ya existentes en uart_rx.
set_property ASYNC_REG TRUE [get_cells {u_uart_rx/r_rx_sync_reg[0] u_uart_rx/r_rx_sync_reg[1]}]

## Las entradas asincronas terminan en la PRIMERA etapa de cada sincronizador.
## La ruta entre ambas etapas conserva su analisis temporal a 100 MHz.
set_false_path -from [get_ports i_reset] -to [get_pins {r_reset_sync_reg[0]/D}]
set_false_path -from [get_ports i_rx] -to [get_pins {u_uart_rx/r_rx_sync_reg[0]/D}]

## LEDs y TX serial no son salidas muestreadas por un reloj externo sincrono.
set_false_path -to [get_ports {o_tx o_leds[*] o_reset_led o_tx_busy_led o_error_led}]

## Configuracion electrica del banco de configuracion de la Basys 3.
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
