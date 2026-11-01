# Interfaz `cpu` ↔ Debug Unit, memorias y sistema

**Estado: v1 propuesta, pendiente de aprobación de A (B-08).** Fija los puertos y la semántica que comparten `cpu.v` (A) y `cpu_stub.v` (B), y cómo se arma el sistema. Los puntos marcados **[A]** son obligaciones del RTL de A que esta interfaz necesita.

## 1. Puertos: `$RTL/debug/cpu_ports.vh`

`cpu.v` y `cpu_stub.v` declaran sus puertos **solo** incluyendo este archivo, así cualquier diferencia no compila:

```verilog
module cpu (
`include "cpu_ports.vh"
);
```

Contenido exacto de `cpu_ports.vh` (sin guardas de include; no lleva `module` ni paréntesis):

```verilog
    input  wire        i_clock,
    input  wire        i_reset,          // síncrono, activo en alto; prioridad sobre i_en
    input  wire        i_en,             // clock enable desde la Debug Unit
    output wire        o_halted,         // HALT válido en WB (combinacional)
    output wire [31:0] o_imem_addr,      // = pc_if (dirección en bytes)
    input  wire [31:0] i_imem_data,      // imem[o_imem_addr[9:2]], combinacional
    input  wire [4:0]  i_dbg_reg_addr,
    output wire [31:0] o_dbg_reg_data,   // x[i_dbg_reg_addr]; x0 = 0
    input  wire [3:0]  i_dbg_latch_sel,
    output wire [31:0] o_dbg_latch_word, // dump.md §3
    input  wire [7:0]  i_dbg_mem_addr,   // índice de palabra de dmem
    output wire [31:0] o_dbg_mem_data,   // 0 si la palabra no está sucia
    output wire        o_dbg_mem_dirty,
    output wire [31:0] o_dbg_pc          // = pc_if
```

## 2. Semántica temporal

| Puerto | Regla |
| --- | --- |
| `i_en` | `adv = i_en && !o_halted`. Todo flip-flop del CPU con efecto (PC, latches, escritura del banco, escritura de dmem, dirty) solo cambia en un flanco con `adv = 1` **[A]** |
| `i_reset` | Síncrono. Un ciclo alcanza. Gana sobre `i_en`. Ver §3 |
| `o_halted` | Combinacional: `valid_wb && halt_wb`. Baja solo con `i_reset` |
| `dbg_*` | Lectura **combinacional**: el dato es válido en el mismo ciclo en que se pone la dirección. La Debug Unit solo lee con `i_en = 0`. Leer no tiene efectos |
| `o_imem_addr` | `pc_if`. La imem vive afuera del CPU (en `system`) |

## 3. Qué hace el reset del CPU **[A]**

| Elemento | Con `i_reset` |
| --- | --- |
| PC | 0 |
| Latches | Burbuja (`valid = 0`, control en 0) |
| x1 … x31 | 0 (el banco tiene reset; da ejecuciones deterministas iguales al ISS) |
| Bits dirty de dmem | 0 |
| Contenido de dmem | No se toca, **pero** una palabra no sucia se lee como 0 (§4): visto desde afuera, dmem queda en 0 |
| `fetch_stopped`, `halted` | 0 |
| imem | No se toca (está afuera) |

## 4. Memoria de datos **[A]**

- 256 palabras de 32 bits (`DMEM_WORDS = 256`, 1 KB), lectura asíncrona, escritura en flanco con `adv && valid_mem && mem_write_mem`.
- Índice de palabra = `addr[9:2]`. Los bits `addr[31:10]` se ignoran (la dirección da la vuelta).
- **Accesos desalineados: se ignoran los bits bajos.** `lw`/`sw` ignoran `addr[1:0]`; `lh`/`lhu`/`sh` ignoran `addr[0]`. El ISS hace exactamente lo mismo (B-21). No hay excepción ni aviso en hardware.
- Un bit `dirty` por palabra. Se pone en 1 en el flanco de cualquier store a esa palabra (`sb`, `sh` o `sw`).
- **Una palabra con `dirty = 0` se lee como 0** (para loads del CPU y para `o_dbg_mem_data`). Un store a una palabra limpia combina sus bytes sobre `0x00000000`, no sobre el contenido viejo. Implementación sugerida (escritura de palabra completa, compatible con RAM distribuida):

```verilog
wire [31:0] w_old  = r_dirty[w_idx] ? r_mem[w_idx] : 32'd0;
wire [31:0] w_new  = merge(w_old, store_data_mem, byte_enable);   // 4 carriles
always @(posedge i_clock) if (w_we) r_mem[w_idx] <= w_new;
```

Por qué: reprogramar deja dmem "en 0" sin un ciclo de borrado, el dump muestra solo lo que escribió el programa nuevo y el resultado coincide con el ISS, que arranca con dmem en 0.

## 5. Memoria de instrucciones: `$RTL/debug/imem.v` (B)

```verilog
module imem (
    input  wire        i_clock,
    input  wire [7:0]  i_raddr,     // = cpu o_imem_addr[9:2]
    output wire [31:0] o_rdata,     // combinacional
    input  wire        i_we,        // desde la Debug Unit
    input  wire [7:0]  i_waddr,
    input  wire [31:0] i_wdata
);
```

256 palabras, sin reset. Contenido inicial: todas en HALT (`0x00000073`), con un `initial` + `for` (excepción permitida de `convenciones.md` §4; Vivado lo vuelca a la inicialización de la LUTRAM). Así una placa recién programada que recibe `R` sin `L` para enseguida.

## 6. Puertos de `debug_unit.v` (B)

```verilog
module debug_unit #(
    parameter BYTE_TIMEOUT = 5_000_000,     // ciclos; protocolo.md §5
    parameter RUN_TIMEOUT  = 150_000_000
)(
    input  wire        i_clock,
    input  wire        i_reset,
    // uart_if (decisiones.md D-14: TX valid/ready)
    input  wire        i_rx_valid,
    input  wire [7:0]  i_rx_data,
    output wire        o_tx_start,
    output wire [7:0]  o_tx_data,
    input  wire        i_tx_busy,
    // cpu
    output wire        o_cpu_rst,
    output wire        o_cpu_en,            // sale directo de un registro
    input  wire        i_cpu_halted,
    output wire [4:0]  o_dbg_reg_addr,
    input  wire [31:0] i_dbg_reg_data,
    output wire [3:0]  o_dbg_latch_sel,
    input  wire [31:0] i_dbg_latch_word,
    output wire [7:0]  o_dbg_mem_addr,
    input  wire [31:0] i_dbg_mem_data,
    input  wire        i_dbg_mem_dirty,
    input  wire [31:0] i_dbg_pc,
    // imem
    output wire        o_imem_we,
    output wire [7:0]  o_imem_waddr,
    output wire [31:0] o_imem_wdata,
    // diagnóstico
    output wire [3:0]  o_state,             // estado de la FSM principal, para LEDs
    output wire        o_overrun            // pulso: byte descartado con el pendiente ocupado
);
```

## 7. Sistema: `$RTL/debug/system.v` (B)

Todo lo que no es reloj ni pines. Lo simulan los TB (nunca el top con Clock Wizard).

```
            ┌──────────────────────────── system ─────────────────────────────┐
i_rx ──────▶│ uart_if ──rx──▶ debug_unit ──cpu_rst/en, dbg_*──▶ cpu │ cpu_stub │
o_tx ◀──────│         ◀─tx──             ──imem_we/waddr/wdata──▶ imem ◀─addr─┘
i_reset ───▶│ (ya sincronizado)                                               │
            └─────────────────────────────────────────────────────────────────┘
```

```verilog
module system #(
    parameter CLOCK_FREQ   = 50_000_000,
    parameter BAUD_RATE    = 115_200,
    parameter BYTE_TIMEOUT = CLOCK_FREQ / 10,
    parameter RUN_TIMEOUT  = 150_000_000,
    parameter HALT_AT      = 20              // solo lo usa cpu_stub
)(
    input  wire       i_clock,
    input  wire       i_reset,
    input  wire       i_rx,
    output wire       o_tx,
    output wire [7:0] o_leds
);
```

- Reset del CPU: `w_cpu_reset = i_reset | w_dbg_cpu_rst`.
- Elección del CPU: con `` `ifdef CPU_STUB `` instancia `cpu_stub #(.HALT_AT(HALT_AT)) u_cpu`, si no `cpu u_cpu`. Mismo nombre de instancia `u_cpu` en los dos casos (los TB lo referencian).
- Nombres de instancia fijos: `u_uart`, `u_debug`, `u_cpu`, `u_imem`.
- LEDs: `[0]` conmuta con cada `o_rx_valid`; `[1]` `o_rx_frame_err` pegajoso; `[2]` `o_overrun` pegajoso; `[3]` `cpu halted`; `[7:4]` `o_state`. Los pegajosos se borran solo con `i_reset`.

Los tops de placa (`$RTL/top/`) solo agregan Clock Wizard, sincronizador de reset (D-10) y pines; `top_debug.v` suma `led[15] = locked`.

## 8. `cpu_stub.v` (B)

Mismos puertos (`cpu_ports.vh`), parámetro `HALT_AT` (0 = nunca para). Comportamiento exacto, con `r_cycles` de 32 bits:

| Señal | Valor |
| --- | --- |
| `r_cycles` | 0 con `i_reset`; `+1` en cada flanco con `adv` |
| `o_halted` | `(HALT_AT != 0) && (r_cycles == HALT_AT)` |
| `o_dbg_pc`, `o_imem_addr` | `r_cycles << 2` |
| `o_dbg_reg_data` | 0 si `addr == 0`; si no `{r_cycles[23:0], 3'b000, addr}` |
| `o_dbg_latch_word` | `{8'h1A, 4'h0, sel, r_cycles[15:0]}` |
| `o_dbg_mem_dirty` | 1 si `r_cycles >= 1` y el índice es 4, 16 o 63; si no 0 |
| `o_dbg_mem_data` | si está sucia: `{8'hD0, 16'h0000, índice}`; si no 0 |

`i_imem_data` se ignora. `sw/host/stub_model.py` reproduce esta tabla en Python: `stub_dump(cycles, halt_at, timeout=False, aborted=False) -> Dump`.
