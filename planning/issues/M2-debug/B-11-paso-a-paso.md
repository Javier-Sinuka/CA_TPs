# B-11 · Paso a paso: comando `S`

`S` · etiquetas `debug-unit` · milestone M2 · **Modelo sugerido:** Sonnet · [índice](../README.md)

## Objetivo
Cada `S` avanza el CPU exactamente un ciclo (`cpu_en` = 1 durante un único flanco) y responde el dump.

## Antes de empezar
- Leer: `protocolo.md` §4 (`S`), B-10 (diseño de la FSM), `decisiones.md` D-25.
- Precondiciones: B-14 cerrado (`tb_debug_unit_h20` con los casos de dump → PASS).
- Rama: `b/B-11-step`.

## Archivos
| Acción | Ruta | Contenido |
| --- | --- | --- |
| modificar | `TP3_FINAL/VIVADO/TP_FINAL/rtl/debug/debug_unit.v` | Marcas `// B-11:` |
| modificar | `TP3_FINAL/VIVADO/TP_FINAL/tb/debug/tb_debug_unit.sv` | Casos de abajo |

## Pasos
1. En `S_IDLE`, reemplazar `// B-11: CMD_STEP` por:

```verilog
                    CMD_STEP: begin
                        r_cpu_en  <= 1'b1;       // 1 durante el ciclo de S_STEP
                        r_timeout <= 1'b0;
                        r_aborted <= 1'b0;
                        r_state   <= S_STEP;
                    end
```

2. Reemplazar `// B-11: S_STEP` por:

```verilog
            S_STEP: begin
                // cpu_en estuvo en 1 durante exactamente el flanco al final de este ciclo
                r_cpu_en <= 1'b0;
                r_maddr  <= 9'd0;
                r_mcount <= 9'd0;
                r_state  <= S_DUMP_COUNT;
            end
```

3. Casos en `tb_debug_unit.sv`, rama `HALT_AT == 20`, después de los de B-14 (estado de partida: 0 ciclos). Guardar `en_cycles` antes de cada `transact` como `en0`.

| Caso | Host envía | Esperado | Chequeo extra |
| --- | --- | --- | --- |
| `S k` para k = 1 … 10 | `53` | `dump_c<k>_h20.hex` (234 bytes) | `en_cycles == en0 + 1` |
| `S k` para k = 11 … 19 | `53` | 234 bytes, sin comparar contenido | `en_cycles == en0 + 1` |
| `S 20` | `53` | `dump_c20_h20.hex` (234; `halted` = 1) | `en_cycles == en0 + 1` |
| `S con halted` | `53` | `dump_c20_h20.hex` otra vez | `en_cycles == en0 + 1` (el pulso existe, pero el stub no avanza) |

   Implementar los 10 primeros con un `for` y `$sformatf("dump_c%0d_h20.hex", k)`. Para k = 11…19: `q_clear; q_push(8'h53); transact(234);` (sin `check_exp`), y el chequeo de `en_cycles`.

## Validación
```
py TP3_FINAL/tools/run.py tb tb_debug_unit_h20 → PASS, código 0
py TP3_FINAL/tools/run.py synth_ooc debug_unit → limpio
```
Prueba de detección (no se commitea): en `S_STEP` dejar `r_cpu_en` en 1 un ciclo más (pasar por un estado intermedio) → fallan los chequeos de `en_cycles` y los vectores; revertir.

## Listo cuando
- [ ] 10 `S` seguidos dan 10 flancos habilitados y 10 dumps iguales al modelo.
- [ ] El `S` número 20 deja `halted = 1` y un `S` más con el CPU en `halted` devuelve el mismo dump.

## No hacer
- No generar `cpu_en` combinacional ni desde el `case` de `S_IDLE` sin pasar por el registro.
- No tocar el contador `r_cycles` (lo maneja su propio bloque).

## Si algo falla
| Síntoma | Qué hacer |
| --- | --- |
| `en_cycles` sube 2 por `S` | `r_cpu_en` no baja en `S_STEP` |
| Dump con `cycles` igual al anterior | `S` cae en `default` (`45 01`): falta el `case` de `CMD_STEP` |
| Dump `c1` correcto pero `M = 0` | El dump arrancó antes de que el stub avance: `S_STEP` tiene que existir como ciclo propio |

## Commits
1. `debug: comando S`
2. `debug: casos de paso a paso en tb_debug_unit`

## Depende de / bloquea
Depende de: B-14. Bloquea: B-12, B-15, B-16.
