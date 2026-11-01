# B-28 · TB de sistema listo para el CPU real

`S` · etiquetas `test` · milestone M4 · **Modelo sugerido:** Sonnet · [índice](../README.md)

## Objetivo

`tb_system_prog.sv` carga un programa de B-22 por la línea serie simulada, ejecuta `R` y vuelca el dump a un archivo; pasa hoy con `cpu_stub` y en la Fase 10 corre con el CPU real cambiando solo la entrada de `tools/tbs.py`.

## Antes de empezar

- Leer: [`interfaz_cpu.md`](../../../TP3_FINAL/doc/documentation/interfaz_cpu.md) §7 (`system`), §8 (stub); [`protocolo.md`](../../../TP3_FINAL/doc/documentation/protocolo.md) §4-§5, §7; [`dump.md`](../../../TP3_FINAL/doc/documentation/dump.md) §1, §4; [`convenciones.md`](../../../TP3_FINAL/doc/documentation/convenciones.md) §3, §5; `$TB/common/uart_bfm.svh` (B-04).
- Precondiciones: B-16 cerrado (`py TP3_FINAL/tools/run.py tb tb_system_debug` pasa); B-22 cerrado.
- Rama: `b/B-28-tb-system-prog`.

## Archivos

| Acción | Ruta | Contenido |
| --- | --- | --- |
| crear | `TP3_FINAL/VIVADO/TP_FINAL/tb/system/tb_system_prog.sv` | TB |
| modificar | `TP3_FINAL/tools/tbs.py` | `CPU_FILES = []` y dos entradas (paso 3) |
| modificar | `TP3_FINAL/tools/run.py` | `tb <nombre> [+k=v ...]` pasa plusargs a `vvp` |

## Pasos

1. **`run.py`:** el objetivo `tb` acepta argumentos extra que empiezan con `+` y los agrega al final del comando `vvp -n <vvp> +k=v ...`. El resto del criterio de PASS no cambia.

2. **TB** (`module tb_system_prog;`, reglas de `convenciones.md` §5):

   - Parámetros locales: `CLOCK_FREQ = 50_000_000`, `BAUD_RATE = 1_562_500`, `BYTE_TIMEOUT = 20_000`, `RUN_TIMEOUT = 20_000`, `HALT_AT = 20`. Reloj de 20 ns.
   - DUT: `system #(.CLOCK_FREQ(CLOCK_FREQ), .BAUD_RATE(BAUD_RATE), .BYTE_TIMEOUT(BYTE_TIMEOUT), .RUN_TIMEOUT(RUN_TIMEOUT), .HALT_AT(HALT_AT)) dut (.i_clock(clk), .i_reset(rst), .i_rx(bfm_rx), .o_tx(bfm_tx), .o_leds())`.
   - BFM: `reg bfm_rx = 1'b1; wire bfm_tx;` y `` `include "uart_bfm.svh" ``; en el `initial`: `bfm_bit_ns = 1.0e9 / BAUD_RATE; bfm_gap_ns = 0; bfm_timeout_ns = 2.0e6;`.
   - Plusargs (con `$value$plusargs`): `+prog=<ruta .hex>` (default `TP3_FINAL/programs/suma.hex`), `+out=<ruta>` (default `TP3_FINAL/build/tb_system_prog.dump.hex`).
   - Secuencia:
     1. `rst = 1` 10 ciclos, después `rst = 0` y 10 ciclos.
     2. Leer el programa: `reg [31:0] words [0:255];` inicializado a `32'hxxxxxxxx` con un `for`, `$readmemh(prog, words)`; `n` = índice de la primera palabra con `^words[i] === 1'bx` (o 256).
     3. `V`: enviar `56`, recibir 6 bytes y comparar con `56 01 00 01 00 01`.
     4. `L`: enviar `4C`, `n[7:0]`, `n[15:8]`; recibir `4B`; enviar cada palabra en 4 bytes LE; recibir `4B`.
     5. Verificar imem por jerarquía: `dut.u_imem.r_mem[i] === words[i]` para `i < n` y `=== 32'h00000073` para `i ≥ n` (el arreglo de `imem.v` se llama `r_mem`; si B-13 usó otro nombre, usar ese).
     6. `R`: enviar `52`; recibir `A5`; recibir 208 bytes (W0..W51) en `reg [7:0] buf [0:4095]`; `M` = W51 (bytes 205..208 de `buf` contando la cabecera en 0, LE); recibir `8·M + 1` bytes más.
     7. Verificar el checksum (`dump.md` §4) y que el largo sea `210 + 8·M`.
     8. Escribir todo (incluida la cabecera) en `out` con `$fdisplay(fd, "%02x", b)`, un byte por línea.
     9. Con `` `ifdef CPU_STUB ``: verificar `halted = 1` en W0 y `W1 = 20` (ciclos = `HALT_AT`), y `M = 3`. Sin `CPU_STUB` no verifica contenido (lo compara B-27 contra el `.expected.json`).
   - Cada falla imprime `FAIL tb_system_prog: <qué> esperado=<x> obtenido=<y>`; final según `convenciones.md` §5 con nombre `tb_system_prog`. Watchdog: 50 ms simulados.

3. **`tools/tbs.py`:**

   ```python
   CPU_FILES: list[str] = []   # Fase 10: A agrega acá sus archivos (cpu.v y submódulos)

   SYSTEM_FILES = [ ... los mismos archivos de system que usa tb_system_debug (B-16), sin cpu_stub.v ... ]

   TBS["tb_system_prog_stub"] = {
       "top": "tb_system_prog",
       "files": SYSTEM_FILES + ["TP3_FINAL/VIVADO/TP_FINAL/rtl/debug/cpu_stub.v",
                                "TP3_FINAL/VIVADO/TP_FINAL/tb/system/tb_system_prog.sv"],
       "defines": {"CPU_STUB": "1"},
   }
   if CPU_FILES:
       TBS["tb_system_prog"] = {
           "top": "tb_system_prog",
           "files": SYSTEM_FILES + CPU_FILES + ["TP3_FINAL/VIVADO/TP_FINAL/tb/system/tb_system_prog.sv"],
           "defines": {},
       }
   ```

   El include de la BFM se resuelve por el `-I` del directorio de cada archivo; agregar `TP3_FINAL/VIVADO/TP_FINAL/tb/common` a la lista de `-I` si `run.py` no lo hace ya.

4. **Paso de la Fase 10** (documentar en un comentario al principio del TB y en B-29): llenar `CPU_FILES` en `tools/tbs.py`. Nada más cambia: `system.v` instancia `cpu` cuando `CPU_STUB` no está definido (`interfaz_cpu.md` §7).

## Validación

```
py TP3_FINAL/tools/run.py tb tb_system_prog_stub                     → PASS tb_system_prog
py TP3_FINAL/tools/run.py tb tb_system_prog_stub +prog=TP3_FINAL/programs/call_ret.hex   → PASS (carga 20 palabras)
```

y `TP3_FINAL/build/tb_system_prog.dump.hex` decodifica con `dump.decode` a `stub_model.stub_dump(20, 20)` (comprobar con una línea de Python en el PR).

## Listo cuando

- [ ] Con el stub, el TB pasa para `suma.hex` y `call_ret.hex`, y el archivo de salida decodifica igual que `stub_model`.
- [ ] Llenar `CPU_FILES` es el único paso para correrlo con el CPU real (revisado en el código: no hay otra referencia al stub fuera de la entrada `tb_system_prog_stub`).
- [ ] `py TP3_FINAL/tools/run.py tbs` sigue pasando.

## No hacer

- No instanciar el top de placa (con Clock Wizard); se simula `system`.
- No reimplementar las tareas de la línea serie: usar `uart_bfm.svh`.

## Si algo falla

| Síntoma | Qué hacer |
| --- | --- |
| `$readmemh` avisa que el archivo es más corto | Es lo esperado (las palabras sobrantes quedan en `x`) |
| El dump no llega antes del watchdog | Verificar que `RUN_TIMEOUT` del TB llega a `system` y que `bfm_timeout_ns` cubre `RUN_TIMEOUT` × 20 ns |
| `SYSTEM_FILES` no coincide con lo que usa B-16 | Usar exactamente la lista de la entrada `tb_system_debug` de `tbs.py`, menos `cpu_stub.v` y su TB |

## Commits

1. `tools: plusargs en run.py tb`
2. `tb: tb_system_prog con stub y CPU_FILES`

## Depende de / bloquea

Depende de: B-04 (BFM), B-16, B-22. Bloquea: B-27 (nivel `rtl`), Fase 10.
