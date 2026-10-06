# Plan de refactorización — GDScript Extreme Tool

Godot 4.7.2. Estado de partida: una única utilidad ("Generate Function Definition" (antes "Generate Method Stub")) con la inserción acoplada a "método nuevo en una clase" y un índice de símbolos que calcula mal dónde termina cada miembro, sobre todo con lambdas y métodos anidados.

| Fase | Contenido | Estado |
|---|---|---|
| 0 | Git, tests headless, formato de parámetros | Hecha |
| 1 | Capa de edición genérica | Hecha |
| 2 | Índice fiable: sentencias, bloques y lambdas como scopes | Hecha |
| 3 | Resolución e inferencia compartidas | Hecha |
| 4 | Acciones y menú | Hecha |
| 5 | Generate local variable y Generate class variable | Hecha |
| 6 | Tipos compuestos, tipos inferidos e iteradores | Hecha |
| 7 | Generate Connected Function | Hecha |
| 8 | Vista y navegación tras generar | Hecha |
| 9 | Reordenar los miembros de una clase | Hecha |
| 10 | Dar formato a las líneas en blanco de una clase | Hecha |
| 11 | Ajustes en Project Settings | Hecha |
| 12 | Acciones bajo demanda: atajo y submenú | Hecha |
| 13 | Terminología: de «method» a «function» | Hecha |
| 14 | Acciones Generate Init (plan propio en `GENERATE_INIT_PLAN.md`) | Hecha |

## Objetivo

1. Que insertar código sea una capa genérica que cualquier utilidad pueda usar sin conocer `CodeEdit`.
2. Que el índice de símbolos dé rangos y scopes fiables, incluidos bloques, lambdas y métodos anidados a cualquier profundidad.
3. Que añadir una utilidad sea escribir un archivo nuevo y registrarlo.
4. Añadir dos utilidades sobre esa base: **Generate local variable** y **Generate class variable**.

Cada fase deja el plugin funcionando y los tests en verde.

## Decisiones de diseño

- **Las utilidades solo producen datos.** Una acción devuelve un `GDSExEditPlan`; `GDSExEditApplier` es la única clase que toca `CodeEdit`.
- **El final del archivo es una posición válida.** Un punto de inserción es "antes de la línea N", con N entre 0 y `line_count` inclusive. Se aplica con `insert_text`, no con `insert_line_at` (que no puede añadir al final).
- **La indentación se copia, no se calcula.** El punto de inserción lleva el texto de indentación de las líneas hermanas. La unidad para los niveles relativos del snippet se detecta del propio archivo; la configuración del editor (`is_indent_using_spaces()`, `get_indent_size()`) solo se usa si el archivo no tiene ninguna línea indentada.
- **El espaciado es un parámetro.** Cada punto de inserción pide un mínimo de líneas en blanco antes y después; el applier cuenta las que ya hay a ambos lados y añade solo la diferencia.
- **Tres tipos de scope.** Clases, funciones (métodos y lambdas) y bloques (`if`, `for`, `while`, `match`). La raíz es una clase más.
- **El índice parte de un árbol de sentencias**, no de líneas sueltas. Es lo que permite tratar bien las lambdas dentro de paréntesis.
- **Disponible = produce plan.** Una acción aparece en el menú contextual solo si `build_plan` devuelve algo.
- **Sin `class_name`.** Se mantiene `preload` en constantes para no ensuciar el espacio global del proyecto que instale el plugin.
- **Estilo.** GDScript tipado, en inglés, sin comentarios, y clases pequeñas en vez de diccionarios como resultado. El código generado usa `name: Type`.

## Estructura objetivo

```
addons/gdscript_extreme_tool/
├── plugin.cfg
├── plugin.gd
├── code_actions_popup.gd
├── init_function_dialog.gd
├── plugin_project_settings.gd
├── actions/
│   ├── action_registry.gd
│   ├── code_action.gd
│   ├── code_context.gd
│   ├── generate_function_action.gd
│   ├── variable_action.gd
│   ├── generate_local_variable_action.gd
│   ├── generate_class_variable_action.gd
│   ├── generate_connected_function_action.gd
│   ├── init_function.gd
│   ├── generate_default_init_action.gd
│   ├── generate_custom_init_action.gd
│   ├── reorder_class_members_action.gd
│   └── format_class_members_action.gd
├── analysis/
│   ├── builtin_types.gd
│   ├── bracket_layout.gd
│   ├── class_layout.gd
│   ├── language.gd
│   ├── member_categories.gd
│   ├── param_names.gd
│   ├── source_scanner.gd
│   ├── symbol_index.gd
│   ├── symbol_index_builder.gd
│   ├── token_spacing.gd
│   ├── call_site_parser.gd
│   └── type_resolver.gd
└── editing/
    ├── indentation.gd
    ├── snippet.gd
    ├── edit_plan.gd
    ├── placement.gd
    └── edit_applier.gd
tests/
├── run_tests.gd
├── main.gd
└── cases/
tools/
└── generate_builtin_types.gd
```

`code_inserter.gd`, `code_generator_unit_tests.gd` y `stub_generator.gd` ya están borrados.

## Piezas clave

### Edición (`editing/`)

```gdscript
class SnippetLine:
	var indent: int
	var text: String

class GDSExSnippet:
	var lines: Array[SnippetLine]
	var selection_line: int = -1
	var selection_from: int
	var selection_to: int

class GDSExInsertionPoint:
	var line: int
	var indent_text: String
	var blank_lines_before: int
	var blank_lines_after: int

class GDSExEditPlan:
	func insert(point: GDSExInsertionPoint, snippet: GDSExSnippet) -> void
```

- `GDSExEditApplier.apply(editor, plan)` aplica todas las ediciones de abajo arriba dentro de una sola operación compleja (un solo undo) y coloca la selección del snippet.
- El plan es una lista, así que reemplazar o borrar rangos se puede añadir cuando una utilidad lo necesite. De momento solo hace falta insertar.

### Colocación (`editing/placement.gd`)

Traduce una intención a un `GDSExInsertionPoint` usando el índice:

| Función | Dónde | Blancos antes / después |
|---|---|---|
| `after_member(scope)` | Tras el miembro de la clase destino que contiene la posición (método, propiedad o clase interna), por muy anidada que esté | 2 / 2 |
| `end_of_class(class_scope)` | Tras el último miembro de la clase | 2 / 2 |
| `class_header(class_scope)` | Tras la cabecera, si la clase está vacía | 1 / 2 |
| `member_variable(class_scope)` | Sección de variables de la clase (ver utilidades) | 0 o 1 / 2 antes de un método |
| `scope_start(scope)` | Primera línea del cuerpo de una función, lambda o bloque | 0 / 0 |

Las tres primeras son el comportamiento actual de `_compute_insertion_position`; las dos últimas son nuevas.

### Árbol de sentencias (`analysis/source_scanner.gd`)

Convierte las líneas físicas en sentencias anidadas. Cada sentencia conoce sus líneas propias, su indentación, su texto con comentarios y strings enmascarados, y los bloques que abre.

Reglas:

1. Los comentarios y el contenido de los strings (también los multilínea) se enmascaran antes de mirar nada más.
2. Un paréntesis, corchete o llave sin cerrar, o una barra invertida final, une las líneas siguientes a la misma sentencia.
3. Una sentencia que termina en `:` abre un bloque con las líneas siguientes más indentadas.
4. Una cabecera de lambda que termina en `:` al final de la línea abre un bloque **aunque haya paréntesis abiertos**. El bloque acaba en la primera línea menos indentada que su primera línea de cuerpo, y esa línea continúa la sentencia que quedó suspendida.
   - También puede acabar a mitad de línea: un cierre de paréntesis sin pareja (`_tick())`) o una coma final (`_on_start(),`) pertenecen a la sentencia exterior.
5. Una sentencia puede abrir varios bloques (dos lambdas en la misma llamada) y los bloques se anidan sin límite.
6. Las líneas en blanco y de comentario no abren ni cierran nada. Un comentario pertenece al bloque más interno cuya indentación de cuerpo alcanza.

Sobre el ejemplo de `tests/main.gd`:

| Líneas | Sentencia | Qué abre |
|---|---|---|
| 4–15 | `func _test_methods() -> void:` | Función (método) |
| 5–7 | `var nested_method = func(value: bool) -> float:` | Función (lambda) con parámetro `value: bool` y retorno `float`; el local `nested_method` es `Callable` |
| 9–13 | `_add_method(func(): … )` | Función (lambda anónima) con cuerpo en 10–12; la línea 13 `)` continúa la sentencia |
| 15 | `_add_method(nested_method)` | Nada |

Los comentarios de las líneas 8 y 14 pertenecen al cuerpo de `_test_methods`, no a las lambdas.

Una lambda de una sola línea (`func(): return 1`) no abre bloque y no crea scope.

### Índice (`analysis/symbol_index.gd`, `symbol_index_builder.gd`)

El builder recorre el árbol de sentencias y crea los scopes:

| Scope | Qué cubre |
|---|---|
| `GDSExClassScope` | La raíz y cada `class` interna |
| `GDSExFunctionScope` | Métodos y lambdas, con o sin variable, a cualquier profundidad (`is_lambda`) |
| `GDSExBlockScope` | `if`, `elif`, `else`, `for`, `while`, `match` y cada rama de `match` |

- Todo scope guarda su línea de cabecera, la primera línea de su cuerpo, su última línea, el texto de indentación de su cuerpo, sus hijos y sus locales en orden de declaración.
- El scope de una posición es el bloque que contiene su sentencia. La condición de un `if` pertenece al scope exterior, no al bloque que abre.
- La búsqueda de un nombre sube de scope en scope y solo considera declaraciones anteriores a la línea de uso. La variable de un `for` es un local de su bloque.
- Una propiedad con `set`/`get` y un valor multilínea ocupan todas sus líneas. El bloque de la propiedad es un scope propio, y `set` y `get` son funciones dentro de él.
- El fin de la cabecera de cada clase y sus miembros en orden de aparición se añaden en la fase 5, que es la primera que los necesita.
- Una sola expresión para `var`/`const` que cubre `:=`, tipos con genéricos y propiedades. Un valor que empieza por `func` es `Callable`.
- `parent` pasa a ser referencia débil (hoy cada construcción deja objetos sin liberar).

### Resolución (`analysis/`)

- **`language.gd`**: palabras clave que no son llamadas y las 130 funciones de `@GlobalScope` y `@GDScript` con su tipo de retorno, extraídas de la documentación del motor.
- **`call_site_parser.gd`**: encuentra las llamadas de una sentencia completa (no de la línea del cursor), con su receptor, sus argumentos y la llamada que las contiene. El receptor puede incluir llamadas, índices, strings y rutas de nodo (`get_parent().foo()`, `$Sprite/Child.hide()`).
- **`type_resolver.gd`**: un único punto de entrada para tipos y miembros.
  - `resolve_expression(expression, scope_info)`: tipo de una expresión encadenada. Empieza por literales, variables del scope, miembros propios o heredados, clases del archivo, tipos y singletons del motor, y funciones globales.
  - `find_member(owner, name)`: variable, método o señal de una clase del archivo o del motor, subiendo por la herencia (clases internas primero, luego ClassDB).
  - `is_function_defined(name, scope_info)`: métodos propios y heredados, funciones globales, constructores de tipos y clases del archivo.
  - `resolve_signal(expression, scope_info)`: la señal a la que apunta `x.signal_name`, con sus parámetros.
  - `expected_type(statement_code, call, scope_info)`: el tipo que el contexto espera de una llamada.
  - `default_value_text(type)`: el literal por defecto de un tipo.
  - `function_return_type(function, scope_info)`: el retorno declarado de un método o lambda o, si no lo declara, el tipo común de sus `return`.
- **`builtin_types.gd`**: métodos, miembros y tipo de elemento de los 38 tipos integrados (`String`, `Vector2`, `Array`, `Packed*Array`...). Está generado; no se edita a mano.

Tipos que se resuelven al consultarlos, no al construir el índice:

- Una variable con `:=` o `=` cuyo valor no es un literal guarda la expresión, y el resolvedor la evalúa con el scope de la línea donde se declara.
- La variable de un `for` guarda la expresión que recorre, y su tipo es el del elemento.
- Una variable que guarda una lambda queda enlazada con ella, de modo que `variable.call()` devuelve lo que devuelve la lambda. Funciona en cadena: una lambda que devuelve `otra.call()` hereda su tipo.
- Hay un límite de profundidad para que una función recursiva no cuelgue la resolución.

Operadores: comparaciones, `and`, `or` y `not` dan `bool`; `as T` da `T`; la aritmética da el tipo común de los operandos (`int` con `float` da `float`); el ternario da el tipo de sus dos ramas si coinciden.

`expected_type` decide así:

| Contexto de la llamada | Tipo |
|---|---|
| Es la sentencia entera (con o sin `await`) | `void` |
| Es un argumento completo de un método, de `emit` o de `connect` | El del parámetro |
| Es el valor completo de un `var`/`const` tipado | El declarado |
| Es el valor completo de una asignación a algo tipado | El del destino |
| Es la expresión completa de un `return` en una función o lambda con tipo | El de retorno |
| Es un operando de la condición de `if`, `elif` o `while` (con `and`, `or`, `not`) | `bool` |
| Cualquier otro caso en que el valor se usa | `Variant`, con `return null` |

### Acciones (`actions/`)

```gdscript
func get_label() -> String
func build_plan(context: GDSExCodeContext) -> GDSExEditPlan
```

- `GDSExCodeContext` se construye a partir del `CodeEdit`: líneas, índice, scope y sentencia de la posición del cursor, selección (como posiciones dentro de la sentencia) y unidad de indentación.
- `action_registry.gd` crea la lista de acciones y decide cuáles están disponibles para un contexto.
- En `_popup_menu`, el plugin añade al menú las acciones disponibles. Al pulsar una, vuelve a construir el contexto y el plan y lo aplica, de modo que nunca se usa un plan calculado sobre un texto anterior.
- Añadir una utilidad es crear `actions/<nombre>_action.gd` y añadir una línea en el registro. Sus casos de test usan `action: <nombre>`.

## Nombres de los parámetros generados

Valores por defecto en las constantes `DEFAULT_` de `plugin_project_settings.gd`, sobrescribibles desde Project Settings (fase 11):

```gdscript
const DEFAULT_GENERATED_PARAM_FORMAT : String = "p_{name}"
const DEFAULT_FALLBACK_PARAM_FORMAT : String = "param_{index}"
const DEFAULT_GENERATED_SIGNAL_CALLBACK_FORMAT : String = "_on_{name}"
```

- Si el argumento es un nombre simple (variable, constante, parámetro) o un parámetro de señal con nombre, se aplica `DEFAULT_GENERATED_PARAM_FORMAT` al nombre en minúsculas y sin guiones bajos iniciales: `event` → `p_event`, `CONST_1` → `p_const_1`, `_item` → `p_item`.
- Un nombre que ya tiene el formato (`p_item`) se deja igual.
- En cualquier otro caso (literal, `null`, `true`, `false`, `self`, expresión, lambda) o si el nombre se repite, se usa `DEFAULT_FALLBACK_PARAM_FORMAT` con la posición del argumento: `param_0`, `param_1`.

Al no empezar por `_`, el stub recién generado muestra el aviso `UNUSED_PARAMETER` de GDScript hasta que se usa el parámetro.

## Utilidades nuevas

Ambas parten de un identificador seleccionado (o la palabra bajo el cursor) que no esté definido.

### Generate local variable

La variable se declara en la primera línea del cuerpo del scope más interno que contiene la selección y admite declaraciones: función, lambda o bloque.

Con `my_item` seleccionado dentro de un `if`:

```gdscript
func _process(_delta: float) -> void:
	print("tick")
	if is_inside_tree():
		print("inside")
		_add_to_list(my_item)
```

Resultado, con `null` seleccionado para escribir encima:

```gdscript
func _process(_delta: float) -> void:
	print("tick")
	if is_inside_tree():
		var my_item: Object = null
		print("inside")
		_add_to_list(my_item)
```

Dentro de una lambda pasada como argumento, va al inicio del cuerpo de la lambda:

```gdscript
	_run_later(func():
		var my_item: Object = null
		print("later")
		_add_to_list(my_item)
	)
```

- **Tipo:** `expected_type_at`; sin tipo si no se puede inferir.
- **Valor inicial:** el literal por defecto para tipos de valor (`0`, `""`, `{}`, `Vector2(0, 0)`) y `null` para objetos.
- **Scopes que no admiten declaraciones:** un `match` (solo sus ramas), una clase y cualquier cuerpo de una sola línea. En esos casos se sube al scope padre.
- **No disponible** fuera de una función.

### Generate class variable

```gdscript
extends Node

var my_item: Object


func _add_to_list(item : Object) -> void:
	pass
```

- **Clase destino:** la clase más interna que contiene la selección, sea la raíz o una interna, con la indentación de sus miembros.
- **Dónde** (`GDSExPlacement.member_variable`), por orden de preferencia:
  1. Tras la última variable declarada antes del primer método, sin línea en blanco.
  2. Tras la última constante, señal o enum, con una línea en blanco.
  3. Tras la cabecera (`@tool`, `class_name`, `extends`, o `class Foo:` y su `extends`), con una línea en blanco.
- **Sin valor inicial**; la selección se queda donde estaba.

## Tests

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/run_tests.gd
```

- Argumentos tras `--`: trozos de ruta para filtrar casos y `--details` para ver por qué falla cada caso pendiente.
- El runner usa un `CodeEdit` real. Un caso falla si el texto o la selección no coinciden, si el motor registra algún error o si un solo undo no restaura el texto original.
- El texto esperado de cada caso se compila antes de ejecutarlo: si no es GDScript válido, el caso falla aunque esté pendiente. `compile_check: skip` lo desactiva para los casos que dejan otra llamada sin definir a propósito.
- El código de salida es distinto de 0 si algo falla. Un caso pendiente que pasa a funcionar también cuenta como fallo hasta que se le quita `status: pending`.
- El nombre de `action:` es el del archivo de la acción sin `_action.gd`, y la acción se busca en el registro.

Cada caso es un `.txt` en `tests/cases/`:

```
action: generate_function
status: pending
indent: spaces
=== input
...
	_add_event(event)<|>
=== expected
...
	<|pass|>
=== end
```

- `<|>` marca el cursor y `<|...|>` una selección, tanto en la entrada como en el resultado esperado.
- Sin sección `expected`, se espera que el texto no cambie.
- Una línea vacía antes del separador significa que el texto acaba en salto de línea.
- `action: describe_scopes` compara el árbol de scopes del script de entrada con una descripción en texto (líneas en base 1).
- `action: check_project_scripts` construye el índice de cada script de `addons/` y `tests/` y lo compara con la reflexión del motor.
- `action: check_no_false_targets` comprueba que el generador no encuentra ninguna llamada indefinida en esos mismos scripts.
- `action: apply_plan` prueba la capa de edición sin pasar por ninguna utilidad: la sección `=== plan` describe las inserciones en JSON (`line`, `indent_text`, `blank_lines_before`, `blank_lines_after`, `lines` y `select`).

## Fases

### Fase 0 — Red de seguridad (hecha)

- Repositorio git inicializado en la raíz, rama `main`, sin commits todavía.
- `tests/run_tests.gd` y los casos de `tests/cases/`.
- Los 17 stubs de `code_generator_unit_tests.gd` están cubiertos por casos y el archivo está borrado.
- Formato de nombres de parámetros implementado en `stub_generator.gd`.

### Fase 1 — Capa de edición genérica (hecha)

- `indentation.gd`, `snippet.gd`, `edit_plan.gd`, `edit_applier.gd` y `placement.gd` (con las tres colocaciones que ya existían).
- El generador de métodos produce un `GDSExSnippet` con indentación relativa y lo inserta a través de `GDSExEditPlan` y `GDSExEditApplier`.
- Arreglados: la inserción al final de un archivo sin salto de línea y los stubs con tabs en archivos indentados con espacios.
- Siete casos en `tests/cases/editing/` prueban la capa directamente: varias inserciones en un plan, principio y final del archivo, reutilización de líneas en blanco, indentación relativa y conservación de la selección.
- `code_inserter.gd` está borrado.

### Fase 2 — Índice fiable (hecha)

- `analysis/source_scanner.gd` produce el árbol de sentencias con las reglas de arriba.
- `analysis/symbol_index_builder.gd` crea los scopes de clase, función (métodos, lambdas y accesores de propiedad) y bloque. `symbol_index.gd` se ha movido a `analysis/` y se queda con los datos, las consultas y los ayudantes de tipos que la fase 3 pasará a `type_resolver.gd`.
- `GDSExPlacement` inserta tras el miembro de la clase destino que contiene la posición, usando su rango real, y copia la indentación del cuerpo de la clase.
- El generador de métodos sigue siendo el antiguo, adaptado al índice nuevo: busca los locales por scope y admite varios `return` por función.
- Arreglados: stubs insertados en medio de lambdas, propiedades y valores multilínea; tipos perdidos en lambdas anidadas; `:=`, genéricos sin valor inicial, firmas multilínea, `func` en comentarios y strings, locales con el mismo nombre en bloques distintos, y la fuga de memoria.
- Ocho casos en `tests/cases/scopes/` comprueban el árbol de scopes directamente. Uno de ellos compara el índice de cada script del proyecto con lo que devuelve el propio motor (métodos, señales, constantes, variables y clases internas).
- Coste medido: 8 ms para un script de 600 líneas y 79 ms para uno de 4.800.

### Fase 3 — Resolución e inferencia compartidas (hecha)

- `language.gd`, `call_site_parser.gd` y `type_resolver.gd`.
- El generador de métodos está reescrito sobre ellos: 218 líneas en vez de 603, sin la función de 130 líneas que infería el retorno.
- Qué se genera ahora:
  - Solo llamadas realmente sin definir. Se descartan los métodos heredados del motor o de una clase interna, las funciones globales, los constructores, las palabras clave y las llamadas sobre objetos cuyo tipo no es una clase del archivo.
  - El callback de un `connect`, esté donde esté el cursor en la sentencia.
  - Con varias candidatas en la misma sentencia: la que tiene el cursor en el nombre; si no, la llamada más interna que contiene el cursor.
  - `static func` cuando la llamada se hace desde una función estática o sobre el nombre de una clase.
- Cuando no hay nada que generar, la acción no hace nada. Los mensajes de error de la versión anterior han desaparecido; en la fase 4 la acción dejará de aparecer en el menú.
- Arreglado de paso: el valor por defecto de `String` era `"<null>"`.
- Comprobación nueva sobre los scripts del proyecto: como compilan, cualquier llamada que el generador tome por indefinida es un falso positivo. No hay ninguno en 1.203 llamadas.
- La variable de un `for` sobre un array tipado sigue sin tipo; pasa a la fase 6.

### Fase 4 — Acciones y menú (hecha)

- `actions/code_context.gd`, `code_action.gd`, `action_registry.gd` y `generate_function_action.gd`. `stub_generator.gd` está borrado.
- `plugin.gd` ya no conoce ninguna utilidad concreta: pide las acciones al registro y solo muestra las disponibles.
- Los tests pasan por el registro, igual que el menú. Además comprueban la disponibilidad: si el caso espera un cambio, la acción tiene que ofrecerse; si no espera ninguno, no.
- La comprobación de scripts del proyecto falla ahora si alguno no compila, incluido el del plugin.
- No verificable en headless: que el menú contextual del editor llame a `_popup_menu` con la ruta del `CodeEdit` y pase el `CodeEdit` al callback. Es lo que dice la documentación de Godot y lo que hacía la versión anterior; si falla, el plugin recurre al editor de scripts activo.

### Fase 5 — Utilidades nuevas (hecha)

- `actions/variable_action.gd` (base común), `generate_local_variable_action.gd` y `generate_class_variable_action.gd`, registradas en `action_registry.gd`.
- `GDSExPlacement.scope_start` y `GDSExPlacement.member_variable`. El índice guarda ahora el fin de la cabecera de cada clase, sus miembros en orden y los `enum`.
- Las dos acciones se ofrecen cuando el cursor o la selección están sobre un identificador sin definir que se usa como valor. No se ofrecen sobre el nombre de una llamada, tras un punto, en una declaración ni sobre nada ya definido: variables del scope, miembros propios o heredados, clases, tipos, singletons, funciones y constantes globales, y parámetros de una lambda de una línea.
- El tipo sale del contexto, igual que el retorno de un método: argumento, declaración tipada, `return`, condición. Además, si el identificador es el destino de una asignación (`total = 3 * 2`, `total += 1`), toma el tipo del valor asignado.
- **Local:** va a la primera línea del cuerpo del scope más interno que admite declaraciones, con el valor por defecto seleccionado (`null` para objetos y cuando no hay tipo).
- **De clase:** `static var` si el uso está en una función estática. Tras la línea `class Foo:` de una clase interna no se deja línea en blanco.
- **Miembros heredados de otro archivo.** Hacía falta para no ofrecer como indefinido lo que viene de un script base: `extends "res://..."` y `extends NombreGlobal` se resuelven cargando el script y leyendo sus métodos, variables, señales y constantes con la reflexión del motor. Lo mismo para una variable cuyo tipo es una clase global. Esto arregla también un falso positivo de Generate Method Stub en scripts que heredan de otro script.
- Comprobación nueva: ningún identificador de los scripts del proyecto se toma por indefinido.

### Fase 6 — Tipos compuestos, tipos inferidos e iteradores (hecha)

- **Tipos compuestos.** `Array[T]` y `Dictionary[K, V]` declarados, como parámetro, como retorno, por índice y como receptor.
- **Tipos inferidos de forma diferida.** `var first := values[0]`, `var child := get_child(0)` y `var foo := Foo.new()` ya tienen tipo.
- **Variable de un `for`.** Sobre `Array[T]`, `Dictionary[K, V]`, un `int`, un `String`, un `Packed*Array` o cualquier expresión que el resolvedor entienda (`get_children()`, `names.values()`).
- **Llamada sin definir usada como iterable.** `for value: int in _values():` genera `-> Array[int]`; sin anotación, `-> Array`.
- **Variables de un patrón de `match`.** `var other:` declara un local de la rama con el tipo de la expresión comparada.
- **Retorno de lambdas y métodos.** El declarado se guardaba ya; ahora se infiere también el no declarado a partir de los `return`, y `variable.call()` lo usa. `hola(level_1.call())` con tres lambdas anidadas genera `hola(param_0: String)`.
- **Operadores.** `count > 3` es `bool`, `count * ratio` es `float`, etc. Antes se tomaba el tipo del primer identificador de la expresión.
- **Tipos integrados.** `label.length()`, `position.x`, `values.front()`, `names.keys()` y `foos.append(_make_foo())` se resuelven con `builtin_types.gd` y con las reglas de genéricos de `language.gd`.

`while` no declara ninguna variable, así que no tiene iterador que tipar.

Descartado: los diccionarios tipados del motor. Ningún método de Godot 4.7.2 devuelve ni recibe uno, así que no hay nada que leer ni con qué probarlo.

Para regenerar `builtin_types.gd` con otra versión de Godot:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --dump-extension-api
```

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/generate_builtin_types.gd -- extension_api.json
```

El primer comando escribe `extension_api.json` en la carpeta actual; se puede borrar después.

### Fase 7 — Generate Connected Function (hecha)

Con el cursor sobre una expresión de tipo señal que ocupa toda la sentencia, completa la conexión y crea el método:

```gdscript
func _ready() -> void:
	my_signal.connect(_on_my_signal)


func _on_my_signal(p_value: int) -> void:
	pass
```

- **Qué se reemplaza.** La expresión puede estar sola o a medio escribir: `my_signal`, `my_signal.`, `my_signal.conn`, `my_signal.connect(` o `my_signal.connect()`. La parte de la señal no se toca; lo que venga detrás se sustituye por `.connect(_on_...)`.
- **Qué señales.** Propias (`my_signal`, `self.my_signal`), de una clase del archivo (`foo.changed`), del motor (`player.animation_changed`) y variables o parámetros de tipo `Signal` (sin parámetros conocidos).
- **Nombre del método.** `DEFAULT_GENERATED_SIGNAL_CALLBACK_FORMAT` aplicado al nombre de la señal sin guiones bajos iniciales (`String.lstrip("_")`): `_my_signal` da `_on_my_signal`. No incluye el nombre del objeto: `button.pressed` da `_on_pressed`.
- **Parámetros.** Los de la señal, con el formato de `DEFAULT_GENERATED_PARAM_FORMAT`.
- **Si el método ya existe**, solo se completa la expresión y el cursor queda detrás. Se mira la clase donde se crearía el método y sus clases base; un método con el mismo nombre en una clase exterior no cuenta, porque desde una clase interna no se puede llamar.
- **Regla general de visibilidad desde una clase interna:** de las clases exteriores solo se ven las constantes (incluidos `preload`, `enum` y clases internas). Sus métodos, variables y señales no cuentan como definidos para ninguna acción.
- **No se ofrece** en la declaración `signal ...`, si la conexión ya tiene argumento, con otro método (`emit`, `disconnect`) ni cuando la señal es parte de una expresión mayor (argumento, asignación, `await`).

Lo que ha hecho falta en las capas comunes:

- `GDSExEditPlan.replace(line, from_column, to_column, text)` y su aplicación en `GDSExEditApplier`, en el mismo undo que las inserciones. Sin selección de snippet, el cursor queda tras el texto reemplazado.
- `GDSExStatement.position_at(offset)` para pasar de una posición de la sentencia a línea y columna.
- **Recuperación ante paréntesis sin cerrar.** `my_signal.connect(` deja un paréntesis abierto, y el escáner unía las líneas siguientes a esa sentencia. Ahora una línea con indentación menor o igual que la de la sentencia, que no empieza por un cierre, una coma, un punto o un operador, empieza una sentencia nueva.

### Fase 8 — Vista y navegación tras generar (hecha)

- **Mostrar lo insertado es una petición explícita de la acción**, separada de dónde queda el cursor. `plan.insert(...)` devuelve la inserción y `plan.reveal(insertion)` indica cuál hay que enseñar. Una acción que inserte varios bloques elige el que le parezca más adecuado, o ninguno.
- **Qué acciones lo piden hoy:** método, función conectada (cuando crea el método) y variable local. Si el bloque ya se ve entero, la vista no se mueve; si no, se centra en él.
- **La selección no mueve la vista.** Un fragmento puede dejar el cursor seleccionando algo sin que se muestre, y se puede mostrar un bloque sin tocar el cursor.
- **El ajuste se repite en el frame siguiente.** Al insertar al final del archivo, el editor aún no ha ampliado su rango de scroll y el primer intento se queda corto. Era el motivo de que los métodos generados al final no se vieran.
- **Si la acción no pide mostrar nada, la vista no se mueve** (variable de clase, o completar una conexión cuyo método ya existe). Si se insertan líneas por encima de lo visible, el scroll se compensa para que el mismo código siga en el mismo sitio de la pantalla.
- **Se puede volver atrás.** Antes de saltar, el plugin emite `request_save_history` en el editor del script, de modo que el botón de historial "anterior" del editor de scripts devuelve el cursor a donde estaba. Comprobado en un editor headless: tras emitirla y saltar, el botón se activa y al pulsarlo el cursor vuelve a la línea original.
- La capa de edición no sabe nada del editor de scripts: el historial lo guarda `plugin.gd`, y `GDSExEditPlan.leaves_current_position()` le dice cuándo (hay un bloque que mostrar o una selección en lo insertado).

Casos en `tests/cases/view/`, con tres cabeceras nuevas:

- `viewport_lines`: alto del editor en líneas.
- `scroll_to_line`: línea (en base 1) que se coloca arriba antes de ejecutar la acción.
- `expect_view`: `caret_visible`, `unchanged` (la primera línea visible no cambia), `same_top_text` (se sigue viendo el mismo código arriba) o `text_visible` (la línea indicada en `view_text` queda a la vista).
- En los casos `apply_plan`, una inserción lleva `"reveal": true` para pedir que se muestre.

### Fase 9 — Reordenar los miembros de una clase (hecha)

"Reorder Class Members" reordena la clase donde está el cursor (la raíz o una interna, sin entrar en sus clases internas). Solo aparece en el menú si la clase no está ya en orden.

El orden es el ajuste `order/class_member_order`, cuyo valor por defecto es `DEFAULT_CLASS_MEMBER_ORDER` de `plugin_project_settings.gd`. La cabecera (`@tool`, `class_name`, `extends`) no se mueve:

1. Señales.
2. Constantes.
3. Variables `static`.
4. Enums.
5. Variables `@export`.
6. Variables `@onready`.
7. Variables públicas.
8. Variables privadas (nombre que empieza por `_`).
9. Clases internas.
10. Funciones `static` públicas.
11. Funciones `static` privadas.
12. `_init`.
13. Métodos del motor (los virtuales de la clase base según ClassDB: `_ready`, `_process`, `_input`...).
14. Métodos públicos.
15. Métodos privados.

Reglas:

- **Dentro de cada categoría se mantiene el orden actual.**
- **Variables con dependencias.** Si el valor inicial de una variable usa otra variable de la clase que se inicializa en la misma fase (`static`, normal u `@onready`), la segunda se declara antes aunque rompa el formato. La variable dependiente se retrasa hasta justo después.
- **`@export_category`, `@export_group` y `@export_subgroup`** forman un bloque con los `@export` a los que afectan, hasta la siguiente anotación de grupo.
- **`#region` ... `#endregion`** es un bloque indivisible, y se coloca según su primer miembro.
- **Anotaciones en línea propia** (`@export`, `@rpc(...)` encima de la declaración) viajan con el miembro y cuentan para su categoría.
- **Comentarios.** Cada bloque de comentarios va con el miembro más cercano, contando las líneas en blanco que lo separan; a igual distancia, con el de abajo. Dos excepciones: entre la cabecera y el primer miembro, y tras el último, un comentario solo viaja con el miembro si está pegado a él; si no, se queda en su sitio. Así la descripción de la clase no se mueve.
- **Comentarios con más indentación que el miembro** (código desactivado al final del cuerpo de un método, o el comentario final de una clase interna) son parte del miembro de arriba, haya o no líneas en blanco por medio.
- **Comentarios al final de una clase interna**, con la indentación de su cuerpo, entran en el tramo que se reordena: si están pegados al último miembro, viajan con él.
- **Líneas en blanco.** Entre dos bloques que ya eran consecutivos se conserva lo que había. Entre los demás: dos alrededor de métodos y clases, una entre categorías distintas, ninguna dentro de la misma categoría. Para normalizarlas todas está la acción de la fase 10.

Cómo se aplica:

- `analysis/class_layout.gd` calcula el texto nuevo recolocando los bloques originales copiados literalmente, sin regenerar código.
- Un único reemplazo (`GDSExEditPlan.replace_lines`), recortado al tramo que cambia, en un solo undo.
- Con el mapa de línea antigua a línea nueva se restauran el cursor, los breakpoints, los marcadores y los plegados, y el scroll se ajusta para que el cursor quede en la misma fila de la pantalla.

Límite conocido: las dependencias entre variables solo se detectan cuando el nombre aparece en el valor inicial. Si el valor llama a un método que lee otra variable, no se ve.

Tests:

- Casos de texto en `tests/cases/reorder_class_members/`. Cabeceras nuevas: `breakpoints`, `bookmarks` y `folds` (líneas en base 1 antes de la acción) con `expect_breakpoints`, `expect_bookmarks` y `expect_folds`, y `expect_view: caret_row_unchanged`.
- `action: check_reorder_project_scripts` reordena la raíz y todas las clases internas de cada script del proyecto y comprueba que no se pierde ni se duplica ninguna línea, que el resultado compila, que el motor ve los mismos métodos, señales, variables y constantes, y que reordenar otra vez no cambia nada. La acción modifica 8 de las 25 clases raíz del proyecto.

### Fase 10 — Dar formato a las líneas en blanco de una clase (hecha)

"Format Class Members" ajusta las líneas en blanco entre los miembros de la clase donde está el cursor y alrededor de sus comentarios, sin cambiar su orden ni tocar ninguna línea de código. Solo aparece en el menú si hay algo que cambiar. Como la fase 9, no entra en las clases internas: se tratan como un miembro más.

Las cantidades son ajustes de la sección `format/`, con sus valores por defecto en las constantes `DEFAULT_` de `plugin_project_settings.gd`:

| Entre | Líneas en blanco | Constante |
|---|---|---|
| Un método o una clase interna y cualquier otro miembro | 2 | `DEFAULT_BLANK_LINES_AROUND_FUNCTIONS_AND_CLASSES` |
| Miembros de categorías distintas (las de `DEFAULT_CLASS_MEMBER_ORDER`) | 1 | `DEFAULT_BLANK_LINES_BETWEEN_MEMBER_CATEGORIES` |
| Miembros de la misma categoría | Las que hubiera, con un máximo de 1 | `DEFAULT_MAX_BLANK_LINES_INSIDE_MEMBER_CATEGORY` |

Reglas entre miembros:

- **Dentro de una categoría se respeta la agrupación del usuario**: dos constantes seguidas siguen seguidas y las separadas por una línea siguen separadas; solo se recorta lo que pase de una.
- **`#region` y `#endregion`** no forman un bloque indivisible como en la fase 9, porque también hay que dar formato dentro: `#endregion` va con el miembro de arriba y `#region` con el de abajo.
- **`@export_group` y similares** tampoco agrupan: cuentan como un miembro de la categoría de exports.
- **No se toca el interior de los miembros**: cuerpos de métodos, enums multilínea, ni los comentarios con más indentación que el miembro. Las excepciones son los espacios sobrantes entre tokens y los cierres de corchetes de diccionarios, arrays y lambdas pasadas como argumento (ver más abajo).
- Una línea que solo tiene espacios o tabuladores cuenta como línea en blanco.
- **Las líneas en blanco entre miembros llevan la indentación de la clase**: vacías en el script raíz, con la indentación del cuerpo en una clase interna. Es como las deja el editor de Godot al escribir. Lo mismo hacen el reordenado y las acciones que generan código (cambio del 2026-10-06; antes quedaban siempre vacías).

Reglas de los comentarios. Hay dos clases de comentario: los del scope (su descripción al principio y lo que haya tras el último miembro) y los de un miembro.

- **Comentarios de un miembro: pegados a él.** Se reparten como en la fase 9 (el más cercano; a igual distancia, el de abajo) y se quitan las líneas en blanco entre el comentario y su miembro. Si un miembro tiene varios bloques de comentarios, quedan todos seguidos. La separación con el miembro vecino se mide desde el comentario.
- **Antes del primer miembro** (`DEFAULT_MAX_BLANK_LINES_OUTSIDE_MEMBERS`, 1): entre el comentario inicial del scope y la primera sentencia, sea `@tool`, `class_name`, `extends` o un miembro, queda una línea en blanco como máximo, o ninguna si no la había. Lo mismo entre las sentencias de la cabecera. Justo bajo la línea `class X:` de una clase interna no queda ninguna línea en blanco (desde el 2026-10-06; antes se conservaba una). Las líneas en blanco al principio del archivo se quitan todas, igual que las sobrantes del final.
- **Comentario entre la cabecera y el primer miembro, separado de los dos**: se aplica la regla general tomando la cabecera como vecino de arriba. Si está más cerca de la cabecera es la descripción de la clase y se queda con ella; a igual distancia o más cerca del miembro, es del miembro y se pega a él.
- **Tras la cabecera**, el primer miembro lleva una línea en blanco delante, dos si es un método o una clase. Sin cabecera, lleva las que hubiera con un máximo de una.
- **Al final del scope**: entre el último miembro y los comentarios que le siguen, y entre esos comentarios, una línea en blanco como máximo. Las líneas en blanco sobrantes al final del archivo se quitan. En una clase interna, los comentarios finales son los que tienen la indentación de su cuerpo, y las líneas en blanco indentadas que queden tras el último miembro o comentario se quitan (desde el 2026-10-06). Las líneas vacías sin indentar que siguen son del scope de fuera y no se tocan.

Espacios entre tokens (`analysis/token_spacing.gd`). En todo el código de la clase, incluidas su cabecera y los cuerpos de métodos y lambdas, cada hueco entre dos tokens que tenga más de un espacio, o algún tabulador, queda en un solo espacio: `var a : int =  4` pasa a `var a : int = 4` y `return<tab>a` a `return a`.

- **Final de línea**: se quitan los espacios y tabuladores sobrantes detrás del código o de un comentario. Una línea que solo tiene indentación dentro del cuerpo de una función no se toca (desde el 2026-10-06; antes se vaciaba). Una línea que queda dentro de una cadena multilínea no se toca, porque ahí son contenido: se sabe porque el trozo de la sentencia llega hasta el final de la línea.
- **No se toca**: la indentación, el interior de las cadenas, el texto de los comentarios, ni el hueco entre el código y un comentario de final de línea.
- No añade ni quita espacios simples: `foo( 1 )` se queda igual.
- Las clases internas no se recorren por dentro, pero su línea `class X extends Y:` sí se limpia, tanto desde la raíz como desde dentro de la clase.
- Se trabaja sobre los trozos de cada sentencia, donde las cadenas ya están enmascaradas y los comentarios fuera. Antes de cambiar un tramo se comprueba que en la línea real solo hay espacios.
- Este paso va antes que los cierres de corchetes: como cambia columnas pero no líneas ni sentencias, se vuelve a pasar el `GDSExSourceScanner` sobre las líneas limpias y las reglas de corchetes trabajan sobre ese resultado.

Cierres de corchetes (`analysis/bracket_layout.gd`). Se aplican a las variables, constantes y métodos de la clase, entrando en los cuerpos de los métodos y de las lambdas, pero no en las clases internas.

Diccionarios y arrays: cada `{...}` o `[...]` que se abre en una línea y se cierra en otra queda así:

```gdscript
var sizes : Dictionary = {
	"alpha" : 2,
	"beta" : 3,
}
```

- **El cierre va en su propia línea**, con la indentación de la línea donde se abrió. Lo que haya detrás del cierre (`.keys()`, `)`, `+ [`, `:`) baja con él.
- **Coma tras el último elemento**, antes del comentario de final de línea si lo hay. Una colección vacía no la lleva. Si el último elemento es una lambda multilínea, la coma va tras la última sentencia de su cuerpo.
- Vale para colecciones anidadas, cada una alineada con la línea donde se abre.

Lambdas multilínea como argumento: el paréntesis que cierra la llamada baja a su propia línea, alineado con la línea donde se abrió.

```gdscript
button.pressed.connect(func() -> void:
	print("pressed")
)
```

- Solo se mueve el cierre que va justo detrás del final de la lambda. Lo que le siga (`.clear()`, otro `)`) baja con él y no se le añade coma.
- Si tras la lambda viene otro argumento (`, 2)`), no se toca: no hay un cierre que recolocar.
- Las lambdas de una línea y las asignadas a una variable no cambian.
- La guía de estilo oficial de GDScript no dice nada de lambdas; el formato es el habitual en la documentación y es válido para el motor, comprobado compilando cada variante.

Lo que no se toca: las colecciones de una sola línea, el reparto de elementos por línea, su indentación, la del cuerpo de las lambdas, el espaciado de `clave : valor`, un primer elemento escrito en la misma línea que la apertura, los `enum`, las llamadas multilínea sin lambda, y un `[` que es un índice (`TABLE[...]`) y no un array.

No hacen falta scopes: ni una colección ni un cierre de llamada declaran nombres. Se trabaja sobre las sentencias del árbol de `GDSExSourceScanner`, que ya traen el código con cadenas y comentarios enmascarados, la posición de cada trozo en su línea y los bloques de las lambdas. Una misma línea puede recibir cambios de dos sentencias (el final del cuerpo de una lambda y el cierre de la llamada que la contiene), así que los cambios se reúnen por línea antes de reescribir.

El cursor se queda en su línea y columna; si la línea se parte, en la primera mitad.

Cómo se aplica: `GDSExClassLayout.format` usa los mismos bloques y el mismo compositor que `GDSExClassLayout.reorder`, con el orden original y las separaciones normalizadas. El tramo que se procesa va desde el principio del scope hasta su último comentario, mientras que el reordenado empieza tras la cabecera. El reemplazo, el undo único y la restauración de cursor, breakpoints, marcadores, plegados y scroll son los de la fase 9. Las líneas en blanco también entran en el mapa de líneas, así que el cursor situado en un hueco se queda en el hueco.

`GDSExEditApplier` necesitó dos casos que el reordenado nunca producía: un reemplazo que solo quita líneas (también al final del documento, donde el cursor se recoloca en la última línea que queda) y uno que solo las añade.

Tests:

- Casos de texto en `tests/cases/format_class_members/` y `tests/cases/view/formatting_keeps_the_caret_on_the_same_row.txt`.
- `action: check_format_project_scripts` da formato a la raíz y a todas las clases internas de cada script del proyecto y comprueba que el código queda idéntico salvo espacios, saltos de línea y comas finales, que los literales de cadena no cambian, que el resultado compila, que el motor ve los mismos miembros y las constantes conservan su valor, y que repetir la acción no cambia nada. La acción modifica 7 de los 27 scripts que revisa.

### Fase 11 — Ajustes en Project Settings (hecha)

La configuración se edita en Project > Project Settings, sección "GDScript Extreme Tool", y se guarda en `project.godot` bajo `[gdscript_extreme_tool]`. Solo se escriben los valores que difieren del valor por defecto, así que se comparten con el proyecto y no se pierden al actualizar el plugin.

- `plugin_project_settings.gd` reúne toda la configuración. Arriba, las constantes `DEFAULT_` con los valores por defecto y las constantes `_KEY` con la ruta de cada ajuste; debajo, una función por ajuste (`GDSExPluginProjectSettings.generated_param_format()`, `GDSExPluginProjectSettings.class_member_order()`...) que lee Project Settings y cae al valor por defecto. El resto del código ya no lee constantes.
- `GDSExPluginProjectSettings.register()`, llamado desde `plugin.gd` al activar el plugin, declara cada ajuste con su valor inicial, su tipo y, en los enteros, un rango de 0 a 10.

| Ajuste | Constante por defecto |
|---|---|
| `naming/generated_param_format` | `DEFAULT_GENERATED_PARAM_FORMAT` |
| `naming/fallback_param_format` | `DEFAULT_FALLBACK_PARAM_FORMAT` |
| `naming/generated_signal_callback_format` | `DEFAULT_GENERATED_SIGNAL_CALLBACK_FORMAT` |
| `format/blank_lines_around_functions_and_classes` | `DEFAULT_BLANK_LINES_AROUND_FUNCTIONS_AND_CLASSES` |
| `format/blank_lines_between_member_categories` | `DEFAULT_BLANK_LINES_BETWEEN_MEMBER_CATEGORIES` |
| `format/max_blank_lines_inside_member_category` | `DEFAULT_MAX_BLANK_LINES_INSIDE_MEMBER_CATEGORY` |
| `format/max_blank_lines_outside_members` | `DEFAULT_MAX_BLANK_LINES_OUTSIDE_MEMBERS` |
| `order/class_member_order` | `DEFAULT_CLASS_MEMBER_ORDER` |

Reglas:

- Los valores se leen en cada uso, sin caché: un cambio en Project Settings se aplica en la siguiente acción.
- Un valor de tipo distinto al del valor por defecto (por ejemplo, tras editar `project.godot` a mano) se ignora y se usa el valor por defecto. Una cantidad negativa de líneas en blanco cuenta como cero.
- Una categoría que falte en `order/class_member_order` va al final.
- Al desactivar el plugin los ajustes no se borran: los valores cambiados siguen en `project.godot`.
- `plugin_project_settings.gd` no puede tener variables `static`: `plugin.gd` lo precarga directamente y, en Godot 4.7.2, un script con variables `static` precargado por el script del `EditorPlugin` hace que el editor avise de recursos sin liberar al cerrar. Por eso los valores por defecto se construyen en una función.

Tests:

- Casos en `tests/cases/settings/`. Cabecera nueva `settings:` con un diccionario en sintaxis de Godot (`{"format/blank_lines_around_functions_and_classes": 1}`); el runner aplica esos valores a Project Settings durante el caso y los retira después.
- `action: check_settings_registration` comprueba que se registran los 8 ajustes con su valor por defecto, que un valor cambiado se devuelve, que un tipo incorrecto cae al valor por defecto, y que el `project.godot` de desarrollo no sobrescribe ninguno (el resto de casos presupone los valores por defecto).

### Fase 12 — Acciones bajo demanda: atajo y submenú (hecha)

Antes, cada clic derecho en el editor de scripts construía el índice del archivo y el plan de las seis acciones para decidir cuáles mostrar, aunque solo se quisiera copiar o pegar. Medido en un M5 Pro: 1,5 ms con 66 líneas, 13 ms con 552, 22 ms con 869 y 31 ms con 1.733. Ahora el análisis solo se hace cuando se piden las acciones.

- **Atajo.** `Alt` + `Intro` (`Option` + `Retorno` en macOS) abre junto al cursor un menú con las acciones disponibles, con la primera enfocada, así que `Intro` la ejecuta. Se registra con `EditorSettings.add_shortcut` en la ruta `gdscript_extreme_tool/show_code_actions` y se puede cambiar en Editor Settings > Shortcuts. Solo actúa si el editor de código del script actual tiene el foco.
- **Clic derecho.** Una única entrada, "Script Extreme Tools", con un submenú que se rellena al abrirse.
- **Sin acciones.** El menú muestra una sola línea desactivada, "No actions available here".

Cómo está hecho:

- `code_actions_popup.gd` (`GDSExCodeActionsPopup`, un `PopupMenu`) sirve para los dos casos: se crea con una línea desactivada, se rellena en `about_to_popup` y ejecuta la acción en `index_pressed`, reconstruyendo el contexto y el plan en ese momento.
- `plugin.gd` atiende el atajo en `_shortcut_input` y añade el submenú con `add_context_submenu_item`. Godot libera el submenú en cada apertura del menú contextual, así que se crea uno nuevo cada vez.
- Por qué `Alt` + `Intro` y no `Ctrl` + `.`: en Godot 4.7.2 `Ctrl` + `.` es "ir al siguiente breakpoint" en el editor de scripts y `Cmd` + `.` detiene el proyecto. `Alt` + `Intro` no lo usa ninguno de los 513 atajos del editor (comprobado en macOS) y un `CodeEdit` con el foco no lo consume.
- `add_shortcut` conserva el atajo que haya personalizado el usuario aunque el plugin vuelva a registrar el valor por defecto en cada arranque. Al desactivar el plugin el atajo no se borra.

Tests:

- `action: run_first_popup_action`, con casos en `tests/cases/menu/`: el menú empieza con la línea desactivada, al abrirse lista las mismas acciones que el registro considera disponibles, y ejecutar la primera deja el resultado esperado.
- El atajo y el submenú no se pueden probar en modo `--script`, porque el `EditorPlugin` no se instancia. Se comprobaron con un plugin de prueba en el editor sin interfaz (`--headless --editor`): abre un script, envía `Alt` + `Intro` a la ventana del editor y comprueba que aparece el menú, que `Intro` genera el método y que el menú se libera; después envía un clic derecho y comprueba que el submenú pasa de la línea desactivada a las acciones al abrirlo. Esa prueba no está en el repositorio.
- Cuidado al repetirla: lo que una prueba cambie en `EditorSettings` (por ejemplo los eventos de un atajo) se guarda en la configuración global de Godot del usuario al cerrar el editor.

### Fase 13 — Terminología: de «method» a «function» (hecha)

GDScript declara con `func` y la documentación de Godot habla de funciones, así que todo nombre propio del plugin que decía «method» pasa a «function». La versión 0.1.0 fue interna y nadie la descargó, por lo que también cambian los valores que se guardan en `project.godot`.

- **Acción:** "Generate Method Stub" es ahora "Generate Function Definition". Archivo `generate_function_action.gd`, alias `GDSExGenerateFunctionAction`, casos en `tests/cases/generate_function/` con `action: generate_function`.
- **Ajuste:** `format/blank_lines_around_functions_and_classes`, con su constante `DEFAULT_BLANK_LINES_AROUND_FUNCTIONS_AND_CLASSES`, su clave `_KEY` y su función de acceso.
- **Categorías de `order/class_member_order`:** `static_public_functions`, `static_private_functions`, `engine_functions`, `public_functions` y `private_functions`.
- **Código:** el índice (`GDSExClassScope.functions`, `GDSExKind.FUNCTION`), `GDSExFunctionSignature`, `GDSExPlacement.new_function`, `GDSExBuiltinTypes.FUNCTIONS` y el resto de identificadores, variables locales incluidas. El generador `tools/generate_builtin_types.gd` ya escribe `const FUNCTIONS`.
- **Tests:** 31 archivos y carpetas de casos renombrados. El código de ejemplo dentro de los casos no se ha tocado.
- **Lo que conserva «method»:** los nombres que son del motor y no del plugin: `get_script_method_list`, `class_get_method_list`, `METHOD_FLAG_*`, `MethodFlags`, la clave `"methods"` del volcado `extension_api.json` y los nombres de la tabla generada de tipos básicos.
- **Menú contextual:** la entrada del clic derecho se llama ahora "Script Extreme Tools".

En las fases anteriores de este documento se han actualizado los nombres de archivos, ajustes y constantes; el texto en español sigue diciendo «método» donde habla del concepto.

### Fase 14 — Acciones Generate Init (hecha)

Dos acciones que generan una función inicializadora con un parámetro por variable y su asignación. El detalle, las decisiones del usuario y lo que se fue encontrando en cada paso están en `GENERATE_INIT_PLAN.md`.

- **"Generate Default Init Definition"** genera `_init` con las variables privadas de la clase, sin preguntar. No se ofrece si ya hay `_init`, si no hay variables privadas o si la clase hereda de `Node` o `Resource`.
- **"Generate Custom Init Definition..."** abre un diálogo para elegir el nombre y las variables (privadas, públicas y exports), con filtros, vista previa de la firma y un panel de validación del nombre.

Lo que deja para el resto del plugin:

- **Acciones con diálogo.** `GDSExCodeAction.create_dialog(context, on_plan_ready)` permite que una acción pida datos antes de dar su plan. El menú abre el diálogo y aplica el plan al confirmar.
- **`analysis/member_categories.gd`.** La clasificación de miembros según `order/class_member_order`, compartida por el reordenado, el punto de inserción y la lista de variables.
- **`GDSExPlacement.function_by_order`.** Coloca una función nueva donde manda el orden de miembros.
- **`analysis/param_names.gd`.** El formato de los nombres de parámetro, compartido con "Generate Function Definition".
- **Ajuste `naming/alternative_init_function_name`.**
- **Las funciones generadas** toman sus líneas en blanco del ajuste `format/blank_lines_around_functions_and_classes`.
- **Nombres de enums globales** (`Key`, `Error`) reconocidos como definidos; antes las acciones de variable se ofrecían sobre ellos.

Cómo se probó: casos `.txt` para la generación, la validación del nombre y el diálogo, y una prueba de extremo a extremo en el editor sin interfaz que no está en el repositorio. Dos avisos para repetirla: lo que la prueba cambie en `EditorSettings` se guarda en la configuración global del usuario, y el editor guarda los scripts modificados al cerrarse.

## Casos pendientes

Todos bajo `tests/cases/`. La columna "Hoy" es lo que hace la versión actual.

| Caso | Hoy | Fase |
|---|---|---|
| `generate_local_variable/*` (6 casos) | La acción no existe | 5 |
| `generate_class_variable/*` (4 casos) | La acción no existe | 5 |

## Fuera de alcance

- Generar código en otro archivo: un método sobre un objeto cuya clase está definida en otro script no se ofrece.
- Rutas relativas en `extends "base.gd"`: solo se resuelven las rutas `res://`.
- Atajos de teclado para las acciones.
- Scope propio para lambdas de una sola línea.
