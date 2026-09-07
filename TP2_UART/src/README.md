# TOP del sistema UART–ALU

El módulo superior del proyecto es [`uart_top`](uart_top.v). Sus puertos son
las señales que se conectan físicamente a la FPGA mediante
[`constraints/Basys3_UART.xdc`](../constraints/Basys3_UART.xdc).

## Placa y configuración

Se utiliza la **Digilent Basys 3**, tomando como referencia el reloj, el botón
central y los LEDs de `TP1_ALU/constraints/Basys3_ALU.xdc`. El proyecto Vivado
de TP1 está configurado para `xc7a35ticpg236-1L`; esa misma configuración se
utiliza para validar este TOP.

El reloj de placa es de **100 MHz**. Los pines de UART y los LEDs adicionales
se verificaron con el
[archivo de constraints oficial de Digilent](https://github.com/Digilent/digilent-xdc/blob/master/Basys-3-Master.xdc).
Todos los puertos físicos usan `LVCMOS33`.

| Parámetro de `uart_top` | Valor predeterminado | Uso |
| --- | --- | --- |
| `CLOCK_FREQ` | `100_000_000` | Frecuencia del reloj que recibe la FPGA, en Hz. |
| `BAUD_RATE` | `9600` | Velocidad de comunicación, en baudios. |

El sobremuestreo se fija en **16 ticks por bit** porque los contadores de
`uart_rx` y `uart_tx` están diseñados para ese valor. Con los parámetros
predeterminados, `baud_gen` genera un tick cada 651 ciclos de reloj. Todos los
módulos reciben el reloj de 100 MHz; el tick es una habilitación de un ciclo,
no un segundo reloj. Cambiar `CLOCK_FREQ` no cambia el oscilador físico: el
parámetro debe describir el reloj conectado y coincidir con el período del XDC.

## Jerarquía del diseño

```text
uart_top
├── u_baud_gen           : baud_gen
├── u_uart_rx            : uart_rx
├── u_interface_circuit : interface_circuit
│   ├── u_interface_rx  : interface_rx
│   ├── u_alu           : ALU
│   └── u_interface_tx  : interface_tx
└── u_uart_tx            : uart_tx
```

`uart_top` conecta los módulos y adapta reset y señales de diagnóstico a la
placa. `interface_circuit` sigue siendo el controlador que interpreta los
bytes como A, B y operación. La ALU ya está instanciada dentro de ese
controlador: no es necesario añadir una segunda ALU en el TOP.

## Conexiones internas

| Señal del TOP | Origen | Destino |
| --- | --- | --- |
| `i_clock` | Oscilador de placa | Todos los módulos y registros del TOP. |
| `w_reset` | Sincronizador del botón | Reset de todos los módulos y LED de reset. |
| `w_baud_tick` | `baud_gen.o_baud_tick` | `uart_rx.i_baud_tick` y `uart_tx.i_baud_tick`. |
| `w_rx_valid` | `uart_rx.o_valid` | `interface_circuit.i_rx_valid`. |
| `w_rx_data[7:0]` | `uart_rx.o_data` | `interface_circuit.i_rx_data`. |
| `w_rx_error` | `uart_rx.o_error` | `interface_circuit.i_rx_error`. |
| `w_tx_start` | `interface_circuit.o_tx_start` | `uart_tx.i_start`. |
| `w_tx_data[7:0]` | `interface_circuit.o_tx_data` | `uart_tx.i_data` y LEDs de resultado. |
| `w_tx_busy` | `uart_tx.o_busy` | `interface_circuit.i_tx_busy` y LED de ocupación. |
| `w_error` | `interface_circuit.o_error` | Registro del LED de error. |

El recorrido de una operación es: la PC transmite tres bytes; RX los convierte
en datos paralelos; la interfaz carga las entradas de la ALU; el resultado
se almacena en la interfaz TX; y el transmisor lo devuelve a la PC.

## Puertos y pines de la Basys 3

Las direcciones de la tabla se expresan **desde la FPGA**. Las asignaciones de
paquete corresponden al
[pinout oficial de Digilent](https://github.com/Digilent/digilent-xdc/blob/master/Basys-3-Master.xdc).

| Puerto de `uart_top` | Dirección | Elemento de placa | Pin FPGA | Función |
| --- | --- | --- | --- | --- |
| `i_clock` | Entrada | Oscilador | W5 | Reloj de 100 MHz, período de 10 ns. |
| `i_reset` | Entrada | Botón central `btnC` | U18 | Reset activo en alto al presionar. |
| `i_rx` | Entrada | Puente USB-UART | B18 | Datos enviados por la PC hacia la FPGA. |
| `o_tx` | Salida | Puente USB-UART | A18 | Respuestas enviadas por la FPGA hacia la PC. |
| `o_leds[0]` | Salida | LD0 | U16 | Bit 0 del último resultado cargado en TX. |
| `o_leds[1]` | Salida | LD1 | E19 | Bit 1 del resultado. |
| `o_leds[2]` | Salida | LD2 | U19 | Bit 2 del resultado. |
| `o_leds[3]` | Salida | LD3 | V19 | Bit 3 del resultado. |
| `o_leds[4]` | Salida | LD4 | W18 | Bit 4 del resultado. |
| `o_leds[5]` | Salida | LD5 | U15 | Bit 5 del resultado. |
| `o_leds[6]` | Salida | LD6 | U14 | Bit 6 del resultado. |
| `o_leds[7]` | Salida | LD7 | V14 | Bit 7 del resultado. |
| `o_reset_led` | Salida | LD8 | V13 | Encendido mientras el reset sincronizado está activo. |
| `o_tx_busy_led` | Salida | LD9 | V3 | Encendido mientras UART TX está transmitiendo. |
| `o_error_led` | Salida | LD10 | W3 | Error de recepción/desbordamiento, retenido hasta reset. |

El puente FTDI integrado utiliza el conector **micro-USB J4, rotulado PROG**.
Ese mismo cable permite programar la placa y comunicarse por UART; las dos
funciones son independientes. La conexión B18/A18 ya está realizada en la
placa. El USB tipo A corresponde a otra función. Véase la sección USB-UART del
[manual de Basys 3](https://reference.digilentinc.com/_media/reference/programmable-logic/basys-3/basys3_rm.pdf).

Los ocho switches y los botones de carga de TP1 quedan sin uso en este TOP:
los operandos y la operación llegan por UART. Los LEDs muestran los ocho bits
del resultado, incluido el complemento a dos cuando es negativo.

## Reset y diagnóstico

`r_reset_sync` tiene dos etapas y sincroniza el botón con `i_clock`. El reset
se activa y se libera después de pasar por esas etapas; los módulos consumen
la salida sincronizada en el siguiente flanco de reloj. El valor inicial
`2'b11` mantiene el conjunto en reset durante el arranque, aunque el botón
esté suelto. Vivado implementa ese valor mediante el atributo `INIT` de los
flip-flops, como describe
[UG901, Initial Values](https://docs.amd.com/r/en-US/ug901-vivado-synthesis/Initial-Values).
El sincronizador no es un filtro antirrebote: al accionar el botón pueden
producirse resets repetidos; se debe soltarlo antes de iniciar una operación.

`uart_rx` ya tiene su propio sincronizador de la entrada serial. El XDC marca
sus dos flip-flops como `ASYNC_REG`. Las excepciones de timing para las entradas
asíncronas terminan en la primera etapa de cada sincronizador; el trayecto
entre etapas se sigue verificando con el reloj de 100 MHz. Las salidas de LEDs
y UART se excluyen de requisitos de captura con un reloj externo, porque no
hay un receptor externo síncrono con `i_clock`.

El TOP tiene un `always` para `r_reset_sync` y otro para `o_error_led`, siguiendo
la separación por registro del resto de las interfaces. `o_leds` utiliza el
dato que ya conserva `interface_tx`, por lo que el último resultado permanece
visible al terminar la transmisión.

El error interno dura un ciclo y sería demasiado breve para verlo en un LED.
Por eso `o_error_led` lo retiene hasta el próximo reset. Si se enciende LD10,
detener el envío, pulsar y soltar `btnC`, y reenviar el comando completo. El
reset descarta comandos parciales, resultados pendientes y cualquier trama
que se estuviera transmitiendo.

## Uso desde la PC

Configurar el puerto serial en **9600 baudios, 8 bits de datos, sin paridad,
un bit de stop (8N1) y sin control de flujo**. Enviar tres bytes binarios,
en el orden **A → B → operación**, y esperar un byte de respuesta antes del
siguiente comando. Los códigos se detallan en la
[guía de la interfaz](../doc/interface_circuit.md).

Ejemplo: enviar `12 34 20` en hexadecimal devuelve `46`. Esto representa
`0x12 + 0x34 = 0x46`; se encenderán LD1, LD2 y LD6. Deben enviarse los valores
de los bytes, no escribir los caracteres ASCII `"12 34 20"` en una terminal.

## Configuración de Vivado

1. Usar la configuración de dispositivo de TP1: `xc7a35ticpg236-1L`.
2. Agregar los ocho archivos `.v` de esta carpeta como **Design Sources**:
   `uart_top.v`, `baud_gen.v`, `uart_rx.v`, `uart_tx.v`, `interface_circuit.v`,
   `interface_rx.v`, `interface_tx.v` y `ALU.v`.
3. Seleccionar `uart_top` como **Top Module** del diseño.
4. Agregar únicamente `constraints/Basys3_UART.xdc` como constraints de TP2.
   El XDC de TP1 usa los nombres de sus propios puertos y no se debe cargar
   junto con este archivo.
5. Para simulación, agregar `sim/tb_uart_top.sv` como **Simulation Source**
   y elegir `tb_uart_top` como top de simulación.
6. Ejecutar síntesis e implementación antes de generar el bitstream.

Los parámetros acelerados del testbench afectan solo a esa simulación. Para
la placa, `uart_top` conserva su valor predeterminado de 9600 baudios.

## Prueba del TOP

[`tb_uart_top.sv`](../sim/tb_uart_top.sv) instancia directamente este TOP y
verifica las respuestas seriales, el reset de arranque, el botón de reset,
los LEDs, un error de trama y la recuperación después de interrumpir una
operación. Se ejecuta desde la raíz `TP2_UART`:

```bash
tp2_top_sim_dir=$(mktemp -d /tmp/tp2_uart_top_sim.XXXXXX)
iverilog -g2012 -s tb_uart_top -o "$tp2_top_sim_dir/top.vvp" \
    src/*.v sim/tb_uart_top.sv && vvp "$tp2_top_sim_dir/top.vvp"
```

Para verificar los tiempos de la configuración de placa, añadir
`-Ptb_uart_top.BAUD_RATE=9600` al comando `iverilog`.

## Validación realizada

El testbench del TOP pasó con 13 respuestas verificadas tanto a 781250 como
a 9600 baudios, incluyendo las comprobaciones de reset y LEDs. Vivado 2025.1
completó síntesis, colocación y ruteo para `xc7a35ticpg236-1L`, con los 15 pines
asignados y sin infracciones DRC. A 100 MHz se obtuvo un margen de setup
de 4,628 ns y de hold de 0,131 ns. La validación física en placa queda pendiente.
