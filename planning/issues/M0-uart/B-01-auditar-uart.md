# B-01 · Importar y auditar la UART de TP2

`S` · etiquetas `uart` `tools` · milestone M0 · **Modelo sugerido:** Haiku · [índice](../README.md)

## Objetivo

La UART de TP2 copiada sin cambios a TP3, el runner mínimo y la síntesis out-of-context funcionando, la línea base de los TB registrada y la auditoría escrita en `$DOCS/uart.md`.

## Antes de empezar

- Leer: [`convenciones.md`](../../../TP3_FINAL/doc/documentation/convenciones.md) §1, §2, §3, §7; [`decisiones.md`](../../../TP3_FINAL/doc/documentation/decisiones.md) D-01, D-07, D-15, D-16 y "Hallazgos resueltos sin decisión".
- Precondiciones: ninguna. Comprobar herramientas:
  - `iverilog -V` → primera línea contiene `Icarus Verilog version 12`.
  - `py --version` → `Python 3.14.x`.
  - `"C:/Xilinx/Vivado/2024.1/bin/vivado.bat" -version` → contiene `Vivado v2024.1`.
- Rama: `b/B-01-auditar-uart`, desde `main`.
- En este issue **no se modifica ninguna línea** de la UART ni de sus TB.

## Archivos

| Acción | Ruta | Contenido |
| --- | --- | --- |
| crear (copia) | `TP3_FINAL/VIVADO/TP_FINAL/rtl/uart/baud_gen.v` | idéntico a `TP2_UART/src/baud_gen.v` |
| crear (copia) | `TP3_FINAL/VIVADO/TP_FINAL/rtl/uart/uart_rx.v` | idéntico a `TP2_UART/src/uart_rx.v` |
| crear (copia) | `TP3_FINAL/VIVADO/TP_FINAL/rtl/uart/uart_tx.v` | idéntico a `TP2_UART/src/uart_tx.v` |
| crear (copia) | `TP3_FINAL/VIVADO/TP_FINAL/tb/uart/tb_baud_gen.sv` | idéntico a `TP2_UART/sim/tb_baud_gen.sv` |
| crear (copia) | `TP3_FINAL/VIVADO/TP_FINAL/tb/uart/tb_uart_rx.sv` | idéntico a `TP2_UART/sim/tb_uart_rx.sv` |
| crear (copia) | `TP3_FINAL/VIVADO/TP_FINAL/tb/uart/tb_uart_tx.sv` | idéntico a `TP2_UART/sim/tb_uart_tx.sv` |
| crear | `TP3_FINAL/tools/run.py` | runner, objetivos `tb`, `tbs`, `synth_ooc` (paso 3) |
| crear | `TP3_FINAL/tools/tbs.py` | tablas `TBS` y `SYNTH` (paso 3) |
| crear | `TP3_FINAL/tools/synth_ooc.tcl` | síntesis out-of-context (paso 4) |
| modificar | `TP3_FINAL/.gitignore` | agregar `build/` |
| modificar | `TP3_FINAL/VIVADO/TP_FINAL/TP_FINAL.xpr` | parte `xc7a35tcpg236-1` (paso 6) |
| crear | `TP3_FINAL/doc/documentation/uart.md` | auditoría y línea base (paso 7) |
| no tocar | `TP2_UART/**` | TP2 es una entrega cerrada |

## Pasos

1. **Copiar** (desde la raíz del repo, en Git Bash):

   ```bash
   mkdir -p TP3_FINAL/VIVADO/TP_FINAL/rtl/uart TP3_FINAL/VIVADO/TP_FINAL/tb/uart
   cp TP2_UART/src/{baud_gen,uart_rx,uart_tx}.v TP3_FINAL/VIVADO/TP_FINAL/rtl/uart/
   cp TP2_UART/sim/{tb_baud_gen,tb_uart_rx,tb_uart_tx}.sv TP3_FINAL/VIVADO/TP_FINAL/tb/uart/
   ```

   Verificar: para cada uno de los 6 archivos, `git diff --no-index --stat TP2_UART/src/uart_rx.v TP3_FINAL/VIVADO/TP_FINAL/rtl/uart/uart_rx.v` (y equivalentes) no imprime nada.

2. **Commit 1, solo la copia.** `git add` de los 6 archivos y nada más. Mensaje del commit 1 (ver "Commits"). Anotar el hash de origen: `git log -1 --format=%H -- TP2_UART/src` (va a `uart.md` en el paso 7).

3. **Runner.** Crear `TP3_FINAL/tools/tbs.py` con exactamente:

   ```python
   """Tablas del runner (convenciones.md §3). Rutas relativas a la raíz del repo."""
   RTL = "TP3_FINAL/VIVADO/TP_FINAL/rtl"
   TB = "TP3_FINAL/VIVADO/TP_FINAL/tb"

   # Claves de cada entrada: "top", "files"; opcionales "incdirs" (lista de directorios para -I,
   # por ejemplo f"{TB}/common" para `include "uart_bfm.svh"), "defines", "params", "legacy".
   # "legacy": TB heredado de TP2 que termina con $finish aunque falle. Pasa si vvp
   # devuelve 0 y no hay líneas que empiecen con FAIL ni contengan TIMEOUT.
   # B-04 convierte esos TB y borra la marca.
   TBS = {
       "tb_baud_gen": {"top": "tb_baud_gen", "legacy": True,
                       "files": [f"{RTL}/uart/baud_gen.v", f"{TB}/uart/tb_baud_gen.sv"]},
       "tb_uart_rx": {"top": "tb_uart_rx", "legacy": True,
                      "files": [f"{RTL}/uart/uart_rx.v", f"{TB}/uart/tb_uart_rx.sv"]},
       "tb_uart_tx": {"top": "tb_uart_tx", "legacy": True,
                      "files": [f"{RTL}/uart/uart_tx.v", f"{TB}/uart/tb_uart_tx.sv"]},
   }

   # Síntesis out-of-context: top -> archivos.
   SYNTH = {
       "baud_gen": [f"{RTL}/uart/baud_gen.v"],
       "uart_rx": [f"{RTL}/uart/uart_rx.v"],
       "uart_tx": [f"{RTL}/uart/uart_tx.v"],
   }
   ```

   Crear `TP3_FINAL/tools/run.py` con exactamente:

   ```python
   """Runner único de TP3 (convenciones.md §3).

   Uso, desde la raíz del repo:
       py TP3_FINAL/tools/run.py tb <nombre> [+plusarg ...]
       py TP3_FINAL/tools/run.py tbs
       py TP3_FINAL/tools/run.py synth_ooc <top>
   iverilog y vvp corren con cwd = raíz del repo: los TB abren archivos con rutas relativas a esa raíz.
   """
   from __future__ import annotations

   import argparse
   import os
   import re
   import subprocess
   import sys
   from pathlib import Path

   TOOLS = Path(__file__).resolve().parent
   REPO = TOOLS.parents[1]
   BUILD = REPO / "TP3_FINAL" / "build"
   sys.path.insert(0, str(TOOLS))
   from tbs import SYNTH, TBS  # noqa: E402

   VIVADO = os.environ.get("VIVADO", "C:/Xilinx/Vivado/2024.1/bin/vivado.bat")
   BAD_SYNTH = re.compile(r"inferring latch|multi-driven|implicit", re.IGNORECASE)


   def run_tb(name: str, plusargs: list[str] | None = None) -> bool:
       spec = TBS[name]
       top = spec["top"]
       files = [REPO / f for f in spec["files"]]
       incdirs = sorted({f.parent.as_posix() for f in files}
                        | {(REPO / d).as_posix() for d in spec.get("incdirs", [])})
       BUILD.mkdir(parents=True, exist_ok=True)
       vvp = BUILD / f"{name}.vvp"
       log = BUILD / f"{name}.log"
       cmd = ["iverilog", "-g2012", "-Wall", "-Wno-timescale"]
       cmd += [f"-I{d}" for d in incdirs]
       cmd += [f"-D{k}={v}" for k, v in spec.get("defines", {}).items()]
       cmd += [f"-P{top}.{k}={v}" for k, v in spec.get("params", {}).items()]
       cmd += ["-s", top, "-o", vvp.as_posix()] + [f.as_posix() for f in files]
       comp = subprocess.run(cmd, capture_output=True, text=True, cwd=REPO)
       if comp.returncode != 0:
           log.write_text(comp.stdout + comp.stderr)
           print(f"FAIL {name}: no compila (ver {log.relative_to(REPO).as_posix()})")
           return False
       sim = subprocess.run(["vvp", "-n", vvp.as_posix(), *(plusargs or [])],
                            capture_output=True, text=True, cwd=REPO)
       out = comp.stdout + comp.stderr + sim.stdout + sim.stderr
       log.write_text(out)
       lines = out.splitlines()
       has_fail = any(l.startswith("FAIL") for l in lines)
       if spec.get("legacy"):
           ok = sim.returncode == 0 and not has_fail and not any("TIMEOUT" in l for l in lines)
       else:
           ok = (sim.returncode == 0 and not has_fail
                 and any(l.startswith(f"PASS {top}:") for l in lines))
       print(f"{'PASS' if ok else 'FAIL'} {name} (log: {log.relative_to(REPO).as_posix()})")
       return ok


   def run_tbs() -> bool:
       results = [run_tb(n) for n in TBS]
       print(f"tbs: {sum(results)}/{len(results)} PASS")
       return all(results)


   def run_vivado(tcl: str, log: Path, args: list[str]) -> int:
       log.parent.mkdir(parents=True, exist_ok=True)
       cmd = [VIVADO, "-mode", "batch", "-nojournal", "-log", log.as_posix(),
              "-source", (TOOLS / tcl).as_posix(), "-tclargs", *args]
       return subprocess.run(cmd).returncode


   def bad_synth_lines(log: Path) -> list[str]:
       text = log.read_text(errors="replace") if log.exists() else ""
       return [l for l in text.splitlines() if BAD_SYNTH.search(l)]


   def run_synth(top: str) -> bool:
       out = BUILD / "synth_ooc" / top
       log = out / "vivado.log"
       files = [(REPO / f).as_posix() for f in SYNTH[top]]
       rc = run_vivado("synth_ooc.tcl", log, [top, out.as_posix(), *files])
       bad = bad_synth_lines(log)
       for l in bad:
           print(f"  {l}")
       ok = rc == 0 and not bad
       print(f"{'PASS' if ok else 'FAIL'} synth_ooc {top} (log: {log.relative_to(REPO).as_posix()})")
       return ok


   def main(argv: list[str] | None = None) -> int:
       p = argparse.ArgumentParser(prog="run.py")
       sub = p.add_subparsers(dest="cmd", required=True)
       ptb = sub.add_parser("tb")
       ptb.add_argument("name", choices=sorted(TBS))
       ptb.add_argument("plusargs", nargs="*", help="se pasan a vvp, por ejemplo +SEED=3")
       sub.add_parser("tbs")
       sub.add_parser("synth_ooc").add_argument("top", choices=sorted(SYNTH))
       a = p.parse_args(argv)
       if a.cmd == "tb":
           ok = run_tb(a.name, a.plusargs)
       elif a.cmd == "tbs":
           ok = run_tbs()
       else:
           ok = run_synth(a.top)
       return 0 if ok else 1


   if __name__ == "__main__":
       sys.exit(main())
   ```

   Objetivos que agregan issues posteriores (no crearlos acá): `mutate` (B-04), `bit` y `program` (B-05), `vectors` (B-09), `pytest` e `iss` (B-18), `regress` (B-27). El objetivo `test` corre, en este orden y sin cortar en la primera falla: `iss` + `vectors --check` + `tbs` + `pytest` + `mutate`; se arma cuando existen sus partes (B-18). En B-01 solo existen `tb`, `tbs` y `synth_ooc`.

   Agregar al final de `TP3_FINAL/.gitignore` la línea `build/`.

   Verificar: `py TP3_FINAL/tools/run.py tb tb_uart_rx` → imprime `PASS tb_uart_rx (log: TP3_FINAL/build/tb_uart_rx.log)` y devuelve 0.

4. **Síntesis out-of-context.** Crear `TP3_FINAL/tools/synth_ooc.tcl` con exactamente:

   ```tcl
   # Uso: vivado -mode batch -source synth_ooc.tcl -tclargs <top> <outdir> <archivo.v> ...
   set top   [lindex $argv 0]
   set out   [lindex $argv 1]
   set files [lrange $argv 2 end]
   set part  xc7a35tcpg236-1
   file mkdir $out
   create_project -in_memory -part $part
   set incdirs {}
   foreach f $files {
       read_verilog $f
       lappend incdirs [file dirname $f]
   }
   synth_design -top $top -part $part -mode out_of_context -include_dirs [lsort -unique $incdirs]
   report_utilization -file $out/util.rpt
   report_methodology -file $out/methodology.rpt
   ```

   Verificar: `py TP3_FINAL/tools/run.py synth_ooc uart_rx` → `PASS synth_ooc uart_rx`. Repetir con `baud_gen` y `uart_tx`.

5. **Línea base de los TB.** Correr `py TP3_FINAL/tools/run.py tbs`. Resultado esperado (y que hay que registrar tal cual):

   ```
   FAIL tb_baud_gen (log: TP3_FINAL/build/tb_baud_gen.log)
   PASS tb_uart_rx (log: TP3_FINAL/build/tb_uart_rx.log)
   PASS tb_uart_tx (log: TP3_FINAL/build/tb_uart_tx.log)
   tbs: 2/3 PASS
   ```

   Y en el log de `tb_baud_gen` una sola línea que empieza con `FAIL`: `FAIL FIRST_TICK | cycle=652 expected=651`. Contar con `grep -c "^PASS" TP3_FINAL/build/<tb>.log` y `grep -c "^FAIL" ...` para cada TB (esperado: rx 26/0, tx 22/0, baud_gen 59/1). El código de salida 1 es la línea base esperada; no se corrige acá (lo hace B-02).

6. **Parte del proyecto Vivado.** En `TP3_FINAL/VIVADO/TP_FINAL/TP_FINAL.xpr` reemplazar las 3 apariciones de `xc7a35ticpg236-1L` por `xc7a35tcpg236-1`:

   ```bash
   sed -i 's/xc7a35ticpg236-1L/xc7a35tcpg236-1/g' TP3_FINAL/VIVADO/TP_FINAL/TP_FINAL.xpr
   ```

   Verificar: `grep -c xc7a35ticpg236-1L TP3_FINAL/VIVADO/TP_FINAL/TP_FINAL.xpr` → `0`; `grep -c xc7a35tcpg236-1 ...` → `3`.

7. **`$DOCS/uart.md`.** Crear `TP3_FINAL/doc/documentation/uart.md` con las secciones de abajo. Las de B-02 a B-05 quedan con el título y la línea `Pendiente (B-0x).`

   ```markdown
   # UART de TP3

   ## Origen
   Copiada de `TP2_UART/src` en el commit <hash del commit 1>. Último commit de origen en TP2: <hash del paso 2>.
   Archivos: `baud_gen.v`, `uart_rx.v`, `uart_tx.v`. No se importan `uart_top.v`, `interface_rx.v`,
   `interface_tx.v`, `interface_circuit.v` ni `ALU.v` (específicos del protocolo de TP2, D-09).

   ## Auditoría
   <tabla de abajo>

   ## Línea base de TB (Icarus 12, sin cambios)
   | TB | PASS | FAIL | Resultado del runner |
   | --- | --- | --- | --- |
   | tb_uart_rx | 26 | 0 | PASS |
   | tb_uart_tx | 22 | 0 | PASS |
   | tb_baud_gen | 59 | 1 | FAIL: `FIRST_TICK cycle=652 expected=651` (H-2, error del TB) |

   ## Síntesis out-of-context (xc7a35tcpg236-1)
   | Módulo | LUT | FF | Latches / multi-driven / implicit |
   | --- | --- | --- | --- |
   <una fila por módulo, de build/synth_ooc/<top>/util.rpt: "Slice LUTs" y "Slice Registers">

   ## Baud rate
   Pendiente (B-02).

   ## Interfaz
   Pendiente (B-03).

   ## Verificación
   Pendiente (B-04).

   ## Resultados en placa
   Pendiente (B-05).

   ## Estado
   Pendiente (B-05).
   ```

   Tabla de auditoría (copiar tal cual; las líneas son de los archivos importados, verificar cada una abriendo el archivo y corregir solo el número si no coincide):

   | Punto | Esperado | Estado | Evidencia | Arreglo |
   | --- | --- | --- | --- | --- |
   | Divisor de baudios | Calculado desde `CLOCK_FREQ` y `BAUD_RATE`, redondeado | Parcial: trunca; `OVERSAMPLE` es parámetro pero RX/TX asumen 16 (H-3); `CNTR_WIDTH = 0` si el divisor es 1 | `baud_gen.v` L1-4, L10-11 | B-02 |
   | Latencia del tick | Fija y documentada | Sí: `o_baud_tick` sale de un registro, 1 ciclo después de `r_counter == CNTR_MAX`. El `FIRST_TICK` que falla es una carrera del TB (H-2) | `baud_gen.v` L27-37 | B-02 (TB) |
   | Muestreo de RX | 16×, centro del bit | Sí: tick 7 de cada bit | `uart_rx.v` L23, L98 | — |
   | Sincronizador de RX | 2 FF | Sí, sin `ASYNC_REG` en el RTL (en TP2 estaba en el XDC por nombre de celda) | `uart_rx.v` L16-17, L59-65 | B-03 |
   | Inicio falso | Descarta glitches | Sí: si en el tick 7 del start la línea está en 1, vuelve a `IDLE` | `uart_rx.v` L39-41 | B-04 lo prueba |
   | Error de framing | Stop en 0 detectado sin falsos positivos | **No (H-1):** el stop se evalúa en el tick 15, a 10,0 bits del flanco de start, en el borde con el start siguiente. Margen hacia emisor rápido ≈ 0,4 %; −0,5 % ya da errores | `uart_rx.v` L51-55, L103-125 | B-04 (D-07) |
   | Interfaz RX | `valid` de 1 ciclo, sin `valid` en bytes con error | Parcial: `o_valid` dura 1 ciclo, pero también sube con error de framing, junto con `o_error` | `uart_rx.v` L111-125 | B-04 (D-08) |
   | Interfaz TX | Handshake sin pérdidas ni duplicados | Sí: `o_busy == (r_state != IDLE)` en todo ciclo, así que es un valid/ready (`ready = ~o_busy`); `i_start` sostenido envía varios bytes, que es lo esperado (D-14) | `uart_tx.v` L73-79, L81-89 | — |
   | Temporización de TX | Bits de igual duración | Parcial (H-7): el bit 0 dura 16 ticks + 1 clock y el bit 7, 16 ticks − 1 clock, porque `o_tx <= r_shift[0]` usa el valor previo al desplazamiento | `uart_tx.v` L67, L86-87 | B-03 |
   | Reset | Síncrono, activo en alto | Sí, en todos los `always` | `if (i_reset)` | — |
   | Estilo | `timescale`, `default_nettype none`, sin `initial`/`negedge`/`#` | Parcial: faltan `timescale` y `default_nettype`; el resto cumple | los 3 archivos | B-03 |
   | Latches / multi-driven | Ninguno | Sí (síntesis OOC, paso 4) | `build/synth_ooc/*/vivado.log` | — |

   Lista de arreglos asignados (al final de la sección Auditoría):

   - B-02: divisor redondeado, `OVERSAMPLE` como `localparam`, rechazo de divisor < 2, TB de baud corregido (H-2).
   - B-03: `ASYNC_REG`, estilo, H-7, wrapper `uart_if`.
   - B-04: D-07 (stop a mitad de bit) y D-08 (sin `valid` en framing), TB automático.

## Validación

```bash
py TP3_FINAL/tools/run.py tbs                 # salida exacta del paso 5, código 1
py TP3_FINAL/tools/run.py synth_ooc baud_gen  # PASS
py TP3_FINAL/tools/run.py synth_ooc uart_rx   # PASS
py TP3_FINAL/tools/run.py synth_ooc uart_tx   # PASS
git diff --no-index --stat TP2_UART/src/uart_tx.v TP3_FINAL/VIVADO/TP_FINAL/rtl/uart/uart_tx.v   # vacío (y los otros 5)
```

## Listo cuando

- [ ] Los 6 archivos importados son idénticos a TP2 y el commit 1 contiene solo esos 6 archivos (`git show --stat HEAD~3` o el hash correspondiente).
- [ ] `run.py tbs` da exactamente la línea base del paso 5.
- [ ] `run.py synth_ooc` da PASS para `baud_gen`, `uart_rx` y `uart_tx`.
- [ ] El `.xpr` ya no contiene `xc7a35ticpg236-1L`.
- [ ] `uart.md` tiene Origen (con los dos hashes), Auditoría (tabla + lista de arreglos), Línea base y Síntesis completas.

## No hacer

- No corregir nada de la UART ni de los TB (ni siquiera el `FIRST_TICK`): eso es B-02 a B-04.
- No abrir el proyecto en el GUI de Vivado ni regenerar el `.xpr` (solo el `sed` del paso 6).
- No agregar los TB de A (`tb_alu.sv`, etc.) a `TBS`.

## Si algo falla

| Síntoma | Qué hacer |
| --- | --- |
| `git` dice `detected dubious ownership` | **[manual]** El usuario corre `git config --global --add safe.directory C:/Personal/Repos/CA_TPs`. El ejecutor no cambia configuración global |
| `run.py synth_ooc` no encuentra Vivado o `subprocess` no ejecuta el `.bat` | Cambiar en `run_vivado` el comando a `["cmd", "/c", VIVADO, ...]`. Si sigue fallando, detenerse y preguntar |
| `synth_ooc` marca una línea con `implicit` que no es un cable implícito | Copiar la línea al PR y detenerse a preguntar; no relajar la expresión regular |
| Los conteos PASS/FAIL del paso 5 no coinciden | Registrar los números reales en `uart.md`, no tocar los TB, y avisar en el PR |
| `py` no existe | Detenerse: `convenciones.md` §2 no se cumple en esta máquina |

## Commits

1. `uart: importada de TP2 sin cambios`
2. `tools: runner mínimo (tb, tbs, synth_ooc) y build/ en .gitignore`
3. `vivado: parte xc7a35tcpg236-1 (Basys3)`
4. `docs: auditoría y línea base de la UART`

## Depende de / bloquea

Depende de: nada.
Bloquea: B-02, B-03.
