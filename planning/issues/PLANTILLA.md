# Plantilla de issue ejecutable

Cada issue de la pista B está escrito para que lo ejecute un modelo barato (Haiku o Sonnet) **sin tomar decisiones de diseño**. Todo lo que hay que decidir ya está en [`decisiones.md`](../../TP3_FINAL/doc/documentation/decisiones.md) y los contratos. Si al ejecutar aparece algo que el issue no cubre, el ejecutor se detiene y pregunta; no improvisa.

Reglas para quien escribe un issue:

- Rutas completas desde la raíz del repo (o alias de [`convenciones.md`](../../TP3_FINAL/doc/documentation/convenciones.md) §1), nombres de módulos, puertos, parámetros, funciones y archivos **exactos**.
- Lo no trivial (FSMs, tareas de TB, fórmulas, layouts de bits) va con código o pseudocódigo concreto, no con prosa.
- Cada paso termina en algo verificable: un comando y qué tiene que mostrar.
- No repetir los contratos: citarlos por archivo y sección.
- Nada de "elegir", "considerar", "si conviene": eso es una decisión pendiente y no puede quedar en un issue.

---

```markdown
# B-xx · Título

`Tamaño` · etiquetas · milestone Mx · **Modelo sugerido:** Haiku | Sonnet · [índice](../README.md)

## Objetivo
Una línea: qué existe o funciona cuando se cierra.

## Antes de empezar
- Leer: lista exacta de archivos y secciones (y nada más).
- Precondiciones: issues que tienen que estar cerrados y el comando que lo comprueba.
- Rama: `b/B-xx-slug`.

## Archivos
| Acción | Ruta | Contenido |
| --- | --- | --- |
| crear / modificar / no tocar | ... | ... |

## Pasos
1. Paso concreto (con código cuando hace falta).
   Verificar: `comando` → salida esperada.
2. ...

## Validación
Comandos exactos y salida esperada (líneas literales cuando se pueda).

## Listo cuando
- [ ] Criterio binario, comprobable con un comando de "Validación".

## No hacer
- Cambios fuera de alcance que un ejecutor podría tener la tentación de hacer.

## Si algo falla
| Síntoma | Qué hacer |
| --- | --- |
| ... | ... (si no está en la tabla: detenerse y preguntar) |

## Commits
1. `area: mensaje exacto`

## Depende de / bloquea
```
