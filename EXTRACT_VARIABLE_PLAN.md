# Plan — Extract Variable...

Una acción nueva con diálogo. Con el cursor sobre un valor escrito en el código (`120.0`, `true`, `Enemy.new()`, `shapes.make()`), le da un nombre: declara una variable con ese valor y deja el nombre donde estaba el valor. El diálogo pide el nombre, dónde va a vivir la variable y de qué clase es.

No se parece a "Generate Local Variable" ni a "Generate Class Variable". Aquellas parten de un nombre que no existe y lo declaran. Esta parte de un valor que sí existe y le pone nombre.

| Paso | Contenido | Estado |
|---|---|---|
| V1 | El valor bajo el cursor, su tipo y el nombre que se propone | Hecha |
| V2 | De qué depende el valor, adónde puede ir y con qué opciones | Hecha |
| V3 | La edición: declaración, sustitución y comprobación del nombre | Hecha |
| V4 | El diálogo y la acción en el menú | Hecha |
| V5 | Pruebas masivas, rendimiento y documentación | Hecha |

Cada paso termina con la suite en verde y una pasada de `--headless --editor --quit` sin errores ni avisos, y se cierra con un commit en la rama `generate-outside`.

El plan está terminado. Lo que se midió al cerrarlo está en el apartado 11, y lo que queda por mirar con ventana, en el 10.

## 1. Qué hace

```gdscript
extends Node


class Spawner:
	var _enemies: Array[Enemy] = []

	func spawn_wave(origin: Vector2, count: int) -> void:
		for index in count:
			var enemy: Enemy = Enemy.new()
			enemy.speed = 120.0
			enemy.position = origin + Vector2(0, 16) * index
			_enemies.append(enemy)
```

Con el cursor en `120.0`, "Extract Variable..." abre el diálogo con el nombre `speed` propuesto. Hay cuatro sitios donde puede vivir la variable, y donde estaba el valor queda su nombre:

| Sitio | Dónde queda la declaración | Declaración |
|---|---|---|
| Block | Dentro del `for`, en la línea de antes | `var speed: float = 120.0` |
| Function | En `spawn_wave`, antes del `for` | `var speed: float = 120.0` |
| Class | Con las variables de `Spawner` | `var _speed: float = 120.0` |
| Script | Con las constantes del script, fuera de `Spawner` | `const SPEED: float = 120.0` |

En cualquiera de ellos se puede pedir además una constante, y en "Class" una estática.

No todos los valores pueden ir a todos los sitios. `Vector2(0, 16) * index` lee la variable del `for`, así que no puede salir del bucle. `origin` es un parámetro, así que lo que lo lee no puede salir de la función. El diálogo apaga los sitios que no valen y dice por qué.

El diálogo, con el estilo de los otros dos:

```
Extract Variable
Name     [ speed                                   ]
Where    [ Block ] [ Function ] [ Class ] [ Script ]
Options  [ Constant ] [ Static ] [ Private ] [ On ready ]
Result
   (el código con la declaración nueva y la línea cambiada, marcadas)
• Variable name is valid.
```

"Where" y "Options" son botones de dos posiciones, como los filtros de "Generate Custom Init Definition...". Los que no se pueden usar salen apagados y al pasar el ratón dicen por qué.

## 2. Decisiones

### Acordadas

Las tomó el usuario el 2026-10-08.

1. **Qué cuenta como valor en esta versión.** Tres cosas: un literal (número, texto, `true`, `false`), una llamada con su cadena completa (`Enemy.new()`, `shapes.make()`, `Vector2(0, 16)`) y un acceso a un nodo (`$Sprite2D`, `%HealthBar`). Una operación (`a + b`) y la lectura de un miembro (`player.health`, `Color.RED`) quedan para después: en las operaciones, sustituir un trozo que no es una pieza completa cambia el resultado sin dar error (apartado 9).
2. **Una opción que no se puede usar** se apaga y dice el motivo; no se esconde. Era la pregunta del usuario: qué pasa si se pide una variable de clase y el valor usa cosas que solo existen dentro de la función. No es un caso raro: en este proyecto, el 85 % de las llamadas con valor leen una variable local o un parámetro (apartado 5).
3. **Una opción que compila pero cambia cuándo se calcula el valor** se permite, con un aviso en el diálogo. Una variable de clase con `Enemy.new()` crea un solo `Enemy` por objeto, al crearlo, en vez de uno cada vez que se ejecuta la función. Es justo el motivo por el que se elige una variable de clase.
4. **El orden entre llamadas de la misma línea** se puede cambiar, con un aviso. En `show(first(), second())`, sacar `second()` a la línea de antes hace que se ejecute antes que `first()`.
5. **`@onready`** es una opción de las variables de clase en los scripts que heredan de `Node`. Sin él, GDScript no deja usar `$Sprite2D` ni `get_node()` en el valor de una variable de clase (apartado 5). `@export` no entra en esta versión.
6. **Solo el valor elegido.** Esta versión cambia un único valor, el del cursor. Cambiar de paso todos los valores iguales queda para después.

Doy por hecho que entra en la 0.4.0, junto con las funciones en otros scripts.

### Dónde vive la variable

El borrador tenía dos sitios, local y de clase. El usuario propuso cuatro: el mismo bloque donde está el valor, la función, la clase y la clase raíz del script. Quedaron así, confirmados por el usuario el 2026-10-08:

7. **Los cuatro sitios y sus nombres.** "Block" es la línea de antes, dentro del mismo bloque; es lo que el usuario llama *scope* y lo que el borrador llamaba local. "Function" es el cuerpo de la función, fuera de los bloques; lo que el usuario llama *local*. "Class" es la clase de la función y "Script" la clase raíz.
8. **Solo se enseñan los sitios que son distintos.** Es la forma de manejar cuatro opciones: casi nunca hay cuatro. "Block" solo aparece si el valor está dentro de un `if`, un `for`, un `while`, un `match` o una lambda; si no, la línea de antes ya es el cuerpo de la función y solo sale "Function". "Script" solo aparece si la función está en una clase interna; si no, la clase ya es la raíz. En el caso más corriente quedan dos botones, "Function" y "Class". No contradice la decisión 2: allí la opción existe y no se puede usar; aquí no hay un segundo sitio que ofrecer.
9. **"Function" no es la primera línea de la función.** Va justo antes de la sentencia del cuerpo de la función que contiene el valor: antes del `for`, no arriba del todo. En la primera línea no podría leer ninguna variable declarada antes en la función, solo los parámetros, y quedaría lejos de donde se usa.
10. **"Script" solo admite una constante.** No es una elección: una clase interna puede leer por su nombre las constantes del script, pero no sus variables, ni las estáticas (apartado 5). Al elegir "Script", "Constant" se marca sola.
11. **Un sitio que cambia cuántas veces se calcula el valor se permite, con aviso.** Sustituye a lo que el borrador proponía para la variable local, que era no ofrecerla. Llevar un valor de dentro de un bucle a "Function" hace que se calcule una vez; eso es lo que se busca al elegirlo. Y hay casos en que hasta el sitio más cercano lo cambia: el valor está en la condición de un `while` o de un `elif`, detrás de un `and` o un `or`, o en un bloque escrito en una línea. Con la regla del borrador, `while index < items.size():` no dejaría sacar `items.size()` de ninguna manera. Queda una regla única para todo el diálogo: **apagado es que no compilaría; con aviso es que compila pero se calcula en otro momento.** Un literal o una constante nunca llevan aviso.

## 3. Detalles decididos al redactar

No los ha fijado el usuario; son la forma concreta que propongo y se pueden cambiar sin rehacer el plan.

- **D1. Cursor o selección.** Sin selección, el valor es el más pequeño que contiene al cursor: el literal, o la llamada cuyo nombre está bajo el cursor con todo lo que lleva delante (`shapes.make()` y no `make()`). Si el cursor está en lo que va delante de una llamada (`Enemy` en `Enemy.new()`), es la primera llamada de esa cadena. Con selección, lo seleccionado tiene que ser exactamente un valor de los de la decisión 1, o algo entre paréntesis, corchetes o llaves; si no, la acción no se ofrece.
- **D2. Dos ejes y no una lista.** El diálogo separa dónde vive la variable (los sitios de la decisión 7) de sus opciones (constante, estática, privada, `@onready`). Es como lo describe el usuario y evita una lista con todas las combinaciones. Constante y estática se excluyen, porque una constante ya es de la clase; `@onready` excluye a las dos.
- **D3. El tipo se escribe siempre que se conoce**, con la forma `name: Type`, también en las constantes. Si no se conoce, la declaración va sin tipo.
- **D4. Una llamada que no devuelve nada no es un valor.** Tampoco la llamada que va justo detrás de `await`. No se ofrece.
- **D5. Cuando el valor es toda la línea** (`Enemy.new()` sola, sin usar el resultado), la línea se convierte en la declaración. "Function" (si es otro sitio), "Class" y "Script" se apagan: no quedaría nada en la línea.
- **D6. Cuando el valor ya es todo el valor de una variable local** (`var speed: float = 120.0`), "Block" se apaga. Los demás sitios sí tienen sentido. Este detalle y el D5 son las dos excepciones a la regla de la decisión 11: lo que apagan compilaría, pero no serviría de nada.
- **D7. Fuera de una función solo hay "Class" y "Script".** El valor de una variable de clase, el valor por defecto de un parámetro y el argumento de una anotación no tienen línea de antes. En una anotación y en el valor de un enum solo vale una constante.
- **D8. Dónde va la declaración en "Block" y en "Function".** En "Block", en la línea anterior a la sentencia que contiene el valor, con su sangría; si la sentencia ocupa varias líneas, antes de la primera. En "Function", lo mismo pero respecto a la sentencia del cuerpo de la función que lo contiene todo (decisión 9). Si el valor está en una lambda de varias líneas, "Block" es dentro de la lambda y "Function" es la función que la contiene.
- **D9. Dónde va la declaración en "Class" y en "Script":** detrás del último miembro de su categoría, según el orden de "Reorder Class Members". Una excepción: si el valor lee otras variables de la clase, nunca antes de la última que lee. Comprobado (apartado 5): una variable de clase que lee otra declarada más abajo compila y toma el valor por defecto de la otra, sin ningún aviso.
- **D10. El nombre propuesto** sale, por este orden, de la llamada (`Enemy.new()` da `enemy`, `get_health()` da `health`, `$Sprite2D` da `sprite_2d`), del sitio donde se usa el valor (lo que se asigna, o el parámetro al que se pasa) y, si no, de `value`. Una constante se propone en mayúsculas y una variable de clase privada con `_`. Al cambiar de opción el nombre se rehace, salvo que el usuario ya lo haya escrito.
- **D11. Por defecto:** el sitio más cercano de los que se pueden usar, sin opciones. Las variables de clase empiezan como privadas y las constantes como públicas.
- **D12. La lista de funciones que valen en una constante sale del volcado de la API**, como el resto de `builtin_types.gd`, y no se escribe a mano. Comprobado (apartado 5): son exactamente las de la categoría `math`.
- **D13. Ante la duda, no es constante.** Si el plugin no sabe si GDScript aceptará un valor en una constante, apaga la opción. Lo contrario daría código que no compila.
- **D14. La acción se ofrece siempre que haya un valor bajo el cursor** y al menos una opción posible. Aparecerá a menudo en el menú; es lo esperable en una acción de este tipo.
- **D15. Entre el bloque y la función no hay sitios intermedios.** Con tres bloques anidados habría tres sitios locales posibles; se ofrecen los dos extremos. Lo mismo con las clases: de una clase a dos niveles de profundidad se ofrece la suya y la raíz.

## 4. Comportamiento

### 4.1 De qué depende un valor

Para saber adónde puede ir, el plugin mira qué lee el valor:

| Lee | Ejemplo |
|---|---|
| Nada del script | `120.0`, `Vector2(0, 16)`, `Enemy.new()` |
| Constantes, enums, funciones y variables estáticas | `Shapes.make()`, `MAX_SPEED * 2` |
| Miembros del objeto: variables, funciones no estáticas, `self` y lo heredado | `get_health()`, `_items.size()` |
| El árbol de escena: `$`, `%` y `get_node`, que es lo que GDScript rechaza fuera de `@onready` | `$Sprite2D`, `get_node("HUD")` |
| Parámetros de la función, o variables locales declaradas en su cuerpo | `origin.distance_to(target)` |
| Algo declarado dentro de un bloque: la variable de un `for`, una local del bloque, un parámetro de una lambda | `items[index]` |

Y aparte, si es una constante para GDScript: literales, operaciones, otras constantes y enums, `preload`, constructores de tipos básicos menos los `Packed...Array`, y las funciones matemáticas, todo ello con argumentos que también lo sean.

### 4.2 Los sitios

| Sitio | Qué es | Cuándo aparece | Cuándo se apaga |
|---|---|---|---|
| Block | La línea de antes, en el mismo bloque | El valor está dentro de un bloque o de una lambda de varias líneas | El valor ya es todo el valor de una variable local |
| Function | El cuerpo de la función, antes de la sentencia que contiene el valor | El valor está en una función | El valor lee algo declarado dentro del bloque del que sale |
| Class | Los miembros de la clase de la función | Siempre | El valor lee una local o un parámetro, contiene un `await` o es toda la línea |
| Script | Las constantes de la clase raíz | La función está en una clase interna | El valor no es una constante para GDScript, o lee algo de la clase interna |

### 4.3 Las opciones

| Opción | En qué sitios | Cuándo se apaga |
|---|---|---|
| Constant | En todos. En "Script" va siempre marcada | El valor no es una constante para GDScript |
| Static | En "Class" | El valor lee miembros del objeto |
| Private | En "Class" y en "Script" | Nunca |
| On ready | En "Class" | El script no hereda de `Node`, o está marcada "Constant" o "Static" |

- Si el valor usa el árbol de escena y se elige "Class", "On ready" se marca sola y no se puede quitar.
- Dentro de una función estática, "Class" obliga a elegir "Constant" o "Static": la función no podría leer otra cosa.

### 4.4 Motivos y avisos, como se leen en el diálogo

Cada botón apagado lleva su motivo al pasar el ratón, con el nombre de lo que estorba:

| Botón apagado | Motivo |
|---|---|
| Function | `The value reads 'index', which only exists inside the loop.` |
| Class | `The value reads 'origin', which only exists inside this function.` |
| Class | `The value is the whole line.` |
| Script | `The value reads 'INNER_LIMIT', which belongs to the class Spawner.` |
| Constant | `A constant cannot hold the result of 'Enemy.new()'.` |
| Static | `A static variable cannot read 'get_health', which belongs to the object.` |
| On ready | `Only scripts that extend Node have @onready.` |

Los avisos van en la franja de abajo, donde hoy va el aviso del nombre. Solo los lleva un valor que no es constante:

| Sitio elegido | Cuándo | Aviso |
|---|---|---|
| Block o Function | El valor está en la condición de un `while` o de un `elif`, detrás de un `and` o un `or`, en una rama de `a if c else b`, o en un bloque o una lambda de una línea | `Here the value runs only sometimes, or more than once. The variable will compute it once, before this line.` |
| Block o Function | Otra llamada de la misma línea iba antes | `'second()' will now run before 'first()'.` |
| Function | Sale de un `for` o de un `while` | `The value will be computed once, before the loop.` |
| Function | Sale de un `if` o de un `match` | `The value will be computed even when that branch does not run.` |
| Function | Sale de una lambda | `The value will be computed when the function runs, not when the lambda is called.` |
| Class | Siempre | `The value will be computed once, when the object is created.` |
| Class, con Static | Siempre | `The value will be computed once, when the script is loaded.` |

### 4.5 El nombre

Se comprueba mientras se escribe, como en los otros diálogos. Comprobado en el apartado 5 qué rechaza GDScript:

| Nombre | Block y Function | Class y Script |
|---|---|---|
| Vacío, palabra reservada o no es un identificador | Error | Error |
| Igual que un parámetro o que una variable local que se ve desde esa línea | Error | Error: ahí el nombre sería la local |
| Igual que una local que se declara más abajo, en el bloque donde queda la variable o en uno de dentro | Error | Sin problema |
| Igual que una local de otro bloque que no se ve desde esa línea | Sin problema | Sin problema |
| Igual que un miembro de la clase | Aviso: lo tapa | Error |
| Igual que una propiedad de la clase del motor (`position`) | Aviso: la tapa | Error |
| Igual que una función de la clase del motor (`get_child_count`) | Sin problema | Error |
| Igual que una clase global | Aviso | Error |
| Igual que un tipo básico del motor (`int`, `float`, `AABB`) | Error | Error |
| `script` | Aviso: tapa la propiedad | Error |
| Igual que el parámetro de la lambda de una línea donde está el valor | Error | Error |
| Igual que un miembro de una clase del mismo script que hereda de esta | Sin problema | Error |

### 4.6 Qué se ve

Una sola vista previa, "Result", con el código ya cambiado. La declaración nueva y la línea donde estaba el valor van marcadas con el color que usa "Extract Function..." para la llamada. Si las dos quedan lejos, la vista se centra en la declaración.

## 5. Hechos comprobados

Todo el 2026-10-08, con Godot 4.7.2, compilando los ejemplos uno a uno.

### Qué acepta GDScript en una constante

| Valor | En una constante |
|---|---|
| Literales, `-1`, `1 + 2`, `1 << 2`, `"a" + "b"`, `"%d" % 1`, `1 if true else 2`, `1 == 1`, `"a" in ["a"]` | Sí |
| `[1, 2, 3]`, `{"a": 1}`, `[1, 2][0]`, `[Vector2(1, 2)]` | Sí |
| Otras constantes, aunque se declaren más abajo; valores de un enum y el enum entero | Sí |
| `preload(...)`, `PI`, `INF`, `KEY_A`, `Node.NOTIFICATION_READY`, `Vector2.ZERO`, `Color.RED` | Sí |
| Constructores de tipos básicos: `Vector2(1, 2)`, `Color("red")`, `Rect2(0, 0, 1, 1)`, `StringName("a")`, `Array()`, `Dictionary()` | Sí, los 27 |
| `Vector2(1, 2).x`, `Vector2(1, 2) * 2` | Sí |
| Las 78 funciones globales de la categoría `math`: `sin`, `max`, `clamp`, `lerp`, `deg_to_rad`, `floor`, `snapped`... | Sí, todas |
| Las 6 de la categoría `random` y las 19 de `general` que devuelven algo: `randi`, `str`, `typeof`, `hash`, `is_instance_valid`... | No, ninguna |
| Los 10 constructores `Packed...Array`, con o sin argumentos | No |
| Cualquier función de un valor: `"abc".length()`, `[1, 2].size()`, `Vector2(1, 2).length()`, `Mode.keys()` | No |
| `Node.new()`, una función estática del script, `OS.get_name()`, `load(...)`, `len(...)`, `range(...)` | No |
| Cualquier cosa que lea una variable del objeto: `member`, `Vector2(member, 1)`, `[member]` | No |

Una constante dentro de una función acepta y rechaza exactamente lo mismo que una de clase, y no puede leer ni parámetros ni variables locales.

### Qué acepta en una variable de clase

| Valor | Variable de clase | Estática |
|---|---|---|
| Una función del objeto, `self`, otra variable del objeto | Compila | No compila |
| Una función estática, una constante, `Node.new()` | Compila | Compila |
| `$X` o `get_node("X")` | No compila sin `@onready` | No compila |
| El nombre de un parámetro de una función | No compila | No compila |

- `@onready` no compila en un script que no hereda de `Node`.
- `get_parent()`, `get_tree()` y `find_child()` sí compilan en una variable de clase, aunque en ese momento el nodo aún no está en el árbol. Para el plugin son miembros del objeto, con el aviso de la decisión 3.
- GDScript solo rechaza el acceso al árbol cuando es el valor entero: `$X`, `%X` o `get_node("X")`. `$X.position` o `str($X)` compilan, pero fallan al ejecutarse porque el nodo aún no existe. El plugin pide `@onready` en los dos casos.
- Sacar a una variable la llamada que va tras `await` no compila: `var pending = wait()` seguido de `await pending` da error. De ahí el detalle D4.
- El orden importa y GDScript no avisa. Con `var reads_after: int = after + 1` escrita antes que `var after: int = 5`, `reads_after` vale 1 y no 6.
- El valor se calcula antes de `_init`: una variable que lee otra a la que `_init` da valor ve el valor de antes.
- Se calcula una vez por objeto: dos objetos de la misma clase llaman dos veces a la función.
- `self` en el valor de una variable estática compila, aunque en una función estática no. Al ejecutarse vale `null`: `static var kept = self` deja `null` y `Callable(self, "run")` deja un `Callable` que no es válido. El plugin apaga "Static" igual. Es la tercera excepción a "apagado es que no compilaría", con los detalles D5 y D6.
- `self` no vale en una constante: `const KEPT = Callable(self, "run")` no compila, aunque `Callable(...)` sea uno de los 27 constructores.
- El `get` y el `set` de una variable estática son código estático: no pueden leer una variable del objeto.
- `new()` sin nada delante compila en una variable de clase y en una estática. Es una función estática de la clase.
- La ruta de un `preload` tiene que ser un texto constante. Vale una constante, de la clase o de la función; una variable no.

### Nombres

- Una variable local puede llamarse como una variable o una constante de la clase, como una propiedad del motor o como una clase global.
- No puede llamarse como un parámetro, ni como otra local del mismo bloque, ni como una local de fuera que ya esté declarada. Sí como la de un bloque que ya terminó o la de un bloque vecino.
- Usar una variable local antes de su declaración no compila.
- Una variable o una constante de clase no puede llamarse como otra variable o función de la clase, como una propiedad de la clase del motor ni como una clase global.
- Una variable de clase con el nombre de una función del motor compila mientras el script no llame a esa función. En cuanto la llama, no compila. Se comprobó en V5, al fallar la prueba masiva: el plan la daba por buena y pasa a ser un error.
- Una variable local con el nombre de una función, propia o del motor, compila y la función se puede seguir llamando.
- Lo mismo con las funciones globales: una variable, local o de clase, puede llamarse `range`, `print`, `str`, `load` o `abs`, y la función se sigue pudiendo llamar.
- Ningún nombre puede ser el de un tipo básico (`int`, `float`, `AABB`, `RID`). En una variable o una constante de clase no compila nunca. En una local compila mientras la función no vuelva a escribir ese tipo: `var int = 1` seguido de `var other: int = 2` no compila.
- `script` no puede ser un miembro de la clase. Es una propiedad de `Object` que `ClassDB` no da en su lista de propiedades, así que hay que nombrarla aparte. Como variable local, compila.
- Un miembro no puede llamarse como otro que ya tenga una clase que hereda de esta. El error sale en la clase hija, no en la que recibe el miembro.
- Dentro de una lambda, su parámetro tapa a cualquier variable de fuera que se llame igual.
- `ClassDB.class_get_property_list` devuelve también los títulos de los grupos del inspector. Quince de esos títulos son además el nombre de una clase o de un singleton: `Input` en `Control` y en todos los cuerpos de física, `Theme` en `Control` y `Window`, `Texture` y `Material` en `CanvasItem`, `Time` en los nodos de partículas. No son miembros.

### Llamadas que no dejan nada que guardar

- Una función con un `await` dentro solo se puede llamar sin `await` cuando no se usa lo que devuelve. `waits()` sola compila; `var kept = waits()` no, tenga o no tipo de retorno. Con un receptor sin tipo sí compila, porque GDScript no sabe qué función es.
- Una función propia sin tipo de retorno devuelve `Variant`, y su resultado se puede guardar aunque no tenga ningún `return`.
- Salvo que reescriba una función del motor que no devuelve nada, como `_ready` o `_update_layout`. Entonces vale la firma del motor y `var kept = _ready()` no compila.
- `super.add_child(node)` no devuelve nada, igual que `add_child(node)`.
- `for index in range(3)` da a `index` el tipo `int`. Con `var numbers: Array = range(3)` y `for index in numbers`, `index` pasa a ser `Variant`, y un `var next := index + 1` de más abajo deja de compilar.
- `get():` y `set(value):`, con paréntesis, son formas válidas de escribir el `get` y el `set` de una propiedad. No son llamadas.

### Compilar ejecuta código

- `GDScript.reload()` ejecuta los valores de las variables estáticas del script que compila. Con `reload(true)` también.
- No los ejecuta si el script no compila.
- Si uno de ellos falla al ejecutarse, los que van detrás en la misma clase no se ejecutan.

### Sitios especiales

- El valor por defecto de un parámetro puede leer constantes, variables y funciones del objeto. En una función estática, solo lo estático.
- El argumento de una anotación (`@export_range(0, MAX)`) y el valor de un enum aceptan una constante y no una variable estática.

### Bloques y clases internas

- Una variable o una constante declarada antes de un `for`, de un `if` o de una lambda se lee desde dentro sin problema.
- Una clase interna lee por su nombre las constantes del script, y una clase a dos niveles lee las de las dos que la envuelven.
- Una clase interna no puede leer por su nombre las variables del script, ni sus variables estáticas, ni sus funciones, estáticas o no. De ahí la decisión 10.
- Una constante del script sí puede leer una constante de una clase interna escribiendo `Inner.NAME`. El plan no lo usa: si el valor lee algo de la clase interna, "Script" se apaga.

### Cuántos valores hay y qué leen

Medido con el código actual, dentro de las funciones.

| Medida | Este proyecto (49 scripts) | GUT (86 scripts) |
|---|---|---|
| Números escritos en el código | 990, de ellos 58 que no son 0 ni 1 | 769, de ellos 136 |
| Textos | 778 | 2.304 |
| `true` y `false` | 333 | 404 |
| Llamadas | 4.815 | 5.437 |
| Llamadas con tipo conocido | 3.924 | 2.011 |
| Leen variables locales o parámetros | 4.088 (85 %) | 3.576 (66 %) |
| Leen miembros del objeto | 232 | 1.507 |
| Leen solo constantes o miembros estáticos | 321 | 82 |
| No leen nada del script | 174 | 272 |
| `.new()` | 207, de ellos 8 leen locales y 1 miembros del objeto | 158, de ellos 56 y 21 |
| En la condición de un `while` o un `elif` | 134 | 7 |
| Detrás de un `and`, un `or` o dentro de un valor condicional | 457 | 164 |

Las llamadas sin tipo conocido incluyen las que no devuelven nada; la medida no las separa.

Lo que sale de aquí:

- La mayoría de las llamadas no pueden salir de su función. Apagar "Class" será lo normal, así que el motivo tiene que verse bien (decisión 2).
- Casi todos los `.new()` de este proyecto podrían ir a "Class": 198 de 207.
- Una de cada ocho llamadas está en un sitio donde hasta la línea de antes cambia cuándo se calcula (decisión 11).

La medida no separa lo que lee parámetros de lo que lee variables de un bloque, así que no dice cuántas llamadas podrían ir de "Block" a "Function". Se mide en V2.

## 6. Arquitectura

- **`analysis/value_finder.gd`** (nuevo, V1). Del cursor o la selección al valor: su texto, dónde empieza y acaba dentro de la sentencia, y de qué clase es (literal, llamada, acceso a nodo).
- **`analysis/value_names.gd`** (nuevo, V1). El nombre propuesto y sus variantes: mayúsculas para una constante, `_` para una privada.
- **`analysis/value_dependencies.gd`** (nuevo, V2). Qué lee el valor y si es una constante para GDScript. Se apoya en lo que ya hay: `variable_usage.gd` sabe qué nombres de una función son locales, y el resolvedor sabe si un nombre es un miembro, de quién y si es estático.
- **`analysis/builtin_types.gd` y `tools/generate_builtin_types.gd`** (V2). La lista de funciones matemáticas, generada del volcado de la API.
- **`actions/extract_variable.gd`** (nuevo, V2 y V3). Qué opciones admite el valor, con el motivo de cada una que no; y el plan de edición para una opción y un nombre dados. Tiene la misma forma que `extract_function.gd`: funciones estáticas que usan tanto la acción como el diálogo.
- **`actions/variable_name_check.gd`** (nuevo, V3). Las reglas del apartado 4.5, con los mismos tres niveles que `function_name_check.gd`.
- **`editing/placement.gd`** (V3). Colocar una variable de clase según su categoría (detalle D9). Hoy solo sabe ponerla detrás de la última variable.
- **`extract_variable_dialog.gd`** (nuevo, V4). Hereda de `function_name_dialog.gd`, como los otros dos: fila del nombre, vista previa con los colores del editor y franja de avisos.
- **`actions/extract_variable_action.gd`** (nuevo, V4) y su alta en `action_registry.gd`.
- **`tests/run_tests.gd`** (V1 a V5). Acciones `describe_value` y `describe_variable_kinds`, cabecera `options:` para elegir opción y nombre, casos de comportamiento y la comprobación masiva.

Reglas del proyecto que aplican: prefijo `GDSEx` en todo tipo nuevo, «function» y no «method», ninguna variable `static` en scripts que `plugin.gd` precargue directamente, y código sin comentarios.

## 7. Pasos

### V1 — El valor bajo el cursor

- Encontrar el valor con cursor y con selección (detalle D1), para las tres clases de valor de la decisión 1.
- Su tipo, con el resolvedor que ya existe.
- El nombre propuesto (detalle D10).

No cambia nada en el menú.

Verificación: una acción del runner, `describe_value`, enseña el valor, su tipo y el nombre. Casos con variaciones: cada clase de literal, con el cursor al principio, en medio y al final; llamadas simples, encadenadas, anidadas y de varias líneas; el cursor en el nombre, en lo que va delante y dentro de los argumentos; selección exacta, con espacios de más, a medias y de algo que no es un valor; textos que contienen paréntesis o comillas; y lo que no es un valor: el nombre de una declaración, el lado izquierdo de una asignación, una anotación, una llamada sin resultado y la que va tras `await`.

Hecho el 2026-10-08:

- **`analysis/value_finder.gd`** (`GDSExValueFinder`). Del cursor o la selección al valor: literal, llamada con su cadena, acceso a un nodo o, solo con selección, algo entre paréntesis, corchetes o llaves. Da también el texto original del valor, que hace falta porque el análisis trabaja con los textos tapados.
- **`analysis/value_names.gd`** (`GDSExValueNames`). El nombre propuesto, y cómo se escribe según sea constante o privado.
- **`actions/extract_variable.gd`** (`GDSExExtractVariable`), de momento solo con `analyze`: el valor, su tipo y su nombre.
- **Runner:** `action: describe_value`.
- **110 casos** en `tests/cases/extract_variable_value/`, 1.022 en total. Cubren cada clase de literal con el cursor al principio, en medio y al final; números en hexadecimal, en binario, con separadores y con exponente; textos con comillas simples, triples, de varias líneas y con paréntesis dentro; llamadas simples, encadenadas, anidadas y de varias líneas, con el cursor en el nombre, delante, entre dos llamadas y detrás; nodos por nombre, por ruta, por nombre único y entre comillas; selecciones exactas, con espacios, a medias y de cosas que no son un valor; de dónde sale el nombre; y lo que no es un valor.
- Se rompió el comportamiento a propósito de dieciséis maneras. Una no la detectaba ningún caso, se añadió uno y ahora se detectan las dieciséis.

Detalles decididos al implementar:

- **Un número negativo se lleva su signo** cuando el `-` es un signo y no una resta: en `Vector2(0, -16)` el valor es `-16`, y en `first - 16` es `16`.
- **Un nodo gana a la llamada que lleva detrás.** En `$Timer.start()`, con el cursor en `Timer` el valor es `$Timer`, que es lo que se suele querer guardar. Con el cursor en `start` es la llamada entera.
- **La llamada tras `await` sí es un valor si la cadena sigue.** En `await get_tree().process_frame` se puede sacar `get_tree()`. Lo que no se puede es sacar lo que se espera.
- **Una llamada que contiene una lambda de varias líneas no es un valor.** Habría que mover también el cuerpo de la lambda. Con la lambda en una línea, sí.
- **`null`, un nombre suelto, `self` y la lectura de un miembro no son valores.** Tampoco nada en una línea de `signal`, `class`, `class_name` o `extends`.
- **Lo que carga `preload` no lleva tipo**, porque el resolvedor lo da como `Resource` y GDScript sabe más que eso. Su nombre sale del archivo: `shapes`.
- **El nombre de una llamada.** Se quita el verbo de delante (`get_health()` da `health`). Si la función es solo el verbo (`make()`), el nombre sale del tipo que devuelve: `circle`.
- **La regla del cursor al final.** El cursor justo detrás del paréntesis de cierre cuenta como estar en la llamada.

Un fallo que ya existía, corregido de paso: un número en binario (`0b101`) no se reconocía como entero. Afectaba también a "Add Explicit Types", que dejaba sin tipo `var mask := 0b101`.

Comprobado de paso, porque condiciona qué tipo se puede escribir: una variable con tipo no es más estricta que el valor usado directamente. `var sprite: Node = $Sprite` seguido de `sprite.texture = ...` compila igual que `$Sprite.texture = ...`, y lo mismo con una clase de script.

### V2 — De qué depende, adónde puede ir y con qué opciones

- Qué lee el valor (apartado 4.1) y si es una constante para GDScript, con la lista de funciones matemáticas generada.
- Qué sitios existen para ese valor y cuáles se pueden usar (apartado 4.2).
- Qué opciones admite cada sitio (apartado 4.3).
- El motivo de cada botón apagado y el aviso de cada combinación que lo lleva (apartado 4.4).

Verificación: `describe_variable_kinds` enseña cada sitio y cada opción con su motivo o su aviso. Un caso por fila de las tablas de los apartados 4.2, 4.3 y 4.4, y además: valor directamente en el cuerpo de la función, dentro de uno y de varios bloques, en una lambda de una y de varias líneas, en una función estática, en una clase interna y en una a dos niveles, valor por defecto de un parámetro, argumento de una anotación, valor de un enum, y un valor que lee a la vez una local y un miembro. Se repite la medida del apartado 5 separando lo que lee parámetros de lo que lee variables de un bloque.

Hecho el 2026-10-08:

- **`analysis/value_dependencies.gd`** (`GDSExValueDependencies`). Qué lee el valor: variables de un bloque, locales y parámetros, miembros del objeto, cosas de una clase interna, el árbol de escena, y si GDScript lo aceptaría en una constante. De cada cosa guarda el primer nombre, que es el que sale en el motivo.
- **`actions/extract_variable.gd`**: los sitios que existen para un valor y cuáles se pueden usar, las opciones de cada sitio, la elección por defecto y cómo queda una elección al cambiar de sitio o pulsar una opción, y los avisos.
- **`builtin_types.gd`** gana `MATH_FUNCTIONS`, las 78 funciones que valen en una constante, generada del volcado de la API. El resto del archivo regenerado es idéntico.
- **Runner:** `describe_variable_places` enseña cada sitio, las opciones que admite y sus avisos; `describe_variable_options`, cada opción de un sitio con su motivo.
- **103 casos** en `tests/cases/extract_variable_places/`, 1.125 en total. Uno o más por fila de las tablas de los apartados 4.2, 4.3 y 4.4, y los sitios especiales: función estática, clase interna y a dos niveles, lambda de una y de varias líneas, valor de una variable y de una constante de clase, valor por defecto de un parámetro, anotación, enum, función de una línea, patrón de un `match` y script que no es un nodo.
- 100 de los 103 se escribieron a mano antes de ejecutarlos y pasaron a la primera. Los otros tres eran expectativas mías.
- Se rompió el comportamiento a propósito de cuarenta y cinco maneras y se detectan cuarenta y cuatro. La que no, era una línea que sobraba y se quitó.

Detalles decididos al implementar:

- **Las cuatro opciones se enseñan siempre.** Las que no valen para el sitio elegido salen apagadas con su motivo ("Only a variable of the class can be static."). Así la fila no cambia de forma al cambiar de sitio. Los sitios sí se esconden cuando no son distintos, que es la decisión 8.
- **Una opción puede estar obligada**: marcada y sin poder quitarse, con el motivo al pasar el ratón. Pasa con "Constant" en "Script" y dentro de una anotación o de un enum, con "On ready" cuando el valor usa el árbol de escena, y con "Static" dentro de una función estática si no se elige "Constant".
- **Un valor que lee el parámetro de una lambda escrita en una línea no se puede extraer.** No hay línea dentro de la lambda donde declarar la variable. La acción no se ofrece.
- **El aviso de orden no cuenta las funciones matemáticas ni los constructores de tipos básicos** que van antes: no tienen efectos.
- **El motivo de "Constant" nombra lo primero que estorba**: en `Shapes.make().grown(2.0)` es `Shapes.make()`.
- **Dentro del patrón de un `match`** la declaración va antes del `match`: entre dos patrones no cabe.

Medido con el análisis ya hecho, sobre los valores que son llamadas:

| Medida | Este proyecto (53 scripts) | GUT (86 scripts) |
|---|---|---|
| Llamadas dentro de funciones | 5.275 | 5.437 |
| De ellas, son un valor que se puede extraer | 3.826 | 4.465 |
| Están dentro de un bloque | 1.645 | 2.015 |
| De esas, pueden salir a "Function" | 792 | 930 |
| No pueden: leen algo del bloque | 853 | 1.085 |
| Pueden ir a "Class" | 641 | 1.052 |
| Pueden ser "Static" | 244 | 271 |
| Pueden ser "Constant" | 3 | 41 |
| El sitio más cercano lleva el aviso de «a veces o más de una vez» | 667 | 257 |
| El sitio más cercano lleva el aviso de orden | 154 | 128 |

Las llamadas que no son un valor son casi todas las que no devuelven nada. Los 1.078 números del proyecto y los 769 de GUT son todos extraíbles y constantes. Analizar los 6.353 valores del proyecto tarda 3,4 segundos, medio milisegundo por valor.

Se revisó una muestra de 37 avisos del proyecto, uno de cada 23 de los de «a veces» y uno de cada 19 de los de orden: todos son correctos. El de «a veces» sale en el 17 % de las llamadas, más que el «una de cada ocho» estimado en el apartado 5, porque cuenta también las ramas de los valores condicionales y las lambdas de una línea.

### V3 — La edición

- La declaración y la sustitución para cada combinación de opciones.
- La colocación en cada uno de los cuatro sitios (detalles D8 y D9).
- Los casos especiales de los detalles D5, D6 y D7.
- La comprobación del nombre (apartado 4.5).

Todavía sin diálogo: los casos eligen opción y nombre con una cabecera, como hacen hoy los de "Extract Function...".

Verificación: casos por sitio y por opción, con variaciones de sangría, bloques anidados, clases internas y sentencias de varias líneas. Casos de comportamiento, que ejecutan la función antes y después y comparan el resultado, con el mecanismo que ya usa "Extract Function...": en los sitios sin aviso tiene que dar lo mismo. Casos del nombre, uno por celda de la tabla del 4.5.

Hecho el 2026-10-08:

- **La edición** (`GDSExExtractVariable.build_plan_for`): la declaración, con `@onready`, `static`, `var` o `const`, el nombre, el tipo si se conoce y el valor; y el nombre en el sitio del valor. Un valor de varias líneas se declara con sus líneas tal cual, recolocadas a la sangría nueva.
- **Colocación local.** En la línea anterior a la sentencia, o a la sentencia del cuerpo de la función en "Function". Tres casos en que esa línea no vale y se sube: delante de un `elif` o de un `else` se va antes del `if`; dentro del patrón de un `match`, antes del `match`; y si la línea de antes es una anotación suelta (`@warning_ignore(...)`), por encima de ella.
- **Colocación en la clase** (`GDSExPlacement.variable_by_order`): detrás del último miembro de su categoría o de una anterior. Si es el primero de la clase, tras la cabecera y su comentario de descripción.
- **`actions/variable_name_check.gd`** (`GDSExVariableNameCheck`), con las reglas del apartado 4.5.
- **El nombre propuesto evita los que dan error o aviso**, añadiendo un número: `health_2`.
- **Runner:** `action: extract_variable` con la cabecera `options:` (nombre, sitio y opciones), `describe_variable_name`, `describe_variable_warnings` y `check_variable_extraction_behavior`, que ejecuta la función antes y después.
- **106 casos** en `tests/cases/extract_variable/`, 1.231 en total: 30 de colocación local, 26 de colocación en la clase y en el script, 8 de combinaciones que se rechazan, 30 del nombre, 5 de avisos y 7 de comportamiento.
- 101 de los primeros 105 se escribieron a mano antes de ejecutarlos y pasaron a la primera. De los otros cuatro, uno era una expectativa mía y tres destaparon las líneas en blanco de más que se cuentan abajo.
- Se rompió el comportamiento a propósito de treinta y tres maneras y se detectan treinta y una. Las otras dos eran código que ya no hacía falta, y se quitó.

Detalles decididos al implementar:

- **Las líneas en blanco que ya hay se respetan.** Al meter una variable detrás de otra, no se añade separación con lo que viene después: se queda la que el usuario tenía. Solo se añade una línea en blanco delante cuando la variable empieza una categoría nueva, y detrás cuando es el primer miembro de la clase.
- **Una constante que usa otra constante va justo antes de ella**, no al final de las constantes. Lo mismo una variable de clase que se usa en el valor de otra: tiene que ir antes, o la otra leería su valor por defecto.
- **El valor dentro de una constante solo puede ser otra constante**, sea de clase o local. Se trata igual que una anotación o un enum: "Constant" va obligada.
- **El valor dentro de una variable estática** se trata como el de una función estática.
- **Una función que no declara lo que devuelve no da tipo.** El resolvedor lo deduce de sus `return`, pero es una suposición; la variable se declara sin tipo.
- **Un nombre local que tapa a un miembro lleva aviso, y el propuesto lo evita.** No es solo estilo: las líneas siguientes del bloque que usaban el miembro pasarían a usar la variable nueva.
- **Lo que carga un script se propone con nombre de clase** cuando es una constante: `const Shapes = preload(...)`, sin tipo.
- **El cursor queda detrás del nombre**, en el sitio donde estaba el valor. Si el valor era toda la línea, delante del valor.
- **El tipo en "Script" no se traduce.** Una constante solo puede ser de un tipo básico, que se escribe igual en todas partes.

### V4 — El diálogo y la acción en el menú

- `extract_variable_dialog.gd` (apartados 1, 4.4 y 4.6).
- La acción, con la etiqueta "Extract Variable...", y su alta en el menú.

Verificación: casos que abren el diálogo desde el menú, cambian nombre y opciones y confirman, como los de los otros dos diálogos. Comprueban que la fila "Where" enseña solo los sitios que son distintos, que un botón apagado lleva su motivo, que al elegir "Script" se marca "Constant", que el nombre se rehace al cambiar de opción y deja de rehacerse cuando el usuario escribe, que "On ready" se marca solo, que con un error no se puede confirmar, y que la vista previa coincide con lo que luego se aplica. Pasada en un editor sin ventana.

Hecho el 2026-10-08:

- **`extract_variable_dialog.gd`** (`GDSExExtractVariableDialog`). Nombre, fila "Where", fila "Options", vista previa "Result" y franja de avisos. Hereda de `function_name_dialog.gd` como los otros dos.
- **`actions/extract_variable_action.gd`**, con la etiqueta "Extract Variable...", dada de alta en el menú detrás de "Extract Function...".
- **La vista previa enseña el script entero ya cambiado**, con la declaración y la línea del valor marcadas y centrado en la declaración. Sale de aplicar la misma edición que luego se aplica al script, así que no puede enseñar otra cosa.
- **Los avisos se juntan en la franja de abajo**, uno por línea: primero el del nombre, si lo hay, y luego los del sitio. Un error del nombre los tapa a todos y apaga "Extract".
- **El estilo de los botones de dos posiciones** estaba en el diálogo del init; pasa a `function_name_dialog.gd` para que lo usen los dos.
- **Runner:** `run_extract_variable_dialog` abre el diálogo desde el menú, pulsa lo que diga la cabecera `options:` y confirma o cancela; además compara el script resultante con lo que enseñaba la vista previa. `check_extract_variable_dialog` recorre el diálogo paso a paso.
- **8 casos nuevos** en `tests/cases/menu/`, 1.239 en total. Uno de ellos hace 54 comprobaciones sobre el diálogo: qué sitios se enseñan en cada situación, qué opciones se pueden pulsar y el motivo de las que no, cómo cambia el nombre propuesto, las opciones que se excluyen entre sí, las obligadas, los avisos, los errores y que confirmar aplica lo que se veía.
- Se rompió el comportamiento a propósito de veintidós maneras. Tres no las detectaba ningún caso: para dos se añadieron comprobaciones y la tercera era una línea que sobraba. Ahora se detectan las veintiuna que quedan.
- **En un editor sin ventana**, con el menú de verdad: la acción aparece, el diálogo se abre con los colores del editor, y con un número, una llamada dentro de un bucle y un nodo la extracción queda en el script como la enseñaba el diálogo. Un deshacer la quita y el archivo no cambia. Cierra sin errores ni avisos.

Detalles decididos al implementar:

- **El nombre propuesto sigue a las opciones hasta que el usuario escribe.** Al marcar "Constant" pasa a mayúsculas, al elegir "Class" gana el `_`. En cuanto se teclea algo, ya no se toca.
- **La privacidad elegida se recuerda.** Si el usuario quita "Private", cambiar luego de opción no la vuelve a poner.
- **Pulsar una opción quita las que no pueden ir con ella**: "Static" quita "Constant" y "On ready", y "On ready" quita las otras dos.
- **Un sitio apagado no se puede elegir ni por error:** la función que cambia de sitio lo comprueba, además del botón.
- **`@onready` va en su categoría**, que en el orden de "Reorder Class Members" está antes de las variables públicas.

Encontrado por la comprobación masiva del plan anterior: la primera versión del diálogo pasaba enteros a funciones que piden un valor de un enum. Compila, pero no es el estilo del proyecto; los botones se guardan ya por el enum.

### V5 — Pruebas masivas, rendimiento y documentación

- **Comprobación por los dos lados, en la suite.** Para cada valor de los scripts del proyecto y cada combinación de sitio y opción: si el plugin la da por buena, se aplica y el script tiene que compilar; si la apaga, se fuerza y el script no tiene que compilar. Con la regla única de la decisión 11, todo lo apagado es algo que no compilaría, salvo los dos casos de los detalles D5 y D6, así que la prueba cubre casi todos los botones. Lo primero detecta código roto. Lo segundo detecta opciones apagadas sin motivo, que es el fallo que nadie ve. En la suite, una muestra; completa, lanzada a mano.
- Lo mismo sobre GUT, lanzado a mano: código ajeno, casi sin tipos.
- Tiempo de abrir el menú. La acción se evalúa en cada apertura con un valor bajo el cursor (detalle D14).
- README, CHANGELOG y la lista del apartado 10.

En cada paso se rompe el comportamiento a propósito de varias maneras y se comprueba que algún caso lo detecta.

Hecho el 2026-10-08:

- **La comprobación por los dos lados está en el runner.** `check_variable_extraction_of_project_scripts` recorre este proyecto y `check_variable_extraction_of_scripts_in`, con la cabecera `scripts_root`, cualquier carpeta. `sample_step` dice cada cuántos valores se prueba uno; `parts` y `part` reparten una pasada entre varios procesos; `lines` la limita a unas líneas, para repetir un fallo. Cuando algo no compila, el fallo lleva el error del compilador y las líneas que cambiaron.
- **En la suite va una muestra**, un valor de cada 150: 82 valores con algo que ofrecer, 218 maneras que compilan y 143 rechazadas con razón, en unos 12 segundos.
- **Completa, sobre este proyecto:** 56 scripts y 14.472 valores, de los que 12.021 tienen algo que ofrecer. 34.980 maneras se aplican y compilan; otras 20.045 están apagadas, se fuerzan y no compilan. Ningún fallo. Con 16 procesos son unos tres minutos.
- **Completa, sobre GUT**, en una copia fuera de `TestProject`: 86 scripts, 9.994 valores, 9.023 con algo que ofrecer, 38.312 maneras que compilan y 13.311 rechazadas con razón. Ningún fallo.
- **La primera pasada completa encontró dieciséis clases de fallo** que no habían visto ni la muestra ni los 328 casos escritos a mano. Están en la tabla de abajo, cada una con sus casos.
- **Dos de los arreglos alcanzan a otras acciones.** En un script que hereda de `CharacterBody2D`, `Area2D` o `Control`, `Input` se tomaba por una propiedad del nodo, y `var direction := Input.get_axis("ui_left", "ui_right")` no ofrecía "Add Explicit Type". Y "Generate Function Definition", dentro del `get` de una variable estática, escribía una función que desde ahí no se puede llamar; ahora escribe `static func`. Los dos fallos estaban en la 0.3.0 y los dos tienen caso.
- **66 casos nuevos, 1.305 en total.** De "Extract Variable" hay ya 389: 116 del valor, 134 de sitios y opciones, 131 de la edición y 8 del diálogo.
- **Se rompió el comportamiento a propósito de 38 maneras**, una por cada regla nueva. La primera vez se detectaron 33. Las otras cinco eran casos míos que no probaban lo que decían: un valor dentro de un texto sin cerrar se rechazaba por los paréntesis que quedaban abiertos, no por el texto. Con los casos corregidos y tres más se detectan las 38.
- **Tiempo de abrir el menú:** medido en el apartado 11. La acción añade alrededor de un milisegundo.
- **README y CHANGELOG.** El apartado "Extract Variable" del README, la fila de la tabla de acciones y la entrada de la 0.4.0. `plugin.cfg` sigue en 0.3.0: el número se cambia al publicar.

Lo que encontró la pasada completa:

| Qué pasaba | Dónde salió | Ahora |
|---|---|---|
| Se proponía `int`, `float`, `AABB` o `RID` como nombre, y el script no compila | `int(part)`, `float(size)`, `AABB()` | El nombre propuesto es `value`. Escrito a mano, es un error |
| Al valor de una variable `static` se le proponía el nombre de su tipo | `static var _generation: int = 0` | Toma el nombre de la variable, como en las demás |
| `get()` y `set(value)` de una propiedad se tomaban por llamadas | GUT | No son valores |
| Dentro del `get` de una variable estática se ofrecía una variable del objeto | GUT, `editor_globals.gd` | "Static" queda marcado y fijo, como en una función estática |
| La ruta de un `preload` podía salir a una variable | GUT, `gut_plugin.gd` | "Constant" queda marcado y fijo |
| `Callable(self, "run")` se daba por constante | GUT, `signal_watcher.gd` | `self` impide la constante |
| `new()` sin nada delante se tomaba por una función del objeto | `explicit_types.gd` | Es estática: en una función estática se ofrece "Static" |
| `Input` se tomaba por un miembro del objeto y apagaba "Static" | GUT, `OutputText.gd` | Los títulos de los grupos del inspector no son miembros |
| Una llamada suelta a una función con `await` pasaba a `var x = ...` | GUT, siete sitios | No es un valor |
| Lo mismo con una función del motor reescrita sin `-> void`, y con `super.add_child(...)` | GUT, `gut_dock.gd`, `test.gd` | No es un valor |
| Sacar el `range(...)` de un `for` quitaba el tipo a la variable del bucle | `class_layout.gd` | No es un valor |
| Se proponía un nombre igual al parámetro de la lambda donde está el valor | `value_finder.gd` | Error en el nombre |
| Se aceptaba `script` como variable de la clase | GUT, tres sitios | Error en el nombre |
| Se aceptaba un nombre que ya tiene una clase del script que hereda de esta | GUT, `panel_controls.gd` | Error en el nombre |
| De la función de un texto de varias líneas se cogía solo la última línea, y las líneas del texto cambiaban de sangría | GUT, `warnings_manager.gd` | El valor es el texto entero y sus líneas se copian tal cual |
| En un texto normal partido en dos líneas, `%s` se tomaba por un nodo | `run_tests.gd` | En una sentencia con un texto sin cerrar no hay valores |

**La pasada completa ejecutaba código, y vació un archivo del proyecto.** Para saber si una extracción compila, el runner compila el script cambiado, y compilar ejecuta los valores de las variables estáticas (apartado 5). Al probar `FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)` de `tools/generate_builtin_types.gd` como variable estática, Godot abrió `analysis/builtin_types.gd` para escribir y lo dejó vacío. Se restauró desde el último commit a los pocos minutos y no se tocó nada más; la carpeta de GUT era una copia. Desde entonces:

- Antes de compilar un script con una variable estática nueva, el runner pone delante otra cuyo valor falla al ejecutarse (`[][0]`). El valor nuevo se compila igual, pero ya no se ejecuta.
- Antes de probar nada, la comprobación verifica que esa guarda funciona: compila un script de prueba sin ella y con ella, y mira si su valor se ejecutó. Si la guarda no frena la ejecución, no prueba ningún script y el caso falla.
- La primera pasada completa sobre este proyecto no vale: desde que se vació el archivo, casi todo dejó de compilar por otro motivo. Las cifras de arriba son de la pasada repetida con el código final.

Detalles decididos al implementar:

- **Lo que no deja nada que guardar no se ofrece.** Amplía el detalle D4 a las funciones que esperan con `await`, a las del motor reescritas sin tipo de retorno, a las llamadas con `super.` y al `range(...)` de un `for`. Como en D4, la acción no aparece: no hay ningún sitio donde el resultado compile.
- **"Static" sigue apagado cuando el valor lee `self`**, aunque compilaría: al ejecutarse, `self` vale `null`. La comprobación por los dos lados lo sabe y no lo cuenta como fallo.
- **El `get` y el `set` de una variable estática cuentan como funciones estáticas** en el índice de símbolos, no solo para esta acción. De ahí el arreglo de "Generate Function Definition".
- **El nombre propuesto nunca es un tipo.** Si lo sería, en minúsculas o en mayúsculas, se propone `value`.
- **Las líneas de un texto de varias líneas van tal cual** en la declaración, sin la sangría del sitio nuevo. Cambiarla cambiaría el texto.
- **Un texto sin cerrar alcanza como mucho 40 líneas.** Si en ese tramo aparece la línea que lo cierra, todas las sentencias de en medio quedan sin valores. Si no aparece, se da por un texto a medio escribir y solo queda sin valores su línea. Sin ese límite, una comilla sin cerrar apagaría la acción en el resto del script.
- **Tampoco hay valores en una sentencia con un paréntesis sin cerrar.**
- **Un miembro nuevo se compara con las clases del mismo script que heredan de la suya.** Las de otros scripts quedan fuera (apartado 8).

Errores míos al escribir las pruebas, corregidos al ejecutarlas:

- Esperaba la declaración antes de la variable estática cuyo `get` la usa. Va detrás, con las de su categoría: a un `get` le da igual el orden.
- Esperaba "Function" como opción por defecto para la ruta de un `preload`. Es "Function constant": la opción obligada forma parte de la opción por defecto.
- Un caso de "Generate Function Definition" esperaba `-> int` con `pass`, que no compila, y el parámetro `arg_0`, que se llama `param_0`.
- Los cinco casos que no detectaban su rotura, ya contados arriba.

## 8. Qué queda fuera

- **Operaciones** (`a + b`, `not ready`, `x if c else y`). Hace falta saber si lo seleccionado es una pieza completa de la expresión. Mientras tanto, lo que va entre paréntesis sí se puede extraer (detalle D1).
- **Lecturas de miembros** (`player.health`, `Color.RED`).
- **Todos los valores iguales** de una vez (decisión 6).
- `@export`.
- Los sitios intermedios: un bloque que no es el más cercano, o una clase que no es ni la de la función ni la raíz (detalle D15).
- Una variable estática en "Script". Haría falta que el script tuviera `class_name` para leerla desde la clase interna.
- Crear la variable en otro script.
- El caso contrario: quitar una variable y poner su valor donde se usa.
- **Un nombre que ya usa una clase de otro script que hereda de esta.** El plugin mira las clases del mismo script. Para las de otros haría falta leer todos los scripts del proyecto; les pasa lo mismo a "Generate Class Variable" y a "Generate Function Definition".
- **Los valores de una sentencia con un texto sin cerrar en su línea.** Un texto normal, el que no va entre tres comillas, puede seguir en la línea siguiente, pero también puede ser un texto a medio escribir. Ahí no se ofrece nada (V5).
- **El `range(...)` de un `for`** y las llamadas a funciones que esperan con `await` (V5).

## 9. Riesgos

- **Cambiar lo que hace el código sin dar error.** Es el riesgo principal y el motivo de los avisos de las decisiones 3, 4 y 11 y de dejar fuera las operaciones. Con la decisión 11 el plugin ya no impide ninguno de esos cambios: los avisa. Red: los casos de comportamiento de V3 para los sitios sin aviso, y un caso por aviso.
- **La regla de qué es una constante.** Si acepta de más, el código no compila; si acepta de menos, apaga una opción válida. Red: los hechos del apartado 5, el detalle D13 y la comprobación por los dos lados de V5.
- **Encontrar mal el valor.** Textos con paréntesis, lambdas, llamadas de varias líneas. El análisis de llamadas que ya usa "Generate Function Definition" cubre casi todo; red: los casos de V1 y GUT.
- **Una variable de clase colocada antes de lo que lee.** Compila y da un valor equivocado. Detalle D9, con casos que ejecutan el resultado.
- **Un nombre que tapa a otro.** Apartado 4.5.
- **El menú.** La acción aparecerá en casi cualquier línea con una llamada o un número. Se mide en V5 que no encarece abrirlo.

## 10. Para comprobar con ventana

Para pasar al cerrar V5:

1. El diálogo se abre con el nombre seleccionado y listo para escribir encima.
2. Los botones apagados se distinguen de los encendidos, y el motivo aparece al pasar el ratón.
3. Con el valor en el cuerpo de una función de la clase raíz salen dos sitios; dentro de un bloque, tres; y en una clase interna, uno más.
4. La vista previa usa los colores y la fuente del editor, y las dos líneas marcadas se ven.
5. Al confirmar, el cursor queda en un sitio razonable y un solo deshacer lo quita todo.
6. Con Intro se confirma y con Escape se cancela.

## 11. Resultado

Cerrado el 2026-10-08, con Godot 4.7.2.

| Medida | Resultado |
|---|---|
| Casos de la suite | 1.305, todos en verde; 389 son de "Extract Variable" |
| Valores de este proyecto probados de todas las maneras | 12.021 de 14.472 tienen algo que ofrecer; 34.980 maneras compilan y 20.045 se rechazan con razón |
| Valores de GUT | 9.023 de 9.994; 38.312 maneras compilan y 13.311 se rechazan con razón |
| Roturas a propósito, en los cinco pasos | 16, 44, 31, 21 y 38; todas detectadas |
| Editor sin ventana | Abre y cierra sin errores ni avisos |

### Lo que cuesta en el menú

Abrir el menú con el código de antes de esta acción (commit `f2d6a27`) y con el de ahora, sobre los mismos scripts. Cada medida se repitió dos veces; donde las dos no coinciden van las dos.

| Medida | Antes | Ahora |
|---|---|---|
| 48 scripts de este plugin, primera apertura, media | 31,0 y 31,2 ms | 31,9 y 32,1 ms |
| Los mismos, aperturas siguientes, media | 18,4 y 18,5 ms | 18,7 y 18,8 ms |
| El más largo (`run_tests.gd`, 1.974 líneas), primera apertura | 300,7 y 302,1 ms | 310,0 y 305,7 ms |
| Cursor sobre una llamada, 240 sitios | 16,2 y 16,3 ms | 17,3 y 17,4 ms |
| Cursor sobre un número, 40 sitios | 23,9 y 24,0 ms | 24,6 y 24,7 ms |
| Cursor al final de una línea, 333 sitios | 16,6 y 16,7 ms | 17,1 ms |
| 86 scripts de GUT, primera apertura, media | 15,0 ms | 15,2 y 15,3 ms |
| GUT, cursor sobre una llamada, 445 sitios | 16,1 y 16,6 ms | 17,2 ms |
| GUT, cursor sobre un número, 51 sitios | 15,1 y 15,4 ms | 15,9 ms |
| GUT, cursor al final de una línea, 648 sitios | 13,9 y 14,3 ms | 14,5 ms |

La acción añade entre medio milisegundo y algo más de uno a cada apertura, sobre 15 a 25. En los 240 sitios con una llamada se ofrece en 173; en los 40 con un número, en los 40; y en 85 de los 333 finales de línea, donde el cursor queda tocando el final de un valor. En GUT, en 349 de las 445 llamadas, en los 51 números y en 261 de los 648 finales de línea.

La segunda medida de "antes" sobre GUT con el cursor en un valor se tomó mientras corría la suite, y por eso sale algo más alta que la primera.

### Lo que queda

- La lista del apartado 10, que pide ventana.
- El número de versión de `plugin.cfg`, que sigue en 0.3.0.
- Lo que el apartado 8 deja fuera.
