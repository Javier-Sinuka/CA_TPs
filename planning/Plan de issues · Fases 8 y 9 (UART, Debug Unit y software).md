# Plan de issues · Fases 8 y 9 (UART, Debug Unit y software)

Oct 31, 2026 · @David Trujillo

## Alcance y supuestos

La pista B termina cuando la Debug Unit funciona en la placa contra un CPU stub y el software de la PC carga, ejecuta y decodifica dumps; en ese punto la Fase 10 solo reemplaza el stub por el CPU real. Son 29 issues en 5 milestones (M0 a M4), cada una con una validación que se puede correr y un criterio de aceptación binario.

Supuestos de partida, tomados de la hoja de ruta (Decisiones 1 a 6):

- Clock único de 50 MHz desde el Clock Wizard al principio; la UART a 115200 baudios, 8N1.
- HALT = `ecall` (0x00000073); memorias de lectura asíncrona; bus de debug direccionable.
- Ensamblador, enlace serie y CLI en Python (pyserial); golden model en C++.
- La UART del proyecto anterior se reutiliza solo si pasa M0. Si falla un punto, se arregla en su issue; no se reescribe entera.

Cómo leer cada issue: **Objetivo** (una línea), **Tareas**, **Validación** (qué se corre y qué se mira) y **Listo cuando** (las casillas que cierran la issue). Etiquetas sugeridas para GitHub: `uart`, `debug-unit`, `contrato`, `sw-asm`, `sw-iss`, `sw-host`, `test`, `bloquea-A`. Tamaño: S ≤ medio día, M ≤ 2 días, L ≤ 4 días.

## Mapa de milestones

&#91;embedded content: milestones de la pista B y su cruce con la pista A\]

M0 y M1 arrancan el primer día y en paralelo; el único punto donde B espera a A es la aprobación de M1, y lo único que A espera de B son el ensamblador, el golden model y los programas de M3.

## M0 · Validar la UART existente

La UART se da por reutilizable cuando pasa B-01 a B-05: auditoría, parametrización, interfaz acordada, testbench automático y eco en placa con 0 errores sobre 100 000 bytes. Este milestone no depende de nadie y conviene cerrarlo en la primera semana.

### B-01 · Auditar la UART del proyecto anterior (S, `uart`)

**Objetivo:** saber exactamente qué tiene y qué le falta antes de tocar una línea.

**Tareas:** copiar los fuentes a `rtl/uart/` en un commit propio ("importada sin cambios") y completar en `docs/uart.md` esta lista:

| Punto a revisar | Qué se espera | Si falta |
| --- | --- | --- |
| Divisor de baudios | Calculado desde parámetros `CLK_FREQ` y `BAUD` | B-02 |
| Muestreo de RX | Sobremuestreo (típico 16×), muestra en el centro del bit | B-02 |
| Sincronizador de RX | 2 flip-flops antes de cualquier lógica | B-02 |
| Inicio falso | Valida el start bit a mitad de bit y descarta glitches | B-04 lo prueba |
| Interfaz RX | `rx_valid` de 1 ciclo + `rx_data[7:0]` | B-03 |
| Interfaz TX | `tx_start` + `tx_data`, `tx_busy` mientras transmite | B-03 |
| Reset | Síncrono, mismo criterio que el resto del diseño | B-03 |
| Estilo | Sin `initial`, `negedge`, `#retardos` ni latches; `default_nettype none` | B-03 |
| Error de framing | Stop bit en 0 se detecta (útil, no obligatorio) | opcional |

**Validación:** síntesis aislada de la UART en Vivado sin warnings de `inferring latch` ni `multi-driven net`.

**Listo cuando:**

- [ ] `docs/uart.md` tiene la tabla completa con "sí / no / parcial" y el archivo y línea de cada punto.
- [ ] Hay una lista de issues B-02 a B-03 abiertas solo por los puntos que fallaron.

### B-02 · Parametrizar el baud rate por frecuencia (S, `uart`)

**Objetivo:** que al cambiar el clock en la Fase 12 la UART siga funcionando sin tocar código.

**Tareas:** `localparam DIV = (CLK_FREQ + BAUD*OS/2) / (BAUD*OS)` (redondeo al entero más cercano, `OS` = sobremuestreo); exponer `CLK_FREQ` y `BAUD` como parámetros del top; agregar el sincronizador si faltaba.

**Validación:** un script (Python o una tabla en el doc) calcula el error de baud para las frecuencias candidatas de la Fase 12. Error = |baud real − baud ideal| / baud ideal.

**Listo cuando:**

- [ ] El error es menor a 2 % para 50, 75, 100 y 125 MHz a 115200.
- [ ] Cambiar `CLK_FREQ` en el top es el único cambio necesario.

### B-03 · Ajustar la interfaz a la acordada (S, `uart`)

**Objetivo:** que la Debug Unit vea siempre la misma interfaz, venga de donde venga la UART.

**Tareas:** si la interfaz original difiere, escribir un wrapper `uart_if.v` en vez de modificar el núcleo; convertir niveles en pulsos con detección de flanco; unificar el reset.

**Validación:** el testbench de B-04 se escribe contra el wrapper, no contra el núcleo.

**Listo cuando:**

- [ ] `rx_valid` dura exactamente 1 ciclo por byte recibido (lo verifica una aserción en el TB).
- [ ] `tx_start` con `tx_busy = 1` se ignora y no corrompe el byte en curso.

### B-04 · Testbench automático de la UART (M, `uart` `test`)

**Objetivo:** un `tb_uart.v` que imprime PASS/FAIL sin mirar formas de onda.

**Tareas:** tasks `uart_send` y `uart_recv` que manejan la línea serie con tiempos de bit; casos:

1. Loopback TX → RX de los 256 valores de byte.
2. 64 bytes consecutivos sin pausa entre el stop y el siguiente start.
3. Emisor con baud desviado +2 % y −2 %: se reciben bien.
4. Pulso en 0 de un cuarto de bit en reposo: no genera `rx_valid`.
5. Reset en medio de una trama: la UART vuelve a reposo y recibe bien el byte siguiente.
6. Simulación con `BAUD` alto (por ejemplo `CLK_FREQ/32`), para que la Fase 10 pueda usarlo.

**Validación:** `make tb_uart` en Icarus o xsim; el TB termina con `$finish` y código de error si algo falla.

**Listo cuando:**

- [ ] Los 6 casos pasan con los parámetros de la placa y con `BAUD` alto.
- [ ] Un bug inyectado a propósito (por ejemplo, invertir el orden de los bits) hace fallar el TB.

### B-05 · Eco en la placa con el clock real (M, `uart`)

**Objetivo:** confirmar en hardware, con el Clock Wizard del proyecto, que no se pierde ni corrompe nada.

**Tareas:** `top_uart_echo` (Clock Wizard → UART, RX conectado a TX, un LED que conmuta por byte) y `sw/host/echo_test.py` que envía bytes aleatorios en ráfagas y compara el eco.

**Validación:** el script informa bytes enviados, recibidos y erróneos; correrlo a 50 MHz y a una segunda frecuencia (por ejemplo 100 MHz) para probar B-02 en hardware.

**Listo cuando:**

- [ ] 100 000 bytes en ráfagas de 256 bytes sin pausa interna: 0 errores y 0 bytes perdidos, en las dos frecuencias. (Ráfagas más largas pueden perder bytes en un eco sin FIFO si el baud de la PC es apenas más rápido; eso no afecta a la Debug Unit, que no reenvía lo que recibe.)
- [ ] `docs/uart.md` dice "reutilizada" o "reutilizada con cambios X, Y", con el commit de cada cambio.

## M1 · Contrato y CPU stub

M1 congela tres documentos que la persona A tiene que aprobar (protocolo, formato del dump, interfaz `cpu`) y entrega un stub con la misma interfaz. Desde acá la pista B no depende del avance de A.

### B-06 · Protocolo UART v1 (S, `contrato` `bloquea-A`)

**Objetivo:** `docs/protocolo.md` como única fuente de verdad entre Verilog y Python.

**Tareas:** partir de la tabla de la Fase 8 (`L R S D X`) y cerrar lo que la guía deja abierto:

- Orden de bytes: little-endian en N, palabras y direcciones.
- Comando `V` (versión): responde `0xA5` + versión del protocolo + tamaño de imem y dmem en palabras. Le sirve al host para verificar que habla con la placa correcta.
- Comando `A` (abortar) aceptado durante `R`: detiene y envía el dump.
- Errores: `E` + código de 1 byte (01 comando desconocido, 02 N fuera de rango, 03 timeout entre bytes en la carga).
- Timeout entre bytes en la carga: 100 ms; vencido, vuelve a reposo y responde `E 03`.

**Validación:** cada comando tiene un ejemplo de la transacción completa en hex (lo que manda la PC y lo que responde la placa). Esos ejemplos se reutilizan como vectores de test en B-16 y B-23.

**Listo cuando:**

- [ ] A aprobó el PR de `docs/protocolo.md`.
- [ ] Hay un ejemplo hex por comando y por código de error.

### B-07 · Formato del dump v1 (M, `contrato` `bloquea-A`)

**Objetivo:** fijar el mapa de palabras y el layout de bits de las palabras "info" de los latches.

**Tareas:** tabla `idx → contenido` (cabecera, estado, PC, x0–x31, 15 palabras de latches, memoria usada, checksum); layout de bits de la palabra de estado (halted, timeout, abortado, ciclos) y de cada palabra info (valid, rd, rs1, rs2, señales de control). El layout de latches lo propone A, porque define su RTL.

**Validación:** `sw/host/dump.py` con `encode()` y `decode()`. Un test arma un dump a mano con valores conocidos, lo codifica, lo decodifica y compara campo por campo.

**Listo cuando:**

- [ ] Round-trip `decode(encode(x)) == x` para 1000 estados aleatorios.
- [ ] Checksum definido (suma módulo 256 de todos los bytes después de la cabecera) y un dump con un byte alterado se rechaza.
- [ ] A aprobó el layout de las palabras info.

### B-08 · Interfaz cpu ↔ debug\_unit congelada (S, `contrato` `bloquea-A`)

**Objetivo:** que el stub y el CPU real sean intercambiables sin cambiar el top.

**Tareas:** partir de la interfaz de la hoja de ruta y definir la semántica temporal de cada puerto en `docs/decisiones.md`:

- `dbg_*`: lectura combinacional, válida en el mismo ciclo que se pone la dirección, solo con el CPU detenido (`en = 0`).
- `rst`: síncrono, un ciclo alcanza; no borra imem.
- Puerto de escritura de imem (`imem_we`, `imem_waddr`, `imem_wdata`) en el top, manejado por la Debug Unit.
- Memoria usada: `dbg_dirty_*` o un barrido; quién limpia los bits dirty y cuándo (en `L` y en `X`).

**Validación:** un archivo `rtl/cpu_ports.vh` con la lista de puertos, incluido por el stub y por el CPU real; si alguno se desvía, no compila.

**Listo cuando:**

- [ ] A aprobó la interfaz y la semántica escrita.
- [ ] El stub (B-09) compila con `cpu_ports.vh`.

### B-09 · CPU stub (M, `debug-unit` `test`)

**Objetivo:** un `cpu_stub.v` determinista, cuyo estado se puede predecir desde Python.

**Tareas:** comportamiento con `en = 1`: `ciclos++`, PC += 4; `halted` sube cuando `ciclos == HALT_AT` (parámetro; con `HALT_AT = 0` nunca, para probar el timeout). Lecturas: `x[i] = (ciclos << 8) | i` (x0 = 0), `latch[k] = 0x1A000000 | (k << 16) | ciclos`. Memoria usada: el stub marca dirty las palabras 4, 16 y 63 con valor `0xD0000000 | addr`. Las escrituras a imem quedan en un arreglo legible por el TB. Con `rst`, todo vuelve a 0.

**Validación:** `tb_cpu_stub.v` y un modelo Python `stub_model(ciclos)` que devuelve el dump esperado; ambos se comparan en B-14.

**Listo cuando:**

- [ ] El TB verifica PC, registros, latches y `halted` después de 0, 1, 7 y `HALT_AT` ciclos.
- [ ] `stub_model()` y el stub coinciden en esos 4 puntos.

## M2 · Debug Unit

La Debug Unit se construye comando por comando, cada uno con su caso en un mismo `tb_debug_unit.v` que maneja la línea RX y decodifica TX como lo haría la PC. M2 cierra cuando la Debug Unit con el stub responde en la placa real (B-17).

Todos los tests de M2 comparan contra `stub_model()` de B-09: el TB escribe lo que recibió por TX en un archivo y un script Python lo decodifica y compara. Así el decodificador del TB y el del host son el mismo código.

### B-10 · FSM base y comandos sin ejecución: X, V, errores (M, `debug-unit`)

**Objetivo:** el esqueleto de estados con despacho de comandos y respuestas fijas.

**Tareas:** estados `IDLE LOAD STEP RUN DUMP TX_RESP`; un sub-bloque `tx_seq` que envía una secuencia de bytes esperando `tx_busy` (lo reutilizan la respuesta corta y el dump); `X` pulsa `cpu_rst` y responde `K`; `V` responde la versión; un byte desconocido responde `E 01`.

**Validación:** casos en el TB con los ejemplos hex de B-06.

**Listo cuando:**

- [ ] `X`, `V` y un comando inválido devuelven exactamente los bytes del protocolo.
- [ ] `cpu_rst` dura 1 ciclo y `cpu_en` no se mueve.
- [ ] Dos comandos seguidos sin pausa se atienden los dos.

### B-11 · Paso a paso: S (S, `debug-unit`)

**Objetivo:** que un `S` avance el CPU exactamente un ciclo.

**Tareas:** `cpu_en` sale de un registro de la FSM, en 1 durante un único flanco; después pasa a `DUMP`.

**Validación:** un contador en el TB suma los flancos con `cpu_en = 1`; después de cada `S` tiene que haber sumado 1. El dump devuelto se compara con `stub_model(n)` para n = 1..10.

**Listo cuando:**

- [ ] 10 `S` seguidos dan 10 flancos habilitados y 10 dumps iguales al modelo.
- [ ] Un `S` con el CPU en `halted` no avanza nada y devuelve el mismo dump.

### B-12 · Ejecución continua: R, timeout y A (M, `debug-unit`)

**Objetivo:** correr hasta `halted`, hasta el timeout o hasta que llegue un `A`.

**Tareas:** contador de ciclos de 32 bits; `TIMEOUT` como parámetro (en la placa, unos segundos de clock; en el TB, 1000 ciclos); el bit de estado indica la causa de la parada.

**Validación:** tres corridas con el stub: `HALT_AT = 20`, `HALT_AT = 0` (nunca para) y `HALT_AT = 0` con un `A` enviado a mitad de camino.

**Listo cuando:**

- [ ] Con `HALT_AT = 20` el dump informa 20 ciclos y `halted = 1`.
- [ ] Sin HALT se detiene en exactamente `TIMEOUT` ciclos con el bit de timeout.
- [ ] Con `A` se detiene con el bit de abortado y el dump coincide con el modelo en el ciclo de parada.

### B-13 · Carga de programa: L (M, `debug-unit`)

**Objetivo:** recibir N palabras y escribirlas en imem con el CPU en reset.

**Tareas:** sub-máquina que arma N (2 bytes) y cada palabra (4 bytes, little-endian); `imem_we` un ciclo por palabra; `cpu_rst` sostenido durante toda la carga; timeout entre bytes; N mayor que imem responde `E 02` sin escribir nada; el resto de imem se rellena con HALT (para la pregunta del enunciado sobre reprogramar).

**Validación:** el TB compara el arreglo de imem del stub con lo enviado.

**Listo cuando:**

- [ ] N = 1, N = 37 y N = tamaño máximo, con palabras aleatorias: imem igual a lo enviado y el resto en HALT.
- [ ] N = máximo + 1 responde `E 02` e imem no cambia.
- [ ] Cortar la transmisión a mitad de una palabra responde `E 03` y el siguiente comando se atiende bien.

### B-14 · Dump: D y el recorrido del mapa (M, `debug-unit`)

**Objetivo:** enviar el mapa de palabras de B-07 con su checksum.

**Tareas:** contador `idx` + contador de byte; un mux elige la palabra (estado, PC, `dbg_reg_addr`, `dbg_latch_sel`, memoria); el checksum se acumula mientras se transmite.

**Validación:** `D` en distintos momentos (antes de correr, a mitad de pasos, después de `R`), decodificado con `dump.py` y comparado con `stub_model()`.

**Listo cuando:**

- [ ] La cantidad de bytes del dump es exactamente la que predice B-07.
- [ ] Los dumps decodificados coinciden campo por campo y el checksum verifica.

### B-15 · Memoria de datos usada (S, `debug-unit` `bloquea-A`)

**Objetivo:** que el dump incluya solo las palabras de dmem escritas por el programa.

**Tareas:** implementar lo acordado en B-08 (bits dirty o barrido); limpiar en `L` y `X`.

**Validación:** el stub marca las palabras 4, 16 y 63; después de `X` no marca ninguna.

**Listo cuando:**

- [ ] El dump lista exactamente 3 pares (dirección, dato), en orden ascendente.
- [ ] Después de `X` o `L` la lista está vacía.

### B-16 · Testbench del sistema de debug completo (M, `debug-unit` `test`)

**Objetivo:** `tb_debug_top.v` con UART + Debug Unit + stub + imem, manejado solo por la línea serie, con `BAUD` alto.

**Tareas:** guion de prueba: `V`, `L` (programa A), 5 × `S`, `R`, `D`, `X`, `L` (programa B), `R`, comando inválido, `D`. Es el mismo guion que va a correr la Fase 10 con el CPU real.

**Validación:** `make tb_debug_top` termina con PASS y deja el log de bytes en `build/`.

**Listo cuando:**

- [ ] El guion completo pasa sin intervención.
- [ ] El tiempo de simulación es menor a 1 minuto (si no, subir `BAUD`).

### B-17 · Debug Unit + stub en la placa (M, `debug-unit`)

**Objetivo:** validar en hardware todo lo que se pueda antes de que exista el CPU real.

**Tareas:** `top_debug_stub` con Clock Wizard, reset por botón y `locked`, LEDs para estado de la FSM y `halted`; síntesis e implementación.

**Validación:** el mismo guion de B-16 corrido desde la PC con `sw/host/link.py` (B-23).

**Listo cuando:**

- [ ] Síntesis sin latches ni `multi-driven`, timing cumplido a 50 MHz.
- [ ] El guion pasa en la placa 20 veces seguidas sin reprogramar la FPGA.

## M3 · Software en la PC

M3 se valida contra referencias externas siempre que se pueda: RARS para el ensamblador y el golden model, los dumps grabados en M2 para el enlace serie. B-19, B-21 y B-22 desbloquean la verificación del CPU de A, así que conviene hacerlas antes que la interfaz gráfica.

### B-18 · Base del repositorio de software (S, `test`)

**Objetivo:** que cualquiera corra todos los tests con un solo comando.

**Tareas:** `sw/asm`, `sw/iss`, `sw/host`, `programs/`; `pytest` para Python, un binario de tests para C++; `make test` en la raíz que corre los tests de software y los TB de M0 y M2.

**Validación:** clonar el repo en una carpeta limpia y correr `make test`.

**Listo cuando:**

- [ ] `make test` corre todo y devuelve código distinto de 0 si algo falla.
- [ ] El README dice qué instalar (Python, pyserial, compilador, Icarus, RARS).

### B-19 · Ensamblador (L, `sw-asm` `bloquea-A`)

**Objetivo:** traducir `.s` a `.hex` (para `$readmemh`) y `.bin` (para `L`).

**Tareas:** dos pasadas con etiquetas; las 32 instrucciones + `halt`; pseudo-instrucciones `nop li mv j ret`; HALT agregado al final si falta; errores con número de línea (registro inválido, inmediato fuera de rango, salto a dirección impar, etiqueta inexistente o repetida).

**Validación:** comparar palabra por palabra contra RARS (volcando el segmento de texto en hex) para un programa con las 32 instrucciones. Casos borde de inmediatos:

| Caso | Valores |
| --- | --- |
| I y S | −2048, −1, 0, 2047 |
| B (beq/bne) | −4096, −4, +4, +4094 |
| J (jal) | −1 048 576, −4, +4, +1 048 574 |
| `li` con redondeo | 0x12345FFF, 0x00000800, 0xFFFFF800, 0x7FFFFFFF, −1 |
| Shifts inmediatos | `srai x1, x1, 31` (bit 30 en 1), `slli` con shamt 0 |

**Listo cuando:**

- [ ] Coincidencia exacta con RARS en el programa de 32 instrucciones y en todos los casos de la tabla.
- [ ] Cada error de la lista produce un mensaje con línea y no genera salida.

### B-20 · Desensamblador (S, `sw-asm`)

**Objetivo:** mostrar la instrucción de cada etapa en la interfaz a partir de su palabra.

**Tareas:** `disasm(word) → str`, con `???` para palabras que no son del subconjunto.

**Validación:** ida y vuelta `asm(disasm(asm(prog))) == asm(prog)` para todos los programas de B-22.

**Listo cuando:**

- [ ] La ida y vuelta da idéntico en todos los programas.

### B-21 · Golden model en C++ (M, `sw-iss` `bloquea-A`)

**Objetivo:** un simulador que corre el mismo `.hex` y escribe el estado final en el formato canónico.

**Tareas:** el `switch` de la Fase 9; dmem del mismo tamaño que la real, con escritura por byte; semántica de accesos desalineados igual a la decidida por A; límite de instrucciones; salida en JSON (`pc`, `x[32]`, palabras de dmem escritas, cantidad de instrucciones, causa de parada).

**Validación:** tests unitarios por instrucción con casos borde (`sra` de negativos, `slt` vs `sltu` con 0x80000000, escritura a x0, `lb` vs `lbu` con 0x80 en los 4 offsets, `jalr` con bit 0 en 1) y comparación de registros y memoria contra RARS en los programas de B-22.

**Listo cuando:**

- [ ] Todos los tests unitarios pasan.
- [ ] Registros y memoria coinciden con RARS en todos los programas de B-22.

### B-22 · Programas de prueba con resultado esperado (M, `test` `bloquea-A`)

**Objetivo:** el banco de programas que usan A (Fases 3 a 7), la Fase 10 y la demo.

**Tareas:** los 9 programas del anexo de la hoja de ruta, cada uno con un encabezado que dice qué cubre y un `.expected.json` generado por el golden model y revisado a mano en los valores clave (por ejemplo, x1 = 55 en `suma.s`).

**Validación:** el ISS reproduce cada `.expected.json`; una tabla en `programs/README.md` mapea programa → fase de A que valida.

**Listo cuando:**

- [ ] Los 9 programas ensamblan, corren en el ISS y tienen su resultado esperado.
- [ ] A los recibió y confirmó que cubren lo que necesita.

### B-23 · Enlace serie: link.py (M, `sw-host`)

**Objetivo:** una capa que habla el protocolo y devuelve objetos, sin nada de interfaz.

**Tareas:** `connect(port)` que verifica con `V`; `load(words)`, `step()`, `run()`, `abort()`, `dump()`, `reset()`; timeouts por comando; verificación de checksum; resincronización descartando bytes hasta la cabecera 0xA5.

**Validación:** tests con un puerto falso que reproduce los logs de bytes grabados en B-16, incluidos un byte corrupto y una respuesta cortada.

**Listo cuando:**

- [ ] Los logs de B-16 se decodifican igual que en el TB.
- [ ] Un checksum incorrecto y un timeout levantan errores claros, y el siguiente comando funciona.
- [ ] El guion de B-16 corre contra la placa con el stub (lo mismo que cierra B-17).

### B-24 · Placa simulada (S, `sw-host` `test`)

**Objetivo:** desarrollar y probar la interfaz sin FPGA.

**Tareas:** un objeto con la misma API de puerto serie que, por dentro, ejecuta el golden model y responde con el protocolo real (la latch info puede quedar en 0).

**Validación:** `link.py` contra la placa simulada da el mismo estado final que el ISS directo en todos los programas de B-22.

**Listo cuando:**

- [ ] Los 9 programas coinciden.

### B-25 · CLI (M, `sw-host`)

**Objetivo:** el primer frontend completo: `load prog.s`, `run`, `step [n]`, `regs`, `mem`, `pipe`, `reset`.

**Tareas:** ensambla y carga en un paso; resalta los registros que cambiaron desde el último paso; `pipe` muestra PC, desensamblado y `valid` de cada etapa.

**Validación:** una sesión guionada (archivo de comandos) contra la placa simulada, con la salida comparada contra un texto esperado.

**Listo cuando:**

- [ ] La sesión guionada pasa contra la placa simulada.
- [ ] La misma sesión corre contra la placa con el stub sin errores.

### B-26 · Interfaz final y diagrama espacio-tiempo (L, `sw-host`)

**Objetivo:** la interfaz de la demo (TUI o GUI) sobre `link.py`.

**Tareas:** vistas de registros, latches, memoria usada y diagrama instrucciones × ciclos acumulado en modo paso a paso; marca de divergencia contra el golden model en paralelo.

**Validación:** checklist manual sobre la placa simulada y después sobre la placa real; capturas para el manual de uso.

**Listo cuando:**

- [ ] Con `suma.s` en paso a paso, el diagrama muestra las 2 burbujas de cada `bne` tomado en los ciclos correctos, y con el programa de load-use, el ciclo de stall (verificado contra el dibujo hecho a mano).
- [ ] Un registro alterado a propósito en la placa simulada se marca como divergencia.

## M4 · Listo para la Fase 10

M4 deja armado todo lo que la integración va a necesitar, para que la Fase 10 sea cambiar `cpu_stub` por `cpu` y correr un comando.

### B-27 · Regresión de tres niveles (M, `test`)

**Objetivo:** `make regress` corre cada programa de B-22 en el ISS, en simulación RTL y (con `BOARD=COM3` o similar) en la placa, y compara los tres JSON.

**Tareas:** un runner Python que ensambla, corre cada nivel, normaliza la salida al formato canónico y muestra un diff legible por registro y dirección. Mientras no exista el CPU real, el nivel RTL corre los TB de la UART y de la Debug Unit con el stub.

**Validación:** romper a propósito el ISS (por ejemplo, `sra` como `srl`) y ver que la regresión falla señalando el programa y el registro.

**Listo cuando:**

- [ ] La regresión corre de punta a punta con el stub y la placa simulada.
- [ ] El bug inyectado se detecta con un mensaje que nombra programa, registro y valores.

### B-28 · tb\_top listo para el CPU real (S, `test`)

**Objetivo:** el testbench de la Fase 10 escrito y probado de antemano.

**Tareas:** `tb_top.v` instancia el `top` real con un `define` que elige `cpu_stub` o `cpu`; reutiliza el guion de B-16 y carga los programas de B-22 por la UART simulada.

**Validación:** con el stub, el guion pasa igual que en B-16.

**Listo cuando:**

- [ ] Cambiar el `define` es el único paso para correrlo con el CPU real.

### B-29 · Entrega a la integración (S, `contrato`)

**Objetivo:** que A pueda usar todo sin preguntar.

**Tareas:** `docs/debug.md` con: cómo correr la regresión, cómo leer un diff, mapa de recursos de la Debug Unit (LUT y FF del reporte de síntesis), y qué quedó pendiente.

**Validación:** A sigue el documento en su máquina sin ayuda.

**Listo cuando:**

- [ ] A corrió `make regress` en su máquina siguiendo solo el documento.

## Plantilla de issue y definición de terminado

Cada issue se copia a GitHub con esta plantilla (guárdenla en `.github/ISSUE_TEMPLATE/tarea.md`):

```markdown
## Objetivo
Una línea: qué existe o funciona cuando se cierra.

## Tareas
- [ ] ...

## Validación
Comando que se corre: `make ...`
Qué se mira: PASS/FAIL, archivo de salida, conteo de errores.

## Listo cuando
- [ ] Criterio binario 1
- [ ] Criterio binario 2

## Depende de / bloquea
B-xx, fase N de A
```

Una issue de la pista B está terminada cuando:

- [ ] Todas las casillas de "Listo cuando" están tildadas.
- [ ] Su test corre dentro de `make test` (o `make regress`) y falla si se rompe lo que prueba.
- [ ] En los módulos Verilog: síntesis sin `inferring latch`, sin `multi-driven` y sin cables implícitos.
- [ ] Si cambió el protocolo, el dump o la interfaz, el doc correspondiente se actualizó en el mismo PR y A lo aprobó.
- [ ] Las decisiones tomadas en la issue están en `docs/decisiones.md` con su porqué (el informe de la Fase 13 sale de ahí).
