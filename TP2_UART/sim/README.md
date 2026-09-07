# Testbenches del TP2 UART

Esta carpeta contiene pruebas unitarias para cada bloque y pruebas de integración
para comprobar su funcionamiento en conjunto. Todos los archivos `.sv` son
exclusivos de simulación y deben agregarse en Vivado como **Simulation Sources**.
No se sintetizan ni forman parte del hardware implementado en la FPGA.

## Pruebas de los módulos UART

### `tb_baud_gen.sv`

Prueba `baud_gen.v`. Verifica que el tick aparezca con el período calculado a
partir de la frecuencia del reloj, el baud rate y el sobremuestreo. También
comprueba que cada tick dure exactamente un ciclo de reloj y que el generador
vuelva a comenzar correctamente después de un reset.

### `tb_uart_rx.sv`

Prueba `uart_rx.v` enviando tramas UART simuladas por la entrada serial. Comprueba:

- Recepción de los bytes `A5`, `00` y `FF`.
- Duración de un ciclo del pulso `o_valid`.
- Rechazo de un falso bit de inicio.
- Detección de un bit de stop inválido mediante `o_error`.
- Recepción de dos tramas consecutivas.

### `tb_uart_tx.sv`

Prueba `uart_tx.v`. Activa `i_start`, captura la trama producida por `o_tx` y
reconstruye sus bits para compararlos con el byte esperado. Comprueba:

- Los bits de inicio, datos y stop.
- La transmisión de `A5`, `00` y `FF`.
- Que cambiar `i_data` durante una transmisión no altere la trama en curso.
- Que un nuevo `i_start` mientras `o_busy` está activo sea ignorado.
- Que `o_busy` vuelva a cero y puedan enviarse bytes consecutivos.

## Pruebas de la interfaz

### `tb_interface_rx.sv`

Prueba solamente `interface_rx.v`, sin instanciar el receptor UART. Introduce
directamente `i_data`, `i_valid`, `i_error` e `i_rd` para verificar:

- Almacenamiento y conservación de un byte recibido.
- Lectura y vaciado del registro.
- Lectura y recepción simultáneas.
- Recepción mientras el registro está lleno y detección de desbordamiento.
- Descarte de bytes con error de trama.
- Recuperación después de un error y comportamiento del reset.

### `tb_interface_tx.sv`

Prueba solamente `interface_tx.v`, representando al transmisor UART mediante la
entrada `i_busy`. Verifica:

- Almacenamiento de un resultado mediante `i_wr`.
- Conservación del dato mientras UART está ocupado.
- Rechazo de escrituras cuando `o_tx_full` está activo.
- Generación de un único pulso `o_start` por cada resultado.
- Espera de la confirmación y finalización indicadas por `i_busy`.
- Envíos sucesivos y reset con un resultado pendiente o en transmisión.

### `tb_interface_circuit.sv`

Prueba `interface_circuit.v` a nivel de bytes. Instancia las interfaces RX/TX y
la ALU, pero reemplaza los módulos UART seriales por estímulos y respuestas
directas. Esto permite comprobar rápidamente:

- El protocolo `operando A → operando B → operación`.
- Las ocho operaciones de la ALU y códigos no implementados.
- Comandos incompletos y bytes consecutivos.
- Espera cuando TX está ocupado.
- Errores de recepción, desbordamiento y reset.

Esta prueba se concentra en la FSM de control y en los handshakes `rd`, `wr`,
`rx_empty` y `tx_full` sin emplear los tiempos de una trama serial completa.

## Prueba de integración completa

### `tb_uart_interface.sv`

Conecta los bloques reales del sistema:

```text
baud_gen + uart_rx → interface_circuit + ALU → uart_tx
```

El testbench genera tramas 8N1 por la entrada serial, envía comandos de tres
bytes y decodifica la salida serial para comprobar el resultado. De esta manera
detecta errores de conexión o temporización que podrían no aparecer en las
pruebas individuales. Utiliza un baud rate acelerado para reducir el tiempo de
simulación; esto no modifica los módulos sintetizables.

### `tb_uart_top.sv`

Instancia `uart_top.v`, el TOP sintetizable que conecta el proyecto con la
Basys 3. Comprueba las respuestas seriales de la ALU, el reset de arranque y
del botón, los LEDs de resultado y TX ocupado, y la retención del LED de error.
También comprueba la recuperación después de resetear una operación parcial
o una transmisión en curso. Cada registro secuencial del TOP tiene su propio
bloque `always`.

A diferencia de `tb_uart_interface`, que conecta los bloques dentro del
testbench, esta prueba utiliza las conexiones del TOP real. El parámetro
`BAUD_RATE` vale `781250` para acelerar la simulación y puede cambiarse a
`9600` con `-Ptb_uart_top.BAUD_RATE=9600` en Icarus Verilog.

## Ejecución con Icarus Verilog

Desde la carpeta raíz `TP2_UART` se pueden ejecutar todas las pruebas con:

```bash
tp2_sim_dir=$(mktemp -d /tmp/tp2_uart_tests.XXXXXX)

for bench in \
    tb_baud_gen \
    tb_uart_rx \
    tb_uart_tx \
    tb_interface_rx \
    tb_interface_tx \
    tb_interface_circuit \
    tb_uart_interface \
    tb_uart_top
do
    iverilog -g2012 -s "$bench" -o "$tp2_sim_dir/$bench.vvp" \
        src/baud_gen.v src/uart_rx.v src/uart_tx.v src/ALU.v \
        src/interface_rx.v src/interface_tx.v src/interface_circuit.v src/uart_top.v \
        "sim/$bench.sv" || break

    vvp "$tp2_sim_dir/$bench.vvp" || break
done
```

Los ejecutables de simulación se generan en un directorio temporal para no
agregar productos compilados al proyecto.
