# Plan de refactorización — CodeGenerator

Godot 4.7.2. Estado de partida: una única utilidad ("Generate Method Stub") con la inserción acoplada a "método nuevo en una clase" y un índice de símbolos que calcula mal dónde termina cada miembro, sobre todo con lambdas y métodos anidados.

| Fase | Contenido | Estado |
|---|---|---|
| 0 | Git, tests headless, formato de parámetros | Hecha |
| 1 | Capa de edición genérica | Hecha |
| 2 | Índice fiable: sentencias, bloques y lambdas como scopes | Pendiente |
| 3 | Resolución e inferencia compartidas | Pendiente |
| 4 | Acciones y menú | Pendiente |
| 5 | Generate local variable y Generate class variable | Pendiente |

## Objetivo

1. Que insertar código sea una capa genérica que cualquier utilidad pueda usar sin conocer `CodeEdit`.
2. Que el índice de símbolos dé rangos y scopes fiables, incluidos bloques, lambdas y métodos anidados a cualquier profundidad.
3. Que añadir una utilidad sea escribir un archivo nuevo y registrarlo.
4. Añadir dos utilidades sobre esa base: **Generate local variable** y **Generate class variable**.

Cada fase deja el plugin funcionando y los tests en verde.

## Decisiones de diseño

- **Las utilidades solo producen datos.** Una acción devuelve un `EditPlan`; `EditApplier` es la única clase que toca `CodeEdit`.
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
addons/code_generator/
├── plugin.cfg
├── code_generator_plugin.gd
├── code_generator_settings.gd
├── actions/
│   ├── code_action.gd
│   ├── code_context.gd
│   ├── generate_method_action.gd
│   ├── generate_local_variable_action.gd
│   └── generate_class_variable_action.gd
├── analysis/
│   ├── source_scanner.gd
│   ├── symbol_index.gd
│   ├── symbol_index_builder.gd
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
```

Desaparecen `code_inserter.gd`, `stub_generator.gd` y `code_generator_unit_tests.gd`.

## Piezas clave

### Edición (`editing/`)

```gdscript
class SnippetLine:
	var indent: int
	var text: String

class Snippet:
	var lines: Array[SnippetLine]
	var selection_line: int = -1
	var selection_from: int
	var selection_to: int

class InsertionPoint:
	var line: int
	var indent_text: String
	var blank_lines_before: int
	var blank_lines_after: int

class EditPlan:
	func insert(point: InsertionPoint, snippet: Snippet) -> void
```

- `EditApplier.apply(editor, plan)` aplica todas las ediciones de abajo arriba dentro de una sola operación compleja (un solo undo) y coloca la selección del snippet.
- El plan es una lista, así que reemplazar o borrar rangos se puede añadir cuando una utilidad lo necesite. De momento solo hace falta insertar.

### Colocación (`editing/placement.gd`)

Traduce una intención a un `InsertionPoint` usando el índice:

| Función | Dónde | Blancos antes / después |
|---|---|---|
| `after_method(function_scope)` | Tras el método de primer nivel que contiene la posición, por muy anidada que esté | 2 / 2 |
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
| `ClassScope` | La raíz y cada `class` interna |
| `FunctionScope` | Métodos y lambdas, con o sin variable, a cualquier profundidad (`is_lambda`) |
| `BlockScope` | `if`, `elif`, `else`, `for`, `while`, `match` y cada rama de `match` |

- Todo scope guarda su línea de cabecera, la primera línea de su cuerpo, su última línea, el texto de indentación de su cuerpo, sus hijos y sus locales en orden de declaración.
- El scope de una posición es el bloque que contiene su sentencia. La condición de un `if` pertenece al scope exterior, no al bloque que abre.
- La búsqueda de un nombre sube de scope en scope y solo considera declaraciones anteriores a la línea de uso. La variable de un `for` es un local de su bloque.
- Cada `ClassScope` guarda el fin de su cabecera y sus miembros en orden de aparición, con tipo de miembro y rango real. Una propiedad con `set`/`get` y un valor multilínea ocupan todas sus líneas.
- Una sola expresión para `var`/`const` que cubre `:=`, tipos con genéricos y propiedades. Un valor que empieza por `func` es `Callable`.
- `parent` pasa a ser referencia débil (hoy cada construcción deja objetos sin liberar).

### Resolución (`analysis/type_resolver.gd`)

Un único punto de entrada que sustituye a `_resolve_receiver_class`, `_resolve_type_from_tokens`, `_infer_type_from_expr` y las búsquedas en ClassDB repetidas:

- `resolve_expression_type(expression, scope_info)`
- `find_method(type, name)` y `find_signal(type, name)`, sobre clases del archivo y, por herencia, ClassDB.
- `is_defined(name, scope_info)`: locales, parámetros, miembros, heredados y funciones globales (lista estática de las 130 funciones de `@GlobalScope` y `@GDScript`).
- `expected_type_at(statement, offset, scope_info)`: el tipo que el contexto espera en una posición. Se extrae de `_infer_return_type` y lo usan tanto el método generado (tipo de retorno) como las variables nuevas.

`expected_type_at` cubre: argumento de una llamada, de `emit` o de `connect`; lado derecho de una declaración o asignación tipada; `return` en una función o lambda con tipo; y condición de `if`, `elif` o `while` (`bool`). Si el valor se usa pero el tipo no se puede inferir, el método generado devuelve `Variant` con `return null`.

`call_site_parser.gd` trabaja sobre sentencias completas, no sobre la línea del cursor, y no trata `func`, `if`, `while` ni otras palabras clave como llamadas.

### Acciones (`actions/`)

```gdscript
func get_label() -> String
func build_plan(context: CodeContext) -> EditPlan
```

- `CodeContext` se construye una vez por clic derecho: líneas, cursor, selección, índice, scope de la posición y estilo de indentación.
- El plugin tiene una lista de acciones. En `_popup_menu` pide el plan a cada una, añade al menú las que devuelven plan y lo aplica al pulsar.

## Nombres de los parámetros generados

Definidos en `code_generator_settings.gd`:

```gdscript
const GENERATED_PARAM_FORMAT : String = "p_{name}"
const FALLBACK_PARAM_FORMAT : String = "param_{index}"
```

- Si el argumento es un nombre simple (variable, constante, parámetro) o un parámetro de señal con nombre, se aplica `GENERATED_PARAM_FORMAT` al nombre en minúsculas y sin guiones bajos iniciales: `event` → `p_event`, `CONST_1` → `p_const_1`, `_item` → `p_item`.
- Un nombre que ya tiene el formato (`p_item`) se deja igual.
- En cualquier otro caso (literal, `null`, `true`, `false`, `self`, expresión, lambda) o si el nombre se repite, se usa `FALLBACK_PARAM_FORMAT` con la posición del argumento: `param_0`, `param_1`.

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
- **Dónde** (`Placement.member_variable`), por orden de preferencia:
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

Cada caso es un `.txt` en `tests/cases/`:

```
action: generate_method
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
- `action: apply_plan` prueba la capa de edición sin pasar por ninguna utilidad: la sección `=== plan` describe las inserciones en JSON (`line`, `indent_text`, `blank_lines_before`, `blank_lines_after`, `lines` y `select`).

## Fases

### Fase 0 — Red de seguridad (hecha)

- Repositorio git inicializado en la raíz, rama `main`, sin commits todavía.
- `tests/run_tests.gd` y los casos de `tests/cases/`.
- Los 17 stubs de `code_generator_unit_tests.gd` están cubiertos por casos. El archivo se borra después del primer commit, para que quede en el historial.
- Formato de nombres de parámetros implementado en `stub_generator.gd`.

### Fase 1 — Capa de edición genérica (hecha)

- `indentation.gd`, `snippet.gd`, `edit_plan.gd`, `edit_applier.gd` y `placement.gd` (con las tres colocaciones que ya existían).
- El generador de métodos produce un `Snippet` con indentación relativa y lo inserta a través de `EditPlan` y `EditApplier`.
- Arreglados: la inserción al final de un archivo sin salto de línea y los stubs con tabs en archivos indentados con espacios.
- Siete casos en `tests/cases/editing/` prueban la capa directamente: varias inserciones en un plan, principio y final del archivo, reutilización de líneas en blanco, indentación relativa y conservación de la selección.
- `code_inserter.gd` ya no se usa. Se borra después del primer commit, igual que `code_generator_unit_tests.gd`.
- Mientras el índice no dé la indentación real del cuerpo de cada clase, `Placement` usa la de la línea `class` más una unidad.

### Fase 2 — Índice fiable

- `source_scanner.gd` con el árbol de sentencias.
- `symbol_index_builder.gd` con los tres tipos de scope; `symbol_index.gd` se queda con los datos y las consultas.
- `Placement` usa los rangos reales.
- Hecho cuando: pasan el resto de `placement/`, todo `index/`, todo `nesting/` y los tres casos de `lambdas/` que no dependen del parser de llamadas.

### Fase 3 — Resolución e inferencia compartidas

- `type_resolver.gd` y `call_site_parser.gd`.
- Descomponer `_infer_return_type` (130 líneas) en `expected_type_at`.
- Hecho cuando: pasan todo `resolution/` y `lambdas/lambda_argument`.

### Fase 4 — Acciones y menú

- `code_context.gd`, `code_action.gd` y `generate_method_action.gd`.
- Registro de acciones en `code_generator_plugin.gd`; el menú muestra solo las disponibles.
- Borrar `stub_generator.gd`.
- Hecho cuando: todos los casos anteriores pasan a través de la acción.

### Fase 5 — Utilidades nuevas

- `Placement.scope_start` y `Placement.member_variable`.
- `generate_local_variable_action.gd` y `generate_class_variable_action.gd`.
- Hecho cuando: pasan `generate_local_variable/` y `generate_class_variable/`, ampliados con: lambdas anidadas, ramas de `match`, cuerpos de una línea, espacios, última línea sin salto final, y tipo inferido por asignación y por `return`.

## Casos pendientes

Todos bajo `tests/cases/`. La columna "Hoy" es lo que hace la versión actual.

| Caso | Hoy | Fase |
|---|---|---|
| `generate_method/placement/method_ending_in_lambda` | El stub parte la lambda | 2 |
| `generate_method/placement/line_after_inline_lambda` | El stub parte el método | 2 |
| `generate_method/placement/target_class_ending_in_property` | El stub parte la propiedad | 2 |
| `generate_method/placement/target_class_ending_in_multiline_value` | El stub parte el diccionario | 2 |
| `generate_method/placement/body_ending_in_comment` | El comentario queda tras el método nuevo | 2 |
| `generate_method/index/inferred_variable_type` | `var a := 5` no se indexa | 2 |
| `generate_method/index/generic_type_without_initializer` | Tipo truncado en `Dictionary[String,` | 2 |
| `generate_method/index/property_type` | Tipo `int:` | 2 |
| `generate_method/index/func_inside_comment` | El comentario se indexa como método | 2 |
| `generate_method/index/multiline_signature` | El método no se indexa | 2 |
| `generate_method/index/same_local_name_in_two_blocks` | Gana la última declaración | 2 |
| `generate_method/index/memory` | 11 objetos sin liberar por construcción | 2 |
| `generate_method/lambdas/nested_method_argument` | Parámetro sin tipo en vez de `Callable` | 2 |
| `generate_method/lambdas/call_inside_lambda_argument` | Stub al final del archivo y sin tipos | 2 |
| `generate_method/lambdas/call_inside_nested_method` | El stub parte la lambda y pierde los tipos | 2 |
| `generate_method/nesting/three_lambda_levels` | El stub parte `level_1` | 2 |
| `generate_method/nesting/arguments_from_every_level` | El stub parte `level_1` y pierde los cuatro tipos | 2 |
| `generate_method/nesting/call_after_inner_lambda` | El stub parte `level_1` y pierde el tipo | 2 |
| `generate_method/nesting/blocks_and_lambda_arguments` | Stub al final del archivo y sin tipos | 2 |
| `generate_method/nesting/inner_class_with_nested_lambdas` | El stub parte la lambda y pierde los tipos | 2 |
| `generate_method/nesting/two_lambdas_in_one_call` | Stub al final del archivo | 2 |
| `generate_method/nesting/lambda_closed_on_body_line` | Stub al final del archivo | 2 |
| `generate_method/nesting/inline_lambda_inside_lambda` | El stub parte la lambda y pierde el tipo | 2 |
| `generate_method/lambdas/lambda_argument` | "More than one undefined function call" | 3 |
| `generate_method/resolution/wrapped_by_global_function` | "More than one undefined function call" | 3 |
| `generate_method/resolution/inherited_engine_method` | Genera `queue_free` en la clase actual | 3 |
| `generate_method/resolution/receiver_of_engine_type` | Genera el método en la clase actual | 3 |
| `generate_method/resolution/multiline_call` | "Cannot parse arguments" | 3 |
| `generate_method/resolution/keyword_before_parenthesis` | `if (` cuenta como llamada | 3 |
| `generate_method/resolution/connect_with_caret_outside_callback` | Genera `func connect(...)` | 3 |
| `generate_local_variable/*` (6 casos) | La acción no existe | 5 |
| `generate_class_variable/*` (4 casos) | La acción no existe | 5 |

## Fuera de alcance

- Resolver clases con `class_name` definidas en otros archivos. `TypeResolver` queda preparado para añadir esa fuente.
- Atajos de teclado para las acciones.
- Ediciones de reemplazo o borrado (por ejemplo, extraer una expresión a una variable).
- Scope propio para lambdas de una sola línea.
