# B-16 · Testbench del sistema de debug completo (guion)

`M` · etiquetas `debug-unit` `test` · milestone M2 · **Modelo sugerido:** Sonnet · [índice](../README.md)

## Objetivo
`tb_system_debug.sv` corre el guion completo de la Fase 10 contra `system` (UART + Debug Unit + stub + imem) manejado solo por la línea serie, y deja un log de bytes que reutilizan B-23 y B-28.

## Antes de empezar
- Leer: B-10 (helpers del TB), `protocolo.md` §7, `convenciones.md` §5.
- Precondiciones: B-15 cerrado (`tb_debug_unit_h20` y `_h0` → PASS).
- Rama: `b/B-16-tb-sistema`.

## Archivos
| Acción | Ruta | Contenido |
| --- | --- | --- |
| crear | `TP3_FINAL/VIVADO/TP_FINAL/tb/debug/tb_system_debug.sv` | Paso 1 |
| modificar | `TP3_FINAL/tools/tbs.py` | Paso 3 |

## Pasos
1. `tb/debug/tb_system_debug.sv`: mismo encabezado, instancia `dut`, `include`s y monitores que `tb_debug_unit.sv` (B-10, B-13), con `HALT_AT = 20` fijo (localparam), `BYTE_TIMEOUT = 20_000`, `RUN_TIMEOUT = 1_000`, `BAUD_RATE = CLOCK_FREQ / 32`. Al empezar:

```systemverilog
log_fd = $fopen("TP3_FINAL/build/tb_system_debug.bytes.log", "w");
$fwrite(log_fd, "# tb_system_debug v1\n");
```

   y `$fclose(log_fd)` antes del `PASS`/`$fatal`. Cada paso del guion empieza con `log_step("<nombre>")` usando exactamente los nombres de la tabla.

2. Guion (en este orden, sin pausas entre pasos salvo las que impone esperar la respuesta). `progA[i] = 32'hA000_0000 + i` para `i = 0..36`; `progB = {32'h0050_0093, 32'h0000_0073}`.

| # | Nombre (`log_step`) | Host envía | Esperado | Chequeo extra |
| --- | --- | --- | --- | --- |
| 1 | `V` | `56` | `56 01 00 01 00 01` | — |
| 2 | `L A` | `4C 25 00`, luego 148 bytes de `progA` | `4B`, luego `4B` | `check_imem(37)` con `prog = progA` |
| 3 | `S 1` … `S 5` | `53` (cinco pasos) | `dump_c1_h20` … `dump_c5_h20` | `en_cycles` +1 por paso |
| 4 | `R` | `52` | `dump_c20_h20.hex` | — |
| 5 | `D` | `44` | `dump_c20_h20.hex` | — |
| 6 | `X` | `58` | `4B` | — |
| 7 | `L B` | `4C 02 00`, luego `93 00 50 00 73 00 00 00` | `4B`, luego `4B` | `check_imem(2)` con `prog = progB` |
| 8 | `R B` | `52` | `dump_c20_h20.hex` | — |
| 9 | `invalido` | `7A` | `45 01` | — |
| 10 | `D final` | `44` | `dump_c20_h20.hex` | — |

   Final: `PASS tb_system_debug: N chequeos`. Watchdog de 100 ms simulados.

   Formato del log (lo que escriben `send_all` y `recv_n` de los helpers; no cambiarlo, B-23 lo parsea):

```
# tb_system_debug v1
# V
> 56
< 56
< 01
...
# L A
> 4c
...
```

   Una línea por byte, `> ` = host → placa, `< ` = placa → host, dos dígitos hex en minúscula; las líneas `# ` son comentarios. En los pasos con envío y recepción simultáneos el orden de las líneas es el del tiempo de simulación.

3. `tools/tbs.py`:

```python
"tb_system_debug": {"top": "tb_system_debug",
                    "files": DEBUG_FILES_BASE + ["TP3_FINAL/VIVADO/TP_FINAL/tb/debug/tb_system_debug.sv"],
                    "defines": {"CPU_STUB": "1"}, "params": {},
                    "incdirs": ["TP3_FINAL/VIVADO/TP_FINAL/tb/common"]},
```

   donde `DEBUG_FILES_BASE` es la lista de B-10 sin `tb_debug_unit.sv` (refactorizar `DEBUG_FILES = DEBUG_FILES_BASE + [tb_debug_unit.sv]`).

4. Medir el tiempo (PowerShell): `Measure-Command { py TP3_FINAL/tools/run.py tb tb_system_debug }`. Anotar los segundos en la descripción del PR.

## Validación
```
py TP3_FINAL/tools/run.py tb tb_system_debug → "PASS tb_system_debug: N chequeos", código 0
Test-Path TP3_FINAL/build/tb_system_debug.bytes.log → True; primera línea "# tb_system_debug v1"
py TP3_FINAL/tools/run.py test → código 0
```

## Listo cuando
- [ ] El guion completo pasa sin intervención.
- [ ] El tiempo total (`Measure-Command`) es menor a 60 s.
- [ ] El log de bytes queda en `TP3_FINAL/build/tb_system_debug.bytes.log` con el formato de arriba (B-23 lo copia a `sw/tests/data/`).

## No hacer
- No copiar el log a `sw/tests/data/` (lo hace B-23).
- No duplicar los helpers: incluir `tb_debug_helpers.svh`.

## Si algo falla
| Síntoma | Qué hacer |
| --- | --- |
| Tarda más de 60 s | Confirmar `BAUD_RATE = CLOCK_FREQ/32` y `RUN_TIMEOUT = 1000`; si igual tarda, detenerse y avisar (no subir el baud: `DIV = 2` es el mínimo) |
| Log vacío | `log_fd` se abre después de los primeros envíos o falta `$fclose` |
| `$fopen` falla | `vvp` no corre con `cwd` = raíz del repo (B-09 paso 7) |

## Commits
1. `debug: tb_system_debug con el guion de la Fase 10 y log de bytes`

## Depende de / bloquea
Depende de: B-10 a B-15. Bloquea: B-17, B-23, B-27, B-28.
