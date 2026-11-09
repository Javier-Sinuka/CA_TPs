# Protocolo UART v1 (PC ↔ Debug Unit)

**Estado: v1 propuesta, pendiente de aprobación de A (B-06).** Única fuente de verdad entre `debug_unit.v` y `sw/host/`. Las constantes de este archivo se copian literalmente a `sw/host/proto.py` y a los `localparam` de `debug_unit.v`.

## 1. Capa física

115200 baudios, 8N1, sin control de flujo. Todos los números multibyte son **little-endian** (byte menos significativo primero): `N`, palabras de programa, palabras del dump, direcciones.

## 2. Reglas generales

1. **Una transacción por vez.** El host no manda un comando nuevo hasta recibir la respuesta completa del anterior (o hasta que venza su timeout).
2. **Byte pendiente.** Mientras la Debug Unit está ocupada (respondiendo, haciendo un paso o un dump), guarda **un** byte recibido en un registro de pendiente y lo atiende como comando al volver a reposo. Un segundo byte con el pendiente ocupado se descarta y prende el LED de overrun. Esto hace que dos comandos de un byte enviados sin pausa se atiendan los dos.
3. Durante `L` (fase de datos) todos los bytes son datos de programa, no comandos.
4. Durante `R`, el byte `A` aborta; **cualquier otro byte se descarta** (no va al pendiente).
5. `A` fuera de `R` se descarta sin respuesta (también si llega al pendiente). Así un `A` que se cruza con el final natural de `R` no produce una respuesta extra.
6. Un byte con error de framing no llega a la Debug Unit (se descarta en `uart_rx`, D-08); solo prende el LED de framing.

## 3. Comandos

| Cmd | Byte | El host envía después | La placa responde |
| --- | --- | --- | --- |
| Versión | `V` 0x56 | — | 6 bytes: `56 01 00 01 00 01` (ver §4) |
| Reset del CPU | `X` 0x58 | — | `4B` (`K`) |
| Cargar programa | `L` 0x4C | `N` (2 bytes LE), espera `K`, luego `N` palabras (4 bytes LE c/u) | `K` tras `N`; `K` final tras escribir |
| Un paso | `S` 0x53 | — | dump |
| Ejecutar | `R` 0x52 | — (puede enviar `A`) | dump al parar |
| Abortar | `A` 0x41 | (solo durante `R`) | — (la respuesta es el dump de `R`) |
| Dump | `D` 0x44 | — | dump |
| Otro byte | — | — | `45 01` (`E` + código 01) |

Respuestas cortas: `K` = 0x4B. Error = `E` (0x45) + 1 byte de código. Dump: empieza con 0xA5, formato en [`dump.md`](dump.md).

### Errores

| Código | Significado | Cuándo |
| --- | --- | --- |
| 0x01 | Comando desconocido | Byte en reposo que no es `V X L S R D A` |
| 0x02 | `N` fuera de rango | `N > IMEM_WORDS` (256). Se responde en lugar del primer `K` de `L`; imem no cambia |
| 0x03 | Timeout entre bytes en `L` | Pasan más de `BYTE_TIMEOUT` (100 ms) entre dos bytes esperados de `L` |

## 4. Detalle por comando

### `V` · versión

Respuesta fija de 6 bytes: `0x56`, versión del protocolo (`0x01`), `IMEM_WORDS` en 16 bits LE (`0x00 0x01` = 256), `DMEM_WORDS` en 16 bits LE (`0x00 0x01` = 256). `link.connect()` la usa para verificar que habla con la placa y con la versión correcta.

### `X` · reset del CPU

`cpu_rst` = 1 durante exactamente 1 ciclo. Pone en 0 el contador de ciclos y los bits `timeout`/`aborted` del estado. El reset del CPU borra PC, latches, registros y bits dirty, pero **no imem** ([`interfaz_cpu.md`](interfaz_cpu.md) §3). Responde `K`.

### `L` · cargar programa (dos fases)

1. Host: `4C NL NH` (`N = NH·256 + NL`).
2. Placa: si `N > 256` → `45 02`, vuelve a reposo, imem intacta. Si no → `4B`. Desde que recibe `L` y hasta enviar el `K` final, `cpu_rst` = 1 sostenido.
3. Host: `N` palabras, cada una `b0 b1 b2 b3` (LE). La placa escribe la palabra `i` en `imem[i]` al completar su 4.º byte.
4. Placa: escribe `HALT` (`0x00000073`) en `imem[N..255]`, pone en 0 el contador de ciclos y los bits de estado, suelta `cpu_rst` y responde `4B`.

`N = 0` es válido: llena toda imem con HALT. Timeout: si en los pasos 1 o 3 pasan más de `BYTE_TIMEOUT` entre bytes (el reloj del timeout arranca al recibir `L` y al terminar de enviar el primer `K`), la placa responde `45 03` y vuelve a reposo. En ese caso el contenido de imem queda indefinido y el host debe recargar.

Por qué dos fases: el host se entera de un `N` inválido antes de mandar los datos, y la placa no necesita lógica para descartar un flujo de datos no pedido.

### `S` · un paso

`cpu_en` = 1 durante exactamente un flanco. Si el CPU no estaba en `halted`, el contador de ciclos suma 1. Pone en 0 `timeout`/`aborted`. Responde el dump. Con el CPU en `halted` no cambia nada y el dump es igual al anterior.

### `R` · ejecutar

Pone en 0 `timeout`/`aborted` y mantiene `cpu_en` = 1 hasta la primera de estas condiciones, en este orden de prioridad:

1. `halted` = 1 → para, `halted` en el estado.
2. Llega `A` → para, `aborted` = 1.
3. `cpu_en` estuvo en 1 durante `RUN_TIMEOUT` ciclos en esta corrida → para, `timeout` = 1.

Responde el dump. Si el CPU ya estaba en `halted`, responde el dump enseguida. `RUN_TIMEOUT` = 150 000 000 ciclos en la placa (3 s a 50 MHz); en los TB se reduce por parámetro.

### `D` · dump

Responde el dump sin tocar el CPU.

## 5. Parámetros (nombres exactos)

| Nombre | Placa | TB (`tb_debug_*`) | Dónde |
| --- | --- | --- | --- |
| `CLOCK_FREQ` | 50 000 000 | 50 000 000 | `system`, `uart_if` |
| `BAUD_RATE` | 115 200 | `CLOCK_FREQ / 32` = 1 562 500 | `system`, `uart_if` |
| `BYTE_TIMEOUT` (ciclos) | `CLOCK_FREQ / 10` | 20 000 | `debug_unit` |
| `RUN_TIMEOUT` (ciclos) | 150 000 000 | 1 000 | `debug_unit` |
| `IMEM_WORDS` | 256 | 256 | fijo |
| `DMEM_WORDS` | 256 | 256 | fijo |

## 6. Timeouts del host (`link.py`)

| Respuesta | Timeout |
| --- | --- |
| `V`, `X`, primer `K` de `L` | 200 ms |
| `K` final de `L` | 200 ms + 4·N·87 µs |
| Dump de `S` o `D` | 500 ms |
| Dump de `R` | 4 s (cubre `RUN_TIMEOUT` + el dump) |

## 7. Transacciones de ejemplo (vectores de test)

Notación: `>` lo que manda el host, `<` lo que responde la placa, bytes en hex. B-10, B-13, B-16 y B-23 usan exactamente estos vectores.

```
# V
> 56
< 56 01 00 01 00 01

# X
> 58
< 4B

# comando desconocido
> 7A
< 45 01

# L con N = 2: addi x1,x0,5 (0x00500093) y halt (0x00000073)
> 4C 02 00
< 4B
> 93 00 50 00  73 00 00 00
< 4B

# L con N = 257
> 4C 01 01
< 45 02

# L cortado: N = 1 y solo 2 bytes de la palabra, luego 100 ms de silencio
> 4C 01 00
< 4B
> 93 00
< 45 03

# S, D, R: la respuesta es un dump (ver ejemplos en dump.md)
> 53
< A5 ...

# R con A
> 52
> 41          (en cualquier momento antes del dump)
< A5 ...      (estado con aborted = 1)
```
