# B-09 · CPU stub, imem, modelo Python y vectores

`M` · etiquetas `debug-unit` `test` · milestone M1 · **Modelo sugerido:** Haiku (RTL y Python dados) · [índice](../README.md)

## Objetivo
`cpu_stub.v` e `imem.v` funcionan, `stub_model.py` predice exactamente el estado del stub, y los vectores esperados de todos los TB de M2 se generan desde Python y se versionan.

## Antes de empezar
- Leer: `interfaz_cpu.md` §5 y §8, `dump.md` §1, `convenciones.md` §3-§5.
- Precondiciones: B-07 mergeado (`sw/host/dump.py`); B-08 (`cpu_ports.vh`); B-04 (`tools/run.py`, `tools/tbs.py`). Comprobar: existen esos cuatro archivos.
- Rama: `b/B-09-cpu-stub`.

## Archivos
| Acción | Ruta | Contenido |
| --- | --- | --- |
| crear | `TP3_FINAL/VIVADO/TP_FINAL/rtl/debug/cpu_stub.v` | Paso 1, literal |
| crear | `TP3_FINAL/VIVADO/TP_FINAL/rtl/debug/imem.v` | Paso 2, literal |
| crear | `TP3_FINAL/sw/host/stub_model.py` | Paso 3, literal |
| crear | `TP3_FINAL/sw/tests/test_stub_model.py` | Paso 3 |
| crear | `TP3_FINAL/tools/gen_vectors.py` | Paso 4, literal |
| crear | `TP3_FINAL/VIVADO/TP_FINAL/tb/debug/vectors/*.hex` | Generados en el paso 4 (se versionan) |
| crear | `TP3_FINAL/VIVADO/TP_FINAL/tb/debug/tb_cpu_stub.sv` | Paso 5 |
| crear | `TP3_FINAL/VIVADO/TP_FINAL/tb/debug/tb_imem.sv` | Paso 6 |
| modificar | `TP3_FINAL/tools/tbs.py` | Paso 7 |
| modificar | `TP3_FINAL/tools/run.py` | Paso 7: objetivo `vectors` |

## Pasos
1. `rtl/debug/cpu_stub.v`:

```verilog
`timescale 1ns/1ps
`default_nettype none

// CPU de mentira con la interfaz real (interfaz_cpu.md §8). Su estado depende
// solo de r_cycles, así sw/host/stub_model.py lo predice exactamente.
module cpu_stub #(
    parameter HALT_AT = 20          // 0 = nunca se detiene
)(
`include "cpu_ports.vh"
);
    reg [31:0] r_cycles;

    wire w_adv = i_en && !o_halted;

    always @(posedge i_clock) begin
        if (i_reset) begin
            r_cycles <= 32'd0;
        end else if (w_adv) begin
            r_cycles <= r_cycles + 32'd1;
        end
    end

    assign o_halted         = (HALT_AT != 0) && (r_cycles == HALT_AT);
    assign o_dbg_pc         = r_cycles << 2;
    assign o_imem_addr      = r_cycles << 2;
    assign o_dbg_reg_data   = (i_dbg_reg_addr == 5'd0) ? 32'd0
                                                       : {r_cycles[23:0], 3'b000, i_dbg_reg_addr};
    assign o_dbg_latch_word = {8'h1A, 4'h0, i_dbg_latch_sel, r_cycles[15:0]};

    wire w_dirty_idx = (i_dbg_mem_addr == 8'd4) || (i_dbg_mem_addr == 8'd16) ||
                       (i_dbg_mem_addr == 8'd63);
    assign o_dbg_mem_dirty = (r_cycles != 32'd0) && w_dirty_idx;
    assign o_dbg_mem_data  = o_dbg_mem_dirty ? {8'hD0, 16'h0000, i_dbg_mem_addr} : 32'd0;

    // i_imem_data se ignora a propósito: el stub no ejecuta instrucciones.
endmodule

`default_nettype wire
```

2. `rtl/debug/imem.v`:

```verilog
`timescale 1ns/1ps
`default_nettype none

// Memoria de instrucciones: 256 palabras, lectura asíncrona, escritura desde la
// Debug Unit. Arranca llena de HALT (interfaz_cpu.md §5, D-20).
module imem (
    input  wire        i_clock,
    input  wire [7:0]  i_raddr,
    output wire [31:0] o_rdata,
    input  wire        i_we,
    input  wire [7:0]  i_waddr,
    input  wire [31:0] i_wdata
);
    localparam [31:0] HALT_WORD = 32'h0000_0073;

    reg [31:0] r_mem [0:255];

    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            r_mem[i] = HALT_WORD;
        end
    end

    always @(posedge i_clock) begin
        if (i_we) begin
            r_mem[i_waddr] <= i_wdata;
        end
    end

    assign o_rdata = r_mem[i_raddr];
endmodule

`default_nettype wire
```

3. `sw/host/stub_model.py`:

```python
"""Modelo Python de cpu_stub.v (doc/documentation/interfaz_cpu.md §8)."""
from __future__ import annotations

from host.dump import FORMAT_VERSION, MASK32, Dump

DIRTY_WORDS = (4, 16, 63)


def stub_dump(cycles: int, halt_at: int, timeout: bool = False,
              aborted: bool = False) -> Dump:
    """Dump que la Debug Unit tiene que enviar con el stub en `cycles` ciclos."""
    if cycles < 0 or (halt_at != 0 and cycles > halt_at):
        raise ValueError(f"cycles={cycles} imposible con halt_at={halt_at}")
    halted = halt_at != 0 and cycles == halt_at
    x = tuple(0 if i == 0 else (((cycles & 0xFF_FFFF) << 8) | i) for i in range(32))
    latches = tuple(0x1A00_0000 | (k << 16) | (cycles & 0xFFFF) for k in range(16))
    mem = tuple((i * 4, 0xD000_0000 | i) for i in DIRTY_WORDS) if cycles >= 1 else ()
    return Dump(halted=halted, timeout=timeout, aborted=aborted,
                version=FORMAT_VERSION, cycles=cycles & MASK32,
                pc=(cycles << 2) & MASK32, x=x, latches=latches, mem=mem)


def stub_state_words(cycles: int, halt_at: int) -> list[int]:
    """Estado del stub visto por sus puertos, en el orden de tb_cpu_stub (563 palabras):
    [0] o_dbg_pc, [1] o_imem_addr, [2] o_halted, [3..34] x0..x31,
    [35..50] latch 0..15, [51..306] dirty de la palabra 0..255, [307..562] dato 0..255."""
    d = stub_dump(cycles, halt_at)
    data = {addr // 4: value for addr, value in d.mem}
    return ([d.pc, d.pc, int(d.halted)] + list(d.x) + list(d.latches)
            + [1 if i in data else 0 for i in range(256)]
            + [data.get(i, 0) for i in range(256)])
```

   `sw/tests/test_stub_model.py`:

```python
import pytest

from host.dump import decode, encode
from host.stub_model import stub_dump, stub_state_words


def test_cycle_zero() -> None:
    d = stub_dump(0, 20)
    assert d.pc == 0 and d.x[1] == 1 and d.x[31] == 31 and d.mem == () and not d.halted
    assert len(encode(d)) == 210


def test_cycle_one_has_three_pairs_ascending() -> None:
    d = stub_dump(1, 20)
    assert d.mem == ((16, 0xD000_0004), (64, 0xD000_0010), (252, 0xD000_003F))
    assert d.x[5] == 0x105 and d.latches[15] == 0x1A0F_0001
    assert len(encode(d)) == 234


def test_halt() -> None:
    assert stub_dump(20, 20).halted and not stub_dump(19, 20).halted
    assert not stub_dump(1000, 0).halted
    with pytest.raises(ValueError):
        stub_dump(21, 20)


def test_round_trip_and_state_length() -> None:
    assert decode(encode(stub_dump(7, 20, aborted=True))) == stub_dump(7, 20, aborted=True)
    assert len(stub_state_words(7, 20)) == 563
```

   Verificar (desde `TP3_FINAL/sw`): `py -m pytest tests/test_stub_model.py -q` → `4 passed`. Además, los dumps de `stub_dump(0, 20)` y `stub_dump(1, 20)` tienen que dar los mismos bytes que los ejemplos de `dump.md` §7.

4. `tools/gen_vectors.py`:

```python
"""Genera los vectores esperados de los TB de la Debug Unit desde stub_model.

Uso, desde la raíz del repo:
    py TP3_FINAL/tools/gen_vectors.py           # escribe los archivos
    py TP3_FINAL/tools/gen_vectors.py --check   # devuelve 1 si alguno difiere
Formato: dump_*.hex = un byte por línea (2 dígitos hex); stub_state_*.hex =
una palabra por línea (8 dígitos hex). Minúsculas, fin de línea LF.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

TP3 = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TP3 / "sw"))

from host.dump import encode  # noqa: E402
from host.stub_model import stub_dump, stub_state_words  # noqa: E402

OUT = TP3 / "VIVADO" / "TP_FINAL" / "tb" / "debug" / "vectors"


def _bytes(b: bytes) -> str:
    return "".join(f"{v:02x}\n" for v in b)


def _words(ws: list[int]) -> str:
    return "".join(f"{w & 0xFFFF_FFFF:08x}\n" for w in ws)


def vectors() -> dict[str, str]:
    v: dict[str, str] = {}
    for c in (0, 1, 7, 20):
        v[f"stub_state_c{c}_h20.hex"] = _words(stub_state_words(c, 20))
    v["stub_state_c25_h0.hex"] = _words(stub_state_words(25, 0))
    for c in [*range(0, 11), 20]:
        v[f"dump_c{c}_h20.hex"] = _bytes(encode(stub_dump(c, 20)))
    v["dump_c0_h0.hex"] = _bytes(encode(stub_dump(0, 0)))
    v["dump_c1000_h0_t.hex"] = _bytes(encode(stub_dump(1000, 0, timeout=True)))
    return v


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    expected = vectors()
    bad: list[str] = []
    OUT.mkdir(parents=True, exist_ok=True)
    for name, text in sorted(expected.items()):
        path = OUT / name
        if args.check:
            if not path.exists() or path.read_text(encoding="ascii") != text:
                bad.append(name)
        else:
            path.write_text(text, encoding="ascii", newline="\n")
    extra = sorted(p.name for p in OUT.glob("*.hex") if p.name not in expected)
    if args.check and extra:
        bad += [f"{n} (sobra)" for n in extra]
    if bad:
        print("FAIL vectors: " + ", ".join(bad))
        return 1
    print(f"PASS vectors: {len(expected)} archivos")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

   Correr `py TP3_FINAL/tools/gen_vectors.py` → `PASS vectors: 19 archivos`. Después `py TP3_FINAL/tools/gen_vectors.py --check` → `PASS vectors: 19 archivos`. Verificar a mano: `dump_c0_h20.hex` tiene 210 líneas y `dump_c1_h20.hex` 234.

5. `tb/debug/tb_cpu_stub.sv`. Dos instancias con las mismas entradas: `u_h20` (`HALT_AT = 20`) y `u_h0` (`HALT_AT = 0`). Estructura obligatoria:

```systemverilog
`timescale 1ns/1ps
`define VEC_DIR "TP3_FINAL/VIVADO/TP_FINAL/tb/debug/vectors/"

module tb_cpu_stub;
    reg clk = 1'b0;
    always #10 clk = ~clk;                        // 50 MHz

    reg        rst = 1'b1, en = 1'b0;
    reg [4:0]  reg_addr = 5'd0;
    reg [3:0]  latch_sel = 4'd0;
    reg [7:0]  mem_addr = 8'd0;

    // salidas de cada instancia: w20_* y w0_* (halted, imem_addr, reg_data,
    // latch_word, mem_data, mem_dirty, pc). i_imem_data = 32'd0.
    ...instancias cpu_stub #(.HALT_AT(20)) u_h20 (...); cpu_stub #(.HALT_AT(0)) u_h0 (...);

    integer errors = 0, checks = 0;
    reg [31:0] exp_words [0:562];

    // en = 1 durante exactamente n flancos de subida
    task automatic run_en(input integer n);
        begin
            @(negedge clk) en = 1'b1;
            repeat (n) @(negedge clk);
            en = 1'b0;
        end
    endtask

    // Recorre todas las direcciones de debug de una instancia (which: 0 = u_h20,
    // 1 = u_h0) y compara contra el vector. Se llama siempre después de un negedge.
    task automatic check_state(input integer which, input string fname);
        integer i;
        reg [31:0] got;
        begin
            $readmemh($sformatf("%s%s", `VEC_DIR, fname), exp_words);
            // [0] pc, [1] imem_addr, [2] halted
            // [3..34] regs: reg_addr = i, #1, leer reg_data
            // [35..50] latches: latch_sel = i, #1, leer latch_word
            // [51..306] dirty y [307..562] dato: mem_addr = i, #1
            // por cada palabra distinta: errors++, $display("FAIL %s[%0d]: exp=%h got=%h", fname, idx, exp, got)
            // checks++ por palabra comparada
        end
    endtask

    initial begin #(2_000_000); $fatal(1, "FAIL tb_cpu_stub: watchdog"); end

    initial begin
        repeat (3) @(negedge clk);
        rst = 1'b0;
        @(negedge clk);
        check_state(0, "stub_state_c0_h20.hex");
        run_en(1);  @(negedge clk); check_state(0, "stub_state_c1_h20.hex");
        run_en(6);  @(negedge clk); check_state(0, "stub_state_c7_h20.hex");
        run_en(13); @(negedge clk); check_state(0, "stub_state_c20_h20.hex");   // halted = 1
        run_en(5);  @(negedge clk); check_state(0, "stub_state_c20_h20.hex");   // halted congela
        repeat (3) @(negedge clk);   check_state(0, "stub_state_c20_h20.hex");   // en = 0 no cambia
        check_state(1, "stub_state_c25_h0.hex");                                  // 1+6+13+5 = 25
        @(negedge clk) rst = 1'b1; @(negedge clk) rst = 1'b0;                     // reset de 1 ciclo
        @(negedge clk); check_state(0, "stub_state_c0_h20.hex");
        if (errors != 0) $fatal(1, "FAIL tb_cpu_stub: %0d errores", errors);
        $display("PASS tb_cpu_stub: %0d chequeos", checks);
        $finish;
    end
endmodule
```

   Completar las partes indicadas con comentarios siguiendo exactamente lo que dicen; no cambiar la secuencia. Total esperado: `checks = 563 × 8 = 4504`.

6. `tb/debug/tb_imem.sv`: instancia `imem`. Casos, con `errors`/`checks` y el final de `convenciones.md` §5:
   1. Las 256 posiciones leen `0x00000073` después de arrancar (sin escribir nada).
   2. En un negedge: `i_we = 1`, `i_waddr = 5`, `i_wdata = 32'hDEADBEEF`; un posedge; `i_we = 0`. Leer `i_raddr = 5` → `DEADBEEF`; `i_raddr = 4` y `6` → `00000073`.
   3. Escribir 255 con `32'h12345678` y 0 con `32'h00500093`; leerlas.
   4. Con `i_we = 0` y `i_wdata` cambiando durante 3 flancos, la posición 5 sigue en `DEADBEEF`.
   Final: `PASS tb_imem: 262 chequeos` (256 + 3 + 2 + 1).
7. Runner. En `tools/tbs.py` agregar (rutas desde la raíz del repo):

```python
"tb_cpu_stub": {
    "top": "tb_cpu_stub",
    "files": ["TP3_FINAL/VIVADO/TP_FINAL/rtl/debug/cpu_stub.v",
              "TP3_FINAL/VIVADO/TP_FINAL/tb/debug/tb_cpu_stub.sv"],
    "defines": {}, "params": {},
},
"tb_imem": {
    "top": "tb_imem",
    "files": ["TP3_FINAL/VIVADO/TP_FINAL/rtl/debug/imem.v",
              "TP3_FINAL/VIVADO/TP_FINAL/tb/debug/tb_imem.sv"],
    "defines": {}, "params": {},
},
```

   En `tools/run.py` agregar el objetivo `vectors` que ejecuta `py TP3_FINAL/tools/gen_vectors.py --check` y devuelve su código; y agregarlo a `test` inmediatamente antes de `tbs` (el orden del resto lo fija `convenciones.md` §3). Los TB leen vectores con rutas relativas a la raíz del repo: `run.py` tiene que correr `vvp` con `cwd` = raíz del repo (verificarlo; si B-04 lo corre en otro directorio, cambiarlo a la raíz).

## Validación
```
py TP3_FINAL/tools/run.py vectors        → PASS vectors: 19 archivos
py TP3_FINAL/tools/run.py tb tb_cpu_stub → log con "PASS tb_cpu_stub: 4504 chequeos", código 0
py TP3_FINAL/tools/run.py tb tb_imem     → log con "PASS tb_imem: 262 chequeos", código 0
cd TP3_FINAL/sw; py -m pytest tests/test_stub_model.py -q → 4 passed
py TP3_FINAL/tools/run.py synth_ooc cpu_stub → sin latch/multi-driven/implicit net
```
Prueba de que el TB detecta errores (no se commitea): cambiar en `cpu_stub.v` `8'h1A` por `8'h1B`, correr `tb tb_cpu_stub` → falla; revertir.

## Listo cuando
- [ ] El TB verifica PC, registros, latches, memoria sucia y `halted` después de 0, 1, 7 y 20 ciclos, congelado en `halted`, con `en = 0`, a los 25 ciclos sin HALT y tras reset (`PASS tb_cpu_stub: 4504 chequeos`).
- [ ] `stub_model` y el stub coinciden en todos esos puntos (los vectores salen de `stub_model`).
- [ ] `run.py vectors` pasa y está dentro de `test`.
- [ ] `tb_imem` pasa.

## No hacer
- No editar a mano ningún `.hex` de `vectors/`: siempre `gen_vectors.py`.
- No agregar lógica de ejecución de instrucciones al stub.

## Si algo falla
| Síntoma | Qué hacer |
| --- | --- |
| `$readmemh` no encuentra el archivo | `vvp` no corre con `cwd` = raíz del repo (paso 7) |
| `$sformatf` no soportado | Confirmar `-g2012`; si persiste, armar el nombre con `{`VEC_DIR, fname}` usando `string` |
| Diferencia solo en la palabra 2 (`halted`) a 20 ciclos | Revisar `o_halted` contra la tabla de `interfaz_cpu.md` §8 |
| `gen_vectors --check` falla en Windows sin cambios | Verificar fin de línea LF (`newline="\n"`) y que git no convierta: agregar `*.hex text eol=lf` a `TP3_FINAL/.gitattributes` |

## Commits
1. `debug: cpu_stub e imem`
2. `sw-host: stub_model y vectores generados`
3. `debug: tb_cpu_stub y tb_imem en el runner`

## Depende de / bloquea
Depende de: B-04 (runner), B-07, B-08. Bloquea: B-10 a B-16.
