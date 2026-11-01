# B-08 · Interfaz `cpu` ↔ Debug Unit congelada (`cpu_ports.vh`)

`S` · etiquetas `contrato` `bloquea-A` · milestone M1 · **Modelo sugerido:** Haiku · [índice](../README.md)

## Objetivo
`$RTL/debug/cpu_ports.vh` existe con el contenido exacto de `interfaz_cpu.md` §1, y A aprobó todas las obligaciones **[A]** de `interfaz_cpu.md`.

## Antes de empezar
- Leer: `TP3_FINAL/doc/documentation/interfaz_cpu.md` (completo), `decisiones.md` D-17 a D-19, D-24, D-27.
- Precondiciones: ninguna.
- Rama: `b/B-08-interfaz-cpu`.

## Archivos
| Acción | Ruta | Contenido |
| --- | --- | --- |
| crear | `TP3_FINAL/VIVADO/TP_FINAL/rtl/debug/cpu_ports.vh` | Contenido de abajo, literal |
| modificar | `TP3_FINAL/doc/documentation/interfaz_cpu.md` | Solo la línea de estado (paso 4) y lo que pida A |

## Pasos
1. Crear `TP3_FINAL/VIVADO/TP_FINAL/rtl/debug/cpu_ports.vh` con exactamente estas líneas (sin guardas `ifndef`, sin `module`, sin paréntesis; la última línea **sin coma**):

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

2. Comprobar que compila dentro de un módulo de prueba descartable (no se versiona). Crear `TP3_FINAL/build/ports_check.v`:

```verilog
`default_nettype none
module ports_check (
`include "cpu_ports.vh"
);
    assign o_halted = 1'b0;
    assign o_imem_addr = 32'd0;
    assign o_dbg_reg_data = 32'd0;
    assign o_dbg_latch_word = 32'd0;
    assign o_dbg_mem_data = 32'd0;
    assign o_dbg_mem_dirty = 1'b0;
    assign o_dbg_pc = 32'd0;
endmodule
```

   Verificar (desde la raíz): `iverilog -g2012 -Wall -I TP3_FINAL/VIVADO/TP_FINAL/rtl/debug -o TP3_FINAL/build/ports_check.vvp TP3_FINAL/build/ports_check.v` → sin errores ni warnings. Borrar `ports_check.v` y `.vvp` después.
3. Revisión con A. Pegar en el PR esta lista y pedir que A tilde cada ítem (son las obligaciones **[A]** de `interfaz_cpu.md`):
   - [ ] `cpu.v` declara sus puertos solo con `` `include "cpu_ports.vh" `` (§1).
   - [ ] `adv = i_en && !o_halted` gobierna PC, latches, escritura del banco, escritura de dmem y dirty (§2).
   - [ ] `o_halted = valid_wb && halt_wb`, combinacional (§2).
   - [ ] Lecturas `dbg_*` combinacionales y sin efectos (§2).
   - [ ] Reset: PC = 0, latches en burbuja, x1-x31 = 0, dirty = 0, `fetch_stopped` = 0; imem no se toca (§3).
   - [ ] dmem de 256 palabras, índice `addr[9:2]`, accesos desalineados ignoran los bits bajos (§4, D-17, D-18).
   - [ ] Palabra limpia se lee 0; store a palabra limpia combina sobre 0 (§4, D-19).
   - [ ] imem fuera del CPU, en `system` (§5, §7).
   - [ ] Palabras de latch y palabra 15 según `dump.md` §3 (lo aprueba también en B-07).
   Cualquier cambio que pida A: en `interfaz_cpu.md` y `cpu_ports.vh` en el mismo commit, con el porqué en `decisiones.md`.
4. Con la aprobación: primera línea de `interfaz_cpu.md` → `**Estado: v1 congelada (aprobada por A el AAAA-MM-DD, PR #n).**`

## Validación
- Paso 2 compila sin warnings.
- B-09 compila `cpu_stub.v` con este archivo (es la prueba definitiva; si B-09 ya existe, `py TP3_FINAL/tools/run.py tb tb_cpu_stub` → `PASS`).

## Listo cuando
- [ ] `cpu_ports.vh` existe y coincide línea por línea con `interfaz_cpu.md` §1.
- [ ] A tildó la lista del paso 3 en el PR.
- [ ] `interfaz_cpu.md` dice "v1 congelada".

## No hacer
- No escribir `cpu_stub.v` ni `imem.v` (B-09).
- No agregar puertos "por si acaso".

## Si algo falla
| Síntoma | Qué hacer |
| --- | --- |
| `syntax error` al final de la lista de puertos | La última línea del `.vh` no lleva coma |
| `Include file cpu_ports.vh not found` | Falta `-I TP3_FINAL/VIVADO/TP_FINAL/rtl/debug` |
| A no acepta "palabra limpia se lee 0" | Detenerse: cambia el dump, el ISS y la Debug Unit; se decide aparte |

## Commits
1. `debug: cpu_ports.vh con la interfaz v1`
2. `docs: interfaz cpu v1 congelada`

## Depende de / bloquea
Depende de: Fase 0 de A (diagrama). Bloquea: B-09, B-10, todo el CPU de A.
