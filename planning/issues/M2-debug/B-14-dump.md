# B-14 · Dump: comando `D` y recorrido del mapa

`M` · etiquetas `debug-unit` · milestone M2 · **Modelo sugerido:** Sonnet · [índice](../README.md)

Se hace **segundo** en M2 (después de B-10), porque `S` y `R` terminan en el dump.

## Objetivo
`D` envía el dump de `dump.md` §1 byte a byte, con las dos pasadas sobre dmem y el checksum, idéntico a `stub_dump()`.

## Antes de empezar
- Leer: `dump.md` §1, §2, §4; la sección "Diseño de la FSM" de B-10 y su `debug_unit.v`.
- Precondiciones: B-10 cerrado (`py TP3_FINAL/tools/run.py tb tb_debug_unit_h20` → PASS).
- Rama: `b/B-14-dump`.

## Archivos
| Acción | Ruta | Contenido |
| --- | --- | --- |
| modificar | `TP3_FINAL/VIVADO/TP_FINAL/rtl/debug/debug_unit.v` | Reemplazar las marcas `// B-14:` |
| modificar | `TP3_FINAL/VIVADO/TP_FINAL/tb/debug/tb_debug_unit.sv` | Casos de abajo |

## Pasos
1. En `S_IDLE`, reemplazar `// B-14: CMD_DUMP` por:

```verilog
                    CMD_DUMP: begin
                        r_maddr  <= 9'd0;
                        r_mcount <= 9'd0;
                        r_state  <= S_DUMP_COUNT;
                    end
```

2. Reemplazar `// B-14: S_DUMP_COUNT, ...` por los seis estados:

```verilog
            S_DUMP_COUNT: begin
                // primera pasada: M = cantidad de palabras sucias
                if (i_dbg_mem_dirty) begin
                    r_mcount <= r_mcount + 9'd1;
                end
                if (r_maddr == 9'd255) begin
                    r_maddr <= 9'd0;
                    r_state <= S_DUMP_HDR;
                end else begin
                    r_maddr <= r_maddr + 9'd1;
                end
            end

            S_DUMP_HDR: begin
                if (!r_tx_valid) begin
                    r_tx_valid <= 1'b1;
                    r_tx_data  <= DUMP_HEADER;
                end else if (w_tx_accept) begin
                    r_tx_valid <= 1'b0;
                    r_csum     <= 8'd0;
                    r_widx     <= 6'd0;
                    r_state    <= S_DUMP_WORD;
                end
            end

            S_DUMP_WORD: begin
                r_word  <= w_fixed_word;
                r_bidx  <= 2'd0;
                r_wkind <= 2'd0;
                r_state <= S_DUMP_BYTES;
            end

            S_DUMP_BYTES: begin
                if (!r_tx_valid) begin
                    r_tx_valid <= 1'b1;
                    r_tx_data  <= r_word[7:0];
                end else if (w_tx_accept) begin
                    r_tx_valid <= 1'b0;
                    r_csum     <= r_csum + r_tx_data;
                    r_word     <= r_word >> 8;
                    r_bidx     <= r_bidx + 2'd1;
                    if (r_bidx == 2'd3) begin
                        case (r_wkind)
                        2'd0: begin
                            if (r_widx == 6'd51) begin
                                r_maddr <= 9'd0;
                                r_state <= S_DUMP_SEEK;
                            end else begin
                                r_widx  <= r_widx + 6'd1;
                                r_state <= S_DUMP_WORD;
                            end
                        end
                        2'd1: begin
                            // terminó la dirección: sigue el dato de la misma palabra
                            r_word  <= i_dbg_mem_data;
                            r_wkind <= 2'd2;
                        end
                        default: begin
                            r_maddr <= r_maddr + 9'd1;
                            r_state <= S_DUMP_SEEK;
                        end
                        endcase
                    end
                end
            end

            S_DUMP_SEEK: begin
                // segunda pasada: próxima palabra sucia, en orden ascendente
                if (r_maddr[8]) begin
                    r_state <= S_DUMP_CSUM;
                end else if (i_dbg_mem_dirty) begin
                    r_word  <= {22'd0, r_maddr[7:0], 2'b00};   // dirección en bytes
                    r_wkind <= 2'd1;
                    r_bidx  <= 2'd0;
                    r_state <= S_DUMP_BYTES;
                end else begin
                    r_maddr <= r_maddr + 9'd1;
                end
            end

            S_DUMP_CSUM: begin
                if (!r_tx_valid) begin
                    r_tx_valid <= 1'b1;
                    r_tx_data  <= r_csum;
                end else if (w_tx_accept) begin
                    r_tx_valid <= 1'b0;
                    r_state    <= S_IDLE;
                end
            end
```

   Notas que el código ya respeta (no cambiarlas): en `S_DUMP_BYTES` con `r_wkind = 1` la asignación `r_word <= i_dbg_mem_data` va después del `>> 8` y le gana; `r_bidx` vuelve solo a 0 (3 + 1). `o_dbg_reg_addr`, `o_dbg_latch_sel` y `o_dbg_mem_addr` ya salen de `r_widx`/`r_maddr` (B-10).

3. Casos en `tb_debug_unit.sv`, **después** de los de B-10, dentro de `HALT_AT == 20` (el último caso de B-10 deja el CPU recién reseteado: 0 ciclos):

| Caso | Host envía | Esperado | Chequeo extra |
| --- | --- | --- | --- |
| `D` | `44` | `dump_c0_h20.hex` (210 bytes) | `en_cycles` no cambió |
| `D D seguidos` | `44 44` | `dump_c0_h20.hex` dos veces (420) | — |
| `D X seguidos` | `44 58` | `dump_c0_h20.hex` + `4B` (211) | la `X` pasó por el pendiente |

   Armar lo esperado con `n_exp = 0; exp_vec("dump_c0_h20.hex", 210); exp_vec(...)/exp_push(8'h4B);` y luego `transact(n_exp); check_exp("<caso>")`.

   Dentro de `HALT_AT == 0` (primer caso de esa rama):

| Caso | Host envía | Esperado |
| --- | --- | --- |
| `D h0` | `44` | `dump_c0_h0.hex` (210 bytes) |

## Validación
```
py TP3_FINAL/tools/run.py tb tb_debug_unit_h20 → PASS, código 0
py TP3_FINAL/tools/run.py tb tb_debug_unit_h0  → PASS, código 0
py TP3_FINAL/tools/run.py synth_ooc debug_unit → limpio
```
Pruebas de detección (no se commitean, revertir cada una): (a) `8'h01` del campo versión en `w_fixed_word` → `8'h02`: falla `D`; (b) no sumar el byte al checksum (`r_csum <= r_csum;`): falla `D`.

## Listo cuando
- [ ] La cantidad de bytes del dump es exactamente `210 + 8·M` (la verifica `recv_n` + el vector).
- [ ] Los dumps coinciden byte a byte con `stub_dump()` (vectores) y el checksum verifica.
- [ ] `D D` y `D X` seguidos se atienden completos.

## No hacer
- No cambiar el orden de los pares ni enviar direcciones en índice de palabra (son bytes: `índice·4`).
- No leer dmem mientras `cpu_en = 1` (el dump siempre arranca con el CPU parado).

## Si algo falla
| Síntoma | Qué hacer |
| --- | --- |
| Dump de 210 bytes cuando se esperaban 234 | `S_DUMP_COUNT` no cuenta: revisar `o_dbg_mem_addr = r_maddr[7:0]` |
| Registros corridos una posición | `w_reg_idx = r_widx - 3`; la palabra 3 es x0 |
| Solo el checksum difiere | El checksum no debe incluir la cabecera; se resetea en `S_DUMP_HDR` |
| Pares con el dato de la palabra siguiente | En `S_DUMP_BYTES`, `r_maddr` se incrementa recién después del dato (`default`) |

## Commits
1. `debug: comando D y recorrido del dump`
2. `debug: casos de dump en tb_debug_unit`

## Depende de / bloquea
Depende de: B-07, B-09, B-10. Bloquea: B-11, B-12, B-15, B-16.
