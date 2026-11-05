# Programa de cierre A-M03

`arith_no_hazard.s` ejecuta 36 instrucciones significativas, cada una seguida por tres `nop` (`addi x0,x0,0`). Son 144 palabras; `arith_no_hazard.hex` completa las 256 posiciones de imem con NOP. No contiene HALT. Los PC e índices del JSON son direcciones byte, no números de instrucción. El programa escribe una sola vez cada destino x1…x31 y también intenta escribir x0; así las expectativas de cada commit coinciden con los valores finales guardados.

## Resultados calculados aparte

Se fijaron constantes a partir de x1 = −16 (`fffffff0`), x2 = 3 y x3 = `12345000`. No se ejecutó el decoder ni la ALU RTL para producirlas. El ensamblador de B se utilizó solamente para codificar instrucciones, desde su worktree original.

| Operación | Registro | Resultado hexadecimal |
|---|---|---|
| ADD / SUB | x4 / x5 | `fffffff3` / `ffffffed` |
| SLL / SRL / SRA | x6 / x7 / x8 | `ffffff80` / `1ffffffe` / `fffffffe` |
| AND / OR / XOR | x9 / x10 / x11 | `00000000` / `fffffff3` / `fffffff3` |
| SLT / SLTU | x12 / x13 | `00000001` / `00000000` |
| ADDI | x14 | `ffffffeb` |
| SLLI / SRLI / SRAI | x15 / x16 / x17 | `ffffff80` / `1ffffffe` / `fffffffe` |
| ANDI / ORI / XORI | x18 / x19 / x20 | `00000050` / `fffffff5` / `0000000f` |
| SLTI / SLTIU | x21 / x22 | `00000001` / `00000001` |
| LW desde palabra 0 | x23 | `12345000` |
| LB / LBU desde byte 5 | x24 / x25 | `fffffff0` / `000000f0` |
| LH / LHU desde byte 6 | x26 / x27 | `fffffff0` / `0000fff0` |
| LW desde palabra 1 / palabra limpia 2 | x28 / x29 | `fff0f000` / `00000000` |
| ADD x23+x28 | x30 | `12254000` |
| Marcador ADDI | x31 | `000005a5` |

La suma de x30 descarta el acarreo de 32 bits: `12345000 + fff0f000 = 1_12254000`. SLTU compara `fffffff0` con 3 y da cero; SLTIU compara con el inmediato −1 extendido (`ffffffff`) y da uno. Los desplazamientos lógicos rellenan con ceros y los aritméticos conservan el signo.

Los cuatro stores son `sw x3,0(x0)`, `sb x1,5(x0)`, `sh x1,6(x0)` y `sw x0,1020(x0)`. La palabra 1 pasa de cero lógico a `0000f000` y luego a `fff0f000`; las únicas palabras sucias finales son 0, 1 y 255. La 255 contiene cero pero tiene dirty=1. Todas las otras palabras deben verse como cero y limpias.

## Archivos de expectativas

`arith_no_hazard.expected.json` es la representación legible: 32 registros, palabras sucias, límites y mapa PC→instrucción. `arith_no_hazard.expected.hex` es su representación para `$readmemh`, con 800 entradas de 40 bits, una por línea:

| Índices inclusivos | Contenido |
|---|---|
| 0…31 | Registro arquitectónico final, extendido por ceros a 40 bits. |
| 32…287 | Las 256 palabras lógicas finales de dmem. |
| 288…543 | Las 256 marcas dirty finales, valor 0 o 1. |
| 544…799 | Evento de escritura WB por índice de instrucción: bit 37 habilita, bits 36:32 son rd, bits 31:0 el valor esperado; bits 39:38 son cero. |

Los eventos de NOP, stores e intento de escritura x0 son cero. Para una instrucción que escribe, el dato se toma de las constantes anteriores, no de sus operandos observados en el DUT. El scoreboard de tiempo no interpreta la ISA ni recalcula la ALU.

## Fin y reproducción

El marcador está en PC byte 560 (palabra 140). Entra a WB después del avance 144 y escribe x31 en el avance 145. El TB exige ese commit, exactamente 31 escrituras efectivas y cuatro stores, además de todos los datos finales. Después pausa cuatro clocks adicionales. Un límite de clocks o el watchdog es un fallo.

Desde `Practico/TPs`:

```bash
python3 TP3_FINAL/tools/run.py tb tb_cpu_no_hazard --companion ../TPs-companion
```

El TB genera `TP3_FINAL/build/a17_pipeline.vcd` y `a17_trace.csv` (ignorados por Git). Repite reset, ejecución continua y ejecución con pausas deterministas. En Vivado las dos entradas `.hex` están en `sim_1` y se copian al directorio de simulación; el TB acepta esos nombres locales. Para otra ubicación se puede pasar `+ROOT=/ruta/a/TPs/` a vvp, o `-testplusarg ROOT=/ruta/a/TPs/` a XSim, incluyendo la barra final. Los archivos de salida quedan en build al usar ROOT o ejecutar desde el repositorio; en el modo de archivos locales quedan junto a la simulación.

Para verificar de nuevo la codificación con el ensamblador de B sin copiarlo ni usar su HALT automático:

```bash
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=../TPs-companion/TP3_FINAL/sw python3 - <<'PY'
from pathlib import Path
from asm.rvasm import assemble, to_hex
base = Path('TP3_FINAL/programs/arith_no_hazard')
words = assemble(base.with_suffix('.s').read_text())
assert words[-1] == 0x73
words = words[:-1]
assert len(words) == 144
assert to_hex(words + [0x13] * (256 - len(words))) == base.with_suffix('.hex').read_text()
print('PASS arith_no_hazard encoding')
PY
```

Esto valida el pipeline sin riesgos. Forwarding, load-use, redirección y finalización HALT se comprobarán en sus milestones; A-29 repetirá aceptación con HALT real.

## Programa `raw_distance` de A-M04

`raw_distance.s` contiene 76 palabras: grupos de distancias RAW 1, 2 y 3 en `rs1` y `rs2`, dos productores distintos, dos escrituras sucesivas al mismo destino, un intento de escritura a `x0`, instrucciones independientes y un marcador final en x31. `raw_distance.hex` tiene 256 palabras; las posiciones 76…255 se completan con NOP. El HALT agregado automáticamente por el ensamblador de B se retira porque el CPU aún no implementa la detención. No hay cargas, stores ni saltos en este programa.

Los valores esperados están escritos como constantes en `tb/tb_raw.sv` y se explican en el [informe A-M04](../doc/documentation/04_forwarding.md). La instrucción final significativa está en PC 288 y escribe x31=`0x000005a5` en el avance 77. El TB verifica PC consecutivos, selectores, operandos, resultados, los 32 registros y las 256 palabras/dirty de dmem.

Desde `Practico/TPs`:

```bash
python3 TP3_FINAL/tools/run.py tb tb_raw --companion ../TPs-companion
```

Para comprobar que el hex sigue correspondiendo al ensamblador del worktree de B:

```bash
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=../TPs-companion/TP3_FINAL/sw python3 - <<'PY'
from pathlib import Path
from asm.rvasm import assemble, to_hex
base = Path('TP3_FINAL/programs/raw_distance')
words = assemble(base.with_suffix('.s').read_text())
assert words[-1] == 0x73 and len(words) == 77
assert to_hex(words[:-1] + [0x13] * (256 - len(words[:-1]))) == base.with_suffix('.hex').read_text()
print('PASS raw_distance encoding')
PY
```
