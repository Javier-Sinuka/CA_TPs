# Restricciones de placa

El archivo `Basys3_ALU.xdc` contiene las restricciones para una Digilent Basys
3 con dispositivo `xc7a35ticpg236-1L`. Asigna el reloj de 100 MHz, ocho
switches al bus `bus`, tres botones de carga, un botón de reset, ocho LEDs de
resultado y un LED auxiliar.

La correspondencia de `button_1`, `button_2` y `button_3` es una convención del
proyecto. Si la práctica exige otra numeración física, se deben cambiar los
`PACKAGE_PIN` de esas tres señales sin modificar la ALU.
