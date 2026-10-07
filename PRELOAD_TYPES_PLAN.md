# Plan — Tipos de otros scripts (`preload`)

Hoy el plugin solo conoce bien los tipos del script que se está editando. Si un valor viene de otro script cargado con `preload` (una función estática, una clase interna, un miembro de una instancia), su tipo es desconocido y cada acción hace lo que puede sin él. El plan es que el plugin lea esos otros scripts con su propio análisis y que todas las acciones se beneficien a la vez, porque todas resuelven los tipos en el mismo sitio.

| Paso | Contenido | Estado |
|---|---|---|
| P1 | Biblioteca de scripts: rutas, lectura y caché | Hecha |
| P2 | De un nombre a la clase de otro script, y sus miembros de tipo básico | Hecha |
| P3 | Tipos del otro script nombrados desde el script actual | Pendiente |
| P4 | Herencia y clases globales por el mismo camino | Pendiente |
| P5 | Repaso acción por acción y reglas de seguridad | Pendiente |
| P6 | Pruebas masivas, rendimiento y documentación | Pendiente |

Cada paso termina con la suite en verde y una pasada de `--headless --editor --quit` sin errores ni avisos. Los commits los hace el usuario al cerrar cada paso.

## 1. Qué cambia

```gdscript
const GDSExSymbolIndex = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index.gd")


func run(index : GDSExSymbolIndex.GDSExSymbolIndexData, line : int) -> void:
	var info := GDSExSymbolIndex.get_scope_info_for_line(index, line)
	var scope := info.scope
	var root := GDSExSymbolIndex.GDSExClassScope.new()
```

Hoy "Add Explicit Types" no toca ninguna de las tres variables. Con el plan:

```gdscript
	var info: GDSExSymbolIndex.GDSExScopeInfo = GDSExSymbolIndex.get_scope_info_for_line(index, line)
	var scope: GDSExSymbolIndex.GDSExScopeBase = info.scope
	var root: GDSExSymbolIndex.GDSExClassScope = GDSExSymbolIndex.GDSExClassScope.new()
```

Lo mismo en el resto de acciones:

| Acción | Qué gana |
|---|---|
| Add Explicit Types | Tipa las variables cuyo valor viene de otro script. |
| Extract Function... | Parámetros y valor devuelto con tipo, y deja de rechazar selecciones por «tipo desconocido». |
| Generate Function Definition | Tipos de los parámetros cuando los argumentos vienen de otro script, y tipo devuelto cuando el resultado se pasa a una función de otro script. |
| Generate Local Variable / Class Variable | El tipo de la variable cuando se deduce de una función o de un miembro de otro script. |
| Generate Connected Function | Los parámetros de una señal declarada en otro script. |

Reorder, Format y las dos acciones de init no dependen de tipos de otros scripts y no cambian.

### Por qué no basta con preguntar al motor

Godot permite preguntar a un script cargado por sus funciones y variables, y el plugin ya lo hace para los scripts base. Pero el motor no dice qué clase de script devuelve una función: solo su clase nativa. Medido el 2026-10-07 sobre `symbol_index.gd`:

| Función | Devuelve en el código | Lo que dice el motor |
|---|---|---|
| `parse_type` | `GDSExTypeData` | `RefCounted` |
| `get_scope_info_for_line` | `GDSExScopeInfo` | `RefCounted` |
| `find_variables` | `Array[GDSExVariableSymbol]` | `Array[RefCounted]` |
| `find_top_level` | `int` | `int` |

Escribir `RefCounted` compila, pero es peor que no escribir nada: la variable pierde sus miembros conocidos. Por eso hay que leer el otro script con el análisis del propio plugin, que sí conserva los nombres.

## 2. Decisiones acordadas

Las tomó el usuario el 2026-10-07.

1. **Clases globales.** Entran también las clases con `class_name`. Es el mismo mecanismo y cambia solo de dónde sale la ruta del script. Hoy `Cosa.new()` no se resuelve, y de una variable tipada con una clase global el motor da `RefCounted` para sus clases internas.
2. **Versión del otro script.** Si el otro script está abierto en una pestaña con cambios sin guardar, se lee lo que hay en la pestaña. Si no, el archivo. Consecuencia que hay que conocer: Godot compila contra la versión guardada, así que si el plugin usa algo que aún no has guardado en la otra pestaña, Godot marcará un error en el script actual hasta que la guardes.
3. **Tipo que no se puede escribir.** Cuando ninguna constante del script actual lleva hasta la clase, el valor se queda sin tipo, como hoy. El plugin no añade constantes `preload` por su cuenta.
4. **Versión.** Entra en la 0.3.0.

Comprobado el 2026-10-07 en un editor sin ventana con tres pestañas, una de ellas un archivo que no es un script: el editor de scripts permite saber qué pestaña es de qué script y leer su texto, y lo que hay sin guardar no está ni en el archivo ni en el script cargado (`Script.source_code`). Un script que llama a una función sin guardar de otro no compila.

## 3. Detalles decididos al redactar

No los ha fijado el usuario; son la forma concreta que propongo y se pueden cambiar sin rehacer el plan.

- **D1. Qué nombre se escribe cuando hay varios.** Por este orden: el `class_name` del script si lo tiene, una constante de la propia clase, una heredada, una de la clase que la envuelve, y por último una constante de otro script alcanzado (`GDSExB.GDSExC`). Entre dos constantes iguales en orden gana la primera declarada.
- **D2. Un solo salto intermedio.** Se nombra a través de otro script como mucho una vez (`GDSExB.GDSExC.Interna`). Más allá no se busca: el tipo queda sin nombre.
- **D3. Caché por ruta y contenido.** El análisis de cada script se guarda y se reutiliza mientras su texto, el de la pestaña o el del archivo, sea el mismo. Se comprueba una vez cada vez que se abre el menú o se ejecuta una acción, no en cada consulta. Se vacía al desactivar el plugin. Si en modo editor provoca avisos de recursos sin liberar, se sustituye por una caché que dura lo que el menú; el coste medido lo permite (apartado 7).
- **D4. El motor, solo como último recurso.** La consulta al motor se mantiene para los scripts que no se puedan leer como texto. Deja de usarse para los scripts base y las clases globales, que pasan a leerse igual que los de `preload`.
- **D5. Otro script no se edita, por ahora.** Una clase de otro script sirve para leer tipos. Las acciones que insertan código en una clase (por ejemplo generar la función que falta en una clase interna) solo actúan si la clase está en el script que se edita. La comprobación va en un único sitio, para que una versión futura que sí cree funciones en otros scripts solo tenga que cambiar ese punto (apartado 8).
- **D6. Nombre tapado por una clase global.** En una anotación de tipo, Godot busca antes las clases globales que las constantes del script. Si el nombre que tocaría escribir empieza por una palabra que es además una clase global distinta, el tipo se da por no escribible.
- **D7. Rutas.** Se admiten `res://`, rutas relativas a la carpeta del script que se edita y `uid://`. Un script nuevo que aún no se ha guardado no tiene carpeta: sus rutas relativas no se resuelven.
- **D8. Variables sin tipo.** Las reglas de prudencia de "Add Explicit Types" para las variables declaradas con `=` se extienden a los otros scripts: una función de otro script que no declara lo que devuelve, o una variable suya sin tipo, no bastan para tipar. Las declaradas con `:=` no se ven afectadas, porque Godot ya exige que su valor tenga tipo.
- **D9. Scripts de prueba.** Los casos necesitan scripts reales en disco. Van en `tests/fixtures/`, que no se exporta. Uno de ellos declara un `class_name`; sus casos quedan como pendientes, con un mensaje, cuando la caché de clases globales del proyecto no lo conoce (un clon recién hecho que no ha abierto el editor).
- **D11. Una clase escrita por su ruta se nombra con esa ruta.** `Shapes.Circle.new()` es de tipo `Shapes.Circle`: si el usuario pudo escribir esa ruta para llegar a la clase, la misma ruta vale como tipo. Salió en P2 y resuelve ya las instancias de clases internas de otro script, y también las de una clase anidada del propio script (`Outer.Nested.new()`), que antes no se reconocían.
- **D10. Pestañas y scripts.** Godot da por separado la lista de scripts abiertos y la de pestañas, y la segunda incluye las de archivos que no son scripts. Se emparejan por orden, descartando esas. Si las cuentas no cuadran, no se lee ninguna pestaña y se usa el archivo de todos los scripts: es la dirección segura. Fuera del editor (los tests) el texto sin guardar se da a mano.

## 4. Comportamiento

### 4.1 Cómo se llega a otro script

| Forma | Entra |
|---|---|
| `const X = preload("ruta.gd")` y `const X := preload(...)` en la clase, en una clase que la envuelve o en una clase base | Sí |
| `extends "ruta.gd"` | Sí |
| `class_name` global | Sí |
| `var X = preload(...)` | No: Godot tampoco deja usarla como tipo |
| `load(...)`, `get_script()` y scripts creados en ejecución | No: no se sabe qué script es hasta ejecutar |
| Autoloads | No en este plan (apartado 8) |

### 4.2 De un nombre a una clase

Un nombre con puntos se resuelve trozo a trozo. El primero puede ser una clase interna del archivo, una constante con `preload` o una clase global. Cada uno de los siguientes es una clase interna, una constante con `preload` o un enum de la clase a la que se ha llegado.

Vale igual para una anotación (`var s : GDSExSourceScanner.GDSExStatement`) que para una expresión (`GDSExSymbolIndex.GDSExClassScope.new()`).

### 4.3 Miembros de la clase alcanzada

Se leen del análisis de su archivo, igual que los de una clase interna del script actual:

- Funciones, estáticas o no, con el tipo que declaran. Si no declaran ninguno se deduce de sus `return`, como ya se hace en el script actual; eso es una suposición y "Add Explicit Types" no la usa para tipar (detalle D8).
- Variables y constantes, con su tipo declarado o el de su valor. Un valor que depende de otras cosas de ese script se resuelve dentro de ese script.
- Señales con sus parámetros.
- Clases internas, constantes con `preload` y enums.
- Lo heredado: la búsqueda sigue por la clase base, esté en el mismo archivo, en otro (`extends "ruta.gd"` o una clase global) o en el motor.

### 4.4 Nombrar el tipo desde el script actual

Es la parte nueva de verdad. En `source_scanner.gd` una variable está declarada como `Array[GDSExPiece]`. Ese texto solo vale dentro de `source_scanner.gd`; desde otro script hay que escribir `Array[GDSExSourceScanner.GDSExPiece]`.

- Tipos básicos, clases del motor y clases globales se escriben igual en todas partes.
- Una clase de otro script se escribe con el nombre que lleva hasta su archivo (detalle D1) seguido de sus clases internas.
- Un enum de otro script, igual: `GDSExB.Kind`.
- Los tipos de dentro de `Array[...]` y `Dictionary[..., ...]` se traducen uno a uno.
- Si no hay forma de escribirlo, el tipo es desconocido (decisión 3).

La regla para las acciones es que nunca reciben un tipo con el nombre de otro archivo: lo que sale del resolvedor ya está escrito para el script que se edita. Así las acciones no cambian.

Comprobado compilando en Godot 4.7.2 el 2026-10-07: valen como tipo `Alias.Interna`, `Alias.Interna.MasInterna`, `Alias.Enum`, `Array[Alias.Interna]`, un alias heredado del script base, `Alias.OtroAlias` (una constante con `preload` de otro script) y `Global.Interna`. Dos scripts que se cargan mutuamente con `preload` compilan.

### 4.5 Qué se lee y cuándo

- El script que se edita, de la pestaña, con sus cambios sin guardar. Como hoy.
- Los demás, de su pestaña si están abiertos con cambios sin guardar y del archivo si no (decisión 2), y solo cuando una acción necesita uno de sus tipos. Un script alcanzable que nadie consulta no se lee.
- Cada script leído se analiza una vez y se reutiliza mientras su texto no cambie (detalle D3).

## 5. Arquitectura

- **`analysis/script_library.gd`** (nuevo, P1). De una ruta al análisis de ese script, con la caché. Recibe el texto sin guardar de las pestañas; no pregunta al editor por su cuenta, para poder probarse sin él.
- **`open_scripts.gd`** (nuevo, P1). El único sitio que habla con el editor de scripts: qué ruta tiene la pestaña en la que se abre el menú y qué scripts abiertos tienen cambios sin guardar (detalle D10).
- **`analysis/script_type_names.gd`** (nuevo, P3). De una clase, quizá de otro archivo, al texto que la nombra desde el script actual; y la traducción de un tipo escrito en otro archivo. `type_resolver.gd` tiene ya 900 líneas y esto es una responsabilidad distinta.
- **`analysis/symbol_index.gd`** (P1). La constante con `preload` guarda la ruta, no solo que lo es. Cada análisis sabe de qué archivo es, y cada clase raíz a qué análisis pertenece, con una referencia débil para no crear ciclos. Resuelve las rutas relativas y `uid://`.
- **`analysis/symbol_index_builder.gd`** (P1). Lee la ruta del `preload`.
- **`analysis/type_resolver.gd`** (P2 a P4). Los puntos que hoy dan por hecho que solo hay un archivo: buscar una clase por su nombre, resolver un valor aplazado, deducir lo que devuelve una función y seguir la herencia. Cada miembro encontrado sabe en qué clase se encontró.
- **`actions/code_context.gd`, `code_actions_popup.gd`, `plugin.gd`** (P1). El contexto recibe la ruta del script abierto y el texto sin guardar de las otras pestañas. Al desactivar el plugin se vacía la caché.
- **`analysis/explicit_types.gd`** (P5). Enums de otros scripts y detalle D8.
- **`actions/generate_function_action.gd`** (P5). Detalle D5.
- **`tests/fixtures/`** (P1). Scripts de prueba.

Reglas del proyecto que aplican: prefijo `GDSEx` en todo tipo nuevo, «function» y no «method», ninguna variable `static` en scripts que `plugin.gd` precargue directamente, y código sin comentarios.

## 6. Pasos

### P1 — Biblioteca de scripts

- Ruta en la constante con `preload`: `res://`, relativa y `uid://`.
- Ruta del script abierto en el contexto. En el runner, una cabecera `script_path:` la simula.
- `script_library.gd`: lectura, análisis y caché.
- `open_scripts.gd` y el texto sin guardar de las pestañas en el contexto.
- Scripts de prueba en `tests/fixtures/`: uno con clases internas a dos niveles, un enum, funciones estáticas y de instancia, una señal y miembros con y sin tipo; uno que carga al anterior (alias de alias); uno base con constantes que otro hereda; dos que se cargan mutuamente.

No cambia el comportamiento de ninguna acción.

Verificación: `describe_scopes` enseña la ruta de cada constante; casos de rutas (absoluta, relativa, `uid://`, archivo que no existe, archivo que no es un script); un caso que modifica un archivo temporal y comprueba que se vuelve a analizar, y que no se vuelve a analizar si no cambió; texto sin guardar que gana al archivo; el control de memoria que ya existe, ampliado a la biblioteca. `open_scripts.gd` no se puede probar en la suite, que no tiene editor de scripts: se comprueba con una pasada en un editor sin ventana sobre un proyecto temporal.

Hecho el 2026-10-07:

- **Rutas.** La constante con `preload` guarda la ruta del script (`script_path`), ya resuelta: absoluta, relativa a la carpeta del script que se edita, o `uid://`. Lo mismo para `extends "ruta.gd"`. La resolución vive en `symbol_index.gd` y no en la biblioteca, para que el análisis no dependa de ella.
- **Análisis con dueño.** Cada análisis guarda la ruta de su archivo, y desde cualquier clase, función o bloque se llega al análisis al que pertenece (`GDSExSymbolIndex.find_index`).
- **`analysis/script_library.gd`** (`GDSExScriptLibrary`). `find_index(ruta)` devuelve el análisis del script, o nada si el archivo no existe o no es un script. Lo reutiliza mientras el texto sea el mismo, y esa comprobación se hace una vez por cada contexto que se crea, es decir, una vez al abrir el menú y otra al ejecutar la acción.
- **`open_scripts.gd`** (`GDSExOpenScripts`). Ruta de la pestaña en la que se abre el menú y texto de los scripts abiertos con cambios sin guardar. La ruta se pide primero a Godot para la pestaña activa; la lista emparejada solo se usa si el editor del menú no es el de esa pestaña.
- **Contexto, menú y plugin.** `GDSExCodeContext` recibe la ruta y los textos sin guardar; el menú se los pasa, y al desactivar el plugin se vacía la biblioteca.
- **Scripts de prueba** en `tests/fixtures/other_scripts/`: `shapes.gd` (clases internas a dos niveles, enum, señal, funciones estáticas y de instancia, miembros con y sin tipo), `drawing.gd` (carga a `shapes.gd`), `base_with_aliases.gd` (constantes para heredar, una con ruta relativa) y `cycle_first.gd` con `cycle_second.gd`, que se cargan mutuamente.
- **Runner.** Cabecera `script_path:` para dar la ruta del script del caso; `describe_scopes` enseña `script <ruta>` en cada constante que carga un script y `extends <ruta>` en cada clase con script base; `action: check_script_library` comprueba la biblioteca directamente.
- **5 casos nuevos**, 739 en total. El de la biblioteca hace 30 comprobaciones: lectura, reutilización, archivo cambiado, borrado y con finales de línea de Windows, texto sin guardar que gana al archivo, script que solo existe en una pestaña, rutas absolutas, relativas y `uid://`, el ciclo de dos scripts y la memoria tras vaciar. Se rompió la biblioteca a propósito de cuatro maneras y el caso detecta las cuatro.
- **En un editor sin ventana**, sobre un proyecto temporal con tres pestañas: ruta correcta de la pestaña activa y de otra pestaña, ninguna para la pestaña que no es un script, y la biblioteca ve una función añadida sin guardar en la otra pestaña mientras el archivo sigue igual. Cierra sin errores ni avisos.

Dos cambios visibles, pequeños, que salen de resolver las rutas:

- Una constante que carga un script por `uid://` cuenta ya como ese script, igual que una que lo carga por ruta.
- Los miembros de un script base dado con ruta relativa (`extends "base.gd"`) se encuentran; antes la ruta se probaba tal cual y no existía.

Queda para P2 dar texto sin guardar a un caso de la suite: hasta que no se lean miembros de otro script no hay nada que observar desde una acción.

### P2 — De un nombre a la clase de otro script

- Resolución de nombres con puntos (4.2), en anotaciones y en expresiones.
- Una constante con `preload` deja de ser un nombre suelto y pasa a apuntar a la clase raíz del otro script.
- Miembros de esa clase (4.3) cuando su tipo es básico, del motor o global, que no necesitan traducción. Los que devuelven una clase de script siguen siendo desconocidos hasta P3.
- Clases internas, constantes con `preload` y enums como miembros.

Verificación: casos en `tests/cases/other_scripts/`, observados con "Add Explicit Types" y con una acción nueva del runner, `describe_types`, que enseña el tipo que el resolvedor da a cada valor aunque la acción no lo escribiera. Como mínimo: función estática que devuelve `int`, miembro `String` de una instancia, de una clase interna y de una clase interna de segundo nivel, variable tipada con un nombre con puntos, parámetro tipado así, constante de otro script, y cada forma de 4.1 que no entra.

Hecho el 2026-10-07:

- **De un nombre a una clase** (`_find_type_class`). Un tipo con puntos se resuelve trozo a trozo: clase del archivo, constante con `preload` visible desde ahí (propia, de la clase envolvente o heredada) y, a partir del segundo trozo, clase interna o constante del script alcanzado. Vale para anotaciones y para expresiones.
- **Cada miembro sabe en qué clase se encontró**, y se resuelve en su propio archivo: su tipo declarado, su valor aplazado o lo que devuelve su función se leen con el análisis de ese archivo, no con el del script que pregunta.
- **Lo que sale de otro archivo se filtra.** Si el tipo se escribe igual en todas partes (básico, del motor, enum global), pasa tal cual. Si es una clase de ese script, pasa la clase pero sin nombre: se puede seguir la cadena (`Shapes.make().radius` es `float`) aunque `Shapes.make()` aún no se pueda tipar. Cualquier otro nombre se descarta. Lo mismo para los parámetros de funciones y señales.
- **Clases internas como miembros**, y detalle D11.
- **Detalle D5, adelantado desde P5.** Desde este paso el resolvedor devuelve clases de otros archivos, así que la protección no podía esperar. `GDSExSymbolIndex.is_declared_in` es el único punto que decide si una clase es del script que se edita; "Generate Function Definition" lo consulta antes de aceptar la clase del receptor.
- **Detalle D8, adelantado desde P5.** Para las variables declaradas con `=`, "Add Explicit Types" recoge los nombres de las funciones sin tipo de retorno y de las variables sin tipo de todos los scripts alcanzables, y no tipa a partir de ellos.
- **Texto sin guardar en los casos:** una sección `=== unsaved <ruta>` da el contenido de otra pestaña.
- **Runner:** `action: describe_types` enseña, para cada variable con valor, el tipo que da el resolvedor, la clase a la que llega y si es una referencia a la clase.
- **26 casos nuevos** para lo de arriba: 18 en `other_scripts/` y el resto en las carpetas de las acciones. Cubren función estática, constante, miembros de una instancia, clases internas a uno y dos niveles, variable y parámetro tipados con puntos, cadenas, colecciones tipadas, señal y referencia a función, script alcanzado a través de otro, constante heredada, de la clase envolvente y con ruta relativa (con y sin carpeta conocida), dos scripts que se cargan mutuamente, texto sin guardar, un nombre local que tapa a la constante, valores supuestos, y las formas que no entran. Se rompió el comportamiento a propósito de cinco maneras y los casos detectan las cinco.

Medido al cerrar el paso, sobre los scripts del proyecto:

| Medida | Antes | Ahora |
|---|---|---|
| Variables que "Add Explicit Types" deja sin tocar | 238 de 1.053 | 120 de 1.122 |
| Extracciones rechazadas por tipo desconocido | 130 de 19.783 rangos | 94 de 21.063 |
| Extracciones que no compilan | 0 de 9.596 | 0 de 10.407 |
| Abrir el menú con los otros scripts ya leídos | 17 ms de media, 156 ms el peor | 17 ms de media, 162 ms el peor |
| Abrir el menú la primera vez | igual que las siguientes | 30 ms de media, 245 ms el peor |

El total de variables y de rangos sube porque el proyecto tiene ahora más código. Las 120 variables que quedan son casi todas valores cuya clase ya se conoce y falta nombrar, que es P3. El peor caso del menú es `run_tests.gd`, que carga 24 scripts: la primera vez hay que leerlos todos.

Lo que se queda como estaba, a propósito:

- Los scripts base siguen consultándose al motor hasta P4. Un miembro encontrado así mientras se recorre otro script se trata como de ese script, para que sus nombres no se cuelen.
- Varios casos antiguos de "Extract Function..." usan un valor de otro script como ejemplo de «tipo desconocido». Siguen pasando porque ese tipo aún no se nombra; en P3 dejará de ser desconocido y habrá que darles otro ejemplo.

Un fallo que ya existía, encontrado por la prueba completa de extracciones y corregido en este paso: una clase o un enum anidados del propio script, a los que se llega por un miembro desde fuera de la clase que los contiene, se escribían con su nombre corto y el resultado no compilaba (`var nested: Nested = outer.nested` a nivel de script, cuando `Nested` está dentro de `Outer`). Ahora se escriben con la ruta completa (`Outer.Nested`, `Outer.Mode`) cuando quien pregunta no ve ese nombre, y con el nombre corto cuando sí lo ve: dentro de la propia clase, de una que ella envuelve o de una que hereda de ella. Es el mismo problema de «nombrar desde donde se escribe» de P3, dentro de un solo archivo. Tres casos más (768 en total), que fallan sobre el commit anterior.

### P3 — Tipos nombrados desde el script actual

- `script_type_names.gd`: nombre de una clase desde el script actual (D1, D2, D6) y traducción de un tipo escrito en otro archivo (4.4).
- Rehacer los casos de "Extract Function..." que usaban un valor de otro script como tipo desconocido.
- Los miembros que salen del resolvedor llevan ya el tipo traducido: variables, lo que devuelve una función, sus parámetros y los de una señal.
- Valores aplazados y tipos deducidos de los `return`, resueltos en el archivo al que pertenecen y traducidos al volver.

Verificación: un caso por regla de 4.4 y por detalle: clase interna, enum, `Array` y `Dictionary` tipados, alias propio frente a alias de alias, alias heredado, alias de la clase envolvente, tipo sin nombre posible, nombre tapado por una clase global, cadena de tres scripts, dos scripts que se cargan mutuamente y dos constantes para el mismo script.

### P4 — Herencia y clases globales

- La búsqueda de miembros heredados sigue por el análisis del script base en lugar de por el motor.
- Una clase global como referencia (`Cosa.new()`, funciones estáticas, constantes y enums) y como tipo de una variable, con sus clases internas.

Verificación: miembro heredado de un script base por ruta y por clase global, a uno y a dos niveles; alias declarado en la base; función de la base que devuelve una clase interna de la base; y los casos de clases globales con el script de prueba del detalle D9.

### P5 — Repaso acción por acción

- **Add Explicit Types:** enums de otros scripts (`var k := GDSExB.Kind.ONE` da `GDSExB.Kind`). El detalle D8 se hizo en P2.
- **Extract Function...:** parámetros y valor devuelto con tipos de otros scripts.
- **Generate Function Definition:** tipos de los parámetros y del valor devuelto. El detalle D5 se hizo en P2.
- **Generate Local Variable y Class Variable:** tipo deducido de una función o de un miembro de otro script.
- **Generate Connected Function:** parámetros de una señal de otro script.

Verificación: casos en la carpeta de cada acción, con variaciones: alias propio, heredado y alias de alias; clase interna; enum; tipo que no se puede escribir. Un caso por acción que compruebe que una clase de otro script no recibe código (D5).

### P6 — Pruebas masivas, rendimiento y cierre

- Las pruebas masivas que ya están en la suite pasan a ejercitar lo nuevo sin cambiarlas: tipar todos los scripts del proyecto y compilar, y extraer rangos y compilar.
- **Contraste con lo que ya está escrito.** En los scripts del proyecto, cada declaración con tipo explícito y valor es una respuesta correcta conocida. Comprobación nueva en la suite: cuando el tipo escrito es una clase de otro script, el plugin da para el valor ese mismo tipo, una clase que hereda de él o nada. Cualquier otra cosa es un fallo. Es la única prueba que detecta un tipo más pobre de la cuenta, que compila igual.
- Prueba completa de extracciones y el addon GUT como código ajeno con clases globales, lanzadas a mano.
- Tiempo de abrir el menú, con la caché vacía y llena, en los scripts más grandes.
- README, CHANGELOG, el listado de archivos de `REFACTOR_PLAN.md` y los apartados de límites de este plan y de `EXTRACT_FUNCTION_PLAN.md`.

## 7. Cómo se mide

Medido el 2026-10-07 sobre los 46 scripts del proyecto, antes de empezar.

| Medida | Hoy | Objetivo |
|---|---|---|
| Variables que "Add Explicit Types" deja sin tocar | 238 de 1.053 | Las que de verdad no tienen tipo conocido; se revisan una a una en P6 |
| De ellas, función estática de otro script | 116 | 0 |
| De ellas, miembro de un valor cuyo tipo viene de otro script | 95 | 0 |
| De ellas, instancia de una clase interna de otro script | 17 | 0 |
| Extracciones rechazadas por tipo desconocido | 130 de 19.783 rangos | Cerca de 0 |
| Extracciones que no compilan | 0 de 9.596 | 0 |
| Suite | 734 casos | Todos, más los nuevos |

Coste de analizar otros scripts, que es lo que se añade al abrir el menú la primera vez:

| Medida | Valor |
|---|---|
| Analizar los 46 scripts (11.146 líneas) | 185 ms en total, 4 ms de media |
| El más lento (`run_tests.gd`, 1.439 líneas) | 26 ms |
| Scripts que carga un script directamente | 3,7 de media, 23 el que más |
| Scripts alcanzables en total | 11,6 de media, 43 el que más |

Con la caché llena el menú no debería tardar más que hoy. Con la caché vacía, el peor caso posible en este proyecto es analizarlos todos: 185 ms una vez.

## 8. Límites que ya se conocen

- `load()`, `get_script()` y los scripts creados en ejecución.
- Lo que el plugin lee de una pestaña sin guardar, Godot aún no lo ve (decisión 2).
- Un tipo que no se puede escribir desde el script actual (decisión 3).
- Las rutas relativas de un script que aún no se ha guardado (detalle D7).
- Autoloads. El mecanismo serviría para leer sus miembros, pero un autoload no tiene nombre de tipo salvo que declare `class_name`. Queda como candidato para después.
- Scripts que no son GDScript.
- Generar código en otro archivo: "Generate Function Definition" sobre una instancia de otro script sigue sin ofrecerse (detalle D5).

### Para después: crear funciones en otro script

No entra en esta versión, pero este plan deja hecha la parte difícil: saber qué clase de qué archivo es el receptor de la llamada y tener ese archivo analizado, que es lo que hace falta para decidir dónde va la función. Faltaría:

- Aplicar la edición en otra pestaña: abrir el script si no lo está, insertar ahí y llevar al usuario, con el deshacer en esa pestaña.
- Decidir qué pasa con el nombre: una función privada (`_nombre`) llamada desde fuera es un aviso de estilo.
- `static` cuando la llamada es sobre la clase y no sobre una instancia.
- No ofrecerla si el otro script es de un addon ajeno o no se puede escribir.

## 9. Riesgos

- **Se toca el resolvedor, que usan todas las acciones.** Red: los 734 casos, las dos pruebas masivas que compilan el resultado y el contraste nuevo de P6. Cada paso se cierra en verde.
- **Un tipo más pobre compila igual.** Si por error se escribiera la clase nativa (`RefCounted`) donde va una clase de script, Godot no se queja. Lo cubren los casos con resultado exacto y el contraste de P6. Un tipo equivocado de otra clase sí lo rechaza el compilador (comprobado).
- **Escribir en el archivo equivocado.** Una clase de otro script tiene números de línea de otro archivo. Detalle D5 y un caso por acción.
- **Rendimiento.** Medido arriba; la caché lo reduce a la primera apertura.
- **Emparejar pestañas y scripts.** Godot no documenta que las dos listas vayan en el mismo orden. Detalle D10: si no cuadran se usa el archivo. Se comprueba en un editor sin ventana en P1 y otra vez en P6.
- **Memoria al cerrar el editor.** Una caché en una variable `static` puede dejar avisos al cerrar. Detalle D3 y la pasada de `--editor --quit` en cada paso.
