# Plan — Acción Extract Function

Una acción nueva: con unas líneas seleccionadas dentro de una función, las saca a una función privada y deja en su lugar la llamada. Es la primera acción que mueve código que ya existe, así que la regla general es conservadora: si no se puede garantizar que el código sigue haciendo lo mismo, la acción no se ofrece.

| Paso | Contenido | Estado |
|---|---|---|
| E1 | Selección en el contexto, rango de sentencias y comprobaciones de estructura y flujo | Pendiente |
| E2 | Entradas, salidas y forma del resultado | Pendiente |
| E3 | Generación de la función y de la llamada, y edición combinada | Pendiente |
| E4 | Validación del nombre | Pendiente |
| E5 | Diálogo de "Extract Function..." | Pendiente |
| E6 | Prueba masiva, verificación en el editor y documentación | Pendiente |

Cada paso termina con la suite en verde y una pasada de `--headless --editor --quit` sin errores ni avisos. Los commits los hace el usuario al cerrar cada paso.

## 1. Qué hace

Con las dos líneas del bucle seleccionadas:

```gdscript
func run(items : Array[int], factor : float) -> void:
	var total := 0
	for item in items:
		total += item
	var scaled := total * factor
	print(scaled)
```

"Extract Function..." abre un diálogo que pide el nombre y, al aceptar, deja:

```gdscript
func run(items : Array[int], factor : float) -> void:
	var total := 0
	total = _sum(items, total)
	var scaled := total * factor
	print(scaled)


func _sum(items: Array[int], total: int) -> int:
	for item in items:
		total += item
	return total
```

## 2. Decisiones acordadas

Las tomó el usuario el 2026-10-07.

1. **Qué se extrae.** Las sentencias completas que cubren las líneas de la selección. Sin selección la acción no existe.
2. **Mismo bloque.** La primera y la última línea tienen que quedar en el mismo scope. La selección no se amplía sola a la sentencia que la contiene: si no cuadra, no se ofrece.
3. **Nombre.** Un diálogo pide el nombre y muestra la firma y la llamada que se van a generar. La etiqueta acaba en puntos suspensivos.
4. **Parámetros.** Conservan el nombre de la variable original, sin el formato `p_{name}`, para que el cuerpo extraído no se toque.
5. **Cuando no se puede.** La acción no aparece en el menú. No se explica el motivo.
6. **Última línea `return`.** La llamada pasa a ser el propio `return`.
7. **Última línea asignación.** Si la última línea asigna o inicializa una variable, la función devuelve ese valor y la asignación se queda donde estaba, con la llamada como valor.

## 3. Detalles decididos al implementar

El usuario no los ha fijado; son la forma concreta de cumplir lo acordado y se pueden cambiar sin rehacer el plan.

- **D1. Nombre con el que abre el diálogo.** `_extracted_function`, seleccionado para escribir encima.
- **D2. Nombre sin `_`.** Se admite y la función se coloca como pública. El panel de validación lo avisa en amarillo, porque la acción está pensada para funciones privadas.
- **D3. Dónde se inserta.** Donde manda `order/class_member_order`, como el resto de funciones que genera el plugin, no justo debajo de la función original.
- **D4. Tras aplicar.** La vista no se mueve y el cursor queda al final de la línea de la llamada.
- **D5. `:=` sin tipo conocido.** `var x := _f()` solo compila si `_f` declara lo que devuelve. Si el plugin no conoce el tipo, la llamada se escribe con `=`. La vista previa del diálogo lo enseña antes de aceptar.
- **D6. Más de una salida.** No se ofrece. No se devuelve un `Array` ni un `Dictionary` como apaño.
- **D7. Variable de fuera reasignada dentro.** Cuenta siempre como salida, se use después o no. Decidir si se usa después obliga a seguir los bucles y no compensa.

## 4. Comportamiento

### 4.1 De la selección a las sentencias

- Cuentan las líneas que la selección toca. Si acaba en la columna 0 de una línea, esa línea no cuenta.
- Las líneas en blanco de los extremos se descartan. Los comentarios seleccionados se van con el código.
- La primera línea con código tiene que ser el principio de una sentencia y la última, el final de otra, con todo su bloque si lo tiene. Las dos tienen que ser hermanas: sentencias del mismo bloque.
- Las líneas seleccionadas solo pueden contener código de esas sentencias. Esto descarta una línea que comparte el final de una lambda con el resto de la llamada (`pass)`).
- El bloque tiene que estar dentro de una función, una lambda o un `set`/`get`. A nivel de clase no se ofrece.

No se ofrece si la selección:

- deja una sentencia a medias, por ejemplo un diccionario de varias líneas;
- empieza en un `elif` o un `else`, o deja uno justo debajo;
- son ramas de un `match` sin el `match`.

### 4.2 Flujo de control

| En la selección | Resultado |
|---|---|
| `break` o `continue` de un bucle que queda fuera | No se ofrece |
| `return` y después de la selección aún se ejecuta código de la función | No se ofrece |
| `return` en la última línea | Se ofrece: apartado 4.4 |
| `return` y la selección llega al final de la función | Se ofrece: la llamada lleva `return` si la función devuelve un valor |
| `super()` sin nombre de función | No se ofrece: en otra función llamaría a otro método del padre |
| `await` | Se ofrece: la llamada lleva `await` |

Un `break`, `continue` o `return` dentro de una lambda seleccionada entera no cuenta: pertenece a la lambda.

Si la función original es `static`, la nueva también.

### 4.3 Variables

Solo interesan los nombres locales de la función: variables locales, parámetros, variables de `for`, enlaces de `match` y, dentro de una lambda, lo que captura de la función que la contiene. Los miembros de la clase no se pasan ni se devuelven: la función nueva los ve igual.

**Entradas.** Todo nombre local declarado fuera de la selección y usado dentro pasa a ser un parámetro, con su nombre original, en el orden en que aparece por primera vez y con el tipo que el plugin conozca. Sin tipo conocido, el parámetro va sin tipo.

**Salidas.** Obligan a devolver un valor:

- una variable declarada en la selección y usada después de ella;
- una variable de fuera reasignada dentro (`total = ...`, `total += ...`), porque `int`, `float`, `String`, `Vector2` y demás tipos por valor no se modifican desde otra función;
- una variable de fuera a la que se le cambia un campo o un índice (`size.x = 2`), si su tipo es un tipo por valor con campos (`Vector2`, `Color`, `Rect2`, `Transform3D`...) o no se conoce. En objetos, arrays y diccionarios no cuenta: se comparten por referencia.

Con más de una salida la acción no se ofrece.

Las variables declaradas en la selección dentro de un bloque interior (el cuerpo de un `if`, de un bucle) no existen después de él y nunca son salidas.

### 4.4 Forma del resultado

Se prueba en este orden y se usa la primera que encaje.

**1. La última línea es un `return`.** La función conserva sus `return` y la llamada ocupa el lugar del último. Los `return` anteriores de la selección valen: como la selección acaba devolviendo, todos sus caminos devuelven.

```gdscript
# Antes (seleccionadas las tres últimas líneas)
func area(width : float, height : float) -> float:
	if width < 0.0:
		return 0.0
	return width * height

# Después
func area(width : float, height : float) -> float:
	return _area_of(width, height)


func _area_of(width: float, height: float) -> float:
	if width < 0.0:
		return 0.0
	return width * height
```

Si el `return` no lleva valor, queda la llamada y debajo el `return`. El tipo de la función nueva es el que declara la original; si no declara ninguno, el de los valores devueltos cuando el plugin lo conoce.

**2. La última línea asigna o inicializa una variable.** Vale para `var x = ...`, `var x := ...`, `var x : T = ...`, `x = ...` y los operadores compuestos (`x += ...`). El lado izquierdo se queda en su sitio tal como está escrito y la función devuelve el valor.

```gdscript
# Antes (seleccionadas las cuatro líneas)
	var total := 0
	for item in items:
		total += item
	var average := total / float(items.size())

# Después
	var average := _average_of(items)


func _average_of(items: Array[int]) -> float:
	var total := 0
	for item in items:
		total += item
	return total / float(items.size())
```

Condiciones:

- el lado izquierdo no usa ninguna variable declarada en la selección, porque dejaría de existir ahí;
- la sentencia no tiene bloque propio (una variable con `set`/`get`, una lambda de varias líneas);
- no hay ninguna otra salida. Si la única salida es la propia variable asignada, vale: el valor final es el que se devuelve.

El tipo de la función es el declarado en la variable, o el del valor si el plugin lo conoce.

**3. Hay una salida.** La función acaba en `return x`. La llamada es `var x: T = _f(...)` si la variable se declaraba dentro, o `x = _f(...)` si era de fuera. Es el ejemplo del apartado 1.

**4. No hay salidas.** La llamada es `_f(...)` y la función devuelve `void`.

### 4.5 Nombre de la función

Las mismas reglas que el nombre de "Generate Custom Init Definition...": vacío, no es un identificador, palabra reservada, ya existe una función u otro miembro con ese nombre, es una función o un callback del motor, o lo hereda de un script base. Además:

- Error: coincide con un parámetro o una variable local de la función original, porque taparía la llamada.
- Aviso: no empieza por `_` (detalle D2).

### 4.6 Diálogo

```
┌ Extract Function ───────────────────────────────────────────┐
│ Name  [ _sum                                              ] │
│ func _sum(items: Array[int], total: int) -> int             │
│ total = _sum(items, total)                                  │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ • Function name is valid.                               │ │
│ └─────────────────────────────────────────────────────────┘ │
│                   [Cancel]      [Extract]                   │
└─────────────────────────────────────────────────────────────┘
```

- **Nombre.** Con el foco al abrir y el texto seleccionado.
- **Vista previa.** La firma y la línea de la llamada, actualizadas al escribir.
- **Panel de validación y botones.** Como en el diálogo del init: mismos colores, Extract bloqueado con un error.
- **Teclado.** `ui_accept` extrae si el nombre es válido y `ui_cancel` cierra sin cambios.

Los parámetros no se pueden reordenar ni renombrar en esta versión.

## 5. Arquitectura

- **`actions/code_context.gd`** (E1). Primera y última línea de la selección del editor. Hoy solo guarda la selección dentro de una sentencia.
- **`analysis/statement_range.gd`** (nuevo, E1). De un rango de líneas a las sentencias hermanas que lo cubren, con las comprobaciones de los apartados 4.1 y 4.2. Devuelve el rango o el motivo por el que no vale; el motivo no se enseña al usuario, pero lo usan los tests.
- **`analysis/variable_usage.gd`** (nuevo, E2). Lecturas y escrituras de nombres locales en un rango de sentencias y después de él. Trabaja sobre el código enmascarado, resuelve cada nombre con los scopes del índice y descarta lo que no es una variable: accesos a miembro, llamadas, claves de diccionario con `=`, rutas de nodo y nombres de declaración.
- **`analysis/symbol_index.gd`** (E2). La búsqueda de una variable devuelve también el scope que la declara, para saber si un parámetro es de una lambda de dentro de la selección o de fuera.
- **`actions/extract_function.gd`** (nuevo, E2 y E3). Lógica sin interfaz, como `init_function.gd`: forma del resultado, firma, línea de la llamada y plan de edición a partir de un nombre.
- **`editing/edit_plan.gd` y `editing/edit_applier.gd`** (E3). Un mismo plan puede sustituir líneas e insertar una función, en un solo paso de deshacer. Hoy un plan con sustitución de líneas ignora las inserciones.
- **`actions/function_name_check.gd`** (nuevo, E4). La validación del nombre, que hoy vive en `init_function.gd`, pasa a un archivo que usan las dos acciones.
- **`actions/extract_function_action.gd`** (nuevo, E3). `build_plan` devuelve el plan con el nombre por defecto, que es lo que usa el menú para decidir si la ofrece. `create_dialog` llega en E5.
- **`extract_function_dialog.gd`** (nuevo, E5). Sin lógica de extracción: pide todo a `extract_function.gd`.

Reglas del proyecto que aplican: prefijo `GDSEx` en todo tipo nuevo, «function» y no «method», y ninguna variable `static` en scripts que `plugin.gd` precargue directamente.

## 6. Pasos

### E1 — Selección, rango y estructura

- Líneas de la selección en el contexto.
- `statement_range.gd` con las reglas de 4.1 y 4.2.
- Runner: una acción de comprobación que describe el rango encontrado o el motivo del rechazo, como `describe_scopes`.

Verificación: casos en `tests/cases/extract_function_range/`. Como mínimo: una sentencia, varias, con bloque, selección que acaba en la columna 0, comentarios y líneas en blanco en los extremos, dentro de un `if`, de un bucle, de una lambda y de un `set`; y un caso por cada rechazo: sin selección, nivel de clase, sentencia a medias, bloques distintos, `elif`/`else` partido, ramas de `match`, línea compartida con otra sentencia, `break`/`continue` de un bucle de fuera, `return` a mitad, `super()`.

### E2 — Entradas, salidas y forma del resultado

- `variable_usage.gd` y el scope en la búsqueda de variables.
- En `extract_function.gd`: parámetros, salidas y cuál de las cuatro formas de 4.4 se usa.
- La acción de comprobación de E1 añade a su descripción los parámetros, la salida y la forma.

Verificación: casos en `tests/cases/extract_function_usage/`. Como mínimo: parámetro leído, variable de bucle, parámetro de la función, captura de una lambda, nombre tapado por una lambda o una declaración interior, miembro de la clase que no se pasa, acceso `.x` que no es la variable `x`, clave `{ x = 1 }`, variable declarada dentro y usada después, declarada dentro de un bloque interior, reasignación de una de fuera, campo de un `Vector2`, `append` en un array, dos salidas, y un caso por cada forma del resultado y por cada condición de la forma 2.

### E3 — Generación y edición combinada

- Plan con sustitución de líneas e inserción en el aplicador, con cursor, vista, puntos de ruptura y marcadores.
- Firma, cuerpo con el sangrado rebajado a un nivel, `return` final cuando toca, `static`, `await` y línea de la llamada.
- Acción en el registro. Hasta E5 genera con el nombre por defecto.

Verificación: casos en `tests/cases/extract_function/` con una cabecera `options:` que da el nombre, sin diálogo. Como mínimo: las cuatro formas, `return` sin valor, `:=` con y sin tipo conocido, operador compuesto, `await`, función `static`, clase interna, selección dentro de un bloque sangrado y dentro de una lambda, colocación como privada y como pública, sangrado con espacios, un solo deshacer, y puntos de ruptura y marcadores que siguen a sus líneas.

### E4 — Validación del nombre

- Sacar la validación a `function_name_check.gd` sin cambiar el comportamiento del init.
- Reglas propias de 4.5.

Verificación: los 25 casos de `init_function_name` siguen en verde y hay casos nuevos para el nombre de una variable local, el de un parámetro y el aviso del nombre sin `_`.

### E5 — Diálogo

- `extract_function_dialog.gd` y `create_dialog` en la acción.

Verificación: casos que abren el diálogo desde el runner, como los del init: genera con el nombre por defecto, genera con otro nombre, la vista previa cambia al escribir, un nombre con error bloquea Extract, `ui_accept` y `ui_cancel`.

### E6 — Prueba masiva y cierre

- Comprobación sobre los scripts del proyecto: para cada función, extraer cada rango de sentencias hermanas en que la acción se ofrece y comprobar que el script sigue compilando. Es la misma idea que encontró tres fallos en "Add Explicit Type".
- Pasada en el editor real: menú, diálogo y resultado.
- README, CHANGELOG y el listado de archivos de `REFACTOR_PLAN.md`.

La prueba masiva encuentra lecturas que se hayan escapado, porque dejan un nombre sin definir. No encuentra una escritura no detectada, que compila y cambia el comportamiento: eso lo cubren los casos de E2.

## 7. Límites conocidos de esta versión

- Una sola salida.
- Los parámetros no se reordenan ni se renombran.
- El análisis de variables es textual sobre el código enmascarado, no un parser completo. Ante un uso que no sepa clasificar lo toma por lectura, que como mucho añade un parámetro de más.
- Los tipos que dependen de otro script cargado con `preload` no se conocen, así que esos parámetros y ese valor devuelto salen sin tipo.
