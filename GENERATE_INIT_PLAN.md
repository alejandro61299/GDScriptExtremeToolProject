# Plan — Acciones Generate Init

Dos acciones nuevas que comparten la misma lógica: generar una función inicializadora a partir de las variables de la clase donde está el cursor. Entran en la versión siguiente a la 0.1.0.

| Paso | Contenido | Estado |
|---|---|---|
| I1 | Categoría de miembro compartida y punto de inserción según el orden de miembros | Hecha |
| I2 | Lógica común y acción "Generate Default Init Definition" | Hecha |
| I3 | Validación del nombre de la función | Hecha |
| I4 | Acciones con diálogo y acción Custom sin interfaz | Hecha |
| I5 | Diálogo de "Generate Custom Init Definition..." | Hecha |
| I6 | Verificación en el editor y documentación | Pendiente |

Cada paso termina con la suite en verde y una pasada de `--headless --editor --quit` sin errores ni avisos. Los commits los hace el usuario al cerrar cada paso.

## 1. Qué hacen

### Generate Default Init Definition

Genera `_init` con un parámetro por cada variable privada de la clase y su asignación, sin preguntar nada.

```gdscript
var _health : int
var _name : String = "unnamed"

func _init(p_health: int, p_name: String) -> void:
	_health = p_health
	_name = p_name
```

### Generate Custom Init Definition...

Abre un diálogo para elegir el nombre de la función y las variables, y genera lo mismo con esas opciones.

## 2. Decisiones acordadas

Las tomó el usuario el 2026-10-06, en dos rondas.

1. **Código generado.** Un parámetro por variable y una asignación por parámetro. La función devuelve `void`; no se devuelve `self`.
2. **Nombre del parámetro.** El ajuste `naming/generated_param_format` aplicado al nombre de la variable sin los `_` iniciales: `_health` da `p_health`. Si ese nombre no se puede usar, porque ya lo tiene otro parámetro o coincide con algo integrado del lenguaje, se usa `naming/fallback_param_format` (`param_1`), como en "Generate Function Definition".
3. **Tipo del parámetro.** El de la variable, declarado o inferido. Una variable sin tipo da un parámetro sin tipo.
4. **Variables con valor inicial.** Cuentan como cualquier otra, en las dos acciones.
5. **Orden de los parámetros.** El de declaración. El diálogo no permite reordenar.
6. **Alcance.** Solo las variables de la clase donde está el cursor: no las heredadas ni las de clases internas. No se genera `super(...)`.
7. **Si `_init` ya existe.** La Default no aparece en el menú (oculta, no en gris). La Custom abre con el nombre alternativo.
8. **Nodos y recursos.** En una clase que hereda de `Node` o `Resource`, Godot llama a `_init` sin argumentos al instanciar una escena o cargar un recurso. Ahí la Default no se ofrece, y la Custom abre con el nombre alternativo y avisa si se elige `_init` con algún parámetro.
9. **Dónde se inserta.** Donde manda `order/class_member_order`: `_init` en la categoría `init`; cualquier otro nombre, en `public_functions` o `private_functions` según empiece o no por `_`.
10. **Cuándo se ofrecen.** La Default, si hay al menos una variable privada que cumpla. La Custom, si hay al menos una variable de cualquiera de los tres grupos.
11. **Nombre inválido.** Se marca en rojo y bloquea el botón Generate.
12. **Diseño del diálogo.** El de los diálogos de Godot 4.7.2: botones en la última fila, centrados y con el espaciado estándar. Los errores y avisos siguen la misma estrategia que esos diálogos.
13. **Teclado.** Las acciones de interfaz de Godot, no teclas fijas: `ui_accept` genera y `ui_cancel` cancela.
14. **Etiqueta.** La Custom acaba en puntos suspensivos.
15. **Nombre alternativo.** `initialize` por defecto, configurable con un ajuste de Project Settings.
16. **Sin variables marcadas.** La Custom genera la función con `pass`.
17. **Tras generar.** La vista muestra la función y el cursor queda al final de su última línea.

## 3. Detalles decididos al implementar

El usuario no los ha fijado; son la forma concreta de cumplir lo acordado y se pueden cambiar sin rehacer el plan.

- **D1. Qué es "algo integrado".** Palabras reservadas, funciones globales (`range`, `print`...), tipos básicos, clases del motor y constantes globales.
- **D2. Parámetro con el nombre de un miembro de la clase.** También usa el nombre de reserva, para no tapar el miembro. Solo puede pasar si el formato configurado es `{name}` a secas.
- **D3. Nombre del ajuste.** `naming/alternative_init_function_name`.
- **D4. Cómo se muestran los errores.** Con `ConfirmationDialog`, que ya da la fila de botones estándar, y un panel de validación encima de los botones como el de "Create Script": una línea por mensaje, con los colores del tema del editor (verde válido, amarillo aviso, rojo error), y Generate desactivado mientras haya un error. El panel propio de Godot (`EditorValidationPanel`) no se puede instanciar desde un plugin, así que se reproduce. Además el texto del nombre se pone en rojo, como pidió el usuario al principio.

## 4. Comportamiento

### 4.1 Variables

Entran las variables de instancia de la clase. Quedan fuera las constantes, las `static` y las `@onready`.

| Grupo | Criterio | Default | Lista de la Custom | Marcada al abrir |
|---|---|---|---|---|
| Privadas | Empiezan por `_` y no llevan `@export` | Sí | Sí | Sí |
| Públicas | No empiezan por `_` ni llevan `@export` | No | Sí | No |
| Exports | Llevan cualquier anotación `@export` | No | Sí | No |

Es la misma clasificación que usa "Reorder Class Members", así que un `@export var _x` es export, no privada.

### 4.2 Nombre de la función

Nombre con el que abre la Custom: `_init`, salvo que la clase ya tenga `_init` o herede de `Node` o `Resource`; entonces el del ajuste `naming/alternative_init_function_name` (`initialize` por defecto).

Errores (línea roja en el panel de validación, nombre en rojo y Generate bloqueado):

- Vacío.
- No es un identificador válido o es una palabra reservada.
- Ya hay una función con ese nombre en la clase.
- Ya hay otro miembro con ese nombre en la clase: variable, constante, señal, enum o clase interna.
- Es una función de la clase del motor de la que hereda, sea normal (`get_class`, `queue_free`) o un callback (`_ready`, `_to_string`). La única excepción es `_init`.
- Lo hereda de un script base o de una clase interna base.

Lo que el compilador acepta no se marca como error: el nombre de una propiedad o señal nativa (`name`, `ready`), de una función global (`print`), de un tipo (`int`) o de una clase del motor (`Node`).

Aviso (línea amarilla en el panel de validación, no bloquea):

- `_init` con algún parámetro en una clase que hereda de `Node` o `Resource`.

Si no hay error, el panel muestra en verde que el nombre es válido.

### 4.3 Diálogo

```
┌ Generate Custom Init Definition ────────────────────────────┐
│ Name  [ initialize                                        ] │
│ [Private] [Public] [Exports]                 [All] [None]   │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ [x] _health          int                                │ │
│ │ [x] _name            String                             │ │
│ │ [ ] speed            float                              │ │
│ └─────────────────────────────────────────────────────────┘ │
│ func initialize(p_health: int, p_name: String) -> void      │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ • Function name is valid.                               │ │
│ └─────────────────────────────────────────────────────────┘ │
│                   [Cancel]      [Generate]                  │
└─────────────────────────────────────────────────────────────┘
```

- **Nombre.** Campo de texto con el foco al abrir y el texto seleccionado.
- **Filtros.** Tres botones de dos estados, todos activos al abrir. Deciden qué filas se ven; una fila oculta conserva su casilla y sigue contando si estaba marcada.
- **All y None.** Marcan o desmarcan las filas visibles.
- **Lista.** Una fila por variable con casilla, nombre y tipo, en orden de declaración.
- **Vista previa.** La firma que se va a generar, actualizada al cambiar el nombre o una casilla.
- **Panel de validación.** Encima de los botones, con el estado del nombre y, si toca, el aviso.
- **Fila inferior.** Cancel y Generate, centrados, los que pone `ConfirmationDialog`.
- **Teclado.** `ui_accept` genera si el nombre es válido, tanto desde el campo del nombre como desde la lista; `ui_cancel` cierra sin cambios. En la lista, `ui_select` (la barra espaciadora) marca o desmarca la fila seleccionada. En los botones, `ui_accept` pulsa el botón, como en cualquier control de Godot.

## 5. Arquitectura

Hoy una acción devuelve su plan al instante con `build_plan(context)`. La Custom necesita pedir datos antes.

- **`analysis/member_categories.gd`** (nuevo, I1). La clasificación de un miembro en su categoría de `order/class_member_order`, que hoy vive dentro de `class_layout.gd`. La usan el reordenado, el punto de inserción y la lista de variables.
- **`editing/placement.gd`** (I1). Función nueva que da el punto de inserción de una función nueva según su categoría: detrás del último miembro cuya categoría va antes o es la misma.
- **`actions/init_function.gd`** (nuevo, I2 e I3). Lógica sin interfaz: variables elegibles con su grupo y tipo, texto de la firma, plan de edición a partir de un nombre y una lista de variables, y validación del nombre.
- **`plugin_project_settings.gd`** (I3). Ajuste nuevo `naming/alternative_init_function_name`.
- **`actions/generate_default_init_action.gd`** (nuevo, I2).
- **`actions/code_action.gd`** (I4). Función nueva `create_dialog(context, on_plan_ready)`, que por defecto devuelve `null`. El menú (`code_actions_popup.gd`) abre el diálogo si la acción devuelve uno y aplica el plan cuando el diálogo confirma.
- **`actions/generate_custom_init_action.gd`** (nuevo, I4). `build_plan` devuelve el plan con las opciones por defecto, que es lo que usa el menú para decidir si la ofrece.
- **`init_function_dialog.gd`** (nuevo, I5). El diálogo. No contiene lógica de generación: pide todo a `init_function.gd`.

Reglas del proyecto que aplican: prefijo `GDSEx` en todo tipo nuevo, «function» y no «method», y ninguna variable `static` en scripts que `plugin.gd` precargue directamente.

## 6. Pasos

### I1 — Categoría compartida y punto de inserción

- Sacar la clasificación de miembros a `member_categories.gd` sin cambiar el comportamiento.
- Añadir a `placement.gd` el punto de inserción por categoría, con las líneas en blanco de los ajustes de formato.

Verificación: la suite existente sigue en verde, incluidas las comprobaciones de reordenado sobre todos los scripts del proyecto. El punto de inserción se prueba en I2, que es su primer uso.

Hecho el 2026-10-06:

- `analysis/member_categories.gd` (`GDSExMemberCategories`) tiene los nombres de las categorías como constantes y las funciones `of_member`, `of_variable`, `of_function`, `index_of`, `is_static` e `is_private`. `class_layout.gd` ya no clasifica por su cuenta.
- `GDSExPlacement.function_by_order(class_scope, function_name, lines, indent_unit)` coloca la función detrás del último miembro cuya categoría va antes o es la misma. Si todos van después, la coloca delante del primero, por encima de los comentarios que tenga pegados.
- Las líneas en blanco alrededor de las funciones que genera el plugin salen ahora del ajuste `format/blank_lines_around_functions_and_classes` en vez de una constante, también en "Generate Function Definition". Con el valor por defecto no cambia nada.

### I2 — Lógica común y acción Default

- `init_function.gd`: variables elegibles, nombres y tipos de parámetro, firma y plan.
- Acción Default y su entrada en el registro.
- Reglas de oferta: sin `_init`, con alguna variable privada y fuera de `Node` y `Resource`.

Verificación: casos en `tests/cases/generate_default_init/`. Como mínimo: caso básico, tipos inferidos y sin tipo, variables con valor inicial, exclusión de `static`, `@onready`, `@export`, públicas y constantes, clase interna, colocación en una clase ordenada y en una desordenada, nombres de parámetro repetidos o que coinciden con algo integrado, formato de parámetro cambiado por ajustes, y los tres casos en que no se ofrece.

Hecho el 2026-10-06:

- `actions/init_function.gd` (`GDSExInitFunction`) va en `actions/` y no en `analysis/` como decía el plan, porque construye el plan de edición y usa el punto de inserción. Da las variables elegibles con su grupo y tipo, la firma y el plan.
- `analysis/param_names.gd` (`GDSExParamNames`) reúne el formato de los nombres de parámetro que antes tenía "Generate Function Definition"; las dos acciones lo comparten. La comprobación de nombres reservados solo la hace la acción nueva.
- `GDSExMemberCategories.of_variables` clasifica las variables teniendo en cuenta un `@export` escrito en la línea de encima y sin confundirlo con `@export_group`.
- El tipo del parámetro se obtiene resolviendo la variable como expresión, así que vale para tipos declarados e inferidos.
- `EditApplier` coloca el cursor cuando la selección de un fragmento está vacía; antes solo seleccionaba texto.
- 16 casos en `tests/cases/generate_default_init/`. La colocación delante del primer miembro solo se alcanza con un orden de miembros personalizado, y así se prueba.
- Pendiente para I4: comprobar que `@onready` queda fuera. No se puede probar aquí porque `@onready` solo compila en nodos y la Default no se ofrece en nodos.

### I3 — Validación del nombre

- En `actions/init_function.gd`: nombre por defecto según la clase, lista de errores y el aviso de `Node` y `Resource`.
- Ajuste `naming/alternative_init_function_name` en Project Settings y en el README.

Verificación: casos con una cabecera nueva para el nombre y el resultado esperado (válido, error o aviso), uno por cada regla del apartado 4.2.

Hecho el 2026-10-06:

- Antes de fijar las reglas se compiló con Godot 4.7.2 una función con cada tipo de nombre. De ahí salen dos cambios respecto al borrador: un callback del motor que la clase aún no declara (`_ready`) pasa a ser error, porque una función con parámetros no coincide con la firma del motor y no compila; y los nombres de propiedades y señales nativas, funciones globales y tipos dejan de ser error, porque sí compilan.
- `GDSExInitFunction.default_function_name(context)` y `check_function_name(context, name, parameter_count)`, que devuelve un nivel (válido, aviso o error) y un mensaje en inglés.
- Ajuste `naming/alternative_init_function_name` en Project Settings. Si su valor no es un identificador válido, se usa `initialize`.
- Runner: la cabecera de cada caso queda disponible entera para las comprobaciones especiales, y `action: check_init_function_name` usa `init_name`, `init_parameters`, `expect_check` y `expect_default_name`.
- 25 casos en `tests/cases/init_function_name/`.

### I4 — Acciones con diálogo y Custom sin interfaz

- `create_dialog` en la acción base y su uso en el menú, tanto desde el atajo como desde el submenú.
- Acción Custom: plan a partir de unas opciones (nombre y variables) y plan con las opciones por defecto.

Verificación: casos en `tests/cases/generate_custom_init/` con una cabecera `options:` que da el nombre y las variables, sin abrir ningún diálogo. Como mínimo: otro nombre, mezcla de privadas, públicas y exports, ninguna variable, colocación como función pública y como privada, y nombre de reserva cuando el parámetro se llamaría igual que un miembro de la clase.

Hecho el 2026-10-06:

- `GDSExCodeAction.create_dialog(context, on_plan_ready)`: una acción que necesita datos devuelve su diálogo y, cuando el usuario confirma, llama a `on_plan_ready` con el plan. Las demás devuelven `null` y siguen como antes.
- `code_actions_popup.gd` abre ese diálogo centrado en la ventana del editor de código y lo libera al cerrarse. Aplicar el plan pasa a ser una función estática, porque el menú ya se ha liberado cuando el diálogo confirma.
- `actions/generate_custom_init_action.gd`: su `build_plan` da el plan con las opciones por defecto (nombre por defecto y variables privadas) y sirve para decidir si la acción se ofrece. Todavía no está en el registro, así que no aparece en el menú hasta I5.
- Runner: `action: generate_custom_init` con cabecera `options: {"name": ..., "variables": [...]}`, y `action: run_dialog_action`, que comprueba con una acción de prueba que el script no cambia hasta confirmar, que el diálogo se abre en la ventana del editor, que al confirmar se aplica el plan y que el diálogo se libera.
- 12 casos en `tests/cases/generate_custom_init/` y 1 en `tests/cases/menu/`. Queda cubierto lo pendiente de I2: `@onready`, `static` y constantes no se pueden elegir aunque se pidan por nombre.

### I5 — Diálogo

- Construir el diálogo del apartado 4.3 y conectarlo a la acción Custom.

Verificación: una comprobación del runner que instancia el diálogo sin editor y revisa el estado inicial (nombre, filas, casillas), los filtros, All y None, la vista previa, el panel de validación en sus tres estados, el nombre en rojo con Generate bloqueado, y que confirmar entrega las opciones elegidas.

Hecho el 2026-10-06:

- `init_function_dialog.gd` (`GDSExInitFunctionDialog`, un `ConfirmationDialog`) con el diseño del apartado 4.3. Los botones de filtro de un grupo sin variables salen desactivados. La acción Custom ya está en el registro y aparece en el menú.
- Colores y fuente salen del tema del editor (`success_color`, `warning_color` y `error_color` del tipo `Editor`; fuente `source` de `EditorFonts` para la vista previa), con valores de reserva fuera del editor.
- Runner: `action: check_init_dialog` recorre los estados del diálogo y `action: run_custom_init_dialog` abre el diálogo desde el menú, aplica las opciones de la cabecera `options:` a través de sus controles y pulsa Generate.
- Dos casos del menú usaban una clase con una variable y pasaron a usar una señal, porque la Custom se ofrece en cualquier clase con variables.

Tres fallos que solo aparecieron al probar en el editor sin interfaz, ya corregidos:

- **Altura desproporcionada.** Una etiqueta con ajuste de línea automático calcula su alto mínimo antes de tener ancho, y la ventana se abría con 868 píxeles de alto. La etiqueta de validación ya no ajusta líneas: recorta con puntos suspensivos y muestra el mensaje completo al pasar el ratón. El aviso de nodos y recursos se acortó para que quepa.
- **`Intro` dejaba de generar tras un error.** Desde Godot 4.4 un `LineEdit` sale del modo edición al enviar. Con `keep_editing_on_text_submit` el campo sigue editando.
- **La barra espaciadora generaba en vez de marcar la fila.** `ui_accept` incluye la barra espaciadora, así que en la lista se comprueba primero `ui_select`.

Un arreglo fuera del diálogo, destapado por el runner: el plugin conocía los valores de los enums globales (`KEY_ENTER`) pero no sus nombres (`Key`, `Error`, `Side`), y ofrecía "Generate Local Variable" y "Generate Class Variable" sobre un tipo así. `GDSExTypeResolver.is_global_enum` los reconoce ahora, con dos casos nuevos.

Nota para repetir la prueba: el editor guarda los scripts modificados al cerrarse, también sin interfaz. El script de ejemplo de la prueba hay que restaurarlo antes de cada ejecución o los resultados se contaminan.

### I6 — Editor y documentación

- Prueba de extremo a extremo en el editor sin interfaz: abrir el diálogo desde el menú, generar y comprobar el script. Sin escribir en `EditorSettings`.
- README: las dos acciones en la tabla.
- `REFACTOR_PLAN.md`: resumen de la fase y enlace a este plan.

Queda para el usuario lo que no se puede ver sin interfaz: aspecto del diálogo, uso con ratón y tamaños.

## 7. Fuera de alcance

- Reordenar los parámetros en el diálogo.
- Variables heredadas y llamada a `super(...)`.
- Devolver `self` o generar una función `static` de fábrica.
- Parámetros con valor por defecto.
- Actualizar un `_init` que ya existe.
- Recordar entre usos el nombre o la selección del diálogo.
