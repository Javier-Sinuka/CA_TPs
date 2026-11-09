# Matriz ISA — decodificación y cobertura final del CPU

> Nota de reorganización: este documento conserva evidencia y comandos históricos. Los helpers `check_*` de A se retiraron y ya no se usa `--companion`; las rutas y comandos vigentes están en [organización del proyecto](organizacion.md).

Estado final: [A-33](../validation/A-33.md) verifica las **32 instrucciones del subconjunto** en RUN y STEP más HALT en WB. Las secciones iniciales conservan el contexto histórico de cada milestone; el cierre vigente está [al final](#cierre-final-a-33--cobertura-dinámica-del-cpu).

La matriz de A-05 describe las **32 instrucciones del subconjunto** más HALT.
La validez de codificación (`o_valid_instr`) es distinta del bit de
ocupación `valid` que tendrán los registros del pipeline. `control.v`
decodifica una palabra aislada; el futuro datapath debe condicionar
sus efectos con la validez de etapa.

## Vectores de control por clase

Abreviaturas: `AS=o_alu_src_b`, `RW=o_reg_write`, `MR=o_mem_read`,
`MW=o_mem_write`, `M2R=o_mem_to_reg`, `BR=o_branch`, `J=o_jump`,
`JR=o_jalr`, `LU=o_lui`, `H=o_halt`, `U1/U2=o_uses_rs1/rs2`,
`V=o_valid_instr`. Cada columna es un bit. `o_alu_op` se detalla por
instrucción en la tabla siguiente.

| Clase | AS | RW | MR | MW | M2R | BR | J | JR | LU | H | U1 | U2 | V |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| R | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 1 |
| I-ALU | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 1 |
| load | 1 | 1 | 1 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 1 |
| store | 1 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 1 |
| branch | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 1 | 1 | 1 |
| JAL | 0 | 1 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 1 |
| JALR | 1 | 1 | 0 | 0 | 0 | 0 | 1 | 1 | 0 | 0 | 1 | 0 | 1 |
| LUI | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 1 |
| HALT | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 1 |
| inválida/burbuja de palabra 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

Para una codificación inválida, `o_alu_op=ALU_ADD` y todas las banderas
son cero. Una burbuja **de etapa** debe anular efectos en la integración;
el módulo combinacional no recibe el bit de validez de etapa. Un NOP
`0x00000013` es ADDI válido a x0: su control indica RW=1 y el banco
de registros debe impedir la escritura efectiva a x0.

## Instrucción → operación e inmediato

`f7` de las tres instrucciones de shift inmediato son `imm[11:5]`.
Para las otras seis I-ALU, esos bits son libres. `I/S/B/J/U` designa
el formato de `imm_gen`; `—` significa salida 0. Las 33 filas tienen
un vector dirigido en `tb_control.sv` (PASS de A-05), que compara ALU
y los 13 bits de control; las familias de inmediato se cotejan también
con `tb_imm_gen.sv` y con un vector de integración en `tb_control.sv`.

| Instrucción | opcode/funct3/f7 | Clase | `ALU_*` | Inmediato | Prueba |
|---|---|---|---|---|---|
| add | 33/0/00 | R | ADD | — | `enc_r` |
| sub | 33/0/20 | R | SUB | — | `enc_r` |
| sll | 33/1/00 | R | SLL | — | `enc_r` |
| slt | 33/2/00 | R | SLT | — | `enc_r` |
| sltu | 33/3/00 | R | SLTU | — | `enc_r` |
| xor | 33/4/00 | R | XOR | — | `enc_r` |
| srl | 33/5/00 | R | SRL | — | `enc_r` |
| sra | 33/5/20 | R | SRA | — | `enc_r` |
| or | 33/6/00 | R | OR | — | `enc_r` |
| and | 33/7/00 | R | AND | — | `enc_r` |
| addi | 13/0/— | I-ALU | ADD | I | `enc_i` y FFF00093 |
| slti | 13/2/— | I-ALU | SLT | I | `enc_i` |
| sltiu | 13/3/— | I-ALU | SLTU | I | `enc_i` |
| xori | 13/4/— | I-ALU | XOR | I | `enc_i` |
| ori | 13/6/— | I-ALU | OR | I | `enc_i` |
| andi | 13/7/— | I-ALU | AND | I | `enc_i` |
| slli | 13/1/00 | I-ALU | SLL | I | `enc_i` |
| srli | 13/5/00 | I-ALU | SRL | I | `enc_i` |
| srai | 13/5/20 | I-ALU | SRA | I | `enc_i` |
| lb | 03/0/— | load | ADD | I | `enc_i` |
| lh | 03/1/— | load | ADD | I | `enc_i` |
| lw | 03/2/— | load | ADD | I | `enc_i` |
| lbu | 03/4/— | load | ADD | I | `enc_i` |
| lhu | 03/5/— | load | ADD | I | `enc_i` |
| sb | 23/0/— | store | ADD | S | 00208023 |
| sh | 23/1/— | store | ADD | S | 00209023 |
| sw | 23/2/— | store | ADD | S | 0020A023 |
| beq | 63/0/— | branch | ADD* | B | 00208063 |
| bne | 63/1/— | branch | ADD* | B | 00209063 |
| jal | 6F/—/— | JAL | ADD* | J | 008000EF |
| jalr | 67/0/— | JALR | ADD | I | `enc_i` |
| lui | 37/—/— | LUI | ADD | U | 123450B7 |
| HALT | palabra exacta 00000073 | HALT | ADD* | — | 00000073 |

`ADD*` es el valor por defecto de `o_alu_op`; no define por sí solo
la comparación de branch, el enlace PC+4 ni la detención. Esas
operaciones pertenecen al futuro datapath. Las cargas y stores usan
ADD para calcular dirección. LUI requiere elegir cero como primer
operando en EX, mediante `o_lui`.

## Estado de la baseline A-M01

Las 33 filas tienen decodificación dirigida en `tb_control`; la ALU,
`alu_control` y los formatos de inmediato cuentan además con pruebas
aisladas en sus respectivos TB. La regresión de la baseline se registra
en [A-M01](../validation/A-M01.md). El contrato de dump v1 sitúa
`alu_op` en `info[21:18]` de ID/EX y toma el valor de los macros
`ALU_*` de `riscv_defs.vh`; los campos ausentes de MEM/WB salen cero.
La lógica de WB, memoria, branches, HALT, stalls y validez de etapa
todavía no existe en esta Fase 1 y requiere las issues posteriores.

Pruebas detalladas de control: [A-05](../validation/A-05.md).

## Cobertura de forwarding en A-M04

La matriz anterior describe la decodificación combinacional de A-M01. El milestone [A-M04](04_forwarding.md) conecta el bypass al CPU; su [evidencia](../validation/A-M04.md) cubre los caminos de datos siguientes:

| Familia | Fuente dependiente | Camino probado | Programa o TB |
|---|---|---|---|
| I-ALU | `rs1` a distancia 1/2/3 | EX/MEM, MEM/WB y captura por bypass WB→ID | `raw_distance`, PC 4/48/100 |
| R-ALU | `rs2` a distancia 1/2/3 | EX/MEM, MEM/WB y captura por bypass WB→ID | `raw_distance`, PC 24/72/128 |
| R-ALU | `rs1` y `rs2` simultáneos | MEM/WB y EX/MEM en ambos órdenes | `raw_distance`, PC 152/248 |
| R/I-ALU | dos escrituras al mismo `rd` | gana el productor joven de EX/MEM | `raw_distance`, PC 176/272 |
| I-ALU | lectura y escritura de `x0` | selector 00, resultado sin dato ficticio | `raw_distance`, PC 196 |
| Store | `rs2` recién producido | EX/MEM alimenta `store_data` | `tb_forwarding_paths`, PC 4 |
| JAL/JALR | enlace usado inmediatamente | se reenvía PC+4; JALR recibe base reenviada | `tb_forwarding_paths`, PC 28/36/68/72 |
| Load con separación | dato desde WB | se usa el mux de writeback, no la dirección | `tb_forwarding_paths`, PC 48 |
| Branch | ambos operandos en EX | datos preparados; decisión y redirección pendientes de A-24/A-25 | `tb_forwarding_paths`, PC 60 |

Una carga seguida inmediatamente por su consumidor exige el interlock de A-M05; esta tabla no la presenta como aprobada. El programa `raw_distance` usa solo instrucciones aritméticas y NOP, y termina por un número acotado de ciclos mientras HALT sigue pendiente.

## Cobertura de load-use en A-M05

El [informe A-M05](05_load_use.md) y su [gate](../validation/A-M05.md) amplían la cobertura anterior mediante `load_use.s` y `tb_load_use_consumers`:

| Consumidor | PC byte | Criterio |
|---|---|---|
| ADD por ambas fuentes / solo rs2 | 40 / 264 | Una burbuja y bypass WB; resultados 146 / 94. |
| ADDI por rs1 | 296 | Una burbuja; resultado 75. |
| SW por dato / base / ambos | 72 / 104 / 424 | Una burbuja; direcciones 64 / 100 / 104 y datos 73 / 21 / 96. |
| BEQ/BNE por rs1 o rs2 | 200 / 232 / 360 / 392 | Una burbuja y operandos correctos; comparación en arnés, redirección pendiente de A-26. |
| ADDI con inmediato que aparenta rs2 | 136 | Cero stalls, resultado 1. |
| ADD independiente | 168 | Cero stalls, resultado 42. |
| Load a x0 y consumidor de x0 | 324 / 328 | Cero stalls; x0 sigue cero. |

La regresión también conserva los TB anteriores de 32 instrucciones y RAW. Esta ampliación no reemplaza la aceptación de control de flujo, HALT ni debug de los próximos milestones.

## Cobertura de control de flujo en A-M06

El [informe A-M06](06_saltos_y_flush.md) y su [gate](../validation/A-M06.md) completan las verificaciones de control que permanecían pendientes en las secciones históricas anteriores:

| Instrucción / combinación | Evidencia |
|---|---|
| BEQ/BNE con operandos forwardeados | `tb_branch_execute`, `suma` y `branch_load_use`; comparación tomada/no tomada en el CPU real. |
| Branch hacia atrás y contador recién actualizado | Diez iteraciones de `suma`, x1=55 y mem[0]=55; nueve redirecciones. |
| JAL / retorno JALR | `jump_link`: ra=8, retorno a 8; enlaces 32/48 separados del destino. |
| JALR con base recién producida / cargada | Base MEM=65→destino 64; base WB=101 más 8→destino 108. |
| Load→BEQ/BNE por rs1/rs2 | Cuatro parejas en `branch_load_use`, una burbuja cada una, tomadas y no tomadas. |
| Camino incorrecto con writes, stores, JAL o HALT | `tb_flush` y programas de control: no deja efectos ni enlaces. HALT persistente se repetirá en A-M07. |
| Pausa con toma o riesgo pendiente | Mismas secuencias, commits, memoria y avances; snapshots estables. |

A-26 conserva el RTL de A-25. El fin es un marcador con avance acotado; la aceptación de HALT real sigue pendiente de A-M07. Los flags debug completos y el sistema UART conservan sus hitos posteriores.

## Cobertura de finalización en A-M07

Los programas de aritmética/memoria, RAW, load-use y control ahora terminan por HALT real, con WB válido y etapas anteriores inválidas. Conservan entre ellos las 32 instrucciones del subconjunto y prueban HALT como instrucción adicional. El banco `tb_cpu_step_halt` repite siete programas positivos en RUN/STEP, comprueba estado por avance y descarta HALT del camino incorrecto. `no_halt` demuestra que el CPU no inventa una parada por timeout. [Informe 07](07_halt_y_congelamiento.md) · [Evidencia A-29](../validation/A-29.md).

## Cierre final A-33 — cobertura dinámica del CPU

El 2026-11-09 se ejecutó `run.py regress --companion ../TPs-companion`: 31 targets y 10.725.344 comparaciones. `check_final_coverage.py` exige el inventario completo y obtiene la cobertura del **PC observado en WB al retirar**, no de la mera presencia de instrucciones en los archivos. Las 32 instrucciones se observaron en ambos modos del banco común; HALT se verifica por separado al quedar válido en WB, con ID/EX/MEM inválidos. NOP `00000013` pertenece a ADDI.

Los PC siguientes son bytes y muestran un sitio realmente observado por instrucción. `tb_cpu_step_halt` ejecuta todos estos programas en RUN y STEP, contrasta estados por avance, 32 registros, memoria/dirty y oráculos independientes. Las pruebas específicas de las etapas y del control permanecen en la regresión.

| Instrucción | Programa | PC byte observado | TB adicional de integración |
|---|---|---:|---|
| `add` | `arith_no_hazard` | 48 | `tb_cpu_no_hazard` |
| `sub` | `arith_no_hazard` | 64 | `tb_cpu_no_hazard` |
| `sll` | `arith_no_hazard` | 80 | `tb_cpu_no_hazard` |
| `slt` | `arith_no_hazard` | 176 | `tb_cpu_no_hazard` |
| `sltu` | `arith_no_hazard` | 192 | `tb_cpu_no_hazard` |
| `xor` | `arith_no_hazard` | 160 | `tb_cpu_no_hazard` |
| `srl` | `arith_no_hazard` | 96 | `tb_cpu_no_hazard` |
| `sra` | `arith_no_hazard` | 112 | `tb_cpu_no_hazard` |
| `or` | `arith_no_hazard` | 144 | `tb_cpu_no_hazard` |
| `and` | `arith_no_hazard` | 128 | `tb_cpu_no_hazard` |
| `addi` | `arith_no_hazard` | 0 | `tb_cpu_no_hazard` |
| `slti` | `arith_no_hazard` | 320 | `tb_cpu_no_hazard` |
| `sltiu` | `arith_no_hazard` | 336 | `tb_cpu_no_hazard` |
| `xori` | `arith_no_hazard` | 304 | `tb_cpu_no_hazard` |
| `ori` | `arith_no_hazard` | 288 | `tb_cpu_no_hazard` |
| `andi` | `arith_no_hazard` | 272 | `tb_cpu_no_hazard` |
| `slli` | `arith_no_hazard` | 224 | `tb_cpu_no_hazard` |
| `srli` | `arith_no_hazard` | 240 | `tb_cpu_no_hazard` |
| `srai` | `arith_no_hazard` | 256 | `tb_cpu_no_hazard` |
| `lb` | `arith_no_hazard` | 432 | `tb_cpu_no_hazard` |
| `lh` | `arith_no_hazard` | 464 | `tb_cpu_no_hazard` |
| `lw` | `arith_no_hazard` | 416 | `tb_cpu_no_hazard` |
| `lbu` | `arith_no_hazard` | 448 | `tb_cpu_no_hazard` |
| `lhu` | `arith_no_hazard` | 480 | `tb_cpu_no_hazard` |
| `sb` | `arith_no_hazard` | 368 | `tb_cpu_no_hazard` |
| `sh` | `arith_no_hazard` | 384 | `tb_cpu_no_hazard` |
| `sw` | `arith_no_hazard` | 352 | `tb_cpu_no_hazard` |
| `beq` | `branch_load_use` | 24 | `tb_control_flow / tb_branch_execute` |
| `bne` | `suma` | 20 | `tb_control_flow` |
| `jal` | `jump_link` | 4 | `tb_control_flow / tb_forwarding_paths` |
| `jalr` | `jump_link` | 44 | `tb_control_flow / tb_forwarding_paths` |
| `lui` | `arith_no_hazard` | 32 | `tb_cpu_no_hazard` |
| HALT `00000073` | Los siete positivos; ejemplo `flush_halt` | 24 | `tb_halt_drain`, `tb_cpu_freeze` |

El JSON y el CSV de cobertura en build conservan **todos** los PC y retiros; esta tabla selecciona un ejemplo de cada encoding. Los conteos de retiradas por programa/modo coinciden con los goldens independientes y el ISS, excluyendo HALT. [Informe de M08](08_cpu_listo_para_debug.md) · [Gate A-M08](../validation/A-M08.md).

### Requisitos microarquitectónicos y de sistema

| Requisito | Programa / caso | TB o check / evidencia |
|---|---|---|
| Prioridad RAW y distancias 1/2/3, x0 | `raw_distance` y productores simultáneos | `tb_raw`, `tb_forwarding_paths`, `tb_forwarding_unit`; [A-M04](../validation/A-M04.md). |
| Load-use por dato/base/store/branch/JALR, falsos riesgos | `load_use`, `branch_load_use` y 13 consumidores | `tb_load_use`, `tb_load_use_consumers`, `tb_hazard_unit`; [A-M05](../validation/A-M05.md). |
| Saltos tomados/no tomados, enlaces y bit 0 de JALR | `suma`, `jump_link`, `branch_load_use` | `tb_branch_execute`, `tb_control_flow`; [A-M06](../validation/A-M06.md). |
| Flush elimina writes, stores y HALT jóvenes | `flush_halt` y caminos incorrectos de control | `tb_flush`, `tb_halt_drain`, `tb_cpu_step_halt`; [A-M07](../validation/A-M07.md). |
| HALT exacto, vaciado y efectos anteriores completos | Siete programas HALT, stop-fetch y WB válido | `tb_halt_drain`, `tb_cpu_step_halt`; [A-29](../validation/A-29.md). |
| Freeze de todos los almacenamientos, STEP y reset dominante | Pausa en cada etapa, stores/riesgos/saltos pendientes | `tb_cpu_freeze`, `tb_cpu_step_halt`; [A-28](../validation/A-28.md). |
| Tamaños, signo, alineación/wrap y zero lógico de memoria | Cinco loads, tres stores y casos de dmem | `tb_dmem`, `tb_dmem_dirty`, `tb_mem_wb`; [A-M02](../validation/A-M02.md). |
| 32 registros + 16 selectores + info/flags reales | Captura frente a forwarding, burbujas y stop-fetch | `tb_cpu_debug`; [A-30](../validation/A-30.md). |
| Contrato público e imem externa preservada | CPU real/stub, PC alto y 256 palabras dirty | `check_cpu_contract.py`, `tb_cpu_contract`, `tb_cpu_contract_stub`, `tb_imem_bridge`; [A-31](../validation/A-31.md). |
| UART real, codec, checksum, dump estable e ISS | 34 tramas, tres finales, diez pasos y D repetidos | `tb_system_cpu_smoke`, `check_system_dumps.py`; [A-32](../validation/A-32.md). |
| Ausencia de HALT, timeout, abort, reset y recarga | `no_halt`, dos RUN y recuperación con `flush_halt` | `tb_system_cpu_smoke`; estado parcial explícito, no solo canónico limit. |
| Reproducibilidad e inventario sin omisiones | Seeds fijas, hashes, mismos PC/estado UART entre simuladores | `check_final_coverage.py`, `check_final_xsim.py`; [A-33](../validation/A-33.md). |

| Banco | Seed hexadecimal |
|---|---|
| `tb_mem_wb` | `16abcdef` |
| `tb_execute_stage` | `15e05eed` |
| `tb_decode_stage` | `14dec0de` |
| `tb_alu` | `5eed1234` |
| `tb_pipeline_regs` | `12ab5eed` |
| `tb_fetch` | `13fe7c01` |

Los demás targets son dirigidos. La cobertura funcional se apoya en estos casos, en assertions por avance y en resultados independientes; el número total de comparaciones no mide por sí solo cantidad de escenarios. Este cierre local entrega baseline para AB-05, sin aprobación conjunta nueva ni validación de placa/timing físico.
