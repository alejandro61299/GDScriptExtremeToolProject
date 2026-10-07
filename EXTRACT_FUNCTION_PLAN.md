# Plan — Acción Extract Function

Una acción nueva: con unas líneas seleccionadas dentro de una función, las saca a una función privada y deja en su lugar la llamada. Es la primera acción que mueve código que ya existe, así que la regla general es conservadora: si no se puede garantizar que el código sigue haciendo lo mismo, la acción no se ofrece.

| Paso | Contenido | Estado |
|---|---|---|
| E1 | Selección en el contexto, rango de sentencias y comprobaciones de estructura y flujo | Hecha |
| E2 | Entradas, salidas y forma del resultado | Hecha |
| E3 | Generación de la función y de la llamada, y edición combinada | Hecha |
| E4 | Validación del nombre | Hecha |
| E5 | Diálogo de "Extract Function..." | Hecha |
| E6 | Prueba masiva, verificación en el editor y documentación | Hecha |

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
- **D5. `:=` sin tipo conocido.** `var x := _f()` solo compila si `_f` declara lo que devuelve. Si el plugin no conoce el tipo, la llamada se escribe con `=`. La vista previa del diálogo lo enseña antes de aceptar. Si más abajo hay otra declaración con `:=` que depende de esa variable, la acción no se ofrece (detalle D11).
- **D6. Más de una salida.** No se ofrece. No se devuelve un `Array` ni un `Dictionary` como apaño.
- **D7. Variable de fuera reasignada dentro.** Cuenta siempre como salida, se use después o no. Decidir si se usa después obliga a seguir los bucles y no compensa.

Los siguientes salieron al implementar, el 2026-10-07. Cada uno está cubierto por tests.

- **D8. Comentarios en los extremos.** Los comentarios seleccionados por encima de la primera sentencia se van con el código. Los que quedan por debajo de la última solo se van si pertenecen a su bloque; si no, se quedan donde están, debajo de la llamada.
- **D9. La salida conserva su declaración.** Cuando la variable que se devuelve se declaraba en la selección, la llamada reutiliza esa declaración tal como estaba escrita: `var total := 0` da `var total := _sum(items)` y `var total : float = 0.0` da `var total : float = _sum(items)`. El borrador generaba siempre `var total: int = ...`, que cambiaba el estilo y podía tipar una variable que no lo estaba.
- **D10. Lo que no tenía tipo sigue sin tenerlo.** Una variable declarada con `=` y sin tipo (`var data = _load()`) admite cualquier valor más adelante. Como parámetro va sin tipo, y si es la salida, la función no declara lo que devuelve, aunque el plugin sepa de qué tipo es el valor inicial.
- **D11. Tipos que Godot conoce y el plugin no.** Un parámetro cuyo tipo no se conoce va sin tipo, y dentro de la función nueva es un `Variant`. Si alguna declaración con `:=` del código extraído depende de él, dejaría de compilar («Cannot infer the type»), así que la acción no se ofrece. Lo mismo si el resultado pierde el tipo (detalle D5) y una declaración con `:=` posterior depende de él. Se sigue la regla de Godot: cualquier operación con un operando sin tipo da un valor sin tipo, y solo lo protegen los argumentos de una llamada, un índice o un literal de array o diccionario. La prueba masiva encontró este fallo: 42 de 1196 extracciones no compilaban antes de añadir la regla.
- **D12. Nombre igual al de una variable local.** Es un aviso, no un error. Se compiló en Godot 4.7.2 y una función puede llamarse como una variable local o un parámetro de quien la llama; solo confunde. `_init` sí es un error: Godot lo trata como constructor y no puede devolver un valor.
- **D13. Nombre por defecto ocupado.** Si la clase ya tiene `_extracted_function`, el diálogo abre con `_extracted_function_2`, y así sucesivamente.
- **D14. Escrituras dentro de una lambda.** No cuentan como salida. Una lambda captura las variables locales por valor, así que lo que les asigne tampoco llegaba fuera en el código original.
- **D15. La forma de asignación no se usa** si la última línea es una condición de una línea (`if listo: total = 1`), porque la llamada quedaría condicionada y con ella todo lo extraído, ni si esa sentencia tiene bloque propio. En esos casos se prueba la forma de una salida.
- **D16. Operador compuesto en la última línea.** `total += extra` se queda fuera como `total += _f(...)` solo si la selección no ha tocado antes `total`. Si lo ha hecho, el `+=` de fuera sumaría sobre el valor antiguo; se usa la forma de una salida, que devuelve el valor final.
- **D17. Puntos de ruptura y marcadores.** El de la primera sentencia se queda en la línea de la llamada. Los de las demás líneas extraídas se pierden: una edición solo sabe mover líneas dentro del tramo que sustituye.
- **D18. Código que comparte clases base.** La validación del nombre y la parte común de los dos diálogos (campo del nombre, panel de validación, colores) se sacaron a `function_name_check.gd` y `function_name_dialog.gd`. El diálogo del init hereda ahora de esa base sin cambiar de comportamiento.

## 4. Comportamiento

### 4.1 De la selección a las sentencias

- Cuentan las líneas que la selección toca. Si acaba en la columna 0 de una línea, esa línea no cuenta.
- Las líneas en blanco de los extremos se descartan. Los comentarios seleccionados por encima se van con el código; los de debajo, solo si pertenecen al bloque de la última sentencia (detalle D8).
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

**Entradas.** Todo nombre local declarado fuera de la selección y usado dentro pasa a ser un parámetro, con su nombre original, en el orden en que aparece por primera vez y con el tipo que el plugin conozca. Sin tipo conocido, o si la variable se declaró sin tipo, el parámetro va sin tipo (detalles D10 y D11).

**Salidas.** Obligan a devolver un valor:

- una variable declarada en la selección y usada después de ella;
- una variable de fuera reasignada dentro (`total = ...`, `total += ...`), porque `int`, `float`, `String`, `Vector2` y demás tipos por valor no se modifican desde otra función;
- una variable de fuera a la que se le cambia un campo o un índice (`size.x = 2`), si su tipo es un tipo por valor con campos (`Vector2`, `Color`, `Rect2`, `Transform3D`...) o no se conoce. En objetos, arrays y diccionarios no cuenta: se comparten por referencia.

Una escritura hecha dentro de una lambda no cuenta (detalle D14). Con más de una salida la acción no se ofrece.

Las variables declaradas en la selección dentro de un bloque interior (el cuerpo de un `if`, de un bucle) no existen después de él y nunca son salidas.

### 4.4 Forma del resultado

Se prueba en este orden y se usa la primera que encaje. Desde el cambio del apartado 8, cuando valen a la vez la forma 2 y la de dejar la última línea dentro, el diálogo deja elegir.

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
- la sentencia no tiene bloque propio (una variable con `set`/`get`, una lambda de varias líneas) ni es una condición de una línea (detalle D15);
- no hay ninguna otra salida. Si la única salida es la propia variable asignada con `=`, vale: el valor final es el que se devuelve. Con un operador compuesto no vale (detalle D16).

El tipo de la función es el declarado en la variable, o el del valor si el plugin lo conoce.

**3. Hay una salida.** La función acaba en `return x`. Si la variable era de fuera, la llamada es `x = _f(...)`; es el ejemplo del apartado 1. Si se declaraba dentro, la llamada reutiliza su declaración (detalle D9).

**4. No hay salidas.** La llamada es `_f(...)` y la función devuelve `void`.

### 4.5 Nombre de la función

Las mismas reglas que el nombre de "Generate Custom Init Definition...": vacío, no es un identificador, palabra reservada, ya existe una función u otro miembro con ese nombre, es una función o un callback del motor, o lo hereda de un script base. Además:

- Error: `_init`, que Godot trata como constructor.
- Aviso: coincide con un parámetro o una variable local de la función original (detalle D12).
- Aviso: no empieza por `_` (detalle D2).

### 4.6 Diálogo

```
┌ Extract Function ───────────────────────────────────────────┐
│ Name    [ _sum                                            ] │
│ Result  [ Return the variable 'total'                   ▾ ] │
│ New function                                                │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ func _sum(items: Array[int], total: int) -> int:        │ │
│ │     for item in items:                                  │ │
│ │         total += item                                   │ │
│ │     return total                                        │ │
│ └─────────────────────────────────────────────────────────┘ │
│ Changed function                                            │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ func run(items : Array[int], factor : float) -> void:   │ │
│ │     var total := 0                                      │ │
│ │     total = _sum(items, total)                          │ │
│ │     var scaled := total * factor                        │ │
│ └─────────────────────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ • Function name is valid.                               │ │
│ └─────────────────────────────────────────────────────────┘ │
│                   [Cancel]      [Extract]                   │
└─────────────────────────────────────────────────────────────┘
```

- **Nombre.** Con el foco al abrir y el texto seleccionado.
- **Resultado.** Las formas válidas para la selección (apartado 8.1). Con una sola, el desplegable está desactivado y solo informa.
- **Función nueva.** La función entera que se va a crear, en un editor de solo lectura.
- **Función cambiada.** La función original entera tal como va a quedar, con la línea de la llamada marcada y centrada.
- **Panel de validación y botones.** Como en el diálogo del init: mismos colores, Extract bloqueado con un error.
- **Teclado.** `ui_accept` extrae si el nombre es válido y `ui_cancel` cierra sin cambios.

Los parámetros no se pueden reordenar ni renombrar en esta versión.

### 4.7 Cuándo no se ofrece, en resumen

| Motivo | Apartado |
|---|---|
| No hay selección o solo cubre comentarios | 4.1 |
| La selección no está dentro de una función | 4.1 |
| Deja una sentencia a medias o sus extremos están en bloques distintos | 4.1 |
| Parte un `if`/`elif`/`else` o son ramas de un `match` | 4.1 |
| Comparte una línea con el resto de una llamada | 4.1 |
| `break` o `continue` de un bucle de fuera, `return` a mitad, `super()` | 4.2 |
| Más de una salida | 4.3 |
| Una declaración con `:=` perdería su tipo | Detalle D11 |

## 5. Arquitectura

- **`actions/code_context.gd`** (E1). Primera y última línea de la selección del editor. Hoy solo guarda la selección dentro de una sentencia.
- **`analysis/statement_range.gd`** (nuevo, E1). De un rango de líneas a las sentencias hermanas que lo cubren, con las comprobaciones de los apartados 4.1 y 4.2. Devuelve el rango o el motivo por el que no vale; el motivo no se enseña al usuario, pero lo usan los tests.
- **`analysis/variable_usage.gd`** (nuevo, E2). Lecturas y escrituras de nombres locales en un rango de sentencias y después de él. Trabaja sobre el código enmascarado, resuelve cada nombre con los scopes del índice y descarta lo que no es una variable: accesos a miembro, llamadas, claves de diccionario con `=`, rutas de nodo y nombres de declaración.
- **`analysis/symbol_index.gd`** (E2). La búsqueda de una variable devuelve también el scope que la declara, para saber si un parámetro es de una lambda de dentro de la selección o de fuera.
- **`actions/extract_function.gd`** (nuevo, E2 y E3). Lógica sin interfaz, como `init_function.gd`: forma del resultado, firma, línea de la llamada y plan de edición a partir de un nombre.
- **`editing/edit_plan.gd` y `editing/edit_applier.gd`** (E3). Un mismo plan puede sustituir líneas e insertar una función, en un solo paso de deshacer. Hoy un plan con sustitución de líneas ignora las inserciones.
- **`actions/function_name_check.gd`** (nuevo, E4). La validación del nombre, que hoy vive en `init_function.gd`, pasa a un archivo que usan las dos acciones.
- **`actions/extract_function_action.gd`** (nuevo, E3). `build_plan` devuelve el plan con el nombre por defecto, que es lo que usa el menú para decidir si la ofrece. `create_dialog` llega en E5.
- **`function_name_dialog.gd`** (nuevo, E5). Base común de los dos diálogos que piden un nombre de función.
- **`extract_function_dialog.gd`** (nuevo, E5). Sin lógica de extracción: pide todo a `extract_function.gd`.
- **`editing/snippet.gd`** (E3). Líneas literales, que se insertan sin sangrado añadido, para el contenido de un string de varias líneas.

Reglas del proyecto que aplican: prefijo `GDSEx` en todo tipo nuevo, «function» y no «method», y ninguna variable `static` en scripts que `plugin.gd` precargue directamente.

## 6. Pasos

### E1 — Selección, rango y estructura

- Líneas de la selección en el contexto.
- `statement_range.gd` con las reglas de 4.1 y 4.2.
- Runner: una acción de comprobación que describe el rango encontrado o el motivo del rechazo, como `describe_scopes`.

Verificación: casos en `tests/cases/extract_function_range/`. Como mínimo: una sentencia, varias, con bloque, selección que acaba en la columna 0, comentarios y líneas en blanco en los extremos, dentro de un `if`, de un bucle, de una lambda y de un `set`; y un caso por cada rechazo: sin selección, nivel de clase, sentencia a medias, bloques distintos, `elif`/`else` partido, ramas de `match`, línea compartida con otra sentencia, `break`/`continue` de un bucle de fuera, `return` a mitad, `super()`.

Hecho el 2026-10-07:

- `GDSExCodeContext` guarda `selection_first_line` y `selection_last_line`.
- `analysis/statement_range.gd` (`GDSExStatementRange.find`) devuelve el rango con sus sentencias hermanas, la función que lo contiene y lo que hace falta saber del flujo (si tiene `return`, si acaba en uno, si llega al final de la función, si tiene `await`), o uno de diez motivos de rechazo.
- Un `return`, `break`, `continue`, `await` o `super()` escrito detrás de un `func` en la misma sentencia se atribuye a esa lambda y no cuenta. Es la dirección segura: un `return` de más solo hace que la acción no se ofrezca.
- Runner: `action: describe_extraction_range` describe el rango o el motivo.
- 47 casos en `tests/cases/extract_function_range/`.

### E2 — Entradas, salidas y forma del resultado

- `variable_usage.gd` y el scope en la búsqueda de variables.
- En `extract_function.gd`: parámetros, salidas y cuál de las cuatro formas de 4.4 se usa.
- La acción de comprobación de E1 añade a su descripción los parámetros, la salida y la forma.

Verificación: casos en `tests/cases/extract_function_usage/`. Como mínimo: parámetro leído, variable de bucle, parámetro de la función, captura de una lambda, nombre tapado por una lambda o una declaración interior, miembro de la clase que no se pasa, acceso `.x` que no es la variable `x`, clave `{ x = 1 }`, variable declarada dentro y usada después, declarada dentro de un bloque interior, reasignación de una de fuera, campo de un `Vector2`, `append` en un array, dos salidas, y un caso por cada forma del resultado y por cada condición de la forma 2.

Hecho el 2026-10-07:

- `analysis/variable_usage.gd` (`GDSExVariableUsage`): usos de nombres locales en unas sentencias, y análisis de una asignación o declaración (destino, operador, dónde empieza el valor, si es compuesta o inferida).
- `GDSExSymbolIndex.find_variable` devuelve también el scope que declara la variable, y cada variable sabe si se declaró sin tipo.
- `actions/extract_function.gd` (`GDSExExtractFunction.analyze`) decide la forma del resultado, los parámetros, la salida y el tipo devuelto, y da la firma y las líneas de la llamada.
- Runner: `action: describe_extraction` enseña la forma, la firma y la llamada.
- 72 casos en `tests/cases/extract_function_usage/`.
- Decisiones tomadas aquí: D9, D10, D11, D14, D15 y D16.

### E3 — Generación y edición combinada

- Plan con sustitución de líneas e inserción en el aplicador, con cursor, vista, puntos de ruptura y marcadores.
- Firma, cuerpo con el sangrado rebajado a un nivel, `return` final cuando toca, `static`, `await` y línea de la llamada.
- Acción en el registro. Hasta E5 genera con el nombre por defecto.

Verificación: casos en `tests/cases/extract_function/` con una cabecera `options:` que da el nombre, sin diálogo. Como mínimo: las cuatro formas, `return` sin valor, `:=` con y sin tipo conocido, operador compuesto, `await`, función `static`, clase interna, selección dentro de un bloque sangrado y dentro de una lambda, colocación como privada y como pública, sangrado con espacios, un solo deshacer, y puntos de ruptura y marcadores que siguen a sus líneas.

Hecho el 2026-10-07:

- `GDSExEditApplier` aplica en un solo paso de deshacer una sustitución de líneas y las inserciones del mismo plan, estén por encima o por debajo. La sustitución puede fijar dónde queda el cursor.
- El cuerpo conserva el sangrado relativo de cada línea, las líneas en blanco y los comentarios. El contenido de un string de varias líneas se copia tal cual.
- `actions/extract_function_action.gd`, registrada detrás de "Add Explicit Type".
- 28 casos en `tests/cases/extract_function/` y uno en `tests/cases/view/` que comprueba que la vista no se mueve. Todos los casos comprueban que un solo deshacer devuelve el texto original.
- Decisión tomada aquí: D17.

### E4 — Validación del nombre

- Sacar la validación a `function_name_check.gd` sin cambiar el comportamiento del init.
- Reglas propias de 4.5.

Verificación: los 25 casos de `init_function_name` siguen en verde y hay casos nuevos para el nombre de una variable local, el de un parámetro y el aviso del nombre sin `_`.

Hecho el 2026-10-07:

- `actions/function_name_check.gd` (`GDSExFunctionNameCheck`) con las reglas comunes; `init_function.gd` solo añade su aviso de nodos y recursos.
- `GDSExExtractFunction.check_function_name` añade el error de `_init` y los dos avisos.
- Runner: `action: check_extract_function_name` con `function_name` y `expect_check`.
- 16 casos en `tests/cases/extract_function_name/`. Los 25 del init siguen en verde.
- Decisión tomada aquí: D12.

### E5 — Diálogo

- `extract_function_dialog.gd` y `create_dialog` en la acción.

Verificación: casos que abren el diálogo desde el runner, como los del init: genera con el nombre por defecto, genera con otro nombre, la vista previa cambia al escribir, un nombre con error bloquea Extract, `ui_accept` y `ui_cancel`.

Hecho el 2026-10-07:

- `function_name_dialog.gd`, la base común, y `extract_function_dialog.gd`. `init_function_dialog.gd` hereda de la base.
- Cuatro casos que abren el diálogo desde el menú (nombre por defecto, otro nombre, cancelar y nombre por defecto ocupado) y uno en `tests/cases/menu/` que recorre la vista previa, los errores, los avisos y el teclado.
- Decisiones tomadas aquí: D13 y D18.

### E6 — Prueba masiva y cierre

- Comprobación sobre los scripts del proyecto: para cada función, extraer cada rango de sentencias hermanas en que la acción se ofrece y comprobar que el script sigue compilando. Es la misma idea que encontró tres fallos en "Add Explicit Type".
- Pasada en el editor real: menú, diálogo y resultado.
- README, CHANGELOG y el listado de archivos de `REFACTOR_PLAN.md`.

La prueba masiva encuentra lecturas que se hayan escapado, porque dejan un nombre sin definir. No encuentra una escritura no detectada, que compila y cambia el comportamiento: eso lo cubren los casos de E2.

Hecho el 2026-10-07:

- **Tests de comportamiento**, que no estaban en el plan. `action: check_extraction_behavior` compila el script del caso, extrae la selección, y ejecuta `run` con los mismos datos en el original y en el resultado; tienen que devolver lo mismo y dejar igual los argumentos y el estado. 33 casos en `tests/cases/extract_function_behavior/`: las cuatro formas, tipos por valor y por referencia, bucles, `match`, lambdas y miembros de la clase. Se comprobó que detectan un fallo: al desactivar a propósito la regla de los tipos por valor, fallan los tres casos que dependen de ella.
- **Prueba masiva en la suite.** `action: check_extract_project_scripts` extrae uno de cada 60 rangos de sentencias hermanas de los scripts del proyecto y comprueba que el resultado compila. La cabecera `sample_step: 1` los prueba todos, pero tarda varios minutos.
- **Prueba masiva completa**, lanzada a mano una vez sobre todos los scripts del proyecto: 18.264 rangos, 8.750 extracciones ofrecidas y aplicadas, y las 8.750 compilan. De los rechazos, 6.071 son rangos a nivel de clase, 1.752 un `return` a mitad, 668 más de una salida, 395 un `break` o `continue` de un bucle de fuera, 348 una cadena `if`/`else` partida, 148 ramas de `match`, 131 un tipo que se perdería y uno una línea compartida.
- README, CHANGELOG y el listado de archivos de `REFACTOR_PLAN.md`.
- Pendiente de la pasada en el editor real por parte del usuario: aspecto del menú y del diálogo.

## 7. Límites conocidos de esta versión

- Una sola salida.
- Los parámetros no se reordenan ni se renombran.
- El análisis de variables es textual sobre el código enmascarado, no un parser completo. Ante un uso que no sepa clasificar lo toma por lectura, que como mucho añade un parámetro de más.
- Los tipos que dependen de otro script cargado con `preload` no se conocen, así que esos parámetros y ese valor devuelto salen sin tipo, y si eso rompe una declaración con `:=` la acción no se ofrece (detalle D11). En un proyecto que usa `class_name` pasa mucho menos.
- Un `return` dentro de una condición de una línea (`if vacio: return 0`) al final de la selección no cuenta como «la última línea es un `return`»: solo se admite si la selección llega al final de la función.

## 8. Cambios tras probarla

Los pidió el usuario el 2026-10-07, después de usarla en `tests/test.gd`.

### 8.1 Elegir el resultado

El caso que lo motivó: al extraer `_dic = { "value" : 2 }`, donde `_dic` es una variable de la clase, la acción dejaba `_dic = _f()` y una función que devolvía el diccionario. El usuario esperaba que la función asignara `_dic` ella misma.

Las dos son correctas, así que ahora se calculan todas las formas válidas y el diálogo deja elegir en un desplegable **Result**:

| Etiqueta | Forma | Qué hace |
|---|---|---|
| Return what the selection returns | 1 | La selección tiene `return`; es la única opción |
| Return the value of the last line | 2 | La asignación de la última línea se queda fuera con la llamada como valor |
| Return the variable 'x' | 3 | Todo se mueve y la función devuelve la variable que hace falta fuera |
| Return nothing | 4 | Todo se mueve, también la asignación, y la llamada va sola |

Hay dos opciones cuando la última línea asigna algo que la función nueva puede asignar por sí misma: una variable de la clase, un elemento o una propiedad de algo (`names[0] = ...`, `$Label.text = ...`), o una variable local que no se usa después.

La que sale marcada:

- **Return nothing**, si el destino no es una variable local (una variable de la clase, `self.x`, una ruta de nodo). Es lo que pidió el usuario.
- **Return the value of the last line**, si el destino es una variable local o una declaración, como se acordó al principio.

Detalles decididos al implementar:

- **D19. Opciones equivalentes.** Si la última línea asigna la misma variable local que habría que devolver, las formas 2 y 3 dan la misma llamada y solo cambia el final de la función (`return valor` frente a asignar y `return total`). Solo se ofrece la 2.
- **D20. Con una sola opción** el desplegable se ve pero está desactivado: así el diálogo siempre dice qué devuelve la función.
- **D21. Cada opción se valida por separado.** Una forma que perdería un tipo (detalle D11) o que tiene más de una salida no aparece, aunque la otra sí.

### 8.2 Vistas previas completas

La firma y la llamada, que eran dos líneas de texto, pasan a ser dos editores de solo lectura: la función nueva entera y la función original entera tal como queda.

- **Colores.** Usan `GDScriptSyntaxHighlighter`, el resaltador del propio editor de scripts, así que el código se ve con los mismos colores y la misma fuente que en el editor. Godot solo deja crearlo dentro del editor; fuera (en la suite de tests) las vistas quedan sin colores.
- **Línea de la llamada.** Va marcada con el color de acento del editor y la vista se centra en ella, para encontrarla en una función larga.
- **Clases internas.** Las dos vistas se enseñan sin el sangrado de la clase.
- **Tamaño.** El diálogo pasa de 560 a 680 de ancho y a 560 de alto.

Hecho el 2026-10-07:

- `GDSExExtractFunction.find_alternatives` devuelve las formas válidas con la preferida primero; `form_label`, `function_text`, `caller_text` y `caller_call_line` dan lo que enseña el diálogo, y `build_plan_for` genera el plan de la opción elegida.
- `extract_function_dialog.gd` tiene el desplegable y las dos vistas.
- Runner: `describe_extraction` añade una línea `or ...` por cada alternativa; la cabecera `options` admite `form` (sin diálogo) y `result` (texto de la opción en el diálogo).
- Tests: 7 casos nuevos de alternativas en `extract_function_usage`, 4 en `extract_function` (por defecto y eligiendo, con y sin diálogo) y el recorrido del diálogo ampliado: dos resultados, cambio de opción, vistas de una clase interna y marca de la llamada.
- Comprobado en un editor real sin ventana, sobre un proyecto de prueba: el resaltador se crea y colorea palabras clave, tipos, números, cadenas y comentarios; la fuente y el tamaño son los del editor.
