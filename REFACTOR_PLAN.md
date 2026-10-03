# Plan de refactorización — CodeGenerator

Godot 4.7.2. Estado de partida: una única utilidad ("Generate Method Stub") con la inserción acoplada a "método nuevo en una clase" y un índice de símbolos que calcula mal dónde termina cada miembro, sobre todo con lambdas y métodos anidados.

| Fase | Contenido | Estado |
|---|---|---|
| 0 | Git, tests headless, formato de parámetros | Hecha |
| 1 | Capa de edición genérica | Hecha |
| 2 | Índice fiable: sentencias, bloques y lambdas como scopes | Hecha |
| 3 | Resolución e inferencia compartidas | Hecha |
| 4 | Acciones y menú | Pendiente |
| 5 | Generate local variable y Generate class variable | Pendiente |
| 6 | Tipos compuestos, tipos inferidos e iteradores | Pendiente |

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
│   ├── language.gd
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

`code_inserter.gd` y `code_generator_unit_tests.gd` ya están borrados; `stub_generator.gd` desaparece en la fase 4.

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
| `ClassScope` | La raíz y cada `class` interna |
| `FunctionScope` | Métodos y lambdas, con o sin variable, a cualquier profundidad (`is_lambda`) |
| `BlockScope` | `if`, `elif`, `else`, `for`, `while`, `match` y cada rama de `match` |

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
- El generador de métodos produce un `Snippet` con indentación relativa y lo inserta a través de `EditPlan` y `EditApplier`.
- Arreglados: la inserción al final de un archivo sin salto de línea y los stubs con tabs en archivos indentados con espacios.
- Siete casos en `tests/cases/editing/` prueban la capa directamente: varias inserciones en un plan, principio y final del archivo, reutilización de líneas en blanco, indentación relativa y conservación de la selección.
- `code_inserter.gd` está borrado.

### Fase 2 — Índice fiable (hecha)

- `analysis/source_scanner.gd` produce el árbol de sentencias con las reglas de arriba.
- `analysis/symbol_index_builder.gd` crea los scopes de clase, función (métodos, lambdas y accesores de propiedad) y bloque. `symbol_index.gd` se ha movido a `analysis/` y se queda con los datos, las consultas y los ayudantes de tipos que la fase 3 pasará a `type_resolver.gd`.
- `Placement` inserta tras el miembro de la clase destino que contiene la posición, usando su rango real, y copia la indentación del cuerpo de la clase.
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

### Fase 4 — Acciones y menú

- `code_context.gd`, `code_action.gd` y `generate_method_action.gd` (el contenido actual de `stub_generator.gd`, que ya solo orquesta).
- Registro de acciones en `code_generator_plugin.gd`; el menú muestra solo las disponibles.
- Borrar `stub_generator.gd`.
- Hecho cuando: todos los casos anteriores pasan a través de la acción.

### Fase 5 — Utilidades nuevas

- `Placement.scope_start` y `Placement.member_variable`.
- `generate_local_variable_action.gd` y `generate_class_variable_action.gd`.
- Hecho cuando: pasan `generate_local_variable/` y `generate_class_variable/`, ampliados con: lambdas anidadas, ramas de `match`, cuerpos de una línea, espacios, última línea sin salto final, y tipo inferido por asignación y por `return`.

### Fase 6 — Tipos compuestos, tipos inferidos e iteradores

No depende de la fase 4 ni de la 5; se puede adelantar a la 5, que saldría ganando porque las variables generadas usarían estos tipos.

Ya cubierto, con 12 casos activos en `generate_method/composite_types/` e `iterators/`:

- `Array[T]` y `Dictionary[K, V]` declarados en variables, constantes, parámetros, señales y tipos de retorno, incluidos los del motor (`get_children()` es `Array[Node]`).
- El tipo se escribe completo en el método generado, como parámetro y como retorno (`-> Array[int]` con `return []`).
- Acceso por índice: `values[0]` es `T` y `names[key]` es `V`, también como receptor (`foos[0].reset()`) y como destino de una asignación (`names[1] = _make()`).
- `for` con variable anotada o sobre `range(...)`, y variables declaradas dentro de un `while`.

Pendiente:

- **Tipos inferidos de forma diferida.** Una variable con `:=` o `=` solo tiene tipo si su valor es un literal o un constructor del motor. `var first := values[0]`, `var child := get_child(0)` y `var foo := Foo.new()` (clase del archivo) quedan sin tipo.
  - El símbolo guarda la expresión del valor y `TypeResolver` la resuelve al consultarla, con el scope de la línea de la declaración y un límite de recursión.
  - Para eso `ScopeInfo` necesita una referencia al índice.
- **Variable de un `for`.** Se resuelve igual, a partir de la expresión que se recorre:
  - `Array[T]` da `T` y `Dictionary[K, V]` da `K`.
  - Un `int` da `int`, un `String` da `String` y un `Packed*Array` da su tipo de elemento.
  - Cualquier expresión que el resolvedor ya entienda (`get_children()`, `names.values()`).
- **Llamada sin definir usada como iterable.** `for value: int in _values():` debe generar `-> Array[int]`, y sin anotación `-> Array`.
- **Métodos y elementos de colecciones.** Los tipos integrados no tienen reflexión, así que hace falta una tabla en `language.gd`, generada desde la documentación del motor como la de funciones globales:
  - Elemento por índice de `Packed*Array` y `String`.
  - Retorno: `front`, `back`, `pop_back`, `pick_random` y `get` dan el elemento; `keys()` da `Array[K]`; `values()` da `Array[V]`; `size` da `int`.
  - Parámetros: `append`, `push_back`, `has`, `erase` y `insert` esperan el elemento, de modo que `foos.append(_make_foo())` genere `-> Foo`.
  - La misma tabla puede ampliarse a todos los tipos integrados (`String.length()`, `Vector2.normalized()`); queda como opción.
- **Variables de un patrón de `match`.** `var other:` como patrón declara un local de la rama con el tipo de la expresión comparada. Dentro de un patrón de array o diccionario queda sin tipo.
- **Diccionarios tipados del motor.** Los arrays tipados de ClassDB ya se leen; los diccionarios usan otro formato de `hint_string` y hoy salen como `Dictionary`.

`while` no declara ninguna variable, así que no tiene iterador que tipar. Lo que se declara en su cuerpo ya pertenece a su scope.

Hecho cuando: pasan los 18 casos pendientes de `composite_types/` e `iterators/`.

## Casos pendientes

Todos bajo `tests/cases/`. La columna "Hoy" es lo que hace la versión actual.

| Caso | Hoy | Fase |
|---|---|---|
| `generate_local_variable/*` (6 casos) | La acción no existe | 5 |
| `generate_class_variable/*` (4 casos) | La acción no existe | 5 |
| `generate_method/composite_types/inferred_from_*` (3 casos) | La variable con `:=` queda sin tipo | 6 |
| `generate_method/composite_types/packed_array_element` | `names[0]` sin tipo | 6 |
| `generate_method/composite_types/collection_method_element` | `values.front()` sin tipo | 6 |
| `generate_method/composite_types/dictionary_keys_and_values` | `keys()` y `values()` sin tipo | 6 |
| `generate_method/composite_types/append_argument` | `-> Variant` en vez de `-> Foo` | 6 |
| `generate_method/iterators/for_over_*` (8 casos) | La variable del bucle queda sin tipo | 6 |
| `generate_method/iterators/*_for_iterable_return_type` (2 casos) | `-> Variant` en vez de `-> Array` | 6 |
| `generate_method/iterators/match_pattern_binding` | La variable del patrón no se indexa | 6 |

## Fuera de alcance

- Resolver clases con `class_name` definidas en otros archivos. `TypeResolver` queda preparado para añadir esa fuente.
- Atajos de teclado para las acciones.
- Ediciones de reemplazo o borrado (por ejemplo, extraer una expresión a una variable).
- Scope propio para lambdas de una sola línea.
