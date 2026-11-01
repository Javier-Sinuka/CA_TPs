# Issues de la pista B · Fases 8 y 9

Las 29 issues del [plan de issues](../Plan%20de%20issues%20%C2%B7%20Fases%208%20y%209%20%28UART%2C%20Debug%20Unit%20y%20software%29.md), escritas para que las ejecute un modelo barato **sin decidir nada**. Estado al 2026-10-31: todas escritas, ninguna ejecutada.

## Cómo se usa

1. **No hay decisiones abiertas.** Todas están en [`decisiones.md`](../../TP3_FINAL/doc/documentation/decisiones.md) (D-01 a D-27, más los hallazgos H-1 a H-7).
2. **Los contratos son la fuente de verdad.** Los issues los citan, no los repiten:
   - [`convenciones.md`](../../TP3_FINAL/doc/documentation/convenciones.md): rutas, herramientas, runner, estilo, reglas de TB, definición de terminado.
   - [`protocolo.md`](../../TP3_FINAL/doc/documentation/protocolo.md): comandos UART, errores, timeouts, vectores hex.
   - [`dump.md`](../../TP3_FINAL/doc/documentation/dump.md): mapa del dump, layout de latches, formato JSON canónico.
   - [`interfaz_cpu.md`](../../TP3_FINAL/doc/documentation/interfaz_cpu.md): puertos `cpu` ↔ Debug Unit, memorias, `system.v`, stub.
3. **Un issue por sesión del modelo ejecutor.** Pasarle el archivo del issue y decirle: *"Ejecutá este issue al pie de la letra. Leé solo lo que dice 'Antes de empezar'. Si algo no está cubierto, detenete y preguntá."* El modelo sugerido figura en la cabecera de cada issue (Haiku para lo mecánico, Sonnet para RTL, TB y software con lógica).
4. **Pasos `[manual]`** (placa, descargas, aprobaciones de A) los hace una persona.
5. Formato de cada issue: [`PLANTILLA.md`](PLANTILLA.md).

## Antes de la primera issue (una sola vez, a mano)

- `git config --global --add safe.directory C:/Personal/Repos/CA_TPs` (git hoy falla en este repo por "dubious ownership").
- `py -m pip install pytest` (pyserial ya está).
- Que A lea y apruebe los puntos **[A]** de `interfaz_cpu.md` y `dump.md` §3: tamaños de memoria, accesos desalineados, reset de registros y dirty, palabras de latch. Si A cambia algo, se cambia el contrato **antes** de ejecutar B-07/B-08/B-09.

## Orden de ejecución

Dos carriles que se separan después de B-18 y se juntan en B-17/B-23. Dentro de cada carril, en orden.

| Paso | Hardware (M0, M1, M2) | Software (M3) |
| --- | --- | --- |
| 1 | B-01 → B-02 → B-03 → B-04 | |
| 2 | B-06 → B-07 → B-08 | |
| 3 | B-18 (base de software, la necesitan los dos carriles) | |
| 4 | B-09 → B-05 `[placa]` | B-19 → B-20 |
| 5 | B-10 → B-14 → B-11 → B-12 → B-13 → B-15 → B-16 | B-21 → B-22 |
| 6 | | B-23 → B-24 → B-25 |
| 7 | B-17 `[placa]` (se cierra junto con el último criterio de B-23) | B-26 |
| 8 | B-28 → B-27 → B-29 | |

El orden de M2 no es el numérico: el dump (B-14) va antes que `S` y `R` porque estos responden con un dump.

## Mapa de issues

Tamaño: S ≤ medio día, M ≤ 2 días, L ≤ 4 días.

### M0 · UART

| Issue | Título | Tam. | Modelo |
| --- | --- | --- | --- |
| [B-01](M0-uart/B-01-auditar-uart.md) | Importar y auditar la UART de TP2 (crea `run.py`, `tbs.py`, `synth_ooc.tcl`) | S | Haiku |
| [B-02](M0-uart/B-02-parametrizar-baud.md) | Divisor de baudios redondeado y TB de `baud_gen` | S | Sonnet |
| [B-03](M0-uart/B-03-interfaz-uart.md) | Wrapper `uart_if`, estilo, `ASYNC_REG` y H-7 | S | Sonnet |
| [B-04](M0-uart/B-04-testbench-uart.md) | TB de la UART, BFM, arreglo de H-1 (stop a mitad de bit) y mutaciones | M | Sonnet |
| [B-05](M0-uart/B-05-eco-en-placa.md) | Eco en placa a 50 y 100 MHz (crea `build_bit.tcl`) | M | Sonnet + `[placa]` |

### M1 · Contratos y stub

| Issue | Título | Tam. | Modelo |
| --- | --- | --- | --- |
| [B-06](M1-contrato/B-06-protocolo.md) | Protocolo v1: `proto.py` y aprobación de A | S | Haiku |
| [B-07](M1-contrato/B-07-formato-dump.md) | Dump v1: `dump.py`, `canonical.py` y aprobación de A | M | Haiku |
| [B-08](M1-contrato/B-08-interfaz-cpu.md) | `cpu_ports.vh` y aprobación de A | S | Haiku |
| [B-09](M1-contrato/B-09-cpu-stub.md) | `cpu_stub`, `imem`, `stub_model.py` y vectores | M | Haiku |

### M2 · Debug Unit

| Issue | Título | Tam. | Modelo |
| --- | --- | --- | --- |
| [B-10](M2-debug/B-10-fsm-base.md) | FSM base, `system.v`, `V`, `X`, errores | M | Sonnet |
| [B-11](M2-debug/B-11-paso-a-paso.md) | `S` | S | Sonnet |
| [B-12](M2-debug/B-12-run-timeout-abort.md) | `R`, timeout y `A` | M | Sonnet |
| [B-13](M2-debug/B-13-carga-programa.md) | `L` en dos fases | M | Sonnet |
| [B-14](M2-debug/B-14-dump.md) | Dump y `D` | M | Sonnet |
| [B-15](M2-debug/B-15-memoria-usada.md) | Memoria usada (dirty) | S | Haiku |
| [B-16](M2-debug/B-16-tb-sistema.md) | TB del sistema completo con guion y log de bytes | M | Sonnet |
| [B-17](M2-debug/B-17-debug-en-placa.md) | Debug Unit + stub en la placa | M | Sonnet + `[placa]` |

### M3 · Software

| Issue | Título | Tam. | Modelo |
| --- | --- | --- | --- |
| [B-18](M3-sw/B-18-base-software.md) | Base de `sw/`, objetivos `pytest`, `iss`, `test` | S | Haiku |
| [B-19](M3-sw/B-19-ensamblador.md) | Ensamblador | L | Sonnet |
| [B-20](M3-sw/B-20-desensamblador.md) | Desensamblador | S | Haiku |
| [B-21](M3-sw/B-21-golden-model.md) | Golden model en C++ | M | Sonnet |
| [B-22](M3-sw/B-22-programas-prueba.md) | 9 programas con resultado esperado | M | Sonnet |
| [B-23](M3-sw/B-23-link.md) | `link.py` | M | Sonnet |
| [B-24](M3-sw/B-24-placa-simulada.md) | Placa simulada | S | Sonnet |
| [B-25](M3-sw/B-25-cli.md) | CLI | M | Sonnet |
| [B-26](M3-sw/B-26-interfaz-final.md) | GUI (tkinter) y diagrama espacio-tiempo | L | Sonnet |

### M4 · Listo para la Fase 10

| Issue | Título | Tam. | Modelo |
| --- | --- | --- | --- |
| [B-27](M4-integracion/B-27-regresion.md) | Regresión de tres niveles | M | Sonnet |
| [B-28](M4-integracion/B-28-tb-system-prog.md) | TB de sistema listo para el CPU real | S | Sonnet |
| [B-29](M4-integracion/B-29-entrega-integracion.md) | Entrega a la integración (`debug.md`) | S | Haiku |

## Advertencia sobre los valores esperados

Los códigos, codificaciones y resultados esperados de los issues se calcularon a mano, no se ejecutaron. Si un valor esperado no coincide al ejecutar, la tabla "Si algo falla" del issue dice qué revisar; si no lo cubre, **el ejecutor se detiene y lo reporta**, no ajusta el valor esperado para que pase.
