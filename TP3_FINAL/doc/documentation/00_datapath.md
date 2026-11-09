# Datapath del procesador RISC-V segmentado

Este documento explica el [diagrama del datapath](../diagramas/datapath.svg) del trabajo final. Describe **qué hace cada bloque, qué información conserva cada registro intermedio y por qué existen los caminos de retorno y las señales de control**. Es una descripción de arquitectura previa al código RTL: donde la consigna y el diagrama todavía no fijan una política concreta, se indica expresamente.

![Diagrama del datapath RV32I](../diagramas/datapath.svg)

## 1. Alcance y lectura del dibujo

El procesador implementará el subconjunto de 32 instrucciones RV32I pedido por la cátedra (aritmética, lógica, cargas, stores, `beq`, `bne`, `jal`, `jalr` y `lui`), más una instrucción de parada codificada como `0x00000073` (`ECALL`). RV32I significa registros y direcciones de **32 bits**. Las instrucciones tienen **32 bits** y, en este subconjunto, cada instrucción ocupa **4 bytes**.

La línea azul superior es el recorrido principal de una instrucción: **IF → ID → EX → MEM → WB**. Los bloques verdes son registros físicos: PC y los cuatro registros intermedios. Los bloques azules calculan una función de sus entradas durante el ciclo. Las líneas discontinuas son caminos de retorno o control: no representan una instrucción retrocediendo de etapa. Los bloques amarillo y violeta representan, respectivamente, el control de riesgos y la Debug Unit.

El pipeline permite que varias instrucciones estén activas simultáneamente, cada una en una etapa distinta. Una instrucción no completa las cinco etapas en un único ciclo: avanza al siguiente registro intermedio en cada flanco habilitado. Una vez lleno el pipeline, idealmente puede terminar una instrucción por ciclo; los stalls y los saltos reducen ese ritmo.

> **Decisión acordada:** memorias pequeñas con lectura asíncrona. La dirección cambia durante un ciclo y, después del retardo combinacional, aparece el dato en ese mismo ciclo. Las escrituras siguen ocurriendo en un flanco de clock. Esto permite representar IF y MEM como en el pipeline clásico de cinco etapas. La capacidad exacta de cada memoria todavía debe fijarse.

## 2. Clock, avance y significado de «un paso»

Todo el sistema usa el mismo clock de la FPGA. La Debug Unit **no corta, combina ni genera pulsos de clock** para mover al CPU. En cambio, entrega `cpu_en`. Definimos conceptualmente:

```text
adv = cpu_en && !halted
```

Cuando `adv = 1`, el PC y los registros intermedios pueden actualizarse en el siguiente flanco. Cuando `adv = 0`, conservan su estado. También se condicionan con `adv` las escrituras arquitectónicas: banco de registros y memoria de datos. Así, pausar el CPU no repite un store ni una escritura de registro. El reset síncrono tiene prioridad sobre `adv` y permite salir del estado `halted` para ejecutar otro programa.

**Un paso avanza un ciclo de pipeline, no una instrucción completa.** Si una instrucción está en ID y otra en MEM, ambas avanzan a la vez con ese paso. En el siguiente paso la primera estará en EX y la segunda en WB, salvo que intervenga un stall, flush o HALT. Esta distinción será importante en la interfaz de usuario.

## 3. IF: búsqueda de instrucción

### PC y selección del próximo PC

El **program counter** (`PC`) guarda la dirección en bytes de la instrucción que se busca. Durante la ejecución normal, el candidato siguiente es `PC + 4`, porque cada instrucción ocupa cuatro bytes. Si EX determina que corresponde un salto, se selecciona su **destino** en lugar de `PC + 4`. Si hay un stall o se detuvo el fetch por HALT, el PC conserva su valor. La prioridad concreta de reset, salto y stall se fijará en la lógica de control; un salto válido de una instrucción anterior debe poder descartar un HALT especulativo posterior.

El «PC» del dibujo reúne el registro y la selección de su entrada. Al bajar a RTL, probablemente se verán como el registro `pc_if`, un sumador `+4` y un multiplexor `pc_next`.

### Memoria de programa (`imem`)

La memoria recibe una dirección de instrucción. Como cada entrada guarda una palabra de 32 bits, la lectura conceptual es `imem[PC >> 2]`: los dos bits menos significativos de una dirección alineada valen cero. El dato sale de forma combinacional. La Debug Unit dispondrá de **un camino de escritura independiente** para cargar el programa por UART mientras el CPU esté detenido. Cargar otro programa no exige resintetizar la FPGA.

Aún debemos definir el tamaño, el comportamiento de una dirección fuera de rango y cómo impedir que queden instrucciones antiguas accesibles después de cargar un programa más corto. Estas decisiones importan especialmente si el programa no contiene HALT.

### IF/ID

En el flanco habilitado, el registro `IF/ID` captura el **PC de la instrucción**, sus 32 bits y un bit `valid`. Ese PC debe acompañar a la instrucción: más adelante se usa para `PC + 4`, destinos relativos de branch/`jal` y para mostrar dónde está cada instrucción.

`valid = 0` identifica una **burbuja**: la etapa no contiene una instrucción que pueda producir efectos. Un flush invalida la instrucción que estaba entrando; un stall conserva la que ya estaba en IF/ID. Poner una codificación `nop` en el campo de instrucción ayuda a leer las ondas, pero el bit `valid` es la autoridad para saber si la etapa está ocupada.

## 4. ID: decodificación y lectura de operandos

La etapa ID interpreta los campos de la instrucción: `opcode`, `funct3`, `funct7`, `rd`, `rs1` y `rs2`, según su formato. Tres subbloques trabajan en paralelo:

1. **Decodificador/control.** Determina qué operación realizará EX, si la instrucción usa `rs1` o `rs2`, si leerá/escribirá memoria, si escribirá `rd`, si es branch, jump o HALT. Las señales que producirían efectos se anulan cuando `valid = 0`.
2. **Banco de registros.** Contiene 32 registros de 32 bits. Dos puertos permiten leer `rs1` y `rs2`; un puerto permite escribir `rd` en WB. `x0` siempre se lee como cero e ignora escrituras. Habrá un puerto de lectura adicional para depuración. Si WB escribe un registro que ID lee en el mismo ciclo, un bypass local deberá ofrecer el dato nuevo sin recurrir a un flanco negativo del clock.
3. **Generador de inmediatos.** Reconstruye y extiende a 32 bits el inmediato de los formatos I, S, B, J o U. En B y J los bits del desplazamiento están repartidos dentro de la instrucción; el generador los reordena y coloca el bit bajo cero. En I/S/B/J, el bit 31 de la instrucción determina la extensión de signo. Para `lui`, los 20 bits altos se colocan en `[31:12]` y los 12 bajos son cero.

Las señales `uses_rs1` y `uses_rs2` son necesarias para detectar riesgos reales. No basta comparar números de campos: en algunas instrucciones los bits que ocuparían `rs2` forman parte de un inmediato y no designan un registro leído.

### ID/EX

`ID/EX` conserva el PC, los dos operandos leídos, el inmediato, los identificadores `rs1`, `rs2`, `rd`, las señales de control y `valid`. Llevar los identificadores permite que la unidad de forwarding compare dependencias en EX. Si el control inserta una burbuja, deben quedar apagadas `reg_write`, `mem_write`, `branch`, `jump`, `halt` y cualquier otra señal con efecto. Los valores numéricos de una burbuja pueden ser irrelevantes, pero su control y `valid` no.

## 5. EX: cálculo, forwarding y saltos

### Selección de operandos

EX necesita dos valores actuales. Antes de usarlos, los multiplexores de **forwarding** pueden sustituir cada valor antiguo de `ID/EX`:

- Desde `EX/MEM`, cuando una instrucción anterior ya calculó su resultado. Esta vía **no entrega el dato de un load**, que aún no estaba disponible al salir de EX.
- Desde `MEM/WB`, cuando el resultado ya está listo para escribirse, incluido el dato de un load.
- Del valor guardado en `ID/EX`, si no existe una dependencia más reciente.

Si ambas vías coinciden con el mismo registro destino, gana `EX/MEM`: corresponde a la instrucción más nueva. Nunca se reenvía una escritura destinada a `x0`.

El forwarding se aplica **antes** de elegir entre el segundo registro y el inmediato para la ALU. Así el valor actualizado de `rs2` también sirve como dato de `store` y para comparar en `beq`/`bne`. Por ejemplo, `addi x5,x0,7` seguido de `sw x5,0(x0)` debe escribir 7.

### ALU y resultado

La ALU realizará suma, resta, desplazamientos lógicos y aritméticos, AND, OR, XOR y comparaciones con y sin signo. El desplazamiento toma los cinco bits bajos de la cantidad; una comparación con signo no equivale a una comparación entre palabras sin signo. En cargas y stores, la ALU suma `rs1 + inmediato` para obtener la dirección efectiva.

El resultado que avanza hacia `EX/MEM` puede venir de distintos cálculos:

- Aritmética/lógica: salida de la ALU.
- `lui`: inmediato U (equivalente a sumar cero + inmediato).
- `jal`/`jalr`: **PC de esa instrucción + 4**, que se escribe en `rd` como dirección de retorno.

Un único campo «resultado» simplifica las etapas posteriores y el forwarding. La operación exacta de la ALU debe decodificarse según el tipo de instrucción: el bit 30 distingue `sub` de `add` en tipo R, pero en `addi` puede ser simplemente parte de un inmediato negativo.

### Branch y jump

`beq` y `bne` comparan los operandos ya corregidos por forwarding. Si se toma un branch, el destino es **PC de la instrucción en EX + inmediato B**. `jal` también usa **PC + inmediato J**. `jalr` usa **(`rs1` reenviado + inmediato I) & ~1**; limpia el bit cero del destino. `jal` no salta a la dirección guardada en `rd`: guarda allí la dirección de retorno.

Resolver saltos en EX simplifica la comparación y el forwarding, pero cuando se conoce la decisión ya pudieron entrar dos instrucciones posteriores. Si se toma el salto, se invalidan IF/ID e ID/EX; ninguna de esas instrucciones puede escribir registros o memoria.

### EX/MEM

Conserva PC, resultado, dato de `store` ya reenviado, `rd`, control y `valid`. El dato de `store` debe viajar por separado de la dirección: en `sw x5,0(x1)`, la ALU calcula la dirección a partir de `x1`, mientras que la memoria escribe el valor de `x5`.

## 6. MEM: acceso a memoria de datos

La memoria de datos se organiza como palabras de 32 bits con **cuatro carriles de byte**. La dirección calculada en EX selecciona una palabra y, mediante sus bits `[1:0]`, un byte dentro de ella. Una lectura entrega combinacionalmente la palabra durante MEM; luego se selecciona y extiende el fragmento solicitado:

| Instrucción | Datos devueltos |
|---|---|
| `lb` / `lh` | Byte / media palabra extendidos con signo a 32 bits |
| `lbu` / `lhu` | Byte / media palabra extendidos con ceros |
| `lw` | Palabra completa de 32 bits |

Los stores escriben en el flanco y habilitan solo los carriles correspondientes: uno para `sb`, dos para `sh`, cuatro para `sw`. La escritura requiere `adv`, `valid` y `mem_write`. Se asume el orden **little-endian** de RISC-V: el byte de menor peso se ubica en la dirección menor.

El dibujo supone accesos alineados: `lh`/`sh` en direcciones pares y `lw`/`sw` en múltiplos de cuatro. **Todavía no fijamos la respuesta ante un acceso desalineado**; no se debe interpretar este dibujo como una promesa de ignorar silenciosamente los bits bajos. También falta definir la capacidad, el valor inicial de la RAM y el mecanismo concreto para identificar la «memoria usada» que se enviará a la PC. Una posibilidad es marcar con un bit `dirty` cada palabra escrita, pero no es una decisión tomada.

### MEM/WB

Conserva PC, el resultado procedente de EX, el dato leído/extendido de memoria, `rd`, el control necesario para WB y `valid`. Se transportan ambos valores porque WB elegirá cuál corresponde a la instrucción. Si no hay load, el dato leído es irrelevante; si sí lo hay, la selección debe tomarlo.

## 7. WB: resultado arquitectónico

Un multiplexor escoge entre el **resultado de EX** y el **dato del load**. Si `valid`, `reg_write` y `adv` lo permiten, escribe ese valor en `rd` durante el flanco. Las instrucciones `store`, branch y HALT no escriben el banco. `x0` continúa valiendo cero incluso si una instrucción lo nombra como destino.

La flecha de WB a ID representa esa escritura y el bypass local del banco. La flecha de WB a EX representa forwarding: el mismo dato que se escribirá puede ser necesario para una instrucción más joven que ya está en EX.

## 8. Unidad de riesgos y control del avance

Esta unidad observa lo que hay en las etapas y decide **qué se actualiza** en el próximo flanco. Hay tres situaciones principales:

| Situación | PC | IF/ID | ID/EX | Instrucciones más antiguas |
|---|---|---|---|---|
| Avance normal | `PC + 4` | Captura la siguiente | Captura lo decodificado | Avanzan |
| Dependencia inmediata de un load | Conserva PC | Conserva su instrucción | Introduce burbuja | El load y las anteriores avanzan |
| Salto tomado en EX | Carga destino | Se invalida | Se invalida | El salto y las anteriores avanzan |
| HALT válido en ID | Deja de buscar nuevas | Se invalida mientras drena | HALT avanza una vez | Las anteriores terminan |

**Load-use.** Si en EX hay un load que escribirá `rd`, y la instrucción válida en ID realmente usa ese registro como `rs1` o `rs2`, forwarding no alcanza: el dato de memoria aparece durante MEM, demasiado tarde para el EX inmediato de la consumidora. Se retienen PC e IF/ID un ciclo y se inserta una burbuja en ID/EX. Al ciclo siguiente, el dato puede venir desde MEM/WB. Una dependencia a distancia mayor suele resolverse con forwarding o con el bypass del banco.

**Flush por salto.** Cuando EX decide tomar un branch o ejecutar `jal`/`jalr`, el PC recibe el destino y se invalidan las instrucciones jóvenes. El salto sigue avanzando; no se «rebobina» ninguna instrucción antigua.

**HALT y drenado.** HALT se reconoce por la palabra exacta `0x00000073` (`ECALL`). La idea es reconocerla en ID, impedir nuevas entradas y dejarla recorrer EX, MEM y WB sin efectos sobre registros ni memoria. Cuando HALT llega válidamente a WB, las instrucciones anteriores ya terminaron; los registros intermedios anteriores deben tener `valid = 0`, y se activa `halted`. Si un salto más antiguo tomado descarta ese HALT antes de comprometerlo, el CPU no debe detenerse.

La prioridad de señales debe implementarse y probarse de forma explícita. Conceptualmente, **reset > actualización habilitada > resolución de salto/flush > stall ordinario**; el caso de HALT especulativo detrás de un salto exige que el salto gane. Esta frase expresa una regla de diseño, no sustituye la tabla de verdad detallada que haremos al codificar.

## 9. Debug Unit y carga de programa

La Debug Unit está fuera del datapath principal, pero lo controla y lo observa. Recibe comandos por UART desde la PC para:

- Escribir palabras en la memoria de programa con el CPU detenido.
- Emitir un pulso de reset del CPU y decidir cuándo `cpu_en` vale 1.
- Leer el PC, los 32 registros, los campos de IF/ID, ID/EX, EX/MEM y MEM/WB, y la memoria de datos utilizada.
- Informar `halted` y devolver el estado tras cada paso o al acabar la ejecución continua.

El dibujo resume esos puertos para mantener legible el recorrido principal. No muestra byte por byte el protocolo UART; ese contrato debe documentarse aparte. En modo continuo se necesita además un límite o mecanismo de recuperación si el programa no alcanza HALT, para que la interfaz no espere para siempre.

**Reprogramar** exige, como mínimo, impedir que queden instrucciones antiguas en vuelo: resetear PC y registros intermedios antes de arrancar el programa nuevo. Si también se limpian registros generales, memoria de datos, marcas de uso y posiciones sobrantes de la memoria de programa es una política que debemos fijar antes de implementar la carga. El reset del CPU del diagrama **no implica** borrar automáticamente `imem`.

## 10. Ejemplo temporal breve

Para `addi x1,x0,5` seguida de `add x2,x1,x1`, sin stalls y suponiendo que ambas instrucciones son válidas:

| Ciclo | Primera instrucción | Segunda instrucción | Punto importante |
|---|---|---|---|
| 1 | IF | — | Se busca `addi` |
| 2 | ID | IF | `addi` lee `x0` |
| 3 | EX | ID | `addi` calcula 5; `add` aún puede leer el valor viejo de `x1` |
| 4 | MEM | EX | Forwarding desde EX/MEM sustituye ambos operandos de `add` por 5 |
| 5 | WB | MEM | Se escribe `x1 = 5` |
| 6 | — | WB | Se escribe `x2 = 10` |

Si la primera fuese `lw x1,0(x0)`, en el ciclo 3 `add` no podría pasar a EX inmediatamente: habría un ciclo de stall. El dato del load se obtendría en MEM y luego llegaría a EX mediante la vía de MEM/WB.

## 11. Decisiones que aún revisaremos juntos

Estas cuestiones aparecen en el diagrama o afectan su implementación, pero **no están cerradas**:

1. Capacidad de `imem` y `dmem`, y comportamiento de direcciones fuera de rango.
2. Tratamiento de instrucciones ilegales más allá de inhibir sus efectos arquitectónicos.
3. Política para accesos de datos desalineados.
4. Qué se limpia al cargar un programa nuevo y cómo se evita ejecutar restos del programa anterior.
5. Mapa exacto del puerto de depuración y de las palabras de cada latch.
6. Protocolo UART, formato del dump y límite de ciclos sin HALT.
7. Mecanismo para identificar y mostrar la memoria de datos usada.

Las decisiones ya fijadas para este dibujo son: **pipeline de cinco etapas**, **saltos resueltos en EX**, **forwarding y stall load-use**, **un solo clock con habilitación**, **memorias pequeñas de lectura asíncrona** y **HALT = `0x00000073`**. La síntesis y la temporización de Vivado permitirán comprobar más adelante si el tamaño elegido es apropiado.

## 12. Registros de pipeline implementados en A-12

Actualización del 2026-11-04: las secciones anteriores describen el diseño inicial. Los contratos posteriores resolvieron capacidad, alineación, dirty e interfaz, como explica [02 — Estado y memorias](02_estado_y_memorias.md). A-12 implementa los cuatro registros por flanco; al cerrar esa issue todavía no existía el CPU que conecta sus etapas. La [evidencia de A-12](../validation/A-12.md) registra las pruebas y la síntesis aislada. La sección 13 describe el fetch incorporado después en A-13.

```mermaid
flowchart LR
    IF[IF: PC e instrucción] --> IFID[if_id: 65 bits]
    IFID --> ID[ID: decode, regfile e inmediato]
    ID --> IDEX[id_ex: 163 bits]
    IDEX --> EX[EX: operandos, ALU y salto]
    EX --> EXMEM[ex_mem: 110 bits]
    EXMEM --> MEM[MEM: dmem]
    MEM --> MEMWB[mem_wb: 105 bits]
    MEMWB --> WB[WB: selección y escritura]
    IDEX -. info_ex .-> DBG[Debug futuro: selector A-30]
    EXMEM -. info_mem .-> DBG
    MEMWB -. info_wb .-> DBG
```

Los bloques `if_id`, `id_ex`, `ex_mem` y `mem_wb` son módulos implementados en `rtl/`. IF, ID, EX, MEM, WB y el selector del dibujo representan sus futuros consumidores/productores. Cada campo tiene su propio `always @(posedge i_clock)`, almacenamiento `r_<campo>` y salida `o_<campo>`. En el CPU se conectarán como `w_<campo>_id/ex/mem/wb`. No hay registros transparentes ni un clock diferente para cada etapa.

### Campos, procedencia y uso

| Registro | Campo almacenado y ancho | Productor previsto | Consumidor previsto | Selector debug |
|---|---|---|---|---|
| IF/ID | `pc[31:0]`, `instr[31:0]` | PC y lectura de imem en IF | Decode en ID; PC de la instrucción | 0, 1 |
| IF/ID | `valid` | Permiso de entrada desde IF | Ocupación de ID; controles efectivos | 15, bit 0 |
| ID/EX | `pc[31:0]` | IF/ID | Destinos relativos y enlace PC+4 en EX | 2 |
| ID/EX | `rs1_data[31:0]`, `rs2_data[31:0]` | Lecturas de regfile en ID, incluido bypass WB→ID | Entradas anteriores a forwarding en EX | 3, 4 |
| ID/EX | `imm[31:0]` | `imm_gen` en ID | ALU y cálculo de destino en EX | 5 |
| ID/EX | `rd[4:0]`, `rs1[4:0]`, `rs2[4:0]` | Campos de instrucción en ID | Destino y comparación de dependencias | 6, bits 4:0, 9:5, 14:10 |
| ID/EX | `funct3[2:0]`, `alu_op[3:0]` | Instrucción y `control` en ID | Tamaño de memoria, branch y ALU | 6, bits 17:15, 21:18 |
| ID/EX | `alu_src_b`, `mem_read`, `mem_write`, `mem_to_reg`, `reg_write`, `branch`, `jump`, `jalr`, `lui`, `halt` | `control` en ID | EX y controles que siguen a MEM/WB | 6, bits 22…31 en ese orden |
| ID/EX | `uses_rs1`, `uses_rs2` | `control` en ID | Habilitar comparación de dependencias de las fuentes en EX | Sin campo en `info` |
| ID/EX | `valid` | Ocupación transferida de ID | Validez de EX | 15, bit 1 |
| EX/MEM | `pc[31:0]`, `result[31:0]`, `store_data[31:0]` | PC y resultado arquitectónico de EX; rs2 forwardeado para store | Dirección/dato de dmem y bypass desde MEM | 7, 8, 9 |
| EX/MEM | `rd[4:0]`, `funct3[2:0]` | ID/EX | Destino WB y tamaño del acceso MEM | 10, bits 4:0, 17:15 |
| EX/MEM | `mem_read`, `mem_write`, `mem_to_reg`, `reg_write`, `halt` | ID/EX | Acceso MEM y controles que siguen a WB | 10, bits 23, 24, 25, 26, 31 |
| EX/MEM | `valid` | Ocupación transferida de EX | Validez de MEM | 15, bit 2 |
| MEM/WB | `pc[31:0]`, `result[31:0]`, `load_data[31:0]` | EX/MEM y load extendido de dmem | Selección WB; PC de HALT | 11, 12, 13 |
| MEM/WB | `rd[4:0]`, `mem_to_reg`, `reg_write`, `halt` | EX/MEM | Destino, selección WB y detección de HALT | 14, bits 4:0, 25, 26, 31 |
| MEM/WB | `valid` | Ocupación transferida de MEM | Validez de WB | 15, bit 3 |

Los selectores son el mapa de conexión para A-30, no un mux implementado en A-12. Los selectores 3 y 4 mostrarán los operandos **capturados**; los futuros `w_rs1_fwd_ex` y `w_rs2_fwd_ex` son conexiones combinacionales separadas. `uses_rs1/uses_rs2` son controles internos de EX y no se añaden al dump. No se transportan rs1, rs2 ni controles de salto hasta MEM/WB para rellenar campos que el contrato declara ausentes.

### Prioridades y representación de burbujas

Los cuatro módulos reciben `i_reset`, `i_en`, `i_flush`, `i_stall` e `i_valid`. El CPU conectará `i_en` a `w_adv`; los permisos locales de flush/stall dependerán de la etapa. En particular, un load-use no deberá detener EX/MEM ni MEM/WB.

| Condición al flanco | PC, datos e identificadores | `valid` y controles |
|---|---|---|
| `i_reset=1`, con cualquier otro permiso | Cero | Cero |
| Sin reset, `i_en=0` | Conservan | Conservan, aunque flush/stall estén activos |
| `i_en=1`, `i_flush=1` | Conservan | Cero, incluso si también hay stall |
| `i_en=1`, sin flush, `i_stall=1` | Conservan | Conservan |
| Captura normal, `i_valid=1` | Capturan sus entradas | Capturan sus entradas |
| Captura normal, `i_valid=0` | Capturan sus entradas | Cero |

En esta tabla, identificadores incluye `rd`, `rs1`, `rs2` y `funct3`; controles incluye `alu_op`, `alu_src_b`, `uses_rs1/uses_rs2` y todas las señales booleanas de efectos. Una burbuja conserva o captura datos según su origen, pero siempre tiene `valid=0` y controles apagados. Por eso su palabra `info` puede contener identificadores distintos de cero. No se ocultan las salidas con `valid`: el debug conserva la representación almacenada.

### Palabras `info` sin almacenamiento adicional

`id_ex`, `ex_mem` y `mem_wb` ofrecen `o_info[31:0]` mediante concatenación combinacional de sus registros. El layout es el de [dump §3.1](../../../planning/_fuentes/documentacion_companero/dump.md); `o_info` no agrega otro flop. EX incluye los campos definidos en el contrato. MEM solo permite bits de la máscara `0x8783801F`; WB solo permite `0x8600001F`. Los bits restantes están conectados a cero. El selector 15 y sus flags globales se implementarán con el CPU; A-12 solo aporta los cuatro bits de validez de etapa.

## 13. IF implementada en A-13: PC y captura de instrucciones

`cpu.v` declara la interfaz pública mediante el `cpu_ports.vh` original de B. Al cerrar A-13 integraba únicamente `r_pc_if` y una instancia `u_if_id`; las etapas ID/EX/MEM/WB todavía no se conectaban. La [evidencia A-13](../validation/A-13.md) distingue las pruebas de fetch de la futura ejecución de programas. La sección 14 describe la integración posterior de ID.

```mermaid
flowchart LR
    PC[r_pc_if: PC byte de 32 bits] --> ADD[PC + 4]
    ADD -->|flanco con w_adv| PC
    PC --> OUT[o_imem_addr y o_dbg_pc]
    OUT --> IDX[Selección externa de bits 9:2]
    IDX --> IMEM[imem de B: 256 palabras]
    IMEM -->|i_imem_data combinacional| IFID[u_if_id]
    PC -->|PC del mismo fetch| IFID
    IFID --> ID[w_pc_id, w_instr_id, w_valid_id]
    ID --> DBG[Lectura debug parcial]
```

En cada flanco con `w_adv = i_en && !o_halted`, IF/ID captura el PC **anterior** al flanco y el dato leído en esa dirección; al mismo tiempo, el PC de IF recibe PC+4. Se usan asignaciones no bloqueantes para que la instrucción no quede asociada al PC del siguiente fetch. Reset es síncrono y prioritario, incluso durante pausa: pone PC e IF/ID a cero y `valid_id=0`. Con `i_en=0`, ambos almacenamientos conservan todos sus bits.

| Avance habilitado tras reset | `o_imem_addr` después del flanco | `w_pc_id` | `w_instr_id` en el TB |
|---|---|---|---|
| 1 | `0x00000004` | `0x00000000` | `0x00500093` |
| 2 | `0x00000008` | `0x00000004` | `0x00A00113` |
| 3 | `0x0000000C` | `0x00000008` | `0x002081B3` |

La dirección pública conserva los 32 bits en bytes. El TB conecta `o_imem_addr[9:2]` a la única `imem` externa de B; CPU no contiene memoria de programa ni un puerto que la borre. Tras alcanzar PC 1024, la memoria vuelve al índice 0 y el PC sigue mostrando 1024. Escribir una instrucción en la memoria mientras el CPU está pausado cambia el dato combinacional de IF y no modifica lo capturado en IF/ID.

Para observar esta etapa desde los puertos públicos, el mux debug parcial usa `casez` con selector conocido: 0 muestra PC ID, 1 muestra instrucción ID y 15 muestra únicamente `valid_id` en bit 0. Los selectores restantes devuelven cero. También quedan en cero `o_halted`, `o_dbg_reg_data`, `o_dbg_mem_data` y `o_dbg_mem_dirty`: sus etapas aún no están implementadas. A-30 completará el mapa debug; estos ceros no representan ejecución ni estado arquitectónico de un CPU completo.

Los puertos flush y stall de `u_if_id` están conectados a cero en A-13. A-22 incorporará la retención común de PC/IFID por load-use; A-25 agregará redirección de PC y flush con prioridad sobre stall; A-27 incorporará `w_stop_fetch` y el drenado de HALT. Esas decisiones deben entrar dentro del guard de avance y respetar el reset prioritario. Todavía no se detiene fetch al leer `0x00000073`.

`cpu.v` y `tb_fetch.sv` están registrados en el proyecto Vivado con tops `cpu` y `tb_fetch`. El proyecto referencia el header de B y su `imem.v` mediante rutas externas; requiere el worktree hermano `TPs-companion`. El runner permite otra ubicación mediante `--companion PATH`:

```bash
python3 TP3_FINAL/tools/run.py tb tb_fetch --companion ../TPs-companion
```

## 14. ID implementada en A-14: decode, regfile e ID/EX

`cpu.v` instancia `decode_stage u_decode` y entrega el PC, la instrucción y la ocupación que salen de IF/ID. Este módulo reúne `control`, `imm_gen`, `regfile` y `id_ex`, sin duplicar sus implementaciones. La separación permite probar ID con WB controlado por el testbench antes de que exista el recorrido completo hasta WB. El CPU usa ese mismo módulo, por lo que el arnés verifica su implementación real.

```mermaid
flowchart LR
    IFID[IF/ID: PC, instrucción y valid] --> ID[decode_stage]
    ID --> CTRL[control con alu_control interno]
    ID --> IMM[imm_gen]
    ID --> RF[regfile: dos lecturas y bypass WB a ID]
    WB[WB: valid, permiso, rd y dato] -.-> RF
    CTRL --> MASK[Controles efectivos]
    ID --> MASK
    MASK --> IDEX[id_ex]
    IMM --> IDEX
    RF --> IDEX
    ID -->|PC e identificadores| IDEX
    IDEX --> EX[Salidas para EX]
    IDEX --> DBG[Debug: selectores 2 a 6]
    RF --> REGDBG[Lectura debug de registros]
```

Los campos se extraen de una única palabra `i_instr_id`: `rs1=[19:15]`, `rs2=[24:20]`, `rd=[11:7]` y `funct3=[14:12]`. `control` e `imm_gen` reciben esa misma instrucción. `i_pc_id` se captura directamente: no se usa el PC actual de IF ni se añade 4. Las salidas `o_*_ex` del módulo se conectan como `w_*_ex` en el CPU; el almacenamiento sigue perteneciendo a `u_decode.u_id_ex`.

### Ocupación, encoding y consumo de fuentes

`w_decode_effective_id = i_valid_id && w_valid_instr_id` habilita los controles enviados a ID/EX. Esta condición incluye escritura de registros/memoria, saltos, HALT, selección de ALU y consumo de fuentes. El latch también neutraliza controles en una captura inválida según A-12. Un inmediato conserva sus bits crudos de `rs2` para debug, pero `uses_rs2=0` impide tratarlo como una dependencia real.

`o_valid_ex` conserva la ocupación de ID. Si la instrucción no está soportada, el encoding se rechaza y los controles quedan en cero; el bit de ocupación puede seguir siendo uno. No se añade una excepción ni se decide todavía cómo contabilizar su retiro en WB. Un load reconocido por `control` sigue siendo válido aunque el subdecoder `alu_control` no reconozca su opcode: este último solo decodifica familias R/I-ALU.

Los operandos capturados conservan el resultado de las lecturas de regfile, incluso cuando la instrucción no consume una fuente. Por ejemplo, los bits altos de ADDI pueden seleccionar un registro para la lectura física de rs2; ese dato puede verse en el selector 4, pero no afecta la operación porque `uses_rs2=0`. Los selectores 3/4 siguen mostrando datos capturados y no valores futuros de forwarding.

### Escritura efectiva y bypass WB→ID

`decode_stage` recibe `i_valid_wb`, `i_reg_write_wb`, `i_rd_wb` e `i_wdata_wb`. La escritura requiere avance, ausencia de reset y ambos permisos de WB; `regfile` bloquea además `rd=0`. El bypass entrega el nuevo dato en las lecturas de ID antes del flanco cuando coinciden con esa escritura efectiva. En cambio, debug muestra el dato almacenado anterior hasta que ocurre el flanco.

| Situación | Captura ID/EX | Escritura del WB anterior |
|---|---|---|
| Avance normal | PC, operandos, inmediato, campos y controles coherentes | Se acepta si WB es válido y escribe rd distinto de cero |
| Pausa externa | Conserva todo | Bloqueada |
| Stall local de ID/EX con avance | Conserva todo | Puede completarse |
| Flush local con avance | Invalida y limpia controles; conserva datos | Puede completarse |
| Reset, incluso pausado | Pone todo a cero | Bloqueada; regfile se limpia |

En el CPU de A-14, las señales de WB permanecen conectadas a cero hasta A-16. El arnés `tb_decode_stage` las maneja de forma independiente para validar escritura y bypass reales; esto no representa un commit de un programa ejecutado por el CPU actual. Flush/stall del CPU también siguen desactivados hasta integrar riesgos y saltos. El módulo dispone de esos controles para verificar su comportamiento local desde ahora.

### Observación e integración verificada

El puerto público de registros ahora lee `u_decode.u_regfile`. El mux parcial agrega selectores 2=PC EX, 3=rs1 capturado, 4=rs2 capturado, 5=inmediato y 6=info EX; el selector 15 presenta valid ID en bit 0 y valid EX en bit 1. Los campos MEM/WB y los flags de riesgos todavía son cero, y `o_halted` continúa en cero.

`tb_decode_stage` prueba las 32 instrucciones más HALT con datos precargados por WB, encodings inválidos, burbujas, colisiones de ambas fuentes, x0, pausa, flush/stall y reset. `tb_fetch` también comprueba el paso IF/ID→ID/EX dentro del CPU contra expectativas independientes de PC, inmediato y controles. [La evidencia A-14](../validation/A-14.md) conserva los resultados y límites.

```bash
python3 TP3_FINAL/tools/run.py tb tb_decode_stage
python3 TP3_FINAL/tools/run.py test --companion ../TPs-companion
```

## 15. EX implementada en A-15: cálculo y captura EX/MEM

`cpu.v` incorpora `execute_stage u_execute`, que recibe las salidas de ID/EX y reúne la ALU auditada con el registro `ex_mem` de A-12. El módulo no añade almacenamiento fuera de ese registro. `tb_execute_stage` controla directamente sus entradas de EX y verifica tanto el resultado combinacional como el paquete capturado para MEM. [La evidencia A-15](../validation/A-15.md) registra resultados, recursos y límites.

```mermaid
flowchart LR
    IDEX[ID/EX: datos, PC y controles] --> RS1[rs1 preparado para forwarding]
    IDEX --> RS2[rs2 preparado para forwarding]
    IDEX --> IMM[Inmediato]
    RS2 --> B[Selección rs2 o inmediato]
    IMM --> B
    RS1 --> ALU[ALU auditada]
    B --> ALU
    IDEX --> LINK[PC EX + 4]
    ALU --> RESULT[Selección del resultado arquitectónico]
    IMM -->|LUI: inmediato completo| RESULT
    LINK -->|JAL y JALR| RESULT
    RESULT --> EXMEM[ex_mem]
    RS2 -->|dato de store independiente| EXMEM
    IDEX -->|PC, rd, funct3, valid y controles MEM| EXMEM
    EXMEM --> NEXT[Salidas para futura MEM]
    EXMEM --> DBG[Selectores debug 7 a 10]
```

### Operandos y selección de resultado

El CPU prepara `w_rs1_fwd_ex` y `w_rs2_fwd_ex`; por ahora son conexiones directas a los operandos capturados. A-M04 sustituirá esa selección con forwarding real. Esas conexiones entran a `u_execute`, mientras los selectores debug 3/4 continúan mostrando los operandos originales de ID/EX.

`i_alu_src_b_ex` selecciona entre rs2 y el inmediato para la segunda entrada de ALU. El dato de store toma rs2 **antes** de ese mux, de modo que un store usa el inmediato para la dirección y conserva el valor del registro como dato. La primera entrada de ALU recibe rs1.

| Operación | Resultado enviado hacia EX/MEM |
|---|---|
| Aritmética, lógica, comparación o dirección de load/store | Salida de `alu` con los operandos seleccionados y `alu_op` de ID/EX |
| LUI | `i_imm_ex` completo; el generador ya colocó los 12 ceros bajos |
| JAL o JALR (`i_jump_ex=1`) | `i_pc_ex + 4`, con aritmética de 32 bits |

El resultado arquitectónico es `u_execute.w_result_ex`, expuesto como `o_result_ex` y capturado como `w_result_mem`. Para LUI no se vuelve a desplazar el inmediato ni se suma el valor físico leído de rs1. El enlace toma el PC de la instrucción en EX: con `PC_EX=0x40`, JAL/JALR producen `0x44` aunque IF esté buscando otra dirección.

`w_link_ex` está separado de `w_alu_result_ex`. En un JALR, la ALU puede tener la suma base+inmediato mientras el resultado de escritura sigue siendo PC+4; el arnés comprueba ambos valores distintos. Esto no implementa todavía el destino definitivo: la selección branch/JAL/JALR, el borrado del bit 0 de JALR y `take_ex` corresponden a A-24, y la redirección/flush a A-25. Un enlace no debe usarse como dirección de salto.

### Paquete hacia MEM y permisos

`u_execute.u_ex_mem` captura PC, resultado, dato de store, rd, funct3 y los controles `mem_read`, `mem_write`, `mem_to_reg`, `reg_write`, `halt`, junto con valid. Su `o_info` conserva la máscara `0x8783801F`; los campos ausentes siguen en cero. Reset, pausa, flush y stall conservan las prioridades de A-12.

Una captura con `valid=0` puede conservar valores de datos, pero anula valid y todos los controles de MEM. El resultado combinacional puede cambiar al cambiar entradas durante una pausa; el estado EX/MEM permanece estable. Eso no es una escritura de memoria: la instancia de dmem y el commit se conectarán en A-16.

El CPU conecta `i_en=w_adv` a EX/MEM y mantiene sus flush/stall locales en cero. Los controles futuros no deben congelar las instrucciones antiguas ante un load-use de etapas jóvenes. Al cerrar A-15, WB seguía conectado a cero; la sección 16 describe su conexión posterior.

El debug parcial ahora incluye 7=PC MEM, 8=resultado MEM, 9=dato de store y 10=info MEM. El selector 15 agrega valid MEM en bit 2; los campos de WB y riesgos siguen pendientes. `tb_fetch` comprueba el recorrido hasta EX/MEM con instrucciones conocidas, incluidos LUI, ADDI negativo y enlaces JAL/JALR, manteniendo avance secuencial porque la redirección aún no se implementó.

```bash
python3 TP3_FINAL/tools/run.py tb tb_execute_stage
python3 TP3_FINAL/tools/run.py tb tb_decode_stage
python3 TP3_FINAL/tools/run.py test --companion ../TPs-companion
```

## 16. MEM/WB implementada en A-16: memoria y commit

`cpu.v` instancia `memory_stage u_memory`, que conecta `dmem` y el registro `mem_wb` ya implementados. Recibe exclusivamente el paquete de EX/MEM: PC, resultado/dirección, dato de store, rd, funct3, valid y controles. El wrapper no agrega almacenamiento fuera de dmem/MEM-WB. [La evidencia A-16](../validation/A-16.md) conserva pruebas de escrituras, programa sin riesgos y reportes de síntesis.

```mermaid
flowchart LR
    EXMEM[EX/MEM: PC, resultado, dato y controles] --> DMEM[dmem: lectura combinacional]
    EXMEM --> STORE[Permiso efectivo de store]
    ADV[Avance y reset] --> STORE
    STORE -->|escritura en flanco| DMEM
    EXMEM --> MWB[mem_wb]
    DMEM -->|dato de load extendido| MWB
    ADV --> MWB
    MWB --> MUX[Selección resultado o load]
    MWB --> COMMIT[Permiso efectivo de escritura de registro]
    ADV --> COMMIT
    MUX --> RF[regfile dentro de decode_stage]
    COMMIT --> RF
    MWB --> WBDBG[Debug WB: selectores 11 a 14]
    DMEM --> MEMDBG[Debug memoria: dato y dirty]
```

### Lectura y escritura en MEM

`w_result_mem` es la dirección byte de dmem; `w_store_data_mem` es el dato del registro fuente y `w_funct3_mem` determina el tamaño. Los tres pertenecen a la misma instrucción en MEM. Se mantiene la política de A-M02: 256 palabras little-endian, índice `[9:2]`, wrap por bits altos, selección de carril y alineación según tamaño, y palabras limpias visibles como cero.

`w_dmem_we = w_adv && !i_reset && w_valid_mem && w_mem_write_mem`. Es el permiso de store del CPU; dmem aplica además su validación de tamaño antes de escribir físicamente. Una lectura nunca activa dirty. Un store de cero sí lo activa y un store parcial sobre palabra limpia mezcla contra cero, sin recuperar bytes físicos anteriores al reset.

El load leído y extendido se captura en MEM/WB en el siguiente flanco habilitado. `w_load_data_mem` se fuerza a cero cuando la instrucción MEM no es un load válido; esa normalización afecta únicamente el campo de datos sin uso. La dirección original se conserva por separado en `w_result_wb`: una carga no debe escribir esa dirección en rd.

### WB y permisos de commit

MEM/WB conserva PC, resultado de EX, dato de load, rd, mem_to_reg, reg_write, halt y valid. WB selecciona `w_load_data_wb` si `w_mem_to_reg_wb=1`, o `w_result_wb` en otro caso. El valor elegido es `w_wb_data` y llega al puerto de escritura de `u_decode`, incluido su bypass WB→ID.

`w_regfile_we = w_adv && !i_reset && w_valid_wb && w_reg_write_wb && w_rd_wb!=0`. El CPU entrega ese permiso a decode; regfile conserva sus protecciones locales de enable, reset y x0. El dato y el destino deben tomarse de WB, aunque MEM ya esté procesando otra instrucción.

| Situación | Store de MEM | Escritura de registro de WB | MEM/WB |
|---|---|---|---|
| Avance con instrucciones válidas y controles activos | Se acepta si el tamaño es válido | Se acepta si rd es distinto de cero | Captura la instrucción de MEM |
| Burbuja con bits de control no nulos | Bloqueado | Bloqueada si WB es inválido | Captura valid/control en cero |
| Pausa global | Bloqueado | Bloqueada | Conserva todos sus campos |
| Reanudación tras pausa | Se acepta la instrucción pendiente una vez, al avanzar | Se acepta el WB pendiente una vez, al avanzar | Avanza normalmente |
| Reset, incluso pausado | Bloqueado; dirty queda en cero | Bloqueada; regfile queda en cero | Cero e inválido |

La cuenta de escrituras aceptadas del arnés mide efectos arquitectónicos, no instrucciones retiradas: NOP, store y otras instrucciones pueden recorrer WB sin escribir un registro.

### Observación y pruebas

Los puertos públicos de memoria debug ahora leen `u_memory.u_dmem`. El mux debug agrega 11=PC WB, 12=resultado/dirección WB, 13=dato de load WB y 14=info WB, con máscara `0x8600001F`. El selector 15 incorpora valid WB en bit 3. La ocupación de las cuatro etapas ya es visible, pero halted y los flags de riesgos siguen pendientes de sus milestones.

`tb_mem_wb` maneja MEM de forma independiente, conecta la salida WB al regfile real y mantiene modelos de bytes, dirty y registros. Pausa con un store y un WB pendientes y cuenta las aceptaciones para detectar repeticiones aunque el dato escrito sea el mismo. Comprueba cargas con signo/cero, stores parciales, wrap, x0, burbujas y reset con escrituras pendientes.

`tb_fetch` ahora modela los operandos capturados, la escritura WB y la memoria real; dejó de asumir registros siempre en cero. Su modelo por ciclos conserva los resultados de los programas de prueba anteriores incluso cuando hay dependencias todavía sin resolver. Además ejecuta un programa corto con NOP de separación y expectativas arquitectónicas constantes: x1=5, x2=10, x3=x8=15, x9=x10=14, memoria[0]=15 y memoria[1]=14; los restantes registros y la siguiente palabra permanecen en cero.

El CPU ya conecta las cinco etapas, pero aún no incorpora forwarding, load-use, redirección ni detención HALT. El programa de esta prueba termina por un número acotado de avances, y `o_halted` sigue en cero hasta A-28. A-17 ampliará la validación del pipeline base; los milestones siguientes resolverán los riesgos y el fin real. No se presenta esta prueba con NOP como validación de esas funciones.

```bash
python3 TP3_FINAL/tools/run.py tb tb_mem_wb
python3 TP3_FINAL/tools/run.py test --companion ../TPs-companion
```

## 17. Cierre del pipeline base en A-17

El CPU de cinco etapas queda validado localmente con un programa de todas las R/I-ALU, LUI y memoria separado por tres NOP, en ejecución continua y pausada. El [informe completo A-M03](03_pipeline_base.md) explica la estructura con diagramas, campos por registro, etapas, permisos, debug y seguimiento temporal. El [gate A-M03](../validation/A-M03.md) y la [evidencia A-17](../validation/A-17.md) registran resultados y límites. Forwarding, riesgos, redirección y HALT se implementarán en las siguientes issues.

## 18. HALT y ejecución controlada completados en A-M07

El [informe 07 — HALT y congelamiento](07_halt_y_congelamiento.md) describe la implementación final de parada y sus diagramas. HALT exacto se acepta en ID con avance y sin redirección anterior; IF/ID se invalida, el PC deja de buscar y HALT atraviesa ID/EX→EX/MEM→MEM/WB mientras terminan las instrucciones anteriores. `o_halted=w_valid_wb && w_halt_wb` desactiva `w_adv=i_en && !o_halted`. Reset síncrono domina incluso pausado o halted, sin borrar imem ni el array físico de dmem.

## Mapa debug completo — A-30

El [mapa debug del CPU real](dump.md) documenta los 16 selectores implementados, los campos `info` presentes en cada etapa y los ocho flags del selector 15. A-30 completa halted, load-use, take y stop_fetch en bits 4…7, conserva ceros en 31:8 y verifica operandos capturados, payload de burbujas y PC WB para HALT. La [evidencia A-30](../validation/A-30.md) registra simulación, sensibilidad y síntesis. El cierre de M08 y su informe quedan para A-33.

La [interfaz pública verificada en A-31](interfaz_cpu.md#interfaz-pública-verificada-en-a-31) agrega un arnés común CPU/stub con barridos de 32 registros, 16 latches y las 256 palabras de memoria, reset, dirty, stores parciales e imem externa. La [evidencia A-31](../validation/A-31.md) registra la sustitución sin cambios de puertos ni copias de B.

La [integración con Debug Unit y UART de A-32](integracion_debug.md) utiliza `system.v` y la BFM originales de B para LOAD, STEP, RUN, DUMP, RESET, ABORT, timeout y recuperación. Los dumps se comparan con el CPU pausado y el codec/ISS de B. El cierre de A-M08 sigue correspondiendo a A-33.

A-28 verificó todos los almacenamientos y A-29 migró los programas a HALT real, conservando sus oráculos y comparando RUN/STEP por avance. Los contadores históricos de finalización por marcador deben leerse junto al informe actual. El selector 15 todavía muestra solamente valid; completar flags y Debug Unit corresponde a A-M08.
