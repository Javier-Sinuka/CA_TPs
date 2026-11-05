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

## A-12: representación local de los registros de pipeline

Se aplica la prioridad `reset > conservar sin enable > flush > stall > captura` prevista por A-12. El reset pone todos los campos a cero. El flush borra `valid` y controles, pero conserva PC, datos, identificadores de registros y `funct3` para facilitar inspección. Una captura con `i_valid=0` actualiza esos datos e identificadores y fuerza todos los controles a cero. Esta es la concreción interna de la política de burbujas que A-12 pide documentar; no modifica puertos públicos ni posiciones del dump de B.

Cada campo almacenado tiene un proceso secuencial propio. Los operandos de ID/EX son los capturados en ID; el forwarding futuro usará conexiones separadas. `uses_rs1/uses_rs2` solo se almacenan en ID/EX para identificar consumidores reales y no ocupan bits de `info`. Las tres palabras `o_info` son concatenaciones combinacionales de los campos presentes; no se añaden registros ni se llevan campos ausentes a etapas posteriores. El detalle de campos y selectores está en [datapath §12](00_datapath.md#12-registros-de-pipeline-implementados-en-a-12).

## A-13: integración inicial de fetch

El primer `cpu.v` contiene solo el PC y `u_if_id`, con un mismo permiso de avance. El PC público es byte y no se trunca al índice de imem. El header público `cpu_ports.vh` y la memoria de B permanecen en su worktree: se incorporan como referencias externas en el proyecto y como dependencias del runner.

Se exponen los campos ya existentes mediante los selectores 0, 1 y el bit 0 de 15; los campos y salidas aún no implementados se conectan a cero, sin emular el stub. La implementación completa de flags/debug corresponde a A-30. No hay detección de HALT, stall ni redirección en esta versión: [datapath §13](00_datapath.md#13-if-implementada-en-a-13-pc-y-captura-de-instrucciones) documenta dónde deberán integrarse y qué prioridades conservar.

## A-14: módulo ID y arnés con WB independiente

`decode_stage` encapsula los bloques ya auditados y es la única implementación de ID tanto para `cpu.u_decode` como para `tb_decode_stage`. Su interfaz interna permite controlar WB, flush y stall en pruebas sin añadir puertos al CPU público ni forzar registros desde el TB. El CPU conserva señales WB nulas hasta A-16; no se implementa commit anticipadamente.

Se mantienen separados encoding y ocupación como pide A-14: controles y consumo efectivos usan `i_valid_id && w_valid_instr_id`, mientras ID/EX transporta `i_valid_id` como ocupación. Una instrucción no soportada no produce efectos ni una nueva excepción; el tratamiento del retiro se revisará al integrar WB. Reset/flush/captura inválida mantienen la política de A-12. WB válido puede completar su escritura durante un stall/flush de una instrucción más joven, pero la pausa global o reset lo impiden.

Los selectores 2…6 y valid EX del debug parcial ahora muestran los registros de ID/EX. Los operandos siguen siendo los capturados y el layout de B no cambia. La estructura, los permisos y los límites actuales se detallan en [datapath §14](00_datapath.md#14-id-implementada-en-a-14-decode-regfile-e-idex).

## A-15: resultado EX separado del destino de salto

`execute_stage` encapsula ALU y EX/MEM para reutilizar exactamente el mismo circuito en CPU y arnés. LUI selecciona el inmediato U completo; JAL/JALR seleccionan PC EX+4; las demás operaciones seleccionan ALU. El dato de store proviene del segundo registro antes del mux de inmediato. Los operandos `w_rs1_fwd_ex/w_rs2_fwd_ex` del CPU preparan la conexión de forwarding y hoy equivalen a los datos capturados.

El enlace y la salida de ALU son señales separadas. No se implementan todavía destino definitivo, condición de branch, `take_ex`, alineación JALR ni redirección; A-24/A-25 conservan ese alcance. EX/MEM aplica la política de A-12 y el debug agrega solo los campos existentes de MEM. El detalle está en [datapath §15](00_datapath.md#15-ex-implementada-en-a-15-cálculo-y-captura-exmem).
