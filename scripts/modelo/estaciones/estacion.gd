class_name Estacion
extends StaticBody2D
## Base de todas las estaciones. Admite un solo ítem a la vez (R2), salvo excepciones por estación.

signal item_cambiado

## Carpeta con el arte de las estaciones (un PNG por escena; los surtidores llevan el ingrediente en el nombre).
const CARPETA_ARTE: String = "res://assets/art/estaciones/"
const INTERVALO_CERCANIA: float = 0.08

@export var nombre: String = "Estacion"
@export var color_placeholder: Color = Color(0.5, 0.5, 0.5)
@export var capacidad: int = 1

var items: Array[Item] = []

## Con el escenario 3D (Escenario3D), el cuerpo de la estacion lo dibuja el modelo 3D: aqui solo quedan los items,
## el resalte y el nombre. "elevacion_3d" es cuanto sube la tapa en pantalla (px), para dibujar encima de ella.
var arte_3d: bool = false
var elevacion_3d: float = 0.0

var _textura: Texture2D = null
var _cerca: bool = false
var _espera_cercania: float = 0.0


func _ready() -> void:
	_cargar_textura()
	queue_redraw()


## Vista: con arte, el nombre solo aparece (con un resalte) cuando un chef tiene esta estacion delante.
func _process(delta: float) -> void:
	if _textura == null and not arte_3d:
		return
	_espera_cercania -= delta
	if _espera_cercania > 0.0:
		return
	_espera_cercania = INTERVALO_CERCANIA
	var hay_chef := false
	for nodo in get_tree().get_nodes_in_group("chefs"):
		var chef := nodo as Chef
		if chef != null and chef.estacion_objetivo() == self:
			hay_chef = true
			break
	if hay_chef != _cerca:
		_cerca = hay_chef
		queue_redraw()


## El PNG de esta estacion (o null si falta). Escenario3D lo pone como tapa del modelo 3D.
func textura_arte() -> Texture2D:
	return _textura


## Busca el PNG segun la escena (plancha.tscn -> plancha.png). Si falta, se queda el dibujo provisional.
func _cargar_textura() -> void:
	var clave := scene_file_path.get_file().get_basename()
	if clave.is_empty():
		return
	var tipo: Variant = get("tipo")
	if tipo != null:
		clave += "_" + Ingrediente.NOMBRES[int(tipo)]
	var ruta := "%s%s.png" % [CARPETA_ARTE, clave]
	if ResourceLoader.exists(ruta):
		_textura = load(ruta) as Texture2D


func esta_ocupada() -> bool:
	return items.size() >= capacidad


func acepta(_item: Item) -> bool:
	return not esta_ocupada()


func puede_entregar() -> bool:
	return not items.is_empty()


func recibir(item: Item) -> bool:
	if not acepta(item):
		return false
	items.append(item)
	item_cambiado.emit()
	queue_redraw()
	return true


func retirar() -> Item:
	var item: Item = items.pop_front()
	item_cambiado.emit()
	queue_redraw()
	return item


## Accion Procesar. Solo la tabla de cortar la usa; en el resto basta depositar.
func procesar() -> void:
	pass


## Avance del tiempo. Lo llama el reloj unico de la partida.
func actualizar(_delta: float) -> void:
	pass


func _dibujar_extra(_tamano: Vector2) -> void:
	pass


## Resalte alrededor de la estacion y etiqueta con su nombre encima.
func _dibujar_nombre(fuente: Font, tamano: Vector2) -> void:
	# Con el modelo 3D el contorno cubre tambien la altura de la estacion.
	var caja := Rect2(-tamano / 2.0 - Vector2(4.0, 4.0 + elevacion_3d), tamano + Vector2(8.0, 8.0 + elevacion_3d))
	draw_rect(caja, Color(1.0, 0.92, 0.45, 0.95), false, 4.0)
	var medida := fuente.get_string_size(nombre, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20)
	var ancho := medida.x + 24.0
	var origen := Vector2(-ancho / 2.0, -tamano.y / 2.0 - 44.0 - elevacion_3d)
	draw_rect(Rect2(origen, Vector2(ancho, 32.0)), Color(0.13, 0.08, 0.05, 0.9))
	draw_string(fuente, origen + Vector2(12.0, 23.0), nombre, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, Color.WHITE)


# Dibujo provisional hasta tener el arte final.
func _draw() -> void:
	var tamano := ($Colision.shape as RectangleShape2D).size
	var fuente := ThemeDB.fallback_font
	var con_arte := _textura != null or arte_3d
	if arte_3d:
		if _cerca:
			_dibujar_nombre(fuente, tamano)
	elif _textura != null:
		draw_texture_rect(_textura, Rect2(-tamano / 2.0, tamano), false)
		if _cerca:
			_dibujar_nombre(fuente, tamano)
	else:
		draw_rect(Rect2(-tamano / 2.0, tamano), color_placeholder)
		draw_string(fuente, Vector2(-tamano.x / 2.0, -tamano.y / 2.0 - 8.0), nombre, HORIZONTAL_ALIGNMENT_CENTER, tamano.x, 20)
	var todo_con_arte := con_arte
	var paso := 52.0 if con_arte else 40.0
	for i in items.size():
		var posicion := Vector2((i - (items.size() - 1) / 2.0) * paso, -10.0 - elevacion_3d)
		if con_arte:
			if IconoItem.dibujar(self, items[i], posicion, 56.0):
				continue
			todo_con_arte = false
		draw_circle(posicion, 16.0, items[i].color())
	if not items.is_empty() and not todo_con_arte:
		var lineas := PackedStringArray()
		for item in items:
			lineas.append(item.etiqueta())
		draw_multiline_string(fuente, Vector2(-tamano.x / 2.0, 16.0), "\n".join(lineas), HORIZONTAL_ALIGNMENT_CENTER, tamano.x, 14)
	_dibujar_extra(tamano)
