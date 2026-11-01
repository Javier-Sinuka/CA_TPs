# B-12 · Ejecución continua: `R`, timeout y `A`

`M` · etiquetas `debug-unit` · milestone M2 · **Modelo sugerido:** Sonnet · [índice](../README.md)

## Objetivo
`R` corre el CPU hasta `halted`, hasta recibir `A` o hasta `RUN_TIMEOUT` ciclos habilitados, con esa prioridad, y responde el dump con la causa en el estado.

## Antes de empezar
- Leer: `protocolo.md` §2 (reglas 4 y 5) y §4 (`R`), `dump.md` §2, B-10 (diseño de la FSM).
- Precondiciones: B-11 cerrado.
- Rama: `b/B-12-run`.

## Archivos
| Acción | Ruta | Contenido |
| --- | --- | --- |
| modificar | `TP3_FINAL/VIVADO/TP_FINAL/rtl/debug/debug_unit.v` | Marcas `// B-12:` |
| modificar | `TP3_FINAL/VIVADO/TP_FINAL/tb/debug/tb_debug_unit.sv` | Casos de abajo |

## Pasos
1. En `S_IDLE`, reemplazar `// B-12: CMD_RUN` por:

```verilog
                    CMD_RUN: begin
                        r_timeout <= 1'b0;
                        r_aborted <= 1'b0;
                        if (i_cpu_halted) begin
                            // ya parado: dump enseguida
                            r_maddr  <= 9'd0;
                            r_mcount <= 9'd0;
                            r_state  <= S_DUMP_COUNT;
                        end else begin
                            r_cpu_en  <= 1'b1;
                            r_run_cnt <= 32'd0;
                            r_state   <= S_RUN;
                        end
                    end
```

2. Reemplazar `// B-12: S_RUN` por:

```verilog
            S_RUN: begin
                // r_cpu_en = 1 en todo este estado. r_run_cnt = ciclos con en = 1
                // ya transcurridos antes de este; prioridad halted > A > timeout.
                r_run_cnt <= r_run_cnt + 32'd1;
                if (i_cpu_halted) begin
                    r_cpu_en <= 1'b0;
                    r_maddr  <= 9'd0;
                    r_mcount <= 9'd0;
                    r_state  <= S_DUMP_COUNT;
                end else if (i_rx_valid && i_rx_data == CMD_ABORT) begin
                    r_cpu_en  <= 1'b0;
                    r_aborted <= 1'b1;
                    r_maddr   <= 9'd0;
                    r_mcount  <= 9'd0;
                    r_state   <= S_DUMP_COUNT;
                end else if (r_run_cnt == RUN_TIMEOUT - 1) begin
                    r_cpu_en  <= 1'b0;
                    r_timeout <= 1'b1;
                    r_maddr   <= 9'd0;
                    r_mcount  <= 9'd0;
                    r_state   <= S_DUMP_COUNT;
                end
            end
```

   Cuentas que salen de este código (las verifica el TB): sin HALT, `cpu_en` vale 1 durante exactamente `RUN_TIMEOUT` flancos. Con `HALT_AT = 20` desde 0 ciclos, vale 1 durante 21 flancos (20 que avanzan + el ciclo en que se ve `halted`, que no avanza). Cualquier byte distinto de `A` durante `S_RUN` se descarta (lo hace `w_consumes` de B-10).

3. Casos en `tb_debug_unit.sv`. Guardar `en0 = en_cycles` antes de cada `transact`.

   Rama `HALT_AT == 20`, después de los de B-11 (estado de partida: 20 ciclos, `halted`):

| Caso | Host envía | Esperado | Chequeo extra |
| --- | --- | --- | --- |
| `R con halted` | `52` | `dump_c20_h20.hex` | `en_cycles == en0` |
| `X` | `58` | `4B` | — |
| `R hasta HALT` | `52` | `dump_c20_h20.hex` | `en_cycles == en0 + 21` |

   Rama `HALT_AT == 0`, después del caso `D h0` de B-14 (0 ciclos):

| Caso | Host envía | Esperado | Chequeo extra |
| --- | --- | --- | --- |
| `R timeout` | `52` | `dump_c1000_h0_t.hex` (234) | `en_cycles == en0 + 1000` |
| `X` | `58` | `4B` | — |
| `R con otro byte` | `52 56` (seguidos) | `dump_c1000_h0_t.hex` | luego `expect_silence(20_000.0, ...)`: la `V` se descartó |
| `X` | `58` | `4B` | — |
| `R con A` | `52 41` (seguidos) | 234 bytes, chequeo estructural (abajo) | — |
| `D tras A` | `44` | los mismos 234 bytes recibidos en `R con A` | — |
| `A suelto` | `41` | nada: `expect_silence(20_000.0, ...)` | — |

   Chequeo estructural de `R con A` (sobre `q_rx[0..233]`; `c` = `q_rx[5] | q_rx[6]<<8 | q_rx[7]<<16 | q_rx[8]<<24`):
   - `q_rx[0] == 8'hA5`; `q_rx[1..4] == 04 01 00 00` (aborted = 1, versión 1).
   - `0 < c < 1000` y `en_cycles == en0 + c`.
   - x1 (palabra W4, bytes `q_rx[17..20]`) `== (c << 8) | 1`.
   - `M` (bytes `q_rx[205..208]`) `== 3`.
   - `(suma de q_rx[1..232]) % 256 == q_rx[233]`.
   Cada punto suma 1 a `checks`; si falla, `FAIL R con A: ...` y `errors++`. Copiar `q_rx[0..233]` a un arreglo `r_abort_dump` para el caso siguiente (`D tras A`), que compara con `exp_push` de esos 234 bytes.

## Validación
```
py TP3_FINAL/tools/run.py tb tb_debug_unit_h20 → PASS
py TP3_FINAL/tools/run.py tb tb_debug_unit_h0  → PASS
py TP3_FINAL/tools/run.py synth_ooc debug_unit → limpio
```
Prueba de detección (no se commitea): cambiar `RUN_TIMEOUT - 1` por `RUN_TIMEOUT` → falla `R timeout`; revertir.

## Listo cuando
- [ ] Con `HALT_AT = 20` el dump informa 20 ciclos y `halted = 1`.
- [ ] Sin HALT se detiene en exactamente `RUN_TIMEOUT` (1000) ciclos con el bit de timeout.
- [ ] Con `A` se detiene con el bit de abortado, y el dump es coherente con el ciclo de parada (chequeo estructural) y se repite igual con `D`.
- [ ] Un byte distinto de `A` durante `R` y un `A` fuera de `R` no producen respuesta.

## No hacer
- No reutilizar `r_cycles` como contador del timeout (se resetea con `X`/`L`; el de `R` es `r_run_cnt`).
- No cambiar la prioridad halted > A > timeout.

## Si algo falla
| Síntoma | Qué hacer |
| --- | --- |
| `en_cycles` = 1001 en el timeout | La comparación tiene que ser con `RUN_TIMEOUT - 1` |
| `R con otro byte` devuelve además `56 01 ...` | La `V` fue al pendiente: `S_RUN` debe estar en `w_consumes` (B-10) |
| `R con A` con `c ≥ 1000` | El `A` llegó tarde: verificar que el TB lo manda sin pausa (`bfm_gap_ns = 0`) |

## Commits
1. `debug: comando R con timeout y abort`
2. `debug: casos de ejecución continua en tb_debug_unit`

## Depende de / bloquea
Depende de: B-11. Bloquea: B-13, B-16.
