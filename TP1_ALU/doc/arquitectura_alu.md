# Arquitectura de la ALU en Verilog

## Idea central

En Verilog no se escribe una secuencia de instrucciones para que la FPGA la ejecute. Se describe el circuito que la herramienta de síntesis debe construir dentro de la FPGA.

Por ejemplo:

```verilog
o_data = i_data_a + i_data_b;
```

describe un sumador cuyas entradas son `i_data_a` e `i_data_b`, y cuya salida es `o_data`.

Para este trabajo práctico se propone la siguiente arquitectura:

```text
Switches + botones + reloj
            |
            v
        ALU_top
  +---------------------+
  | Registro A ---------+-->
  | Registro B ---------+---> ALU ---> LEDs
  | Registro Op --------+-->
  +---------------------+
```

La ALU realiza el cálculo, mientras que `ALU_top` permite ingresar y conservar los datos desde la placa FPGA.

## Separación en módulos

Un `module` representa un bloque de hardware con entradas, salidas y lógica interna. Para este TP se utilizan dos módulos principales:

- `ALU.v`: núcleo combinacional. Recibe los operandos `A`, `B` y el código de operación `Op`; entrega el resultado.
- `ALU_top.v`: módulo superior. Conecta switches, botones, reloj, registros internos y LEDs con el núcleo de la ALU.

La ALU no debe depender de botones, switches ni LEDs. Esta separación permite reutilizarla y verificarla mediante simulación de forma independiente.

## Interfaz y parametrización de la ALU

Antes de implementar la lógica se definen las señales que utilizará el módulo:

```verilog
module ALU #(
    parameter NB_DATA = 8,
    parameter NB_OP   = 6
) (
    input  wire signed [NB_DATA-1:0] i_data_a,
    input  wire signed [NB_DATA-1:0] i_data_b,
    input  wire        [NB_OP-1:0]   i_op,
    output reg  signed [NB_DATA-1:0] o_data
);
```

- `i_data_a` e `i_data_b` son los operandos de datos.
- `i_op` contiene el código de operación de seis bits definido por la consigna.
- `o_data` es el resultado de la ALU.
- Los parámetros permiten cambiar el ancho del bus de datos sin reescribir la estructura del módulo. Por ejemplo, con `NB_DATA = 16`, los operandos y el resultado pasan a tener 16 bits.

## Lógica combinacional

La lógica combinacional produce una salida que depende únicamente de las entradas actuales. No almacena estados ni espera un reloj.

```text
A = 5, B = 3, Op = ADD  =>  Resultado = 8
```

En Verilog se describe mediante un bloque `always @(*)`:

```verilog
always @(*) begin
    o_data = {NB_DATA{1'b0}};

    case (i_op)
        OP_ADD: o_data = i_data_a + i_data_b;
        OP_SUB: o_data = i_data_a - i_data_b;
        OP_AND: o_data = i_data_a & i_data_b;
        // Otras operaciones...
        default: o_data = {NB_DATA{1'b0}};
    endcase
end
```

El bloque `case` selecciona una de las operaciones y se sintetiza como lógica de selección. La asignación inicial de cero garantiza que la salida siempre reciba un valor, evitando la inferencia accidental de *latches*.

Que `o_data` sea declarado como `reg` no implica necesariamente un registro físico. En Verilog clásico, `reg` indica una variable que recibe asignaciones dentro de un bloque `always`. Como este bloque es `always @(*)`, el hardware resultante es combinacional.

## Lógica secuencial y registros

La lógica secuencial conserva un valor anterior y cambia cuando ocurre un flanco de reloj. Se describe, por ejemplo, de la siguiente forma:

```verilog
always @(posedge clock) begin
    if (button_1)
        reg_data_A <= bus;
end
```

Esta descripción sintetiza registros físicos o *flip-flops*. La variable `reg_data_A` mantiene el valor cargado incluso si luego cambian los switches.

En bloques secuenciales se utiliza normalmente la asignación no bloqueante `<=`.

## Ingreso de A, B y Op desde switches

La placa posee un conjunto compartido de switches. Para poder ingresar valores distintos en `A`, `B` y `Op`, se necesitan registros en el módulo superior.

El uso previsto es:

1. Se configura en los switches el valor para `A` y se presiona el botón 1. El valor se guarda en `reg_data_A`.
2. Se modifica el valor de los switches para `B` y se presiona el botón 2. El valor se guarda en `reg_data_B`.
3. Se configuran los seis bits inferiores de los switches con el código de operación y se presiona el botón 3. El valor se guarda en `reg_op`.
4. La ALU recibe los tres valores almacenados y el resultado se muestra en los LEDs.

Sin estos registros, al modificar los switches para cargar `B` se perdería el valor previamente elegido para `A`.

La condición de que la ALU sea combinacional se mantiene: la ALU no contiene reloj. El reloj pertenece al módulo superior y se utiliza únicamente para guardar los valores de entrada.

## Instanciación de la ALU

El módulo superior crea una instancia de la ALU y conecta las señales internas a sus puertos:

```verilog
ALU #(
    .NB_DATA(DATA_LEN),
    .NB_OP(OP_LEN)
) alu (
    .i_data_a(reg_data_A),
    .i_data_b(reg_data_B),
    .i_op    (reg_op),
    .o_data  (led)
);
```

Las conexiones por nombre, como `.i_data_a(reg_data_A)`, mejoran la legibilidad y evitan errores por el orden de los puertos.

## Responsabilidad de cada archivo

`ALU.v` debe contener:

- Parámetros de ancho de buses.
- Entradas de datos y código de operación.
- Códigos de operación declarados con `localparam`.
- Lógica combinacional que calcula el resultado.

`ALU_top.v` debe contener:

- Puertos asociados a la placa: reloj, reset, botones, switches y LEDs.
- Registros para almacenar `A`, `B` y `Op`.
- Lógica secuencial de carga de registros.
- Instancia del módulo `ALU`.

Finalmente, un archivo de restricciones `.xdc` asocia cada puerto del módulo superior con un pin físico de la placa FPGA.

## Método de diseño reutilizable

Para diseñar futuros circuitos en Verilog se puede seguir esta secuencia:

1. Definir las entradas y salidas del circuito.
2. Determinar qué información debe conservarse.
3. Implementar como lógica combinacional lo que no requiere memoria.
4. Implementar mediante registros, reloj y habilitaciones aquello que debe conservar estado.
5. Separar el núcleo reutilizable de la interfaz física de la placa.
6. Instanciar los módulos y conectar sus puertos explícitamente.
7. Simular primero el núcleo y luego el diseño completo.
8. Asignar los pines físicos mediante el archivo `.xdc`.

En esta ALU, los valores `A`, `B` y `Op` deben conservarse, por lo que se almacenan en registros dentro de `ALU_top`. El resultado no necesita memoria: se recalcula de forma combinacional ante cualquier cambio de sus entradas.

## Simulación e interpretación de formas de onda

La verificación funcional se realiza mediante un testbench, que es un módulo utilizado únicamente en simulación. El testbench instancia la ALU, genera valores de entrada y permite observar la respuesta `o_data`.

Para ejecutar la simulación comportamental en Vivado, el módulo superior de la simulación debe ser el testbench, por ejemplo `Test_Bench_ALU`, y no `ALU_top`. `ALU_top` representa el circuito de la FPGA y requiere señales externas de reloj, botones y switches; si se simula directamente sin estímulos, sus entradas quedan sin valor definido (`Z`) y sus registros o salidas pueden aparecer como desconocidos (`X`).

### Señales relevantes

Al observar las formas de onda se recomienda mantener visibles y contraídas las siguientes señales:

```text
i_data_a[7:0]
i_data_b[7:0]
i_op[5:0]
o_data[7:0]
```

Los bits individuales de cada bus sólo son necesarios para depurar un bit específico. Para facilitar la lectura se puede configurar el radix de las señales en Vivado:

| Señal | Radix recomendado |
| --- | --- |
| `i_data_a` | Decimal con signo o hexadecimal |
| `i_data_b` | Decimal con signo o hexadecimal |
| `i_op` | Binario o hexadecimal |
| `o_data` | Decimal con signo o hexadecimal |

El cursor vertical de la ventana de ondas determina el instante que se está observando. La columna **Value** muestra el valor de cada señal en la posición del cursor. Se recomienda posicionarlo en el centro de un intervalo estable y no sobre una transición de señales.

### Códigos de operación

Cuando `i_op` se visualiza en hexadecimal, los códigos definidos para la ALU se interpretan de la siguiente forma:

| Hexadecimal | Binario | Operación |
| ---: | :---: | --- |
| `20` | `100000` | ADD |
| `22` | `100010` | SUB |
| `24` | `100100` | AND |
| `25` | `100101` | OR |
| `26` | `100110` | XOR |
| `03` | `000011` | SRA |
| `02` | `000010` | SRL |
| `27` | `100111` | NOR |

Por ejemplo, si el cursor indica:

```text
i_data_a = 02
i_data_b = FF
i_op     = 20
o_data   = 01
```

se está realizando una suma. Como las entradas de datos son con signo, `02` representa el valor decimal `2` y `FF` representa `-1`. Por lo tanto, el resultado `01` corresponde a:

```text
2 + (-1) = 1
```

### Secuencia temporal del testbench

El testbench actual mantiene un mismo par de valores `A` y `B` durante 80 ns y cambia la operación cada 10 ns. La secuencia dentro de cada grupo de 80 ns es:

| Intervalo relativo | Operación |
| ---: | --- |
| 0 a 10 ns | ADD |
| 10 a 20 ns | SUB |
| 20 a 30 ns | AND |
| 30 a 40 ns | OR |
| 40 a 50 ns | XOR |
| 50 a 60 ns | SRA |
| 60 a 70 ns | SRL |
| 70 a 80 ns | NOR |

Al finalizar los 80 ns se generan nuevos valores para `i_data_a` e `i_data_b`, y la misma secuencia de operaciones vuelve a ejecutarse. Para comprobar una operación se selecciona un instante de su intervalo y se relacionan los valores de entrada con el resultado según la ecuación correspondiente.

Por ejemplo, para el primer conjunto de datos, se puede observar la suma cerca de `5 ns`, la resta cerca de `15 ns` y la operación AND cerca de `25 ns`.
