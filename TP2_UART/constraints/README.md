# Restricciones de placa

[`Basys3_UART.xdc`](Basys3_UART.xdc) conecta el módulo `uart_top` con la Digilent
Basys 3. Conserva el reloj W5, el reset U18 y los LEDs LD0..LD8 de TP1, y añade
RX B18, TX A18, LD9 para TX ocupado y LD10 para error retenido.

El reloj se declara a 100 MHz y todos los puertos usan `LVCMOS33`. El archivo
también identifica los sincronizadores y limita las excepciones de las
entradas asíncronas a su primera etapa.

Agregar este XDC al proyecto TP2 junto con `src/uart_top.v` como top de diseño.
No agregar el XDC de TP1: sus nombres de puertos pertenecen a otro TOP.
La tabla completa de pines, el dispositivo tomado de TP1 y las instrucciones
de conexión están en [`src/README.md`](../src/README.md).
