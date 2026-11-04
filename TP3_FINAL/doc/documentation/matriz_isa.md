# A-05 — matriz ISA y señales de control de Fase 1

La matriz describe las **32 instrucciones del subconjunto** más HALT.
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
