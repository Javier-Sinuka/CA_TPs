# B-15 · Memoria de datos usada en el dump

`S` · etiquetas `debug-unit` `bloquea-A` · milestone M2 · **Modelo sugerido:** Haiku · [índice](../README.md)

## Objetivo
Comprobar de punta a punta que el dump lista solo las palabras sucias, en orden ascendente, y que la lista queda vacía después de `X` y de `L`.

No hay RTL nuevo: el recorrido está en B-14 y la limpieza la hace el reset del CPU (`interfaz_cpu.md` §3, D-19), que `X` y `L` ya disparan. Este issue es de verificación y deja la obligación de A explícita.

## Antes de empezar
- Leer: `dump.md` §1, `interfaz_cpu.md` §3, §4 y §8.
- Precondiciones: B-13 cerrado.
- Rama: `b/B-15-dirty`.

## Archivos
| Acción | Ruta | Contenido |
| --- | --- | --- |
| modificar | `TP3_FINAL/VIVADO/TP_FINAL/tb/debug/tb_debug_unit.sv` | Casos de abajo |

## Pasos
1. Casos en la rama `HALT_AT == 20`, después de los de B-13:

| Caso | Host envía | Esperado | Chequeo extra |
| --- | --- | --- | --- |
| `X` | `58` | `4B` | — |
| `S 1..3` | `53` ×3 (tres `transact`) | `dump_c1_h20`, `dump_c2_h20`, `dump_c3_h20` | — |
| `D con 3 sucias` | `44` | `dump_c3_h20.hex` (234) | `q_rx[205..208] == 03 00 00 00`; direcciones de los pares (bytes `q_rx[209..212]`, `[217..220]`, `[225..228]`) `== 0x10, 0x40, 0xFC` |
| `X limpia` | `58` | `4B` | — |
| `D tras X` | `44` | `dump_c0_h20.hex` (210, `M = 0`) | — |
| `S` | `53` | `dump_c1_h20.hex` | — |
| `L N=0` | `4C 00 00` | `4B 4B` | — |
| `D tras L` | `44` | `dump_c0_h20.hex` (210, `M = 0`) | — |

2. No editar `interfaz_cpu.md` (ya lo dice). Agregar al final de la descripción del PR la línea: "A: con el CPU real, este mismo caso tiene que dar M = 0 después de X y L (reset de dirty, interfaz_cpu.md §3)", para que A lo tenga en su checklist de la Fase 10.

## Validación
```
py TP3_FINAL/tools/run.py tb tb_debug_unit_h20 → PASS
```

## Listo cuando
- [ ] El dump lista exactamente 3 pares (dirección, dato) en orden ascendente (0x10, 0x40, 0xFC).
- [ ] Después de `X` o de `L` la lista está vacía (`M = 0`, dump de 210 bytes).

## No hacer
- No agregar lógica de dirty a la Debug Unit: los bits viven en el CPU (stub o real).

## Si algo falla
| Síntoma | Qué hacer |
| --- | --- |
| Tras `X` el dump sigue con 3 pares | El stub no recibe el reset: revisar `w_cpu_reset = i_reset | w_dbg_cpu_rst` en `system.v` |
| Pares desordenados | `S_DUMP_SEEK` recorre `r_maddr` de 0 a 255 en orden; revisar B-14 |

## Commits
1. `debug: casos de memoria usada en tb_debug_unit`

## Depende de / bloquea
Depende de: B-13, B-14. Bloquea: B-16.
