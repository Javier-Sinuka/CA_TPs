# A-01 — inventario y contrato del RTL de Fase 1

Estado observado el 2026-11-03. Ruta base real: `TP3_FINAL/VIVADO/TP_FINAL/`.
El proyecto Vivado `TP_FINAL.xpr` registra los cinco archivos RTL y los tres TB
de la tabla. El top de diseño configurado actualmente es `control`; el top de
simulación configurado es `tb_alu`. No hay aún un módulo `cpu`. El `.xpr`
declara `xc7a35ticpg236-1L`; las convenciones recibidas identifican la Basys3
como `xc7a35tcpg236-1`, discrepancia que requiere corrección antes de usar
ese proyecto para síntesis de la placa.

## Módulos y puertos

| Módulo | Fuente y TB | Entradas → salidas | Tipo, valores por defecto y dependencia |
|---|---|---|---|
| `alu` | `rtl/cpu/execute/alu.v`, `tb/cpu/unit/tb_alu.sv` | `i_operand_a[31:0]`, `i_operand_b[31:0]`, `i_op[3:0]` → `o_result[31:0]` | Combinacional; código no definido devuelve 0. Incluye `riscv_defs.vh`. |
| `alu_control` | `rtl/cpu/decode/alu_control.v`; **sin TB propio** | `i_opcode[6:0]`, `i_funct3[2:0]`, `i_funct7[6:0]` → `o_alu_op[3:0]`, `o_valid` | Combinacional; default ADD e inválido. Lo instancia `control`; incluye `riscv_defs.vh`. |
| `imm_gen` | `rtl/cpu/decode/imm_gen.v`, `tb/cpu/unit/tb_imm_gen.sv` | `i_instr[31:0]` → `o_imm[31:0]` | Combinacional; opcode no reconocido devuelve 0. Incluye `riscv_defs.vh`. |
| `control` | `rtl/cpu/decode/control.v`, `tb/cpu/unit/tb_control.sv` | `i_instr[31:0]` → `o_alu_op[3:0]` y 13 señales de 1 bit: `o_alu_src_b`, `o_reg_write`, `o_mem_read`, `o_mem_write`, `o_mem_to_reg`, `o_branch`, `o_jump`, `o_jalr`, `o_lui`, `o_halt`, `o_uses_rs1`, `o_uses_rs2`, `o_valid_instr` | Combinacional; default ADD y todas las banderas a 0. Requiere `alu_control.v` y el include. |

Ninguno tiene clock, reset, enable ni parámetros. Los cuatro usan `always @(*)`
y asignan un valor inicial a cada salida. `alu` interpreta `SRA` y `SLT`
con signo mediante `$signed`; `SLTU` y los demás operadores de comparación
son unsigned. ADD/SUB conservan 32 bits y los shifts usan `b[4:0]`.
`imm_gen` extiende signo en I/S/B/J; U concatena 12 ceros. El control usa
`casez` para los inmediatos ALU cuyo campo alto es libre; antes descarta X/Z
en sus tres entradas. Para una instrucción desconocida, `control` no activa
efectos. HALT solo se reconoce como palabra exacta `00000073`.

`riscv_defs.vh` es la única definición de opcodes, `funct7`, HALT y códigos
ALU dentro del RTL de Fase 1. No se encontraron redefiniciones en estos
módulos. Códigos internos: ADD=0, SUB=1, SLL=2, SRL=3, SRA=4, AND=5,
OR=6, XOR=7, SLT=8, SLTU=9. `o_alu_op` mide 4 bits y cabe en `info[21:18]`
del dump v1 recibido en `planning/_fuentes/documentacion_companero/dump.md`.
Su encabezado aún lo rotula como propuesta; A confirmó el 2026-11-04
que el contrato ya fue acordado con B y debe cumplirse.
Sus palabras `info` transportan `alu_op` solo en EX; MEM/WB exponen cero
en ese campo, según presencia por etapa.

## Matriz de las 32 instrucciones y HALT

`C` = `control.v` + `alu_control.v` para R/I-ALU; `C` = `control.v`
para las restantes. `I` = `imm_gen.v`; `A` = `alu.v` (uso previsto en
el futuro datapath). Cada fila tiene un vector dirigido en `tb_control`,
que **se ejecutó y pasó** en A-01. Los TB de ALU e inmediatos prueban
operaciones/formatos por separado; **no prueban todavía la instrucción
extremo a extremo**. No hay CPU ni memoria para ello.

| Instrucción | Decodificación C | Inmediato I | Operación A / destino previsto | Estado de prueba |
|---|---|---|---|---|
| add | R, f3=0, f7=00 | — | ADD | Control dirigido; ALU separada |
| sub | R, f3=0, f7=20 | — | SUB | Control dirigido; ALU separada |
| sll | R, f3=1, f7=00 | — | SLL | Control dirigido; ALU separada |
| slt | R, f3=2, f7=00 | — | SLT | Control dirigido; ALU separada |
| sltu | R, f3=3, f7=00 | — | SLTU | Control dirigido; ALU separada |
| xor | R, f3=4, f7=00 | — | XOR | Control dirigido; ALU separada |
| srl | R, f3=5, f7=00 | — | SRL | Control dirigido; ALU separada |
| sra | R, f3=5, f7=20 | — | SRA | Control dirigido; ALU separada |
| or | R, f3=6, f7=00 | — | OR | Control dirigido; ALU separada |
| and | R, f3=7, f7=00 | — | AND | Control dirigido; ALU separada |
| addi | I-ALU, f3=0 | I | ADD | Control dirigido; ALU/I separados |
| slti | I-ALU, f3=2 | I | SLT | Control dirigido; ALU/I separados |
| sltiu | I-ALU, f3=3 | I | SLTU | Control dirigido; ALU/I separados |
| xori | I-ALU, f3=4 | I | XOR | Control dirigido; ALU/I separados |
| ori | I-ALU, f3=6 | I | OR | Control dirigido; ALU/I separados |
| andi | I-ALU, f3=7 | I | AND | Control dirigido; ALU/I separados |
| slli | I-ALU, f3=1, imm[11:5]=00 | I | SLL | Control dirigido; ALU/I separados |
| srli | I-ALU, f3=5, imm[11:5]=00 | I | SRL | Control dirigido; ALU/I separados |
| srai | I-ALU, f3=5, imm[11:5]=20 | I | SRA | Control dirigido; ALU/I separados |
| lb | load, f3=0 | I | ADD dirección; LB pendiente | Control dirigido; memoria ausente |
| lh | load, f3=1 | I | ADD dirección; LH pendiente | Control dirigido; memoria ausente |
| lw | load, f3=2 | I | ADD dirección; LW pendiente | Control dirigido; memoria ausente |
| lbu | load, f3=4 | I | ADD dirección; LBU pendiente | Control dirigido; memoria ausente |
| lhu | load, f3=5 | I | ADD dirección; LHU pendiente | Control dirigido; memoria ausente |
| sb | store, f3=0 | S | ADD dirección; SB pendiente | Control dirigido; memoria ausente |
| sh | store, f3=1 | S | ADD dirección; SH pendiente | Control dirigido; memoria ausente |
| sw | store, f3=2 | S | ADD dirección; SW pendiente | Control dirigido; memoria ausente |
| beq | branch, f3=0 | B | comparación/destino en EX pendiente | Control dirigido; datapath ausente |
| bne | branch, f3=1 | B | comparación/destino en EX pendiente | Control dirigido; datapath ausente |
| jal | jump, opcode=6F | J | PC+4 y PC+imm pendientes | Control dirigido; datapath ausente |
| jalr | jump, opcode=67, f3=0 | I | PC+4 y (rs1+imm)&~1 pendientes | Control dirigido; datapath ausente |
| lui | U, opcode=37 | U | inmediato U; mux EX pendiente | Control dirigido; datapath ausente |
| HALT | palabra exacta 00000073 | — | avance/detención pendientes | Control dirigido; CPU ausente |

Las 32 instrucciones más HALT aparecen en la lógica de control. `imm_gen`
selecciona por opcode y no valida `funct3`; es responsabilidad de `control`
neutralizar instrucciones inválidas. `alu_control.o_valid` solo informa
validez de R/I-ALU, no de toda la ISA. `o_valid_instr` es validez de
codificación, distinta del futuro bit `valid` de los registros de pipeline.

## Brechas y siguiente trabajo

- **A-02:** ampliar las pruebas de bordes de ALU, signed/unsigned y shifts.
- **A-03:** falta `tb_alu_control` aislado; probar patrones R/I válidos e
  inválidos y la conexión decoder→ALU, en particular ADDI negativo.
- **A-04:** ampliar `tb_imm_gen` con límites I/S/B/J y negativos.
- **A-05:** confirmar cobertura exacta de controles y fuentes para las
  32 instrucciones y codificaciones inválidas. La matriz de arriba prueba
  decodificación dirigida, no resultados arquitectónicos.
- **A-06:** congelar la baseline solo después de esas auditorías.
- **Interfaz B-08:** existe el documento completo
  `planning/_fuentes/documentacion_companero/interfaz_cpu.md`, cuyo encabezado
  conserva el estado anterior aunque A confirmó el acuerdo con B. No existe en el árbol de
  implementación `rtl/debug/cpu_ports.vh` ni `cpu.v`. Son puertos del futuro
  módulo `cpu`, no de estos bloques internos; no se detecta incompatibilidad
  de nombres/ancho en Fase 1. La implementación futura debe cumplirlo.
- **Convenciones de TB:** los tres TB existentes tenían 81 checks y `$fatal`
  ante discrepancia, pero imprimían `tb_* passed` en vez de `PASS <top>:`.
  A-01 ajustó solo esas líneas finales para que el runner reconozca el éxito.
  Las auditorías A-02…A-05 deben incorporar el resto del formato exigido
  (contador `errors`, líneas `FAIL`, watchdog independiente y bordes faltantes).

Evidencia de comandos y resultados: [A-01](../validation/A-01.md).
