# Organización del proyecto después del merge

Esta guía registra la limpieza posterior al merge. La integración ya se completó después de esa limpieza: el estado actual, bitstream y validación están en [09 — Integración y Basys3](09_integracion_cpu_debug_basys3.md).

La limpieza conserva el código de A y B y prepara un único árbol para la siguiente iteración. No modifica la lógica del CPU, los contratos públicos ni la Debug Unit, y no ejecuta la integración funcional CPU–Debug Unit. Los conflictos del merge se resuelven preservando los dos aportes, sin crear un commit.

## Directorios

```text
TP3_FINAL/
├── VIVADO/TP_FINAL/
│   ├── rtl/
│   │   ├── common/                 riscv_defs.vh
│   │   ├── cpu/                    cpu.v
│   │   │   ├── decode/             decoder, control, inmediatos y etapa ID
│   │   │   ├── execute/            ALU y etapa EX
│   │   │   ├── memory/             dmem y etapa MEM
│   │   │   ├── registers/          regfile y registros entre etapas
│   │   │   └── hazards/            interlock y forwarding
│   │   ├── debug/                  Debug Unit, imem, stub, system y cpu_ports.vh
│   │   ├── uart/                   interfaz, transmisor, receptor y baud
│   │   └── top/                    tops de placa y generación de clock
│   └── tb/
│       ├── cpu/
│       │   ├── unit/               módulos y etapas aisladas
│       │   ├── pipeline/           CPU: fetch, RAW, load-use, flush y HALT
│       │   └── debug/              mapa debug y contrato del CPU
│       ├── common/                BFM UART de B
│       ├── debug/                 bancos de Debug Unit y stub de B
│       ├── system/                bancos con system e imem externa
│       ├── uart/                  bancos UART de B
│       └── top/                   banco del top UART
├── programs/
│   ├── cpu/                       programas y goldens históricos de A
│   └── *.s / *.hex / *.bin / ...   nueve programas del host de B
├── tools/                         runner y herramientas comunes de B
└── build/                         compilados, simulaciones y logs ignorados
```

Los 17 archivos RTL de A se trasladan sin alterar su contenido. Los 29 archivos de bancos de A conservan módulos, assertions y expectativas; sus rutas de programa apuntan ahora a `programs/cpu/`. No se renombran módulos ni señales. `cpu_ports.vh` permanece en debug como contrato compartido, y todos los consumidores incluyen `riscv_defs.vh` desde common mediante include paths.

## Herramientas y bancos que se conservan

Se retiran los seis helpers de cierre por issue/milestone: `check_control_programs.py`, `check_cpu_contract.py`, `check_final_coverage.py`, `check_final_xsim.py`, `check_halt_programs.py` y `check_system_dumps.py`. También desaparece el runner paralelo de A: se conserva la implementación de B de `run.py` y `synth_ooc.tcl`, con sus funciones de host, ISS, vectores, síntesis y placa.

Se conservan los bancos del CPU y sus datos esperados porque la Debug Unit no comprueba por sí misma ALU, riesgos, memoria, flush o vaciado de HALT. `tools/tbs.py` reunió 43 targets durante la limpieza y ahora reúne 44 con el CPU real integrado, con rutas locales, además de los targets de síntesis y placa existentes. `DATAPATH_FILES` evita repetir la lista completa de fuentes en cada banco. Los directorios common y debug se incluyen al compilar bancos del CPU y al sintetizar; no se depende del worktree del compañero.

Al terminar la limpieza, `CPU_FILES` de B quedó vacío. En la integración posterior se activó `CPU_FILES = DATAPATH_FILES` y se validaron `tb_system_prog` y el bitstream de `top_debug`; ver el [informe 09](09_integracion_cpu_debug_basys3.md). El smoke histórico de A queda conservado y registrado para una ejecución explícita posterior; no se ejecutó en esta limpieza. No se cambian los defines ni el cableado del sistema para adelantar la integración.

Desde la raíz `Practico/TPs`, en Linux:

```bash
python3 TP3_FINAL/tools/run.py tb tb_alu
python3 TP3_FINAL/tools/run.py tb tb_cpu_step_halt
python3 TP3_FINAL/tools/run.py iss
VIVADO=/tools/Xilinx/2025.1/Vivado/bin/vivado python3 TP3_FINAL/tools/run.py synth_ooc cpu
```

En Windows se puede usar `py`. Los comandos antiguos con `--companion` y los helpers retirados permanecen identificados como históricos en la evidencia de los milestones. La regresión común completa sigue siendo `run.py test`; su ejecución incluye bancos de sistema y queda para el trabajo de integración solicitado para después.

## Resolución de colisiones

Los contratos de B mantienen sus nombres públicos: [decisiones.md](decisiones.md), [dump.md](dump.md) e [interfaz_cpu.md](interfaz_cpu.md). Las explicaciones y evidencias propias del datapath se conservan en [cpu_decisiones.md](cpu_decisiones.md), [cpu_dump.md](cpu_dump.md) y [cpu_interfaz.md](cpu_interfaz.md). Los enlaces de A apuntan a esas copias cuando describen su implementación.

Los 26 archivos de programa/oráculo de A se conservan íntegros bajo `programs/cpu/`, junto con su README. Los nombres `suma`, `load_use` y `no_halt` corresponden a programas distintos en ambas pistas: no se mezclan instrucciones ni se selecciona un único golden para ambos. La raíz de programs conserva los nueve programas originales de B con sus binarios y resultados, utilizados por sus herramientas y tests. No se regeneran goldens durante esta reorganización.

El `.xpr` usa las nuevas rutas, fuentes locales e include paths. Se eliminan sus referencias a scripts retirados y se registran los documentos de implementación conservados. No se cambia su versión de Vivado ni la parte FPGA como consecuencia de ordenar directorios.

## Validación de esta reorganización

Se elaboraron los 43 targets de `tbs.py` con Icarus, sin ejecutar los bancos de sistema: [log de compilación](../../build/restructure/compile.log). Se comparó el contenido trasladado con HEAD: los 17 RTL son idénticos, los 29 TB solo cambian las rutas de programa y los 26 datos/oráculos de A permanecen idénticos.

Pasaron los 13 bancos de `tb/cpu/unit/`, `tb_cpu_debug` y `tb_cpu_step_halt`: **15 targets aislados del CPU**. El último vuelve a ejecutar las ocho variantes de A con sus propios goldens y demuestra que la separación de programs conserva sus expectativas. [Log CPU e ISS](../../build/restructure_cpu_tests.log).

El runner común compiló y ejecutó las **96 comprobaciones del ISS**. Los nueve programas de B conservan exactamente sus cuatro archivos originales; se verificaron assembler→hex/bin y el JSON completo del ISS frente al golden, incluido el estado parcial de `no_halt`. [Log de programas](../../build/restructure_programs.log). El intento de ejecutar `tests/test_programs.py` con pytest no pudo iniciar porque pytest no está instalado en el Python local; esa suite no se presenta como ejecutada. Las verificaciones de archivos, ensamblado e ISS anteriores se hicieron directamente sin instalar paquetes.

La síntesis OOC del CPU desde sus nuevas rutas terminó con PASS para `xc7a35tcpg236-1`; conserva 2.872 LUT, 1.739 FF y cero latches. [Log de síntesis](../../build/restructure_synthesis.log). Se comprobaron las rutas XML del `.xpr`, los manifests de síntesis/placa, los enlaces Markdown y la ausencia de marcadores de conflicto. Los logs de build no se versionan y los scripts temporales de esta comprobación tampoco forman parte del proyecto entregado.

No se ejecutaron smoke UART con CPU real, regresión de sistema, bitstream ni programación de placa en esta iteración.

## Trabajo posterior a la limpieza

Conviene hacer la integración en un cambio separado: completar `CPU_FILES`, elegir el banco de sistema de referencia y comparar ambos catálogos de programas con sus propios oráculos. Antes de generar el bitstream también corresponde unificar la versión de Vivado y confirmar la parte `xc7a35tcpg236-1`, ya que el `.xpr` histórico declara otra. Esas tareas quedaron fuera de la limpieza y se completaron después en la [integración 09](09_integracion_cpu_debug_basys3.md), excepto la programación y validación física de la placa, que hará el usuario.
