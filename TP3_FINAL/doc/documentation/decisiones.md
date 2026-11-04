# Decisiones aplicadas a la memoria de datos

Este archivo registra cómo se aplican en A-09 las decisiones [D-17, D-18 y D-19](../../../planning/_fuentes/documentacion_companero/decisiones.md). No establece un contrato nuevo. La explicación general del milestone A-M02 se escribirá después de A-11.

| Decisión | Aplicación en `dmem.v` |
|---|---|
| D-17: 256 palabras de 32 bits y wrap | `i_addr[9:2]` elige la palabra. `i_addr[31:10]` se ignora. Por ejemplo, 0 y 1024 acceden a la misma palabra. |
| D-18: accesos desalineados sin excepción | `sb/lb/lbu` usan `i_addr[1:0]`; `sh/lh/lhu` usan `i_addr[1]` e ignoran bit 0; `sw/lw` ignoran ambos bits bajos. Un acceso nunca cruza a la siguiente palabra. |
| D-19: estado lógico tras reset | El reset síncrono limpia `dirty`, sin borrar el array físico. Una palabra limpia se lee como cero y un store parcial parte de cero. |

## Interfaz local de A

`dmem.v` recibe `i_addr` en bytes, `i_store_data`, `i_funct3`, `i_we`, `i_en`, `i_reset` e `i_clock`. `i_funct3` conserva el código RISC-V: 000 byte con signo o `sb`, 001 half con signo o `sh`, 010 word o `sw`, 100 byte sin signo y 101 half sin signo. Los stores solo aceptan 000/001/010; otros valores no escriben. `o_load_data` es combinacional. El puerto debug recibe un **índice de palabra** de 8 bits y devuelve dato lógico y dirty; A-10 dedicará una prueba exhaustiva a ese puerto.

La escritura local efectiva es `i_en && i_we && !i_reset && tamaño_store_válido`. En A-16, `cpu.v` deberá suministrar `i_en = w_adv` y `i_we = w_valid_mem && w_mem_write_mem`, ambos de la misma etapa MEM que dirección, dato y `funct3`. El CPU será responsable de filtrar burbujas y congelamiento; `dmem` aplica además reset y validez del tamaño. El puerto debug público de `cpu_ports.vh` se conectará al puerto local en A-31.

La palabra física y el vector de dirty están en procesos `always @(posedge i_clock)` separados, con un solo almacenamiento asignado por proceso. Una carga o lectura debug no cambia ninguno de ellos. El `casez` de selección usa comodines solo en los bits bajos de dirección, porque el tamaño decide cuáles no importan; los patrones de `funct3` son explícitos.

La política de signo se aplica después de escoger el byte o half de la palabra little endian. Así, sobre `0x11223344`, los bytes de direcciones 0 a 3 son `44`, `33`, `22`, `11`. Si el byte elegido es `0x80`, `lb` entrega `0xFFFFFF80` y `lbu` `0x00000080`.
