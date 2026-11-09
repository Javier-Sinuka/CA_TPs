# Programas de regresión del CPU

Estado vigente desde A-29 (2026-11-09): todos los programas de aceptación terminan mediante HALT explícito. `no_halt` es la excepción deliberada para comprobar ejecución sin parada interna. Los marcadores x31 siguen formando parte del scoreboard, pero ya no son el criterio de finalización.

## Banco común de A-M07

| Programa | PC de HALT | Avances hasta HALT | Writes / stores | Stalls / tomas |
|---|---:|---:|---|---|
| `arith_no_hazard` | 576 | 148 | 31 / 4 | 0 / 0 |
| `raw_distance` | 304 | 80 | 30 / 0 | 0 / 0 |
| `load_use` | 452 | 131 | 36 / 5 | 10 / 2 |
| `suma` | 32 | 57 | 24 / 1 | 0 / 9 |
| `jump_link` | 100 | 30 | 9 / 1 | 0 / 6 |
| `branch_load_use` | 136 | 43 | 17 / 4 | 5 / 4 |
| `flush_halt` | 24 | 10 | 2 / 1 | 0 / 1 |
| `no_halt` | No tiene | Intervalo observado de 100 avances | 0 / 0 | 0 / 33 |

Las direcciones son byte. HALT no se cuenta entre las instrucciones retiradas del ISS: los siete positivos ejecutan 144, 76, 113, 35, 14, 26 y 4 instrucciones anteriores a la parada, respectivamente. El ISS secuencial no modela ciclos de pipeline. `no_halt` se observa durante 100 ciclos de CPU; el límite independiente de su ISS es de 1000 instrucciones, sin exigir igualdad entre ambas cantidades.

Cada `.hex` tiene 256 palabras. Se conserva todo el código anterior y se agrega HALT al final del `.s`; el relleno posterior también es HALT. `flush_halt` tiene un HALT descartado en PC=8, uno alcanzable en PC=24 y writes posteriores que no deben ejecutarse. `no_halt` usa `jal x0,0` y relleno con ese mismo salto: la preparación retira únicamente el HALT automático del ensamblador de B para este caso negativo.

```bash
python3 TP3_FINAL/tools/check_halt_programs.py --companion ../TPs-companion
python3 TP3_FINAL/tools/run.py tb tb_cpu_step_halt --companion ../TPs-companion
python3 TP3_FINAL/tools/run.py test --companion ../TPs-companion
```

Ejecutar desde `Practico/TPs`. El helper comprueba assembler/hex, JSON/hex y los siete estados arquitectónicos contra el ISS de B, sin copiar ni modificar su worktree. El banco común ejecuta los ocho programas en RUN y en STEP: cada flanco habilitado se separa por dos clocks con enable cero. Compara el estado de cada avance, verifica el vaciado en HALT y prueba freeze posterior. CSV/VCD se generan en `TP3_FINAL/build/`.

`tb_cpu_step_halt` acepta `+ROOT=/ruta/a/TPs/`, con barra final, o los nueve archivos hex locales al directorio de simulación. Están registrados en `sim_1` de Vivado. El negativo `vvp -n TP3_FINAL/build/tb_cpu_step_halt.vvp +EXPECT_HALT_NO_HALT` debe fallar al exigir deliberadamente HALT al programa que no lo tiene. Su diagnóstico incluye PC y valid; ese error esperado no es una parada exitosa del CPU.

## Aritmética sin riesgos

`arith_no_hazard.s` conserva 36 instrucciones significativas, cada una seguida de tres NOP; HALT ocupa la palabra 144. Cubre 10 R, 9 I-ALU, LUI y las cinco cargas/tres stores. Parte de x1=-16, x2=3 y x3=0x12345000. Entre sus resultados están x4=fffffff3, x5=ffffffed, x6=ffffff80, x7=1ffffffe, x8=fffffffe y x30=12254000. El marcador x31=000005a5 sigue escribiéndose en el avance 145; el CPU termina en 148.

Los stores son SW de x3 a byte 0, SB de x1 a byte 5, SH de x1 a byte 6 y SW de x0 a byte 1020. Las palabras dirty son 0=12345000, 1=fff0f000 y 255=00000000. Escribir cero igualmente activa dirty.

`arith_no_hazard.expected.json` contiene los 32 registros, palabras dirty, lista de instrucciones significativas, PC de HALT y avances vigentes. Su `.expected.hex` conserva las 800 palabras de 40 bits del scoreboard original:

| Índices | Contenido |
|---|---|
| 0…31 | Registros finales. |
| 32…287 | 256 palabras lógicas finales. |
| 288…543 | 256 dirty finales. |
| 544…799 | Eventos WB por índice de instrucción: bit 37 habilita, 36:32=rd, 31:0=dato. |

Los eventos de NOP, stores, intento de escritura x0 y HALT son cero. El banco dirigido `tb_cpu_no_hazard` mantiene su scoreboard por commit y ahora espera HALT, comprobando PC y valid durante el vaciado.

## RAW y load-use

`raw_distance` conserva distancias 1/2/3 por rs1 y rs2, productores de ambos operandos, prioridad del productor más joven, x0 e instrucciones independientes. Los 30 writes incluyen dos escrituras de x16 y de x29; no son 30 registros distintos. `tb_raw` conserva las comprobaciones dirigidas de selectores y operandos, y ahora termina en HALT. El banco común agrega ejecución paso a paso.

`load_use` conserva sus 13 consumidores. El estado final relevante es x1=96, x2=146, x3=1, x4=42, x5=94, x6=75, x8=73, x9=21, x10=96, x12=31 y x31=1445; el resto es cero. Memoria dirty: byte 0→73, 4→96, 64→73, 100→21 y 104→96. Tiene diez dependencias inmediatas reales y dos ramas tomadas con destino en la siguiente instrucción, que igualmente requieren redirección/flush. `tb_load_use_consumers` conserva el modelo de PC/valid y los 13 casos, incorporando aceptación y vaciado de HALT.

Los 127 avances documentados en A-M05 precedían a la implementación de saltos; desde A-M06 son 131. Agregar HALT inmediatamente después del marcador no aumenta ese número: HALT llega a WB en el mismo flanco en que el marcador anterior escribe el registro.

## Control de flujo

`suma` acumula 1…10: x1=55, x2=x3=11 y memoria byte 0=55. `jump_link` prueba llamada/retorno y JALR impar: ra=x11=8, x5=32, x6=65, x7=48, x8=49, x10=7 y memoria byte 0=49. `branch_load_use` prueba las cuatro condiciones BEQ/BNE posteriores a carga y load→JALR: x1=x4=x8=73, x2=x3=x9=21, x5=x6=101, x7=104, x10=1, x11=2 y x12=3; memoria 0→73, 4→21, 12→101, 16→3. Los tres conservan x31=0x5a5.

Sus JSON conservan las secuencias dinámicas independientes de A-26, ahora con `halt_pc`. Los `.expected.hex` conservan 1152 palabras de 32 bits: cabecera 0…6, registros 7…38, memoria 39…294, dirty 295…550 y eventos de 14 palabras desde 551. El evento describe PC, efectos, rd/dato WB, dirección/dato store, control/destino/toma, dependencia load-use, operandos esperados y selectores. HALT se comprueba aparte de los eventos anteriores, sin inventar un commit para la parada.

`check_control_programs.py` ahora contrasta los hex RTL que realmente contienen HALT; ya no genera una entrada de ISS distinta sin avisar. `tb_control_flow` conserva el seguimiento EX/MEM/WB y espera HALT válido con las etapas jóvenes vacías.

## Oráculo común serializado

`halt_suite.expected.json` define los ocho casos y `halt_suite.expected.hex` contiene ocho bloques de 560 palabras de 32 bits:

| Offset dentro del bloque | Contenido |
|---|---|
| 0…6 | PC HALT (`ffffffff` para no_halt), avances, writes, stores, stalls, tomas, instrucciones anteriores a HALT o retiradas en el intervalo acotado. |
| 7…38 | x0…x31. |
| 39…294 | 256 palabras lógicas de memoria. |
| 295…550 | 256 dirty. |
| 551…559 | Reservado, cero. |

El estado se fijó con las constantes históricas y los programas simples nuevos; el ISS se utiliza como una segunda comprobación arquitectónica. No se usa el resultado del RTL para regenerar expectativas. El helper solo verifica, sin reescribir los golden.

El [informe A-M07](../doc/documentation/07_halt_y_congelamiento.md) explica la estructura de HALT, el vaciado, el enable común, los pasos, el reset y sus límites. Los resultados de las issues anteriores se conservan como evidencia histórica de su versión del diseño.
