# Plan — Crear funciones en otro script

Hoy "Generate Function Definition" solo escribe en el script que se está editando. Si la llamada es sobre un objeto o una clase de otro script (`shapes.missing()`, `Shapes.missing()`), la acción no se ofrece. El plan es que se ofrezca y que cree la función en ese otro script, en su pestaña, con los tipos escritos como hay que escribirlos allí.

Sale del apartado «Para después: crear funciones en otro script» de `PRELOAD_TYPES_PLAN.md`. Aquel plan dejó hecho lo difícil: saber de qué clase y de qué archivo es el receptor de la llamada, y tener ese archivo analizado.

| Paso | Contenido | Estado |
|---|---|---|
| C1 | Un plan de edición puede ir a otra pestaña | Hecha |
| C2 | La acción elige el otro script como destino | Hecha |
| C3 | Tipos escritos para el script de destino | Pendiente |
| C4 | Pruebas masivas, editor y documentación | Pendiente |

Cada paso termina con la suite en verde y una pasada de `--headless --editor --quit` sin errores ni avisos, y se cierra con un commit en la rama `generate-outside`.

## 1. Qué cambia

El script que se edita:

```gdscript
const Shapes = preload("res://shapes.gd")

var shapes: Shapes = Shapes.new()


func run(circle: Shapes.Circle) -> void:
	var area: float = shapes.scaled_area(circle, 2.0)
```

Hoy el menú no ofrece nada sobre `scaled_area`. Con el plan ofrece "Generate Function Definition in shapes.gd", y al elegirla se abre la pestaña de `shapes.gd` con esto añadido al final de la clase y el cuerpo seleccionado:

```gdscript
func scaled_area(circle: Circle, param_1: float) -> float:
	return 0.0
```

El tipo del primer parámetro es `Circle` y no `Shapes.Circle`: dentro de `shapes.gd` la constante `Shapes` no existe.

| Llamada | Dónde se crea | Cómo |
|---|---|---|
| `shapes.missing()`, con `shapes` una instancia de otro script | En la clase raíz de ese script | `func` |
| `Shapes.missing()`, sobre la constante con `preload` o la clase global | En la clase raíz de ese script | `static func` |
| `circle.missing()`, con `circle` una instancia de una clase interna de otro script | Dentro de esa clase interna, en su archivo | `func` |
| `Shapes.Circle.missing()` | Dentro de esa clase interna | `static func` |
| `base.missing()`, con `base` tipada con el script base | En el script base | `func` |
| `missing()` sin receptor | En la clase actual, como hoy | Como hoy |
| `super.missing()` | No se ofrece, como hoy | |

Solo cambia "Generate Function Definition". Las demás acciones siguen escribiendo únicamente en el script que se edita.

## 2. Decisiones acordadas

Las tomó el usuario el 2026-10-08.

1. **Adónde va el usuario después de generar.** A la pestaña del otro script, con el cuerpo de la función seleccionado. Es lo que ya pasa dentro de un archivo, y lo siguiente que se hace es escribir el cuerpo. Se vuelve a la llamada con «atrás» del editor de scripts.
2. **Guardar el otro script.** El plugin no lo guarda. Consecuencia que hay que conocer: Godot compila contra la versión guardada, así que la llamada sigue marcada como error hasta que se guarde la otra pestaña.
3. **Dónde se puede escribir.** En cualquier script, sea de quien sea, también los de un addon ajeno. Lo único que queda fuera es una clase del motor, que no tiene script donde escribir. El borrador proponía no ofrecer la acción en addons de otros; el usuario decidió que se intente siempre.
4. **Nombre que empieza por `_`.** Se ofrece y la función se crea con el nombre que el usuario escribió. GDScript no impide llamarla desde fuera y Godot 4.7.2 no tiene ningún aviso para ello (apartado 5).
5. **Versión.** Entra en la 0.4.0.

## 3. Detalles decididos al redactar

No los ha fijado el usuario; son la forma concreta que propongo y se pueden cambiar sin rehacer el plan.

- **D1. Siempre a través de una pestaña.** El plugin nunca escribe el archivo del otro script directamente. Pide a Godot que lo abra y edita su pestaña. Así el deshacer funciona, no se pisa lo que haya sin guardar en esa pestaña y Godot no encuentra un archivo cambiado por fuera.
- **D2. Manda el texto de la pestaña.** El sitio donde va la función se calcula sobre el texto de la pestaña de destino en el momento de aplicar, no sobre lo que se leyó al abrir el menú. Motivo, comprobado (apartado 5): si el archivo cambió por fuera con la pestaña abierta, la pestaña y el archivo tienen textos distintos, y un número de línea sacado del archivo caería en otro sitio de la pestaña.
- **D3. Comprobar antes de tocar.** Tras pedir que se abra el script, la pestaña activa tiene que ser la suya y admitir edición. Y al rehacer el análisis con su texto, la acción tiene que seguir teniendo sentido: si resulta que la función ya existe en la pestaña, no se inserta. En cualquiera de esos casos no se cambia nada.
- **D4. Dónde va la función.** Al final de la clase de destino, tras su última función o variable, con las líneas en blanco de la configuración del proyecto y la sangría del archivo de destino. Es la misma regla que hoy cuando la clase de destino no es la que rodea al cursor.
- **D5. Tipo que no se puede escribir en el destino.** El parámetro queda sin tipo y el valor devuelto como `Variant`. El plugin no añade constantes `preload` al otro script. Es la decisión 3 del plan anterior, vista desde el otro lado.
- **D6. `static`.** Solo cuando la llamada es sobre la clase y no sobre una instancia. Ya se calcula así para las clases internas del propio script.
- **D7. Qué script puede recibir código.** Siguiendo la decisión 3, cualquier script que el plugin haya podido leer y que no sea el que se edita. Solo se descarta lo que no tiene pestaña donde escribir: un script que ni está abierto ni existe como archivo, y cualquiera si Godot está configurado para abrir los scripts en un editor externo. La pregunta se hace en un único sitio, `GDSExOpenScripts`, que sustituye a la comprobación del detalle D5 del plan anterior.
- **D8. No se mira si el archivo admite escritura.** El borrador lo comprobaba antes de ofrecer la acción. Con la decisión 3 se quita: la función se inserta en la pestaña, y si el archivo no se puede guardar es Godot quien lo dice al guardar, con su propio mensaje.
- **D9. El menú dice dónde va.** La etiqueta lleva el nombre del archivo: "Generate Function Definition in shapes.gd". Sin eso el usuario no sabría que la acción lo va a sacar del script.
- **D10. Un plan, un script.** Un plan de edición se aplica entero a un solo script, el que se edita u otro. Ninguna acción toca dos archivos a la vez; esta no lo necesita porque la llamada no cambia.
- **D11. Solo acciones sin diálogo.** Un plan para otro script solo puede salir de una acción que se aplica directamente. Las que pasan por un diálogo siguen escribiendo en el script que se edita.
- **D12. Casos con dos scripts.** Un caso de la suite da el otro script con la sección `=== unsaved <ruta>` que ya existe, o con un archivo de `tests/fixtures/`, y lo que se espera de él con una sección nueva, `=== expected <ruta>`.
- **D13. Funciones que toda clase de script tiene.** Una referencia a una clase de script es un objeto del motor con funciones propias: `Shapes.can_instantiate()`, `Shapes.get_base_script()`. Sobre una referencia a clase, esas no se ofrecen. Salió en C2: con solo el propio script casi no se veía, y al abrir la acción a las constantes con `preload` habría sido una oferta falsa frecuente. Vale también para las clases internas del propio script.
- **D14. Clases escritas en una línea.** Sobre una clase como `class Empty: pass` no se ofrece. No hay bloque donde meter la función, y lo que se generaba no compilaba. Salió en C2 y vale también para el propio script.

## 4. Comportamiento

### 4.1 Cuándo se ofrece

Tienen que cumplirse todas:

| Condición | Si no se cumple |
|---|---|
| El receptor se resuelve a una clase de otro script: constante con `preload`, clase global, script base o una clase interna de cualquiera de ellos. Una clase del motor no lo es | No se ofrece, como hoy |
| La función no existe en esa clase ni en las que hereda, contando lo que haya sin guardar en su pestaña | No se ofrece |
| El script de destino tiene una pestaña donde escribir (detalle D7) | No se ofrece |
| No es `.new()` ni una llamada sobre `super` | No se ofrece, como hoy |

Si el receptor resulta ser una clase del propio script alcanzada dando la vuelta por otro (`second.first.rename()`), se escribe en el script que se edita. Ya funciona así.

### 4.2 Qué se genera

Lo mismo que hoy, con el destino cambiado:

- Nombre: el de la llamada (decisión 4).
- `static` según el detalle D6.
- Un parámetro por argumento, con el nombre sacado del argumento como hoy.
- Tipo devuelto: el que pide el sitio donde se usa la llamada, como hoy.
- Cuerpo: `pass`, o un `return` con un valor de relleno del tipo devuelto.

### 4.3 Tipos vistos desde el destino

Es la parte técnica nueva. Los tipos de los argumentos se conocen escritos para el script que llama; hay que reescribirlos para el script donde va la función.

| Tipo en el script que llama | En el script de destino |
|---|---|
| `int`, `String`, `Node`, una clase global, un enum global | Igual |
| `Shapes.Circle`, una clase del propio destino | `Circle` |
| `Shapes.Kind`, un enum del propio destino | `Kind` |
| `Array[Shapes.Circle]` | `Array[Circle]` |
| Una clase del script que llama | Con el `class_name` del que llama o con la constante que el destino tenga para cargarlo. Si no tiene ninguna, sin tipo |
| Una clase de un tercer script | Con el nombre que lleve hasta ella desde el destino. Si no hay, sin tipo |

El valor de relleno del `return` sigue la misma regla: se escribe con el nombre que el tipo tiene en el destino.

No hace falta mecanismo nuevo. El resolvedor ya traduce un tipo «escrito en un script» a «escrito para otro»; hasta ahora solo se usaba hacia el script que se edita. Medido en el apartado 5 con el código de hoy: funciona en el otro sentido sin tocarlo.

### 4.4 En el editor

1. Al abrir el menú se decide si se ofrece, con el otro script leído como hasta ahora: de su pestaña si tiene cambios sin guardar y del archivo si no.
2. Al elegir la acción se guarda la posición actual en el historial de navegación y se pide a Godot que abra el otro script. Si ya estaba abierto, se cambia a su pestaña y conserva lo que tuviera sin guardar.
3. Se comprueba el detalle D3 y se rehace el análisis con el texto de esa pestaña (detalle D2).
4. La función se inserta en la pestaña como un solo paso de deshacer, con el cuerpo seleccionado y a la vista.
5. El otro script queda con cambios sin guardar. El script de la llamada no se toca.

## 5. Hechos comprobados

Todo el 2026-10-08, con Godot 4.7.2.

### Llamadas a otros scripts en este proyecto

Medido sobre los 49 scripts del proyecto con el código actual, sin cambiar nada. Para cada llamada a una función que ya existe en otro script se calculó el tipo de cada argumento, se reescribió para el script de destino y se comparó con el tipo que la función declara de verdad.

| Medida | Valor |
|---|---|
| Llamadas con un receptor de otro script | 681, a 36 scripts distintos |
| Sobre la clase, que serían `static` | 503 |
| Sobre una instancia | 178 |
| Sobre una clase interna del otro script | 69 |
| Con un nombre que empieza por `_` | 0 |
| Argumentos comparados | 885 |
| Tipo igual al declarado | 840 |
| De ellos, con un nombre distinto en el destino que en el script que llama | 145 |
| Tipo compatible pero no igual | 39 |
| Tipo que no se puede escribir en el destino | 0 |
| Argumento de tipo desconocido | 6 |
| Tipo incompatible con el declarado | 0 |

Los 39 compatibles son 26 en que el argumento es de una clase más concreta que la declarada (`GDSExClassScope` donde la función pide `GDSExScopeBase`) y 13 en que es un diccionario vacío `{}` donde la función declara `Dictionary[String, String]`.

El valor devuelto se pudo comparar en 355 llamadas: 333 iguales y 22 distintas. En 17 el uso solo deja ver `Array` donde la función declara un array más concreto, en 4 el resultado no se usa y sale `void`, y en 1 sale una clase base de la declarada. No es de este plan: es cómo se deduce hoy el tipo devuelto también dentro de un archivo.

### El editor de scripts

En un editor sin ventana, sobre un proyecto temporal:

- Pedir a Godot que abra un script que no estaba abierto es inmediato: en el mismo fotograma es el script activo, su pestaña tiene el texto del archivo y el plugin la identifica con lo que ya tiene (`GDSExOpenScripts`).
- Aplicar un plan de edición a esa pestaña inserta la función y selecciona el cuerpo. La pestaña queda sin guardar, el archivo no cambia y la pestaña de la llamada no se toca.
- Un solo deshacer en la pestaña de destino la deja como estaba y sin cambios pendientes. Rehacer vuelve a poner la función.
- Volver a pedir un script que ya está abierto con cambios sin guardar da la misma pestaña con esos cambios.
- Si el archivo cambia por fuera con su pestaña abierta, la pestaña conserva el texto antiguo, no figura como sin guardar y el script cargado tampoco tiene el texto nuevo. De ahí el detalle D2.
- Un script que no compila se abre igual. Si no estaba ya cargado, cargarlo deja sus errores en la salida de Godot.
- Con cinco pestañas abiertas en desorden, el emparejado de pestañas y scripts del plugin sigue acertando.
- Abrir un archivo para lectura y escritura falla con uno de solo lectura y no cambia la fecha de uno normal. El atributo de solo lectura que ofrece Godot da `false` en los dos casos en macOS. Al final no se usa (detalle D8).

### Nombres con `_`

Godot 4.7.2 tiene 50 avisos de GDScript y ninguno trata de llamar desde fuera a una función que empieza por `_`. Un script que llama a `target._hidden()` y a `Target._hidden_static()` de otro script compila y se ejecuta.

### No comprobado

Nada de esto se ha visto en un editor con ventana: que la pestaña cambie a la vista, que el foco acabe en ella, que la selección quede visible y que «atrás» devuelva a la llamada. Está en la lista del apartado 10.

## 6. Arquitectura

- **`editing/edit_plan.gd`** (C1). El plan guarda la ruta del script al que se aplica. Vacía quiere decir el script que se edita, así que los planes de hoy no cambian.
- **`open_scripts.gd`** (C1 y C2). Sigue siendo el único sitio que habla con el editor de scripts. Gana dos cosas: abrir un script y devolver su editor, comprobando que la pestaña activa es la suya, y decir si un script se puede editar en una pestaña (detalle D7).
- **`code_actions_popup.gd`** (C1). Al ejecutar una acción cuyo plan es para otro script: historial, abrir, rehacer el plan con el texto de la pestaña y aplicarlo allí. La etiqueta del menú añade el nombre del archivo.
- **`actions/action_registry.gd`** (C1). Hoy devuelve las acciones disponibles y descarta sus planes; pasa a devolver también la etiqueta de cada una, que depende del plan.
- **`analysis/script_library.gd`** (C2). Da también las líneas del script leído, que hacen falta para calcular la sangría y el sitio de la inserción.
- **`actions/generate_function_action.gd`** (C2 y C3). El destino puede ser una clase de otro script. La colocación usa las líneas del destino. Los tipos de la firma se reescriben para el destino.
- **`analysis/type_resolver.gd`** (C3). Una función pública para reescribir un tipo de un script para otro. La traducción ya existe y es privada.
- **`tests/run_tests.gd`** (C1 a C4). La sección `=== expected <ruta>`, la compilación de los dos scripts juntos y el contraste masivo.

Reglas del proyecto que aplican: prefijo `GDSEx` en todo tipo nuevo, «function» y no «method», ninguna variable `static` en scripts que `plugin.gd` precargue directamente, y código sin comentarios.

## 7. Pasos

### C1 — Un plan de edición puede ir a otra pestaña

- El plan de edición lleva la ruta de su script.
- `GDSExOpenScripts` abre un script y devuelve su editor, o nada si la pestaña activa no es la suya.
- El menú aplica un plan para otro script siguiendo el apartado 4.4, y pone el nombre del archivo en la etiqueta.
- Runner: sección `=== expected <ruta>`. El plan se aplica a un segundo editor con el texto del otro script y se compara con lo esperado, incluida la selección.

Ninguna acción produce todavía un plan para otro script, así que el comportamiento no cambia.

Verificación: casos con la acción de prueba `apply_plan` que ya existe en el runner, ampliada para dar el script de destino: inserción al final, en una clase interna, en un script vacío, con sangría de espacios en el destino y de tabuladores en el que llama, y con el otro script dado como texto sin guardar. Un caso que comprueba que el script de la llamada no cambia. Un caso del menú con la etiqueta. La parte que habla con el editor no se puede probar en la suite: se comprueba en un editor sin ventana con un plugin de prueba que pide aplicar un plan a un script cerrado, a uno abierto, a uno con cambios sin guardar y a uno cuyo archivo cambió por fuera.

Aviso para esas pasadas, aprendido al preparar este plan: `--import` también carga los plugins del proyecto temporal, y al cerrarse el editor sin ventana guardó en disco la pestaña que el plugin de prueba había modificado. Hay que restaurar los archivos antes de cada pasada, o el resultado engaña.

Hecho el 2026-10-08:

- **El plan de edición lleva su script** (`GDSExEditPlan.script_path`). Vacío quiere decir el script que se edita, así que ningún plan de los que ya había cambia.
- **`GDSExOpenScripts.open(ruta)`** pide a Godot que abra el script y devuelve su editor, o nada si después la pestaña activa no es la suya. Si el script ya está abierto usa el que tiene el editor, sin volver a cargarlo.
- **El menú** (`code_actions_popup.gd`). Una acción cuyo plan es para otro script sigue el apartado 4.4: guarda la posición en el historial, abre el otro script y llama a `apply_in_tab`. Esa función rehace el plan con el texto de la pestaña y lo aplica allí, y no hace nada si la pestaña no admite edición, si el plan rehecho ya no existe o si ahora apunta a otro script.
- **La etiqueta** la compone el registro de acciones a partir del plan: "<acción> in <archivo>". `find_available` devuelve ahora cada acción con su etiqueta.
- **Un plan para otro script nunca se aplica al script que se edita.** `apply_plan`, que es por donde pasan los diálogos, lo descarta (detalle D11).
- **El contexto guarda el texto sin guardar que recibió**, para poder rehacerse con el de la pestaña de destino añadido.
- **`GDSExScriptLibrary.find_lines(ruta)`**, adelantado desde C2: hace falta para calcular el sitio de la inserción en el otro script.
- **Runner.** Sección `=== expected <ruta>` con lo que se espera del otro script, selección incluida; sección `=== tab <ruta>` para dar a su pestaña un texto distinto del que se leyó; cabeceras `offered: yes` (se ofrece aunque al final no cambie nada), `expect_label:` y `tab_read_only: yes`. Tras cada caso se comprueba también que un solo deshacer deja el otro script como estaba y que ningún otro script cambió sin que el caso lo esperase. Los planes se aplican con la misma función que usa el menú.
- **14 casos nuevos** en `tests/cases/other_script_edits/`, 844 en total, con una acción de prueba que añade una función al final de otro script: otro script con funciones, vacío, solo con variables, con una clase interna detrás de sus funciones y con sangría de espacios; pestaña con más y con menos líneas que el archivo; pestaña que ya tiene la función, que no admite edición y que manda la función a un tercer script; script que no se puede leer; el menú con su etiqueta; un plan hecho a mano para una clase interna de otro script, y un plan para otro script que llega por el camino de los diálogos.
- Se rompió el comportamiento a propósito de seis maneras. Una no la detectaba ningún caso, se añadió uno y ahora se detectan las seis.
- **En un editor sin ventana**, con el menú de verdad sobre un proyecto temporal: script cerrado, abierto, abierto con cambios sin guardar y con el archivo cambiado por fuera. En los cuatro el menú nombra el archivo, la pestaña activa pasa a ser la del otro script, la función aparece una vez al final del texto de la pestaña con el cuerpo seleccionado, un deshacer la quita, el archivo no cambia y el script de la llamada tampoco. Con la función ya en la pestaña no se inserta nada, y con un archivo que no existe no se ofrece. Cierra sin errores ni avisos.

Un detalle decidido al implementar: `apply_in_tab` recibe el editor de la pestaña como argumento en lugar de abrirlo ella. Así la suite, que no tiene editor de scripts, ejercita la misma función que el menú con un editor suyo.

### C2 — La acción elige el otro script como destino

- "Generate Function Definition" acepta como destino una clase de otro script cuando ese script se puede editar en una pestaña (detalle D7). Es el punto único que el plan anterior dejó preparado.
- `static` (detalle D6) y colocación al final de la clase con las líneas y la sangría del destino (detalle D4).
- Tipos: en este paso solo los que se escriben igual en todas partes, es decir, básicos, del motor, clases globales y enums globales. Cualquier otro deja el parámetro sin tipo y el valor devuelto como `Variant`, que es correcto aunque pobre. Se completa en C3.
- Los cinco casos `unavailable_on_...` que hoy comprueban que no se ofrece pasan a comprobar lo que se genera, y se añaden los que siguen sin ofrecerse.

Verificación: casos en `tests/cases/generate_function/`, con variaciones:

- Receptor: instancia, constante, clase global, instancia y referencia de una clase interna, clase interna de segundo nivel, variable tipada con el script base, script alcanzado a través de otro.
- Destino: con funciones, solo con variables, vacío, con clases internas detrás de la última función, con cambios sin guardar.
- No se ofrece: la función ya existe, existe solo en el texto sin guardar, es heredada de una clase del motor, el receptor es de una clase del motor, el receptor no se resuelve.
- Sí se ofrece: destino dentro de `res://addons/`, nombre con `_`.

Comprobación nueva en el runner para estos casos: se guardan en una carpeta temporal el script de destino ya modificado y el que llama, y se compila el que llama. Así se comprueba que la llamada encaja con la función generada: nombre, `static` y número de argumentos.

Hecho el 2026-10-08:

- **La acción acepta una clase de otro script.** El receptor puede ser una instancia o una referencia a clase, de la clase raíz o de una interna a cualquier nivel, alcanzada por una constante, por una clase global, por herencia o a través de otro script. La función va a la clase del receptor: si es una instancia de un script que hereda de otro, a ese script y no a su base.
- **`GDSExOpenScripts.can_edit(ruta)`** es el único sitio que decide si un script puede recibir código (detalle D7). No mira carpetas ni permisos (decisión 3 y detalle D8).
- **`static`** cuando la llamada es sobre la clase, también si se llega a ella a través de otro script (`Through.Target.missing()`). Sobre una instancia nunca, aunque la llamada esté dentro de una función estática.
- **Colocación** al final de la clase de destino, con su sangría: tabuladores o espacios según el archivo de destino, no según el que llama.
- **Tipos.** En este paso solo pasan los que se escriben igual en todas partes. El resto deja el parámetro sin tipo y el valor devuelto como `Variant`; un caso lo fija y se cambia en C3.
- **Detalles D13 y D14**, que salieron aquí.
- **Runner.** Los casos con otro script se compilan juntos: el destino ya modificado se guarda en una carpeta temporal y el script que llama se compila contra esa copia. Así un caso falla si la función generada no encaja con la llamada. Cuando el que llama no nombra la ruta del destino (clase global, o destino alcanzado a través de otro script) se compila solo el destino. `compile_check: apart` fuerza eso mismo.
- **La comprobación de ofertas falsas** que ya existía en la suite recorre los scripts del proyecto y ahora ve también los destinos en otros scripts. Sigue en cero: ninguna de las 681 llamadas del proyecto a otros scripts se toma por una función que falta.
- **47 casos nuevos y 5 retirados**, 886 en total. Los cinco `unavailable_on_...` que comprobaban que la acción no se ofrecía tienen ahora su equivalente con lo que se genera. Los nuevos están en `tests/cases/generate_function/other_scripts/`:
  - Receptor: instancia, constante, clase interna (instancia y referencia), clase a dos niveles, valor devuelto por una función del otro script, miembro de una instancia, script alcanzado a través de otro (instancia y constante), clase global (instancia y referencia), clase heredada del script base y script que hereda de otro.
  - Destino: con funciones, solo con variables, vacío, con clases internas detrás de las funciones, clase interna sin miembros, leído del archivo, dentro de `res://addons/`, con sangría de espacios en la clase raíz y en una interna, y con otro valor del ajuste de líneas en blanco.
  - Firma: valor devuelto sacado del uso, parámetros con tipos del motor y colecciones con tipo, parámetro con una clase global, nombre con `_`, llamada desde una función estática.
  - Cursor: segunda de dos llamadas, y llamada usada como argumento de otra.
  - Pestaña distinta de lo leído: con otras líneas, con la función ya escrita, sin la clase, y con una función que ahora devuelve una clase de un tercer script. En las tres últimas no cambia nada.
  - No se ofrece: la función existe, existe solo en el texto sin guardar, la tiene el script base del otro, es del motor, la tiene toda clase de script, es `.new()`, es una variable, el receptor es del motor, no se conoce, su script no se puede leer, es `super`, o la clase está escrita en una línea (en el otro script y en el propio).
- Se rompió el comportamiento a propósito de nueve maneras y se detectan siete. Las otras dos son la misma idea, calcular la colocación como si el destino fuese el script que llama (con su regla o con sus líneas), y no cambian ningún resultado: esos datos solo se usaban para las clases escritas en una línea, que ya no se ofrecen (detalle D14).
- **En un editor sin ventana**, con la acción y el menú de verdad: instancia, clase, clase interna, clase global y un script dentro de `res://addons/`. En los cinco el menú nombra el archivo, la función aparece en su pestaña con la firma esperada y el cuerpo seleccionado, y el archivo no cambia. Tres funciones seguidas en el mismo script caen cada una en su sitio. Una llamada sin receptor sigue yendo al script que se edita. Cierra sin errores ni avisos.

Cambio respecto al plan: no hay archivo `writable_scripts.gd`. Con la decisión 3 las reglas se quedaron en lo que `GDSExOpenScripts` ya sabe contestar.

### C3 — Tipos escritos para el script de destino

- Los tipos de los parámetros y el devuelto se reescriben para la clase de destino (apartado 4.3).
- El valor de relleno del `return` se escribe con el nombre del destino, y `0` para un enum, como ya se hace.

Verificación: casos con variaciones de cada fila de la tabla del apartado 4.3, y además: clase interna del destino pasada a una función de otra clase interna del mismo destino, enum del destino, colecciones con tipo, una clase del script que llama cuando el destino lo carga (los dos scripts que se cargan mutuamente) y cuando no, un tercer script que el destino carga con otro nombre de constante, una clase global, una constante tapada por una clase global, `self` como argumento, y el valor devuelto en cada una de esas formas. La compilación de los dos scripts juntos del paso C2 cubre aquí también los tipos.

### C4 — Pruebas masivas, editor y documentación

- **Contraste con lo que ya está escrito, en la suite.** Es la medida del apartado 5 convertida en prueba. Para cada llamada del proyecto a una función que existe en otro script, se pregunta a la acción qué generaría si no existiera y se compara con la declaración real: mismo `static`, mismo número de parámetros y, en cada uno, el mismo tipo, uno compatible o ninguno. Un tipo incompatible es un fallo. Además se añade la función generada al texto del destino y se compila. En la suite, una muestra; completa, lanzada a mano.
- El addon GUT como código ajeno, lanzado a mano: las mismas llamadas, con clases globales y casi sin tipos.
- Editor sin ventana con el menú de verdad: ofrecer, ejecutar, deshacer, y repetir con el destino cerrado, abierto y sin guardar.
- Tiempo de abrir el menú, con el cursor sobre una llamada a otro script y fuera de ella.
- README: la fila de la acción, y la frase que hoy dice que el plugin nunca escribe en otro script. CHANGELOG. El apartado de límites de `PRELOAD_TYPES_PLAN.md`.
- La lista del apartado 10, para que el usuario la pase en un editor con ventana.

En cada paso se rompe el comportamiento a propósito de varias maneras y se comprueba que algún caso lo detecta, como en el plan anterior.

## 8. Qué queda fuera

- `super.missing()`: crear la función en la clase base. Encaja en el mismo mecanismo y queda como candidata.
- Una función pasada como referencia a otro objeto: `button.pressed.connect(controller.on_pressed)`.
- Variables y señales en otro script: `other.missing_value = 1`, `other.missing_signal.emit()`.
- Autoloads sin `class_name`, y scripts a los que se llega con `load()` o `get_script()`: el receptor no se resuelve.
- Crear el script si no existe, y mover funciones de un script a otro.
- Scripts que no son `.gd`, los que van dentro de una escena y los que están fuera de `res://`.
- Godot configurado con un editor externo.
- Añadir al otro script las constantes `preload` que harían falta para escribir un tipo (detalle D5).

## 9. Riesgos

- **Escribir en el sitio equivocado.** El análisis y la pestaña podrían no tener el mismo texto. Detalles D2 y D3, y la pasada en el editor sin ventana con un archivo cambiado por fuera.
- **Escribir en un addon ajeno.** Lo permite la decisión 3. Lo que se escriba ahí se pierde al actualizar el addon; va dicho en el README.
- **Un tipo que no compila en el destino.** El nombre vale en el script que llama y no en el otro. Lo cubren los casos de C3, la compilación de los dos scripts juntos y el contraste de C4. Con el código de hoy la medida da 0 tipos no escribibles y 0 incompatibles en 885 argumentos.
- **El menú y el cambio de pestaña.** La acción se ejecuta mientras se cierra un menú y cambia de pestaña en ese momento. En un editor sin ventana no se ve si el foco acaba donde debe. Si no, la aplicación se retrasa un fotograma; es un cambio pequeño y localizado en el menú.
- **La llamada sigue en rojo.** No es un fallo, pero lo parece: hasta que no se guarda la otra pestaña, Godot no ve la función (decisión 2). Va explicado en el README.
- **Ruido en la salida.** Abrir un script que no compila y que no estaba cargado deja sus errores en la salida de Godot. No se puede evitar desde el plugin.
- **Se toca el menú y el registro de acciones, que usan todas las acciones.** Red: los 830 casos, de los que solo deben cambiar los cinco que hoy comprueban que la acción no se ofrece, y los casos del menú.

## 10. Para comprobar con ventana

Lo que un editor sin ventana no enseña. Para pasar al cerrar C4:

1. Con el otro script cerrado: la acción aparece con el nombre del archivo, se abre su pestaña, la función está al final y el cuerpo queda seleccionado y a la vista.
2. Con el otro script ya abierto en otra pestaña, y con cambios sin guardar: lo mismo, sin perder esos cambios.
3. Escribir justo después sustituye el cuerpo seleccionado: el foco está en la pestaña nueva.
4. Deshacer en esa pestaña quita la función.
5. «Atrás» en el editor de scripts devuelve a la línea de la llamada.
6. Lo mismo desde el menú contextual y desde el atajo.
7. La llamada deja de estar marcada como error al guardar la otra pestaña.
