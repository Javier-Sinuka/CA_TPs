# B-13 · Carga de programa: comando `L`

`M` · etiquetas `debug-unit` · milestone M2 · **Modelo sugerido:** Sonnet · [índice](../README.md)

## Objetivo
`L` recibe `N` y `N` palabras en dos fases, las escribe en imem con el CPU en reset, rellena el resto con HALT y responde `K`; `N` inválido da `E 02` y un corte da `E 03`.

## Antes de empezar
- Leer: `protocolo.md` §3 (errores) y §4 (`L`), `interfaz_cpu.md` §5, B-10 (diseño de la FSM).
- Precondiciones: B-12 cerrado.
- Rama: `b/B-13-load`.

## Archivos
| Acción | Ruta | Contenido |
| --- | --- | --- |
| modificar | `TP3_FINAL/VIVADO/TP_FINAL/rtl/debug/debug_unit.v` | Marcas `// B-13:` |
| modificar | `TP3_FINAL/VIVADO/TP_FINAL/tb/debug/tb_debug_unit.sv` | Monitor y casos de abajo |

## Pasos
1. En `S_IDLE`, reemplazar `// B-13: CMD_LOAD` por:

```verilog
                    CMD_LOAD: begin
                        r_load_active <= 1'b1;   // cpu_rst = 1 hasta el K final
                        r_timeout     <= 1'b0;
                        r_aborted     <= 1'b0;
                        r_n_high      <= 1'b0;
                        r_to_cnt      <= 32'd0;
                        r_state       <= S_LOAD_N;
                    end
```

2. Reemplazar `// B-13: S_LOAD_N, S_LOAD_DATA, S_LOAD_FILL` por:

```verilog
            S_LOAD_N: begin
                if (i_rx_valid) begin
                    r_to_cnt <= 32'd0;
                    if (!r_n_high) begin
                        r_n[7:0] <= i_rx_data;
                        r_n_high <= 1'b1;
                    end else begin
                        r_n[15:8] <= i_rx_data;
                        if ({i_rx_data, r_n[7:0]} > 16'd256) begin
                            r_load_active <= 1'b0;
                            r_resp        <= {32'd0, ERR_N_RANGE, RESP_ERR};
                            r_resp_len    <= 3'd2;
                            r_ret_state   <= S_IDLE;
                            r_state       <= S_RESP;
                        end else begin
                            r_lidx      <= 9'd0;
                            r_lbyte     <= 2'd0;
                            r_resp      <= {40'd0, RESP_OK};
                            r_resp_len  <= 3'd1;
                            r_ret_state <= S_LOAD_DATA;   // S_RESP pone r_to_cnt en 0 al volver
                            r_state     <= S_RESP;
                        end
                    end
                end else if (r_to_cnt == BYTE_TIMEOUT - 1) begin
                    r_load_active <= 1'b0;
                    r_resp        <= {32'd0, ERR_TIMEOUT, RESP_ERR};
                    r_resp_len    <= 3'd2;
                    r_ret_state   <= S_IDLE;
                    r_state       <= S_RESP;
                end else begin
                    r_to_cnt <= r_to_cnt + 32'd1;
                end
            end

            S_LOAD_DATA: begin
                if (r_lidx == r_n[8:0]) begin            // N ≤ 256 garantizado
                    r_state <= S_LOAD_FILL;
                end else if (i_rx_valid) begin
                    r_to_cnt <= 32'd0;
                    r_lbyte  <= r_lbyte + 2'd1;
                    if (r_lbyte == 2'd3) begin
                        r_imem_we    <= 1'b1;
                        r_imem_waddr <= r_lidx[7:0];
                        r_imem_wdata <= {i_rx_data, r_wbuf};   // little-endian
                        r_lidx       <= r_lidx + 9'd1;
                    end else begin
                        r_wbuf <= {i_rx_data, r_wbuf[23:8]};
                    end
                end else if (r_to_cnt == BYTE_TIMEOUT - 1) begin
                    r_load_active <= 1'b0;
                    r_resp        <= {32'd0, ERR_TIMEOUT, RESP_ERR};
                    r_resp_len    <= 3'd2;
                    r_ret_state   <= S_IDLE;
                    r_state       <= S_RESP;
                end else begin
                    r_to_cnt <= r_to_cnt + 32'd1;
                end
            end

            S_LOAD_FILL: begin
                if (r_lidx[8]) begin                      // llegó a 256
                    r_load_active <= 1'b0;
                    r_resp        <= {40'd0, RESP_OK};
                    r_resp_len    <= 3'd1;
                    r_ret_state   <= S_IDLE;
                    r_state       <= S_RESP;
                end else begin
                    r_imem_we    <= 1'b1;
                    r_imem_waddr <= r_lidx[7:0];
                    r_imem_wdata <= HALT_WORD;
                    r_lidx       <= r_lidx + 9'd1;
                end
            end
```

   El contador de ciclos queda en 0 solo (su bloque se resetea con `o_cpu_rst`, que vale 1 mientras `r_load_active`). El reloj del timeout arranca al recibir `L` y, en la fase de datos, cuando `uart_tx` acepta el primer `K` (no al terminar de salir por la línea: la diferencia, 1 byte, es despreciable frente a 100 ms).

3. TB: agregar un monitor (todo el TB):

```systemverilog
always @(negedge clk) begin
    if (dut.u_debug.o_imem_we && !dut.u_debug.o_cpu_rst) begin
        errors = errors + 1;
        $display("FAIL L: escritura de imem con cpu_rst = 0");
    end
end
```

   Y una tarea `check_imem(input integer n, input string caso)` que compara `dut.u_imem.r_mem[i]` con `prog[i]` para `i < n` y con `32'h00000073` para `n ≤ i < 256` (`checks++` por palabra, `FAIL` por diferencia). `prog` es `reg [31:0] prog [0:255]` del TB. Tarea `send_load(n)` que hace dos `transact`: primero `4C NL NH` esperando `4B`, después los `4·n` bytes de `prog[0..n-1]` en little-endian esperando `4B` (`check_exp` en ambos).

4. Casos en `tb_debug_unit.sv`, rama `HALT_AT == 20`, después de los de B-12 (estado: 20 ciclos, `halted`). `integer seed = 32'h0000_0B13;` y palabras aleatorias con `$random(seed)`. Guardar `en0` al principio de cada caso.

| Caso | Host envía | Esperado | Chequeo extra |
| --- | --- | --- | --- |
| `L N=2 ejemplo` | `4C 02 00` / `93 00 50 00 73 00 00 00` | `4B` / `4B` | `prog = {0x00500093, 0x00000073}`; `check_imem(2)`; `en_cycles == en0` |
| `D tras L` | `44` | `dump_c0_h20.hex` (la carga resetea el CPU) | — |
| `L N=1` | `prog[0]` aleatoria | `4B` / `4B` | `check_imem(1)` |
| `L N=37` | 37 aleatorias | `4B` / `4B` | `check_imem(37)` |
| `L N=256` | 256 aleatorias | `4B` / `4B` | `check_imem(256)` |
| `L N=0` | `4C 00 00` | `4B 4B` (un solo `transact` con 2 esperados) | `check_imem(0)`: todo HALT |
| `L N=257` | `4C 01 01` | `45 02` | antes, copiar imem a `snap[]`; después imem == `snap` (256 chequeos); `dut.u_debug.o_cpu_rst == 0` |
| `L corte en datos` | `4C 01 00` / `93 00` | `4B` / `45 03` | luego `V` → `56 01 00 01 00 01` |
| `L corte en N` | `4C 01` | `45 03` | luego `V` → `56 01 00 01 00 01` |

   Para los dos casos de corte el `bfm_timeout_ns` de 2 ms alcanza (el timeout del TB es 20 000 ciclos = 400 µs).

## Validación
```
py TP3_FINAL/tools/run.py tb tb_debug_unit_h20 → PASS
py TP3_FINAL/tools/run.py tb tb_debug_unit_h0  → PASS
py TP3_FINAL/tools/run.py synth_ooc debug_unit → limpio
```
Prueba de detección (no se commitea): `{i_rx_data, r_wbuf}` → `{r_wbuf, i_rx_data}` → fallan los `check_imem`; revertir.

## Listo cuando
- [ ] N = 1, 37 y 256 con palabras aleatorias: imem igual a lo enviado y el resto en HALT; N = 0 deja todo en HALT.
- [ ] N = 257 responde `45 02` e imem no cambia.
- [ ] Cortar la transmisión en `N` o a mitad de una palabra responde `45 03` y el comando siguiente se atiende bien.
- [ ] Ninguna escritura de imem ocurre con `cpu_rst = 0` (monitor) y `cpu_en` no se mueve durante `L`.

## No hacer
- No escribir imem antes de completar los 4 bytes de una palabra.
- No esperar al `K` del host ni agregar más fases al protocolo.

## Si algo falla
| Síntoma | Qué hacer |
| --- | --- |
| `N=256` responde `45 02` | La comparación es `> 256`, no `>= 256` |
| `N=256` nunca termina el relleno | `r_lidx` tiene que ser de 9 bits y `S_LOAD_FILL` mira `r_lidx[8]` |
| Palabras con los bytes rotados | `r_wbuf <= {i_rx_data, r_wbuf[23:8]}` y la palabra es `{byte3, r_wbuf}` |
| `45 03` aparece en una carga normal | El host del TB tardó: `send_load` tiene que mandar los datos apenas recibe el primer `4B` |

## Commits
1. `debug: comando L en dos fases con timeout y relleno con HALT`
2. `debug: casos de carga en tb_debug_unit`

## Depende de / bloquea
Depende de: B-06, B-12. Bloquea: B-15, B-16.
