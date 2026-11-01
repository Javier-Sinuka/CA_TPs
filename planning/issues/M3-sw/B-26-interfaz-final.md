# B-26 · Interfaz final y diagrama espacio-tiempo

`L` · etiquetas `sw-host` · milestone M3 · **Modelo sugerido:** Sonnet · [índice](../README.md)

## Objetivo

Una GUI con `tkinter` (biblioteca estándar, sin dependencias nuevas) sobre `link.py`, con registros, latches decodificados, memoria usada, diagrama espacio-tiempo acumulado en paso a paso y marca de divergencia contra el golden model.

## Antes de empezar

- Leer: [`dump.md`](../../../TP3_FINAL/doc/documentation/dump.md) §3 completo; [B-25](B-25-cli.md) paso 2 (reglas de `pipe` y de registros cambiados: se reutilizan); [B-24](B-24-placa-simulada.md) "Diseño".
- Precondiciones: B-25 cerrado.
- Rama: `b/B-26-gui`.

## Archivos

| Acción | Ruta | Contenido |
| --- | --- | --- |
| crear | `TP3_FINAL/sw/host/spacetime.py` | Construcción del diagrama (lógica pura, §A) |
| crear | `TP3_FINAL/sw/host/golden.py` | Comparación contra el ISS (§B) |
| crear | `TP3_FINAL/sw/host/gui.py` | Ventana (§C) |
| crear | `TP3_FINAL/sw/tests/test_spacetime.py` | Escenarios de §A |
| crear | `TP3_FINAL/sw/tests/test_golden.py` | §B |
| crear | `TP3_FINAL/doc/documentation/manual_interfaz.md` | Manual con capturas (§D) |

## A. Diagrama espacio-tiempo (`spacetime.py`)

Entrada: la lista de dumps consecutivos `D0, D1, …` (D0 = estado después de `load`/`reset`, cada `Dk` después de un paso). Salida: filas (una por instancia dinámica de instrucción) × columnas (índice de dump).

Etapas de un dump: `IF` (pc = W2, válida si `not stop_fetch and not halted`), `ID` (latch 0, `valid_id`), `EX` (latch 2, `valid_ex`), `MEM` (latch 7, `valid_mem`), `WB` (latch 11, `valid_wb`).

```python
@dataclass
class Row:
    pc: int
    cells: dict[int, str]       # columna → "IF", "ID", "EX", "MEM", "WB", "IF*", "ID*" (stall), "IF×", "ID×", "EX×" (anulada)

def build(dumps: list[Dump]) -> list[Row]: ...
```

Algoritmo (asigna una instancia a cada etapa válida de cada dump):

1. `D0`: cada etapa válida crea una fila nueva; orden de creación WB, MEM, EX, ID, IF (la más vieja primero).
2. Para `t ≥ 1`, con `p = D(t−1)`, recorrer las etapas de `t` en el orden WB, MEM, EX, ID, IF. Para la etapa `s` válida con pc `x`:
   - Si `s` no es IF, la etapa anterior `s−1` en `p` era válida, tenía pc `x` y su instancia no fue tomada todavía en `t` → misma instancia (avanzó). Celda = nombre de `s`.
   - Si no, si `s` es IF o ID, `p.load_use_stall` era 1, la misma etapa en `p` tenía pc `x` → misma instancia (stall). Celda = nombre de `s` + `*`.
   - Si no → fila nueva. Celda = nombre de `s`.
3. Anuladas: si `p.take_ex` era 1, las instancias que estaban en IF y en ID en `p` y no aparecen en `t` cambian su celda de la columna `t−1` a `IF×`/`ID×`. Igual con `stop_fetch` en `p` para la instancia de ID que no aparece en `t`.
4. Filas en orden de creación; la etiqueta de una fila es `f"0x{pc:08x} {disasm_at(words, pc)}"`.

Escenarios de test (dumps armados a mano en `test_spacetime.py` con un helper `mk(pc_if, id=None, ex=None, mem=None, wb=None, stall=0, take=0, stop=0, halted=0)` que arma un `Dump` con esos pc y bits; etapas `None` = inválidas):

**Load-use** (`0: lw x1,0(x0)`, `4: add x2,x1,x1`, `8: addi x3,x0,1`, `12: halt`):

| Dump | IF | ID | EX | MEM | WB | bits |
| --- | --- | --- | --- | --- | --- | --- |
| D0 | 0 | — | — | — | — | |
| D1 | 4 | 0 | — | — | — | |
| D2 | 8 | 4 | 0 | — | — | stall |
| D3 | 8 | 4 | — | 0 | — | |
| D4 | 12 | 8 | 4 | — | 0 | |
| D5 | 16 | 12 | 8 | 4 | — | stop |
| D6 | 16 | — | 12 | 8 | 4 | stop |
| D7 | 16 | — | — | 12 | 8 | stop |
| D8 | 16 | — | — | — | 12 | stop, halted |

Esperado (`build` devuelve exactamente estas 4 filas; la IF de pc 16 nunca es válida porque `stop_fetch` está en 1):

| Fila | D0 | D1 | D2 | D3 | D4 | D5 | D6 | D7 | D8 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0x0 | IF | ID | EX | MEM | WB | | | | |
| 0x4 | | IF | ID | ID* | EX | MEM | WB | | |
| 0x8 | | | IF | IF* | ID | EX | MEM | WB | |
| 0xc | | | | | IF | ID | EX | MEM | WB |

**Salto tomado** (`0: addi x1,x0,1`, `4: bne x1,x0,+12`, `8: addi x2,x0,2`, `12: addi x3,x0,3`, `16: halt`):

| Dump | IF | ID | EX | MEM | WB | bits |
| --- | --- | --- | --- | --- | --- | --- |
| D0 | 0 | — | — | — | — | |
| D1 | 4 | 0 | — | — | — | |
| D2 | 8 | 4 | 0 | — | — | |
| D3 | 12 | 8 | 4 | 0 | — | take |
| D4 | 16 | — | — | 4 | 0 | |
| D5 | 20 | 16 | — | — | 4 | stop |
| D6 | 20 | — | 16 | — | — | stop |
| D7 | 20 | — | — | 16 | — | stop |
| D8 | 20 | — | — | — | 16 | stop, halted |

Esperado:

| Fila | D0 | D1 | D2 | D3 | D4 | D5 | D6 | D7 | D8 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0x0 | IF | ID | EX | MEM | WB | | | | |
| 0x4 | | IF | ID | EX | MEM | WB | | | |
| 0x8 | | | IF | ID× | | | | | |
| 0xc | | | | IF× | | | | | |
| 0x10 | | | | | IF | ID | EX | MEM | WB |

Las dos burbujas del `bne` tomado son las filas `0x8` y `0xc` que terminan en `×`, y las columnas D4/D5 sin instrucción en EX/MEM.

## B. Divergencia contra el golden model (`golden.py`)

Instrucciones retiradas después de `n` pasos: `r(n) = cantidad de dumps D0 … D(n−1) con valid_wb = 1 y info_wb.halt = 0` (la instrucción que está en WB en un dump escribe en el flanco del paso siguiente). Con la placa simulada `valid_wb = 1` en cada estado no detenido (B-24), así que `r(n) = n`.

```python
class Golden:
    def __init__(self, iss_exe: Path, words: list[int]) -> None: ...
    def state_after(self, retired: int) -> dict: ...      # iss.exe --max-instr retired --full, JSON canónico
    def diverging(self, d: Dump, retired: int) -> set[str]: ...   # {"x5", "mem[0x00000008]"}: claves que difieren
```

`diverging` compara `x1..x31` y los pares de memoria (si el dump está `halted`, compara contra `state_after(retired)` igual). Tests (`test_golden.py`): con `FakeBoard` sin fallas, recorrer `suma` paso a paso hasta `halted` → `diverging` vacío en todos los pasos; con `FakeBoard(fault={"x5": 0xdead})` sobre `branches` → `"x5"` en `diverging` desde el primer paso.

## C. Ventana (`gui.py`)

`py -m host.gui (--port COMx | --fake) [--iss <ruta>]`. Un solo `tk.Tk`, sin hilos (las llamadas a `Link` bloquean; con los timeouts de B-23 son ≤ 4 s).

| Zona | Contenido |
| --- | --- |
| Barra superior | Botones `Cargar .s…` (filedialog), `Reset`, `Paso`, `Paso ×N` (Spinbox 1-100), `Ejecutar`, `Dump`; etiqueta de estado `ciclos=… pc=… halted/timeout/abort` |
| Registros | Grilla 8×4 con el formato de `regs` de B-25; fondo amarillo si cambió, rojo si está en `diverging` |
| Pipeline | Las 5 líneas de `pipe` de B-25 |
| Latches | Por latch ID/EX, EX/MEM, MEM/WB: palabras crudas en hex y la info decodificada (`LatchInfo`) como `rd=… rs1=… … reg_write=1 …` |
| Memoria | Lista de pares; rojo si diverge |
| Espacio-tiempo | `Canvas` con scroll horizontal: filas de `spacetime.build()`, una columna por dump, celdas con el texto de la etapa; `*` en gris, `×` en rojo. Se reinicia en `Cargar` y `Reset`; `Ejecutar` agrega una sola columna (no hay pasos intermedios) |

Errores de `Link`: `messagebox.showerror` y la ventana sigue.

## D. Manual (`manual_interfaz.md`)

Secciones: cómo abrir (comandos de §C), cada zona de la ventana con una captura (PNG en `TP3_FINAL/doc/documentation/img/`), flujo típico (cargar, paso a paso, ejecutar, reprogramar), cómo leer el diagrama (`*`, `×`) y la marca roja.

## Validación

```
cd TP3_FINAL/sw && py -m pytest -q tests/test_spacetime.py tests/test_golden.py     → pasan
py -m host.gui --fake                                                              → abre
```

Checklist manual (copiar al PR y tildar), primero con `--fake`, después con la placa real (Fase 11):

- [ ] Cargar `../programs/suma.s`, 10 pasos: ciclos sube de 1 en 1, registros cambiados en amarillo.
- [ ] `Ejecutar`: `halted`, `x1 = 0x00000037`, memoria `0x00000000: 0x00000037`.
- [ ] `Reset` y `Cargar` de nuevo: el diagrama se reinicia.
- [ ] Con `FakeBoard(fault={"x5": 0xdead})` (lanzar con `--fake-fault x5=0xdead`, opción solo para esta prueba) y `branches.s`: `x5` en rojo.
- [ ] Capturas del manual tomadas.

## Listo cuando

- [ ] Los dos escenarios de §A dan exactamente las tablas esperadas (verificado por test).
- [ ] Un registro alterado a propósito en la placa simulada se marca como divergencia (test y checklist).
- [ ] Con el CPU real (Fase 10/11): `suma.s` en paso a paso muestra las 2 anuladas de cada `bne` tomado y `load_use.s` muestra el ciclo de stall (`*`); se compara con un dibujo a mano adjunto al PR.
- [ ] `manual_interfaz.md` con capturas.

## No hacer

- No instalar Textual, Qt ni Dear PyGui.
- No meter lógica del diagrama ni de divergencia en `gui.py`: va en `spacetime.py` y `golden.py`, que son las que se testean.

## Si algo falla

| Síntoma | Qué hacer |
| --- | --- |
| `import tkinter` falla | El Python instalado no trae Tcl/Tk: detenerse y avisar (no instalar otra biblioteca) |
| Un escenario de §A no da la tabla | Revisar el orden WB→IF del paso 2: las etapas más viejas toman primero su instancia |

## Commits

1. `sw-host: diagrama espacio-tiempo`
2. `sw-host: comparación contra el golden model`
3. `sw-host: GUI tkinter`
4. `docs: manual de la interfaz`

## Depende de / bloquea

Depende de: B-25. El último criterio necesita el CPU real (Fase 10). Bloquea: demo (Fase 11).
