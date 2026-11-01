# B-29 · Entrega a la integración

`S` · etiquetas `contrato` · milestone M4 · **Modelo sugerido:** Haiku · [índice](../README.md)

## Objetivo

`$DOCS/debug.md` permite que A corra la regresión, lea un diff y conecte su CPU en la Fase 10 sin preguntar.

## Antes de empezar

- Leer: [`convenciones.md`](../../../TP3_FINAL/doc/documentation/convenciones.md) §2-§3; [B-27](B-27-regresion.md) pasos 1-3; [B-28](B-28-tb-system-prog.md) paso 4; [`interfaz_cpu.md`](../../../TP3_FINAL/doc/documentation/interfaz_cpu.md) §1-§4 (marcadas **[A]**).
- Precondiciones: B-01 a B-28 cerrados (B-26 puede tener pendiente solo su criterio con CPU real). Comprobar: `py TP3_FINAL/tools/run.py test` y `py TP3_FINAL/tools/run.py regress` → código 0.
- Rama: `b/B-29-entrega`.

## Archivos

| Acción | Ruta | Contenido |
| --- | --- | --- |
| crear | `TP3_FINAL/doc/documentation/debug.md` | Secciones del paso 1 |
| modificar | `TP3_FINAL/README.md` | Un enlace a `debug.md` en la sección "Instalación y tests" |

## Pasos

1. Escribir `debug.md` con exactamente estas secciones, en este orden:

   1. **Qué hay.** Una tabla: módulo/herramienta → archivo → issue (UART, Debug Unit, stub, imem, system, tops, ensamblador, ISS, link, fakeboard, CLI, GUI, regresión).
   2. **Instalar y verificar.** Copiar los comandos de instalación del README de TP3 y los dos comandos de comprobación (`run.py test`, `run.py regress`) con la salida esperada (la tabla de B-27 con todo `OK`).
   3. **Conectar el CPU real (Fase 10).** Pasos numerados:
      1. `cpu.v` declara sus puertos con `` `include "cpu_ports.vh" `` (`interfaz_cpu.md` §1).
      2. Cumplir las obligaciones **[A]**: §2 (`adv`), §3 (reset), §4 (dmem con dirty y "limpia se lee 0", desalineados).
      3. Agregar los archivos a `CPU_FILES` en `TP3_FINAL/tools/tbs.py`.
      4. `py TP3_FINAL/tools/run.py tb tb_system_prog` → `PASS tb_system_prog`.
      5. `py TP3_FINAL/tools/run.py regress` → la columna `rtl` ahora compara los 9 programas.
   4. **Leer un diff.** El ejemplo de salida de B-27 (mutante `sra`) explicado línea por línea: programa, nivel, clave (`pc`, `xN`, `mem[...]`, `stop`), esperado y obtenido; y qué mirar primero según la clave (`stop` distinto → HALT/timeout; `pc` → saltos/HALT; un registro → la instrucción que lo escribe por última vez; `mem` → stores y dirty).
   5. **Placa.** `py TP3_FINAL/tools/run.py bit top_debug --mhz 50`, programar, `py -m host.cli --port COMx` (con `cwd = TP3_FINAL/sw`), y `run.py regress --board COMx`. LEDs de `interfaz_cpu.md` §7.
   6. **Recursos de la Debug Unit.** Tabla LUT / FF / LUTRAM / BRAM de `debug_unit`, `uart_if` e `imem`, copiada del reporte de utilización jerárquico de la última síntesis de `top_debug` (`report_utilization -hierarchical`, que genera `tools/build_bit.tcl`; si no lo genera, correr `py TP3_FINAL/tools/run.py synth_ooc system` y usar ese reporte). Indicar el archivo de reporte del que salen los números y el commit.
   7. **Pendiente.** Lista de casillas sin tildar de B-01 a B-28 (por ejemplo, el criterio de B-26 con CPU real) y decisiones con **[A]** todavía sin aprobar, cada una con su issue.

2. Pedirle a A que siga `debug.md` en su máquina sin ayuda, de "Instalar y verificar" a "Leer un diff" (la sección de la Fase 10 la sigue cuando tenga el CPU). Cada duda que surja se corrige en `debug.md` en el mismo PR.

## Validación

- `py TP3_FINAL/tools/run.py test` y `regress` → 0 (en la máquina de B).
- A comenta en el PR: "corrí `run.py regress` siguiendo solo `debug.md`" con la tabla de salida pegada.

## Listo cuando

- [ ] `debug.md` tiene las 7 secciones con números reales (recursos) y comandos copiables.
- [ ] A corrió `run.py regress` en su máquina siguiendo solo el documento (comentario en el PR).

## No hacer

- No repetir los contratos: enlazarlos.
- No inventar números de recursos: si no hay reporte, se corre la síntesis.

## Si algo falla

| Síntoma | Qué hacer |
| --- | --- |
| A no puede correr algo por una diferencia de su máquina (otra ruta de Vivado, `py` ausente) | Agregar el caso a la sección 2 con la solución; no cambiar `convenciones.md` sin aprobación |

## Commits

1. `docs: debug.md para la integración`

## Depende de / bloquea

Depende de: B-01 a B-28. Bloquea: Fase 10.
