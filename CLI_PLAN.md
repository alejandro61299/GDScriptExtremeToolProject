# Plan — Línea de comandos y skill (`gdsex`)

Las acciones del plugin, usables desde la terminal y por una IA. Un comando `gdsex` ejecuta cualquier acción sobre los archivos del proyecto sin abrir el editor, y una skill le enseña a la IA cuándo usarlo. El objetivo es que la IA gaste menos tokens: escribe código suelto y deja que la herramienta ponga los tipos, las firmas y el orden, y mueve código con las extracciones en vez de reescribirlo.

No se porta nada a otro lenguaje. La CLI usa el mismo código GDScript que el menú del editor, ejecutado con Godot en modo headless. El motivo está en el apartado 5.

| Paso | Contenido | Estado |
|---|---|---|
| T1 | El análisis no compila los scripts del proyecto | Hecha |
| T2 | Núcleo: archivos, destinos, informes y los comandos de script entero | Hecha |
| T3 | Comandos en una posición: `function`, `local`, `member`, `connect`, `init`, `actions` | Hecha |
| T4 | Extracciones con opciones: `extract-function`, `extract-variable` | Hecha |
| T5 | Lotes, carpetas, `--changed` y clases globales nuevas | Hecha |
| T6 | El lanzador `gdsex`, la instalación y la skill | Hecha |
| T7 | Medidas de rendimiento y de tokens, documentación | Hecha en parte: falta medir sesiones de un agente |

Cada paso termina con la suite en verde.

El plan está implementado (2026-10-30). La suite pasa con 1.418 casos: 113 nuevos, 104 de la CLI y 9 de T1. Lo que decidí al implementar y cambia lo de arriba está en "Decididas al implementar" (apartado 2). Lo que se midió está en el apartado 11. Lo único que queda es medir sesiones reales de un agente con y sin la skill (apartado 11), porque en esta máquina no hay un CLI de Claude instalado.

`tidy` es el comando central, como pediste: tipos, orden y formato de todas las clases de los scripts que se le den, en una sola orden.

```bash
sh addons/gdscript_extreme_tool/cli/gdsex tidy .
```

## 1. Qué hace

```bash
gdsex function player.gd:42:take_damage
```

```
player.gd +4
88	func take_damage(p_amount: int, p_source: Node2D) -> void:
89		pass
```

```bash
gdsex extract-function player.gd:30-38 --name _apply_knockback
```

```
player.gd +13 -9
30		_apply_knockback(direction, force)
62	func _apply_knockback(direction: Vector2, force: float) -> void:  (+9)
```

```bash
gdsex tidy scripts/
```

```
scripts/player.gd typed 12, reordered, formatted
scripts/enemy.gd formatted
4 unchanged
```

Varios comandos en una sola llamada, con los números de línea del archivo tal como estaba al empezar:

```bash
gdsex <<'EOF'
function player.gd:42:take_damage
local player.gd:50:speed
connect player.gd:20:timeout
tidy player.gd
EOF
```

La IA no vuelve a escribir lo que la herramienta ya sabe: la firma de una función nueva, el tipo de una variable, el orden de los miembros, el código que se mueve. Y lo que lee de vuelta es un resumen, no el archivo.

## 2. Decisiones

### Acordadas en la conversación

- **No portar a Rust ni a C++.** La IA tarda segundos por turno. Godot headless tarda unos 0,3 s en arrancar y cada acción tarda de 1 a 170 ms en scripts de hasta 2.600 líneas (apartado 5). Los tokens dependen de la interfaz, no del lenguaje.
- **Una CLI sobre el código actual y una skill encima.** Usabilidad y tokens antes que todo lo demás.

### Decididas al redactar

Las referencias "decisión N" del resto del documento apuntan a esta lista.

1. **CLI y skill, no un servidor MCP.** Las herramientas MCP cargan su esquema en el contexto, y una CLI sirve igual a cualquier IA, a un script o a una CI. La skill solo entra en el contexto cuando hace falta.
2. **La CLI vive dentro del addon**, en `addons/gdscript_extreme_tool/cli/`, y va en las releases. No registra nada global: ni `class_name`, ni autoloads. Así se cumple lo que el README promete en "Footprint in your project".
3. **Un lanzador `gdsex` en `sh`** busca Godot y la raíz del proyecto, y ejecuta `cli.gd` con `--headless --no-header`. `--no-header` quita el banner de Godot (unos 15 tokens por llamada). `--quiet` no sirve, porque también calla los `print` de la CLI (apartado 5).
4. **Un destino se escribe `archivo:línea:texto`**, con líneas desde 1, como las muestran el editor y la herramienta Read. El formato está en 3.1.
5. **El texto del destino se selecciona exacto, y si la acción no se ofrece con esa selección, se reintenta con el cursor al principio del texto.** `make` en `shapes.make()` no es un valor, pero el cursor en `make` sí encuentra `shapes.make()`. Así la IA no necesita saber qué acción quiere selección y cuál quiere cursor.
6. **Si el texto no está en esa línea, se busca hasta 20 líneas más arriba o más abajo**, y el informe dice en qué línea estaba. La IA suele tener los números de antes de sus propias ediciones, y un error obligaría a leer otra vez el archivo. Si dos apariciones están a la misma distancia, es un error que da las dos líneas.
7. **Por defecto se imprime un informe, no un diff.** En `medium.gd` (767 líneas), Add Explicit Types cambia 90 líneas y su diff ocupa 12 KB (unos 3.000 tokens), cuando el informe es una línea. Cada comando muestra solo las líneas que la IA necesita (3.3). `--diff` da el diff completo.
8. **Las líneas se muestran como `N<tab>texto`**, el formato de Read, para que la IA use esos números directamente. Las rutas van relativas a la carpeta de trabajo, como las escribió quien llamó.
9. **Cada archivo se escribe una sola vez, al final, y solo si cambió.** Un archivo sin cambios conserva su fecha de modificación: ni el editor de Godot ni Claude Code lo dan por modificado. Se conservan `\r\n` y el salto de línea final.
10. **Los lotes se leen de la entrada estándar, un comando por línea.** Todos los números de línea se refieren a los archivos como estaban al empezar la llamada, y la CLI los traslada a través de los cambios anteriores (3.4). Si un comando falla, siguen los demás y el código de salida es 1.
11. **`function` sobre un archivo entero crea todas las funciones que faltan**, también las de otros scripts. Así la IA escribe las llamadas y crea todas las firmas con una sola orden.
12. **`init` reúne las dos acciones de init.** Sin opciones hace lo mismo que Generate Default Init Definition. Con `--name` o `--vars` hace lo mismo que la versión del diálogo. Si la clase extiende `Node` o `Resource` o ya tiene `_init`, usa el nombre alternativo de los ajustes (`initialize`), igual que el diálogo.
13. **`tidy` aplica Add Explicit Types, Reorder y Format** a la clase del script y a cada clase interna. `--only types,format` elige los pasos. Ninguno de los tres cambia lo que hace el código, así que encajan como el último paso tras generar código.
14. **Una carpeta incluye sus `.gd` recursivamente, excepto `addons/` y `.godot/`**, salvo que la ruta pedida esté dentro de ellas. Un `tidy .` no debe tocar addons de terceros.
15. **La CLI nunca compila scripts del proyecto** (T1). Compilar ejecuta los inicializadores `static`, y en un proceso sin editor eso es ejecutar código del proyecto, que puede escribir en `user://`.
16. **Las clases globales salen de la caché de Godot, y si falta un nombre se hace un escaneo de `class_name`** en los `.gd` del proyecto. Solo pasa una vez y solo cuando falta un nombre. Una clase que la IA acaba de crear todavía no está en la caché, porque esta solo la actualiza el editor.
17. **La CLI lee y escribe el disco, no las pestañas del editor.** Si el editor tiene cambios sin guardar en ese archivo, Godot pregunta al volver a él. La skill y el README lo dicen.
18. **La lógica que convierte opciones en una elección pasa de los tests al addon.** Hoy `VariableTestAction.choose` y `ExtractTestAction` están en `tests/run_tests.gd`. La CLI y los tests usarán el mismo código, y los casos de prueba existentes lo cubren.
19. **Códigos de salida:** 0 si todo se aplicó o no había nada que hacer; 1 si un comando no se pudo aplicar o si `--check` encontró cambios; 2 si el uso es incorrecto; 3 si falta Godot, el proyecto o el addon.
20. **Nombres de comandos cortos y únicos, sin alias.** Un solo nombre por comando mantiene la skill corta y evita dudas. Se dice "function" y no "method", como en el resto del plugin.
21. **La skill está en inglés y en el propio proyecto**: `gdsex install` la copia a `.claude/skills/gdsex/SKILL.md`. Está en inglés como el código y el README.

### Decididas al implementar

Numeradas a continuación de las anteriores. Cuando una sustituye a otra, lo dice.

22. **La CLI arranca con un `MainLoop`, no con un `SceneTree`.** Con `SceneTree`, Godot crea los autoloads del proyecto antes de que empiece la CLI y ejecuta su `_init` y su `_ready` (apartado 5). Sin árbol de escena no hay autoloads. Las acciones funcionan igual, porque el `CodeEdit` nunca entra en el árbol.
23. **El código de salida pasa por un archivo temporal** (sustituye en parte a la decisión 19). Un `MainLoop` no tiene forma de fijar el código de salida: no existe `OS.set_exit_code` y `quit(code)` es de `SceneTree`. El lanzador crea un archivo con `mktemp`, se lo pasa con `--status-file` y sale con el código que la CLI escribió en él, o con 3 si Godot no llegó a escribirlo. Si se llama a Godot sin el lanzador, sale siempre con 0.
24. **El reintento con el cursor solo se hace con textos sin espacios** (sustituye a la decisión 5). Con `Vector2(0, 16) * index`, que no es un valor que el plugin sepa extraer, el reintento extraía solo `Vector2(0, 16)`: otro cambio del pedido. Con `make` o `damage(` sigue reintentando.
25. **`_load_script` rechaza los `.gd`, pero sigue cargando otros lenguajes** (sustituye a "En la CLI devuelve siempre `null`" de T1). Los `.gd` siempre se pueden leer del código fuente. Un script C# o de GDExtension no se puede leer, y cargarlo no ejecuta inicializadores de GDScript.
26. **En un lote, los números de línea de la salida son los del archivo final.** Cada bloque guarda sus líneas y se trasladan con cada cambio posterior, así que lo impreso se puede usar tal cual con Read.
27. **El resumen es `+añadidas -quitadas`**, con una línea cambiada contada en las dos. En `extract-function` se calcula con el plan y no con el diff, porque el diff ve el cuerpo movido como líneas sin cambios y mostraba `(+0)`.
28. **`types` sin nada que tipar dice `nothing to type`**, y si quedan variables sin tipo las lista igual (`nothing to type; untyped 12: ...`). En un archivo sin cambios ni variables sin tipo dice `unchanged`.
29. **Una posición encontrada fuera de su línea se anota en el resumen**: `player.gd +4; found on line 10`.
30. **El error de un comando que no aplica dice qué comandos sí aplican allí**, con los mismos nombres de la CLI: `local does not apply at player.gd:12:print. Available there: init, extract-function.`
31. **`init` sin variables privadas es un error** que propone `--vars` o `--all-vars`, en lugar de escribir un `_init` vacío.
32. **`install` copia el lanzador en lugar de enlazarlo.** El lanzador no depende del proyecto, y un enlace se rompería al mover o borrar el proyecto del que salió.
33. **El escaneo de `class_name` solo se hace para nombres que empiezan por mayúscula y no son clases del motor**, una vez por llamada, y recorre todo `res://` menos las carpetas ocultas, también `addons/`. Lo activa la CLI con `GDSExScriptLibrary.scans_for_global_classes`. En el editor está apagado.
34. **La CLI vacía la caché de `GDSExScriptLibrary` al terminar.** Sus entradas mantienen vivos los scripts del addon, y Godot avisaba al salir de objetos sin liberar.
35. **`cli_commands.gd` no precarga `generate_connected_function_action.gd`: la toma del registro de acciones.** Precargarla directamente hacía que Godot avisara al salir de 43 objetos y 14 recursos sin liberar (apartado 5), el mismo fallo que la nota de 2026-10-04 describe para el `EditorPlugin`. Las demás acciones sí se precargan, porque se usan funciones suyas que el tipo base no declara.
36. **La lógica que convierte opciones en una elección vive en el addon** (decisión 18): `GDSExExtractVariable.choice_from_options`, que además devuelve el motivo cuando una opción no vale, y `GDSExExtractFunction.alternative_with_form`. Los tests las usan también.
37. **El runner acepta `--failed-only`**, que solo imprime los fallos, los pendientes y el total. Lo pediste para no gastar tokens leyendo 1.400 líneas `PASS`.

## 3. Comportamiento

### 3.1 Destinos

| Forma | Qué señala |
|---|---|
| `player.gd` | El script entero. |
| `player.gd:42` | La línea 42: su clase para `reorder`, `format` e `init`, y su primer código para el resto. |
| `player.gd:30-38` | Las líneas 30 a 38 enteras: lo que se extrae con `extract-function`. |
| `player.gd:42:texto` | `texto` en la línea 42, o en la más cercana dentro de ±20 líneas. |
| `player.gd:texto` | La única aparición de `texto` en el archivo. Si hay varias, el error da sus líneas. |
| `-` | El código llega por la entrada estándar y el resultado entero sale por la estándar. `--as res://player.gd` le da una ruta para resolver `preload` y `extends`. |

Después de `.gd:` solo es un número de línea lo que encaja con `^\d+(-\d+)?(:|$)`. Todo lo demás es texto, y puede contener `:`. Para extraer el literal `120`, se escribe `player.gd:42:120`. Si el texto aparece varias veces en la línea, `--nth 2` elige la segunda.

Las rutas pueden ser relativas a la carpeta de trabajo, absolutas dentro del proyecto o `res://`. Una ruta fuera del proyecto es un error.

### 3.2 Comandos

| Comando | Acción del plugin | Destino | Opciones |
|---|---|---|---|
| `function` | Generate Function Definition | La llamada, o un archivo para todas las que faltan | — |
| `local` | Generate Local Variable | El identificador sin declarar | — |
| `member` | Generate Class Variable | El identificador sin declarar | — |
| `connect` | Generate Connected Function | La señal | — |
| `init` | Generate Default / Custom Init | Una línea de la clase | `--name`, `--vars a,b`, `--all-vars` |
| `types` | Add Explicit Types | El script | — |
| `extract-function` | Extract Function... | Las líneas | `--name`, `--form return\|assignment\|output\|plain` |
| `extract-variable` | Extract Variable... | El valor | `--name`, `--place block\|function\|class\|script`, `--const`, `--static`, `--private`, `--public`, `--onready` |
| `reorder` | Reorder Class Members | El script (todas sus clases) o una línea de una clase | — |
| `format` | Format Class Members | El script (todas sus clases) o una línea de una clase | — |
| `tidy` | `types` + `reorder` + `format` | Scripts y carpetas | `--only types,reorder,format` |
| `actions` | El menú Alt+Enter | Un destino | — |
| `help` | — | Un comando, opcional | — |

Sin opciones, cada comando hace lo que propone el diálogo: el mismo nombre, el mismo sitio y las mismas opciones. Una opción que el diálogo tendría apagada es un error con su motivo, el mismo texto del tooltip (`A constant cannot hold the result of 'make'.`). Los avisos de Extract Variable salen como `! texto` y no impiden el cambio.

Cuando un comando no se puede aplicar en el destino, el error dice qué comandos sí se pueden aplicar allí:

```
error: no missing function at player.gd:50:speed; available here: local, member
```

### 3.3 Qué imprime

Cada archivo que cambia tiene una línea de cabecera, `<ruta> <resumen>`, seguida de las líneas que la IA necesita ver. En los comandos que muestran código, el resumen son las líneas añadidas y quitadas (`+13 -9`). En los de script entero, lo que se hizo (`typed 12, reordered, formatted`). Los archivos sin cambios se cuentan en una sola línea final (`4 unchanged`).

| Comando | Muestra |
|---|---|
| `function`, `init`, `connect` | El código nuevo entero: la firma importa y es corto. |
| `local`, `member` | La declaración. |
| `extract-function` | La línea de la llamada y la firma nueva, con `(+N)` en lugar del cuerpo, que es código que la IA ya conoce. |
| `extract-variable` | La declaración y la línea donde quedó el nombre, y los avisos. |
| `types` | Solo el resumen: `typed 12; untyped 2: 40 total, 52 data`. Las variables que quedan sin tipo sí le sirven a la IA, porque puede ponérselo ella. Se muestran 10 como mucho. |
| `reorder`, `format`, `tidy` | Solo el resumen. |

Opciones generales:

| Opción | Efecto |
|---|---|
| `-q` | Solo las cabeceras. |
| `--diff` | Un diff unificado sin contexto (`-U0`) en lugar del informe. |
| `--check` | No escribe nada. Sale con 1 si algo cambiaría. Sirve para una CI. |
| `--print` | No escribe nada e imprime los archivos resultantes enteros. Es lo que hace `-` por defecto. |

Los errores salen como `error: ...`, en la salida estándar como todo lo demás. Así el que llama lo ve todo junto y en orden, y el código de salida dice si algo falló.

### 3.4 Lotes

Sin argumentos, `gdsex` lee comandos de la entrada estándar, uno por línea. Las líneas vacías y las que empiezan por `#` se ignoran. Si la entrada es una terminal, el lanzador muestra la ayuda en lugar de esperar (`[ -t 0 ]`). Cada archivo se lee una vez y se escribe una vez, al final.

Cada archivo tiene una correspondencia entre sus líneas al empezar la llamada y las de ahora. Después de cada cambio, la correspondencia se actualiza:

- Si el cambio no altera el número de líneas, como `types` o un `replace` de una línea, la correspondencia queda igual.
- Si lo altera, se usa la correspondencia que ya calcula el plan (`line_map` en Reorder y Format) o, en su defecto, un diff por líneas de la zona cambiada, quitando antes el principio y el final comunes.

Un destino cuya línea desapareció es un error que da el texto de esa línea.

### 3.5 Archivos

- **Carpetas**: incluyen sus `.gd` recursivamente, menos `addons/` y `.godot/` (decisión 14).
- **`--changed`**: los `.gd` que `git status` da como modificados o nuevos. Pensado para la IA al terminar una tarea y para un hook `Stop` de Claude Code, que deja el trabajo ordenado sin gastar tokens del modelo.
- **Función en otro script**: `function` escribe en ese archivo, y el informe lleva su ruta.
- **Ajustes**: los de `project.godot` se aplican igual que en el editor, porque Godot carga el proyecto con `--path`.

### 3.6 Lo que no hace

- No compila ni ejecuta scripts del proyecto (T1).
- No lee las pestañas del editor sin guardar (decisión 17).
- No resuelve scripts que no sean GDScript (C#, GDExtension): sus valores quedan sin tipo, igual que hoy los que no se pueden leer.

## 4. La skill

`gdsex install`, ejecutado desde el proyecto:

1. Copia `addons/gdscript_extreme_tool/cli/SKILL.md` a `.claude/skills/gdsex/SKILL.md`.
2. Si `~/.local/bin` está en el `PATH`, enlaza allí `gdsex`. Si no, lo dice y deja la ruta larga, que la skill también menciona.

La descripción entra en el contexto en cada sesión, así que es corta. El cuerpo solo se carga cuando la skill se usa, y aun así no pasa de unas 60 líneas. Borrador:

````markdown
---
name: gdsex
description: Write and refactor GDScript (.gd) in this Godot project with the gdsex CLI - typed function stubs, variables, signal callbacks, _init, explicit types, extract function/variable, reorder and format. Use it whenever you create, change or tidy .gd files.
---

# gdsex

Run `gdsex <command> <target> [options]` from the project. If `gdsex` is not found, run `sh addons/gdscript_extreme_tool/cli/gdsex`. It edits the files in place and prints only what you need.

## Targets
`file.gd` whole script · `file.gd:42` line 42 · `file.gd:30-38` lines 30 to 38 · `file.gd:42:text` that text on line 42 (found up to 20 lines away if it moved) · `file.gd:text` the only occurrence in the file. Lines start at 1, as Read shows them.

## Commands
- `function <call>` creates the missing function with typed parameters and return type, also in another script. On a whole file it creates every missing one.
- `local <name>` / `member <name>` declare an undefined identifier as a local / class variable, typed from its use.
- `connect <signal>` writes `signal.connect(_on_signal)` and the callback.
- `init <line>` writes `_init` that assigns the private variables. `--name`, `--vars a,b`, `--all-vars`.
- `extract-function <lines> --name n` moves the lines to a new function and leaves the call.
- `extract-variable <value> --name n` names a value. `--place block|function|class|script`, `--const`, `--static`, `--private`, `--public`, `--onready`.
- `types <file>` writes the type of every variable that has none.
- `tidy <files or folders>` types, reorders and formats. `--changed` takes the .gd files changed in git.
- `actions <target>` lists what can run there.

## Spend fewer tokens
- Write loosely: `:=`, calls to functions that do not exist yet, members in any order. Then `gdsex function file.gd` and `gdsex tidy file.gd` write the signatures, types and layout.
- Never retype code to move it: use `extract-function` and `extract-variable`.
- Put several commands in one call. Their line numbers refer to the files before the call:
  gdsex <<'EOF'
  function player.gd:42:take_damage
  local player.gd:50:speed
  EOF
- Run `tidy` when you have finished a file. If gdsex changed a file you will edit again, Read only the lines it printed.

## Output
`path summary`, then `N<TAB>line` for the lines you need, `! warning` for behaviour changes, `error: ...` with exit code 1. Use `--diff` only to review every change.
````

Lo que la skill pide a la IA, ordenado por los tokens que ahorra:

1. **Extracciones**: mover 20 líneas a una función nueva sin reescribirlas es lo que más ahorra.
2. **`tidy` al terminar un archivo**: tipos, orden y formato sin escribirlos ni leerlos.
3. **`function` sobre el archivo entero**: todas las firmas de una vez.
4. **Generadores sueltos** (`local`, `member`, `connect`, `init`): ahorran poco en tokens. Su valor está en que los tipos y el sitio sean correctos.

## 5. Hechos comprobados

Medido el 2026-10-30 con Godot 4.7.2 en el Mac del proyecto.

### Tiempos

| Qué | Tiempo |
|---|---|
| Arranque de Godot headless hasta `_initialize` | 285–300 ms |
| Construir el contexto (índice y ámbitos), de 570 a 2.585 líneas | 13–55 ms |
| Add Explicit Types | 8–168 ms |
| Format Class Members | 25–158 ms |
| Reorder, init y el resto | 0,2–4 ms |
| La suite (1.305 casos) | 57 s |
| Prototipo: acciones de un script con base, y 3 acciones sobre 2 archivos grandes | 1,2 s en total, arranque incluido |

Rust llevaría los 150 ms a unos pocos, pero la IA no lo notaría: cada turno suyo dura segundos.

### Tamaño de lo que se imprimiría

Calculado con `diff -U0` sobre el resultado de cada acción. Los tokens se estiman a unos 4 bytes por token.

| Archivo | Acción | Líneas cambiadas | Diff `-U0` | Archivo entero |
|---|---|---|---|---|
| `extract_variable.gd` (767 líneas) | Add Explicit Types | 90 | 12,1 KB (~3.000 tokens) | 36,8 KB (~9.000) |
| `extract_variable.gd` | Format | 3 quitadas, 19 nuevas | 0,5 KB | — |
| `extract_variable.gd` | Reorder | 3 | 0,5 KB | — |
| `run_tests.gd` (2.585 líneas) | Add Explicit Types | 344 | 52 KB (~13.000 tokens) | 136,6 KB |

Un informe de una línea ocupa unos 15 tokens (decisión 7).

### Godot headless

- `--no-header` quita el banner. `--quiet` calla también los `print` del script, así que no sirve.
- Un `CodeEdit` creado con `new()` y sin añadir al árbol funciona con `GDSExCodeContext` y `GDSExEditApplier`.
- `OS.get_environment("PWD")` da la carpeta desde la que se llamó. El lanzador la pasa igualmente con `--cwd`.
- La caché de clases globales (`.godot/global_script_class_cache.cfg`) se lee en headless: `Gadget.new()` se resolvió como `Gadget`.

### Compilar ejecuta código del proyecto

En un proyecto de prueba, `child.gd` extiende `"res://base.gd"`, y `base.gd` tiene `static var marker: int = _mark()` con un `print`. Construir el contexto de `child.gd` y pedir las acciones disponibles imprimió `STATIC INITIALIZER OF base.gd RAN`. La llamada viene de `GDSExTypeResolver.engine_base_type`, que pasa por `_load_script` para saber la clase del motor de la base.

La clase global `Gadget`, que también tenía un inicializador con `print`, no lo ejecutó: se resolvió desde su código fuente.

En la CLI se ejecutan, y por eso existe T1. No he comprobado si en el editor pasa lo mismo con los scripts sin `@tool`. T1 lo comprueba antes de cambiar nada.

Al instrumentar `_load_script` en una copia del proyecto y pasar la suite entera, solo `engine_base_type` cargaba scripts `.gd`: 668 cargas. Las otras dos llamadas a `_load_script` nunca recibieron un `.gd`, porque esos scripts ya se leen del código fuente.

### Los autoloads se ejecutan con `--script`

Con un autoload que imprime en su `_init` y su `_ready`, `Godot --headless --script` con un `SceneTree` imprimió los dos. Con un `MainLoop` no se creó el autoload, y un `CodeEdit` con `GDSExCodeContext` y Format funcionó igual (decisión 22).

### Un `MainLoop` no puede fijar el código de salida

En la API de 4.7.2, `OS`, `Engine` y `MainLoop` solo tienen `get_process_exit_code` y las funciones de reinicio. No hay ninguna para fijar el código propio (decisión 23).

### Leer la entrada estándar

`OS.get_stdin_type()` distingue una tubería (`STD_HANDLE_PIPE`) de un archivo y de la consola. `OS.read_buffer_from_stdin` lee por trozos hasta vaciarla, y 200 KB llegaron completos. La CLI solo lee la entrada en un lote o con `-`: si leyera siempre, se quedaría esperando con una tubería que nadie cierra.

### Precargar ciertos scripts deja objetos sin liberar al salir

Un `MainLoop` que solo precargaba `cli_commands.gd` dejaba al salir 43 objetos (scripts y `RegEx` estáticos) y 14 recursos sin liberar. Quitando los `preload` de uno en uno, solo desaparecía al quitar el de `generate_connected_function_action.gd`, que tiene variables `static` y extiende otra acción. Precargando el registro de acciones, que a su vez precarga esa acción, no pasa (decisión 35).

### Rendimiento con un proyecto real

Copia de los 140 scripts de `TastyDeath` (10.008 líneas) en el scratchpad, con `gdsex --check tidy .`:

| Medida | Valor |
|---|---|
| Tiempo total, arranque de Godot incluido | 1,9 s |
| Scripts que cambiarían | 55: 20 reordenados y 41 formateados (ninguno sin tipos) |
| Informe completo | 2,4 KB, unas 600 tokens |
| Diff `-U0` de los mismos cambios | 24,7 KB, unas 6.200 tokens |

Sobre el propio addon, `run_tests.gd` y `tools` (64 scripts que usan `:=` en todas partes), `--check tidy` tarda 6,1 s y escribiría 1.786 tipos.

## 6. Arquitectura

Archivos nuevos en `addons/gdscript_extreme_tool/cli/`:

| Archivo | Contenido |
|---|---|
| `gdsex` | Lanzador `sh`: busca Godot (`$GODOT`, `godot` o `Godot` en el `PATH`, `/Applications/Godot.app`), sube desde la carpeta de trabajo hasta `project.godot`, comprueba el addon y ejecuta `cli.gd`. También `install`. |
| `cli.gd` | `extends SceneTree`. Lee los argumentos o el lote, ejecuta y sale con su código. |
| `cli_session.gd` | Los archivos en memoria: lectura, finales de línea, correspondencia de líneas y escritura final. La lectura y la escritura pasan por dos `Callable`, para que los tests usen archivos en memoria. |
| `cli_target.gd` | Interpreta un destino y lo convierte en cursor y selección sobre un `CodeEdit` en memoria. |
| `cli_commands.gd` | La tabla de comandos: nombre, acción, opciones y qué líneas muestra. |
| `cli_report.gd` | Informes, diff `-U0` y errores. |
| `SKILL.md` | La skill que copia `install`. |

Cambios en lo que ya existe:

- `analysis/type_resolver.gd`: la clase del motor de una base se busca en el código fuente (T1).
- `analysis/script_library.gd`: el escaneo de `class_name` cuando falta un nombre (T5).
- `actions/extract_variable.gd` y `actions/extract_function.gd`: reciben de los tests la elección a partir de opciones (decisión 18).
- `tests/run_tests.gd`: un tipo de caso nuevo, `action: cli`, con `command:` en la cabecera, las secciones `=== input` y `=== expected` que ya existen, `=== expected res://...` para otros archivos y `=== output` para lo que se imprime.

Cada script nuevo lleva su `.gd.uid`, generado en una copia del proyecto antes de su commit.

## 7. Pasos

### T1 — El análisis no compila los scripts del proyecto

- `engine_base_type`, `find_member` y `_find_member_of_an_unread_base` siguen la cadena de `extends` en el código fuente, con `GDSExScriptLibrary`, hasta llegar a una clase del motor.
- `_load_script` queda solo para scripts que no son `.gd`. En la CLI devuelve siempre `null`.
- El editor usa el mismo código, así que sus resultados tienen que seguir iguales. La suite lo comprueba.

Pruebas: una base con un inicializador `static` que marca con `Engine.set_meta`, como `STATIC_GUARD_PROBE` en `run_tests.gd`, y casos que piden acciones en un script que la extiende. Variaciones: base por ruta relativa, por `uid://` y por `class_name`; cadena de tres scripts; ciclo; base en una carpeta desconocida; base que extiende `Node`, para comprobar que `@onready` e init se siguen ofreciendo como antes. Toda la suite actual tiene que seguir igual.

**Hecho (2026-10-30).** `engine_base_type` sigue la base con `GDSExScriptTypeNames.find_base_class`, que lee el código fuente, y `_load_script` devuelve `null` para cualquier `.gd`, también escrito como `uid://` (decisión 25). Se añadió la acción de prueba `describe_engine_base`. Muestra la clase del motor, las acciones ofrecidas, qué scripts de prueba quedaron compilados (`ResourceLoader.has_cached`) y si corrió el inicializador. Son 9 casos en `tests/cases/static_values`: base por ruta, por ruta relativa, base de la base, clase interna que extiende la base, clase interna que extiende otra interna, dos clases internas que se extienden entre sí, base global por `class_name`, clase del motor y base que no existe. Con el código anterior fallan los 9, y el primero con `static values ran: yes`. No hay caso con `uid://`: un `.uid` nuevo no entra en la caché de UIDs hasta que el editor escanea el proyecto, y el caso quedaría pendiente.

### T2 — Núcleo y comandos de script entero

`cli.gd`, la sesión, los destinos, los informes, `types`, `reorder`, `format` y `tidy` (todas las clases, también las internas, cada una con el índice reconstruido), `-q`, `--diff`, `--check`, `--print`, `-` con `--as`, los códigos de salida y `help`.

Pruebas, unos 40 casos: cada forma de destino; texto en otra línea dentro y fuera de ±20; texto ambiguo, en el archivo y en la línea, con `--nth`; ruta fuera del proyecto; `\r\n` y archivo sin salto final; archivo sin cambios que no se reescribe; `untyped` con más de 10 variables; `tidy` con una clase interna desordenada; `--only`; `--check` con y sin cambios; `-` con `--as` y un `preload` relativo. Dos casos de extremo a extremo con el binario real (`OS.execute`), en modo `--check` y `-`, para no escribir en el repositorio.

**Hecho (2026-10-30).** Archivos `cli.gd`, `cli_session.gd`, `cli_target.gd`, `cli_report.gd`, `cli_files.gd`, `cli_line_map.gd` y `gdsex.gd`. Reorder y Format ganaron `plan_for_class` para recorrer también las clases internas. El runner tiene el tipo de caso `action: cli`, con `command:`, `exit:`, `=== file <ruta>`, `=== expected <ruta>`, `=== stdin`, `=== output` y `=== error output`. Corre la CLI dentro del mismo proceso sobre archivos en memoria (`CliTestFiles`), comprueba cada archivo al final y falla si alguno se escribió sin cambios. Son 37 casos: tidy completo, con clases internas, sin cambios, `--only` en dos combinaciones y con un paso desconocido; variables sin tipo y su límite de 10; `types` solo y sin nada que tipar; varios archivos con uno sin cambios; carpeta, `res://` sin `addons/`, carpeta dentro de `addons/` y carpetas ocultas; archivo y carpeta inexistentes, ruta fuera del proyecto y un archivo que falta entre otros; reorder del script, en una línea, en un texto y en un texto de una clase interna; format; `--check` con y sin cambios, `-q`, `--diff` y `--print`; entrada estándar sin y con `--as`; comando y opción desconocidos, opción sin valor, comando sin destino y opciones antes del comando; finales de línea `\r\n` y archivo sin salto final, con la comprobación de que un archivo sin cambios no se escribe. Los casos de extremo a extremo quedaron en T6.

### T3 — Comandos en una posición

`function` (también en otro script, y sobre un archivo entero), `local`, `member`, `connect`, `init`, `actions`, y el error que dice qué se puede aplicar en el destino.

Pruebas, unos 35 casos: cada comando con selección exacta y con el texto dentro de otra expresión (para el reintento con cursor de la decisión 5); `function` en otro script y estática; `function` sobre un archivo con tres llamadas, dos al mismo nombre, para que solo se cree una; `init` en `Node`, con `_init` existente, con `--vars` y con `--all-vars`; `actions` en una línea vacía, en una llamada y en un valor.

**Hecho (2026-10-30).** 28 casos: `function` normal, con un texto dentro del nombre (`damage(`, que encuentra `compute_damage` por el reintento), encontrada 4 líneas más abajo, por su única aparición, en otro script, estática en otro script y sobre un archivo entero con dos llamadas iguales, una retrollamada de `connect` y una función de otro script; `function` sobre un archivo sin nada que crear; `local`; dos `member` en una orden con las líneas del principio; `member` sobre un nombre definido; `connect`; `init` por defecto, con `--vars` y `--name`, con `--all-vars`, en un `Node`, con `--name _init` en un `Node` (aviso), con una variable desconocida, sin variables privadas y con un nombre ocupado; `actions` en una llamada y en una línea vacía; texto repetido en el archivo, texto que no está cerca, texto que no está, texto a la misma distancia arriba y abajo, línea pasado el final, `--nth` en la línea y `--nth` mayor que las apariciones. Sobre un archivo, `function` crea las funciones justo detrás de la que las llama, como el menú, así que la última creada queda la primera.

### T4 — Extracciones con opciones

Mover al addon la elección a partir de opciones (decisión 18), `--name`, `--form`, `--place`, las cuatro opciones de Extract Variable con `--public`, avisos y errores con el motivo del diálogo.

Pruebas, unos 30 casos: cada sitio; cada opción permitida y prohibida, con su motivo; un valor que lee la variable de un bucle llevado a `function` (con aviso) y a `class` (con error); `--form` en una selección que termina asignando una variable de clase; nombre inválido; nombre por defecto que sigue a las opciones (`speed`, `SPEED`, `_speed`).

**Hecho (2026-10-30).** 24 casos. `extract-function`: varias líneas con nombre, una línea con el nombre por defecto, `--form assignment` y `--form plain` sobre la misma selección, una forma que no encaja (el error lista las que sí), líneas de bloques distintos, fuera de una función, con un `return` en medio, con dos resultados, nombre ocupado y sin líneas. `extract-variable`: en el bloque con nombre, con el nombre propuesto, como constante de la clase, desde una palabra de la llamada (`Vector2`), fuera del bucle con aviso, una operación sin paréntesis (error, decisión 24), un valor que lee la variable del bucle llevado a la función (error con el motivo del diálogo), variable pública de la clase, `--static` fuera de la clase, `--place script` en la clase del script, un sitio desconocido, un nombre que no es un valor y un nodo que pasa a `@onready` con su aviso. La suite de las dos extracciones (611 casos) siguió en verde al mover la lógica de opciones.

### T5 — Lotes, carpetas y clases nuevas

Lotes por la entrada estándar, la correspondencia de líneas, carpetas, `--changed` (con `OS.execute("git", ...)`, para que funcione también en Windows) y el escaneo de `class_name`.

Pruebas, unos 25 casos: lote con dos generadores en el mismo archivo, el segundo por debajo del primero; un destino cuya línea borró un comando anterior; `extract-function` seguido de `tidy`; un comando que falla en medio de un lote; carpeta con `addons/` dentro, y la misma carpeta pedida dentro de `addons/`; `--changed` fuera de un repositorio git; una clase global que no está en la caché y se resuelve igual.

**Hecho (2026-10-30).** 14 casos (las carpetas se probaron en T2): lote con comentarios y líneas vacías; números finales en la salida cuando un comando posterior inserta líneas por encima; un comando que falla y los demás siguen; una línea que `format` borró; comillas sin cerrar; comando desconocido en una línea; lote vacío; opciones de la llamada para todo el lote (`--check -q`); `extract-function` seguido de `tidy`; un destino que `reorder` movió y se encuentra; `--changed` con uno de dos scripts sin cambios, sin nada cambiado y fuera de un repositorio; y una clase global que solo existe en un archivo en memoria. Las líneas extraídas a una función nueva no cuentan como borradas: se movieron y la correspondencia las sigue hasta la función.

### T6 — Lanzador, instalación y skill

`gdsex` y `gdsex install`, los mensajes cuando falta Godot o el proyecto, y `SKILL.md`.

Pruebas: el lanzador desde una subcarpeta del proyecto, fuera de cualquier proyecto, con `$GODOT` apuntando a un binario que no existe, y con `install` repetido (no duplica nada ni pisa una skill modificada sin avisar).

**Hecho (2026-10-30).** Un caso, `launcher_runs_godot_and_installs`, que ejecuta el `sh` de verdad con `OS.execute`. Lo lanza desde `tests/fixtures` con `--check`, con código por la entrada estándar, con un comando desconocido (código 2), desde `/` (código 3) y con `GODOT=/missing/godot` (código 3). Después prueba `install` en una carpeta temporal con un `HOME` propio, para no tocar el `~/.local/bin` real: la primera vez copia la skill y el lanzador, con la skill cambiada a mano la deja y avisa, y con `--force` la reemplaza. La skill final está en `addons/gdscript_extreme_tool/cli/SKILL.md`. Es el borrador del apartado 4 con `tidy` al principio, como "the one to remember".

### T7 — Medidas y documentación

- Rendimiento: `tidy` sobre una copia del corpus de GUT (86 scripts) y sobre el propio addon, para dar el tiempo total y el tiempo por archivo.
- Tokens: un conjunto fijo de tareas en una copia de un proyecto de prueba, con `claude -p --output-format json` con y sin la skill, tres veces cada una. Se comparan los tokens de entrada y de salida. Las tareas son: añadir una mecánica que necesita tres funciones nuevas, partir una función larga en tres y tipar y ordenar un script suelto.
- Comprobar en esas sesiones si una lectura parcial (Read con `offset` y `limit`) basta para que Claude Code acepte un Edit después de que `gdsex` cambie el archivo. La regla de la skill depende de eso.
- Probar la variante del hook `Stop` con `gdsex tidy --changed -q`, y si ahorra, documentarla en el README.
- README (sección "Command line and AI agents") y CHANGELOG.

**Hecho en parte (2026-10-30).** Rendimiento medido (apartado 5). README con la sección "Command line and AI agents" y CHANGELOG con una entrada "Unreleased": la versión de `plugin.cfg` no cambia. No se midieron sesiones de un agente: en esta máquina no hay un `claude` en el `PATH`, solo el binario interno de la app de escritorio, que no usé. Tampoco se comprobó la lectura parcial ni el hook `Stop`. En su lugar, el apartado 11 compara lo que un agente tendría que escribir para hacer el mismo cambio a mano con lo que escribe y lee usando `gdsex`.

## 8. Qué queda fuera

| Qué | Por qué |
|---|---|
| Portar a Rust o C++ | Apartado 5: el tiempo no es el cuello de botella, y habría que rehacer ClassDB a partir de `extension_api.json`, compilar GDExtension para cada plataforma y mantener dos lenguajes. Tendría sentido para usarlo sin Godot instalado o como servidor LSP para otros editores. |
| Un servidor MCP | Decisión 1. |
| Un modo persistente (un proceso de Godot que recibe comandos) | Ahorra 0,3 s por llamada, que no se notan, a cambio de cachés que pueden quedar viejas. Si T7 muestra que hace falta, se añade después. |
| Un hook `PostToolUse` que ordene cada archivo justo después de que la IA lo escriba | El archivo cambiaría por debajo de la IA, que tendría que leerlo otra vez antes de su siguiente edición. El hook `Stop` de T7 no tiene ese problema. |
| `gdsex.cmd` para Windows | Claude Code en Windows usa Git Bash, donde funciona el lanzador `sh`. |
| Leer pestañas del editor sin guardar | La CLI no tiene acceso al editor (decisión 17). |
| Scripts C# | Igual que en el editor. |

## 9. Riesgos

- **Que T1 cambie algún tipo.** Hoy algunos tipos se resuelven compilando la base, y desde el código fuente podrían salir distintos. La suite completa y el corpus de GUT lo dirán, y lo que cambie se apunta aquí.
- **Que la correspondencia de líneas de un lote se equivoque tras un Reorder.** Las pruebas de T5 encadenan comandos después de un `reorder`. Si no es fiable, un destino posterior a un `reorder` en el mismo archivo pasa a ser un error claro, no una suposición.
- **El editor de Godot abierto con el mismo archivo y cambios sin guardar.** Godot pregunta qué versión quedarse. Se documenta, no se puede evitar desde fuera.
- **Que la IA no siga la skill.** T7 mide si de verdad baja el gasto. Si no baja, se corrige la skill antes de dar el plan por cerrado.
- **La versión de Godot.** La CLI usa el ClassDB del Godot instalado. Si el proyecto apunta a otra versión, algún tipo del motor puede diferir. Es lo mismo que pasa hoy en el editor.

## 10. Para revisar

Decisiones que tomé yo y que quizá prefieras de otra forma:

1. `tidy` incluye Reorder (decisión 13). Si prefieres que no mueva miembros salvo que se pida, se cambia a `types,format` por defecto.
2. `function` sobre un archivo entero crea todas las funciones que faltan (decisión 11).
3. La tolerancia de ±20 líneas (decisión 6).
4. `install` copia `gdsex` en `~/.local/bin` (decisión 32).
5. El Format del plugin escribe `"clave" : valor` con espacio antes de los dos puntos, y deja con indentación las líneas en blanco de una clase interna. Están fijados en sus tests, así que la CLI los aplica igual. `tidy` sobre el propio addon formatearía 28 scripts. No toqué nada de eso.
6. `function` sobre un archivo pone `count_items([]) + count_items([1])` como `-> Variant`, porque la suma no dice el tipo de cada llamada. Es lo mismo que hace el menú.

## 11. Resultado

### Lo que se ahorra

Lo que un agente tendría que escribir para hacer el cambio a mano (el diff) frente a lo que escribe y lee con `gdsex`. Los tokens se estiman a unos 4 bytes por token.

| Trabajo | A mano | Con `gdsex` |
|---|---|---|
| `tidy` de los 140 scripts de `TastyDeath` | 24,7 KB de diff, unas 6.200 tokens | orden de 10 tokens y 2,4 KB de informe, unas 600 |
| `types` de `extract_variable.gd` (90 variables) | 12,9 KB, unas 3.200 tokens | orden y 66 bytes de informe, unas 30 tokens |
| `extract-function` de 4 líneas | el cuerpo dos veces (quitarlo y escribirlo) más la firma y la llamada | 58 bytes de orden y 87 de informe |
| Una función nueva con su firma | la firma, unos 15 tokens | orden e informe, unas 35 tokens |

La última fila es la honesta: crear una función suelta no ahorra tokens. Su valor está en que los tipos y el sitio salen bien. Lo que ahorra de verdad es `tidy` y las extracciones, y más cuanto más grande es el cambio.

Además, Claude Code exige volver a leer un archivo cambiado desde fuera antes de editarlo. Por eso la skill pide pasar `tidy` después de la última edición de cada archivo.

### Lo que queda

- **Medir sesiones reales de un agente con y sin la skill.** Desde una terminal con Claude Code instalado, en una copia de un proyecto, con las tres tareas de T7 y `claude -p --output-format json`, comparando `usage`. Eso dirá también si leer solo las líneas impresas basta para que Claude Code acepte el siguiente Edit.
- **El hook `Stop` con `gdsex tidy --changed -q`.** No se probó.
- **Windows.** El lanzador es `sh` y no se ha probado en Git Bash.
- **Un caso con `uid://`** para T1, cuando el editor haya escaneado el `.uid` de la base de prueba.
