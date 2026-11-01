# B-18 · Base del repositorio de software

`S` · etiquetas `test` · milestone M3 · **Modelo sugerido:** Haiku · [índice](../README.md)

## Objetivo

Que la estructura de `$SW` exista, que `py TP3_FINAL/tools/run.py test` corra pytest y los tests del ISS además de los TB, y que el README de `TP3_FINAL` diga qué instalar.

## Antes de empezar

- Leer: [`convenciones.md`](../../../TP3_FINAL/doc/documentation/convenciones.md) §1, §2, §3, §6. Nada más.
- Precondiciones: existe `TP3_FINAL/tools/run.py` con los objetivos `tb`, `tbs` y `synth_ooc` (lo crea B-01; B-04 agrega `mutate`). Comprobar: `py TP3_FINAL/tools/run.py tbs` → termina con código 0.
- Rama: `b/B-18-base-software`.

## Archivos

| Acción | Ruta | Contenido |
| --- | --- | --- |
| crear | `TP3_FINAL/sw/requirements.txt` | Exactamente el de `convenciones.md` §2 |
| crear | `TP3_FINAL/sw/asm/__init__.py` | Vacío |
| crear | `TP3_FINAL/sw/host/__init__.py` | Vacío |
| crear | `TP3_FINAL/sw/tests/__init__.py` | Vacío |
| crear | `TP3_FINAL/sw/tests/data/.gitkeep` | Vacío |
| crear | `TP3_FINAL/sw/conftest.py` | Ver paso 2 |
| crear | `TP3_FINAL/sw/tests/test_smoke.py` | Ver paso 3 |
| crear | `TP3_FINAL/sw/iss/.gitkeep` | Vacío (B-21 pone el código) |
| crear | `TP3_FINAL/programs/.gitkeep` | Vacío |
| modificar | `TP3_FINAL/tools/run.py` | Objetivos `pytest`, `iss`, `test` (paso 4) |
| modificar | `TP3_FINAL/.gitignore` | Agregar líneas `build/` y `tools/*.jar` |
| crear | `TP3_FINAL/README.md` | Paso 5 (si ya existe, agregar la sección "Instalación y tests" al principio) |

## Pasos

1. Crear los archivos vacíos y `requirements.txt`. Instalar: `py -m pip install -r TP3_FINAL/sw/requirements.txt`.
   Verificar: `py -m pytest --version` → `pytest 8.x` o mayor.

2. `TP3_FINAL/sw/conftest.py` (lo usan B-21 en adelante; se escribe completo ahora):

   ```python
   """Configuración común de pytest para TP3_FINAL/sw."""
   from __future__ import annotations

   import subprocess
   from pathlib import Path

   import pytest

   SW = Path(__file__).resolve().parent
   TP3 = SW.parent
   BUILD = TP3 / "build"
   ISS_SRC = [SW / "iss" / "iss.cpp", SW / "iss" / "iss_main.cpp"]
   ISS_EXE = BUILD / "iss.exe"


   def build_iss() -> Path:
       """Compila build/iss.exe si falta o si algún fuente es más nuevo."""
       if not ISS_SRC[0].exists():
           pytest.skip("sw/iss/iss.cpp todavía no existe (B-21)")
       BUILD.mkdir(exist_ok=True)
       newest = max(p.stat().st_mtime for p in ISS_SRC + [SW / "iss" / "iss.hpp"])
       if not ISS_EXE.exists() or ISS_EXE.stat().st_mtime < newest:
           cmd = ["g++", "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror",
                  "-o", str(ISS_EXE), *map(str, ISS_SRC)]
           subprocess.run(cmd, check=True)
       return ISS_EXE


   @pytest.fixture(scope="session")
   def iss_exe() -> Path:
       return build_iss()
   ```

   Por qué compila desde pytest: el objetivo `test` corre `pytest` antes que `iss` (orden fijo de `convenciones.md` §3), y los tests de B-22, B-24 y B-25 necesitan el ejecutable.

3. `TP3_FINAL/sw/tests/test_smoke.py`:

   ```python
   import asm
   import host


   def test_paquetes_importan() -> None:
       assert asm is not None and host is not None
   ```

   Verificar: `cd TP3_FINAL/sw` y `py -m pytest -q` → `1 passed`.

4. En `run.py` agregar (manteniendo lo existente):

   - `pytest`: `subprocess.run(["py", "-m", "pytest", "-q"], cwd=TP3/"sw")`; devuelve su código.
   - `iss`: si `sw/iss/test_iss.cpp` no existe imprime `SKIP iss: sw/iss/test_iss.cpp no existe (B-21)` y devuelve 0. Si existe: compila `build/iss.exe` (fuentes `iss.cpp iss_main.cpp`) y `build/test_iss.exe` (fuentes `iss.cpp test_iss.cpp`) con `g++ -std=c++17 -O2 -Wall -Wextra -Werror`, corre `build/test_iss.exe` y devuelve su código. Cualquier error de compilación → 1.
   - `test`: corre `tbs`, `pytest`, `iss`, `mutate` (si `mutate` todavía no existe, se omite con `SKIP mutate`), sin cortar en la primera falla. Al final imprime una tabla:

     ```
     resumen:
       tbs     OK
       pytest  OK
       iss     SKIP
       mutate  OK
     ```

     y devuelve 1 si alguno es `FAIL`.

   Verificar: `py TP3_FINAL/tools/run.py test` → la tabla y código 0.

5. `TP3_FINAL/README.md`, sección "Instalación y tests", con exactamente estos puntos:
   - Python 3 instalado con el administrador de Python de Windows; se invoca con `py` (no `python`). `py -m pip install -r TP3_FINAL/sw/requirements.txt`.
   - Icarus Verilog 12 en `C:\iverilog\bin`, en el `PATH`.
   - g++ (MinGW, por ejemplo `winget install BrechtSanders.WinLibs.POSIX.UCRT`) en el `PATH`.
   - Java 21 (Temurin) en el `PATH`; RARS 1.6: descargar `rars1_6.jar` de las releases de `TheThirdOne/rars` en GitHub y guardarlo como `TP3_FINAL/tools/rars1_6.jar` (no se versiona).
   - Vivado 2024.1 en `C:\Xilinx\Vivado\2024.1` o variable de entorno `VIVADO` con la ruta a `vivado.bat`.
   - Comando único: `py TP3_FINAL/tools/run.py test`.
   - Python se corre con `cwd = TP3_FINAL/sw`: `py -m asm.rvasm`, `py -m host.cli`.

6. Prueba de clon limpio: `git clone <ruta local del repo> %TEMP%\ca_clean`, `cd %TEMP%\ca_clean`, `py TP3_FINAL/tools/run.py test` → código 0. Borrar la carpeta después.

## Validación

```
py TP3_FINAL/tools/run.py test       → "resumen:" y código 0
py TP3_FINAL/tools/run.py pytest     → "1 passed"
```

Romper a propósito `test_smoke.py` (`assert False`) → `run.py test` imprime `pytest  FAIL` y devuelve 1. Revertir.

## Listo cuando

- [ ] `py TP3_FINAL/tools/run.py test` corre todo y devuelve distinto de 0 si algo falla (comprobado con la rotura a propósito).
- [ ] El README dice qué instalar (Python, pyserial, pytest, g++, Icarus, Java, RARS, Vivado).
- [ ] El clon limpio pasa.

## No hacer

- No crear código de ensamblador, ISS ni host (son B-19 a B-26).
- No agregar `make` ni un `Makefile`.
- No cambiar el orden de objetivos de `test`.

## Si algo falla

| Síntoma | Qué hacer |
| --- | --- |
| `python` abre la Microsoft Store | Usar `py`, nunca `python` |
| `pip` falla por permisos | `py -m pip install --user -r ...` |
| `ModuleNotFoundError: asm` en pytest | El `cwd` no es `TP3_FINAL/sw`; corregir en `run.py` |

## Commits

1. `tools: estructura de sw, requirements y conftest`
2. `tools: objetivos pytest, iss y test en run.py`
3. `docs: instalación y tests en README de TP3`

## Depende de / bloquea

Depende de: B-04 (runner con `tb`/`tbs`). Bloquea: B-19 a B-29.
