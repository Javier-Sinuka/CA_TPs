## Restricciones para Digilent Basys 3 rev. B.
## Dispositivo: xc7a35ticpg236-1L
##
## Convencion elegida para este TP:
##   button_1 = btnU, button_2 = btnD, button_3 = btnL
##   reset    = btnC
##   btnR queda sin utilizar.
## Si la numeracion fisica de los botones debe ser otra, cambiar solamente
## el PACKAGE_PIN de cada puerto button_*.

## Reloj onboard de 100 MHz (periodo = 10 ns).
set_property -dict { PACKAGE_PIN W5 IOSTANDARD LVCMOS33 } [get_ports clock]
create_clock -add -name sys_clk_pin -period 10.000 -waveform {0.000 5.000} [get_ports clock]

## Switches SW0..SW7 conectados al bus de datos.
set_property -dict { PACKAGE_PIN V17 IOSTANDARD LVCMOS33 } [get_ports {bus[0]}]
set_property -dict { PACKAGE_PIN V16 IOSTANDARD LVCMOS33 } [get_ports {bus[1]}]
set_property -dict { PACKAGE_PIN W16 IOSTANDARD LVCMOS33 } [get_ports {bus[2]}]
set_property -dict { PACKAGE_PIN W17 IOSTANDARD LVCMOS33 } [get_ports {bus[3]}]
set_property -dict { PACKAGE_PIN W15 IOSTANDARD LVCMOS33 } [get_ports {bus[4]}]
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 } [get_ports {bus[5]}]
set_property -dict { PACKAGE_PIN W14 IOSTANDARD LVCMOS33 } [get_ports {bus[6]}]
set_property -dict { PACKAGE_PIN W13 IOSTANDARD LVCMOS33 } [get_ports {bus[7]}]

## Botones de carga y reset.
set_property -dict { PACKAGE_PIN T18 IOSTANDARD LVCMOS33 } [get_ports button_1]
set_property -dict { PACKAGE_PIN U17 IOSTANDARD LVCMOS33 } [get_ports button_2]
set_property -dict { PACKAGE_PIN W19 IOSTANDARD LVCMOS33 } [get_ports button_3]
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports reset]

## LEDs LD0..LD7 muestran el resultado de la ALU.
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN E19 IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN V19 IOSTANDARD LVCMOS33 } [get_ports {led[3]}]
set_property -dict { PACKAGE_PIN W18 IOSTANDARD LVCMOS33 } [get_ports {led[4]}]
set_property -dict { PACKAGE_PIN U15 IOSTANDARD LVCMOS33 } [get_ports {led[5]}]
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports {led[6]}]
set_property -dict { PACKAGE_PIN V14 IOSTANDARD LVCMOS33 } [get_ports {led[7]}]

## LED auxiliar: se enciende mientras reset esta activo.
set_property -dict { PACKAGE_PIN V13 IOSTANDARD LVCMOS33 } [get_ports test_led]
