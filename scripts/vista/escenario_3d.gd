class_name Escenario3D
extends RefCounted
## Escenario del nivel en 3D: suelo de baldosas, paredes de ladrillo con altura, mostradores y cada estacion como un
## volumen (cajas y cilindros) con su arte de siempre puesto como tapa. Se dibuja con la misma camara inclinada de
## Proyeccion3D que usan los chefs y los efectos, asi todo cae justo sobre su posicion 2D.
##
## El juego sigue siendo 2D: colisiones, estaciones, items e interaccion no cambian. Solo se oculta el dibujo plano
## (Suelo, Mostradores y el PNG de cada estacion) y se pone el modelo 3D detras. Los items, el resalte y el nombre de
## las estaciones se siguen dibujando en 2D, subidos a la altura de la tapa (Estacion.elevacion_3d).
## Todo sale de formas simples y de los PNG que ya existen: nada nuevo que licenciar (RNF-06).
## Si algo falta (sin Suelo o sin PNG), ese elemento se queda como estaba. Se elige en EscenaCocinaView.

const ANCHO_PANTALLA: float = 1920.0
const ALTO_PANTALLA: float = 1080.0
const CARPETA_ARTE: String = "res://assets/art/escenario/"
const TEMAS: Array[String] = ["enrico", "jlb"]
const GROSOR_PARED: float = 40.0

## Alturas en unidades 3D (100 px = 1 unidad). La pared del frente es baja para no tapar la cocina.
const ALTURA_PARED: float = 0.55
const ALTURA_PARED_FRONTAL: float = 0.12
const ALTURA_MOSTRADOR: float = 0.35
const ALTURA_TAPA: float = 0.03
## La tapa del modelo sube un poco para no pelear con la caja de abajo (z-fighting).
const SOBRE_TAPA: float = 0.004

## Sombras reales de las luces. Si se ven mal en un equipo, basta con ponerlo en false.
const SOMBRAS: bool = false

const COLOR_PARED := Color(0.86, 0.86, 0.9)
const COLOR_MOSTRADOR := Color(0.52, 0.33, 0.2)
const COLOR_MESON := Color(0.6, 0.68, 0.78)
const COLOR_TOPE_MESON := Color(0.83, 0.87, 0.93)
const COLOR_MANIJA := Color(0.2, 0.2, 0.22)


## Reemplaza el dibujo plano del nivel por el modelo 3D. Devuelve false si el nivel no tiene Suelo (no se cambia nada).
static func aplicar(nivel_escena: Node2D, numero: int) -> bool:
	var suelo := nivel_escena.get_node_or_null("Suelo") as ColorRect
	if suelo == null:
		return false
	var tema: String = TEMAS[clampi(numero - 1, 0, TEMAS.size() - 1)]
	var mundo := _crear_capa(nivel_escena, suelo.get_index())
	var rect_suelo := Rect2(suelo.offset_left, suelo.offset_top, suelo.offset_right - suelo.offset_left, suelo.offset_bottom - suelo.offset_top)
	suelo.visible = false
	_poner_suelo(mundo, rect_suelo, CARPETA_ARTE + "suelo_%s.png" % tema)
	_poner_paredes(mundo, rect_suelo, CARPETA_ARTE + "pared_%s.png" % tema)
	for nombre in ["Mostrador1", "Mostrador2"]:
		_poner_mostrador(mundo, nivel_escena.get_node_or_null(nombre) as Node2D)
	for hijo in nivel_escena.get_children():
		var estacion := hijo as Estacion
		if estacion != null:
			_poner_estacion(mundo, estacion)
	return true


# --- Capa 3D --------------------------------------------------------------------------------

## Capa a pantalla completa con fondo transparente, justo donde estaba el suelo (detras de estaciones y chefs).
static func _crear_capa(nivel_escena: Node2D, indice: int) -> Node3D:
	var contenedor := SubViewportContainer.new()
	contenedor.name = "Escenario3D"
	contenedor.stretch = true
	contenedor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	contenedor.size = Vector2(ANCHO_PANTALLA, ALTO_PANTALLA)
	nivel_escena.add_child(contenedor)
	nivel_escena.move_child(contenedor, indice)
	var vista := SubViewport.new()
	vista.transparent_bg = true
	vista.own_world_3d = true
	vista.msaa_3d = Viewport.MSAA_4X
	vista.gui_disable_input = true
	vista.handle_input_locally = false
	contenedor.add_child(vista)
	var mundo := Node3D.new()
	mundo.name = "Mundo3D"
	vista.add_child(mundo)

	var ambiente := Environment.new()
	ambiente.background_mode = Environment.BG_CLEAR_COLOR
	ambiente.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	ambiente.ambient_light_color = Color(0.9, 0.92, 1.0)
	ambiente.ambient_light_energy = 0.5
	var entorno := WorldEnvironment.new()
	entorno.environment = ambiente
	mundo.add_child(entorno)

	# La luz viene de arriba, algo por delante y a un lado: la tapa queda mas clara que el frente y el costado.
	var luz := DirectionalLight3D.new()
	luz.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	luz.light_energy = 0.72
	luz.shadow_enabled = SOMBRAS
	luz.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	luz.directional_shadow_max_distance = 60.0
	mundo.add_child(luz)

	var camara := Camera3D.new()
	mundo.add_child(camara)
	Proyeccion3D.configurar_camara(camara, ALTO_PANTALLA, Vector2(ANCHO_PANTALLA, ALTO_PANTALLA) / 2.0)
	camara.current = true
	return mundo


# --- Suelo, paredes y mostradores -----------------------------------------------------------

static func _poner_suelo(mundo: Node3D, rect: Rect2, ruta: String) -> void:
	var plano := PlaneMesh.new()
	plano.size = _tamano_suelo(rect)
	var textura := _cargar(ruta)
	var material := _material(Color(0.55, 0.65, 0.8))
	if textura != null:
		material = _material(Color.WHITE, textura)
		# La baldosa mide 120 px: se repite igual que el mosaico 2D de antes.
		material.uv1_scale = Vector3(rect.size.x / float(textura.get_width()), rect.size.y / float(textura.get_height()), 1.0)
	plano.material = material
	var suelo := MeshInstance3D.new()
	suelo.mesh = plano
	suelo.position = Proyeccion3D.a_3d(rect.get_center())
	suelo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mundo.add_child(suelo)


## Cuatro franjas de ladrillo alrededor del suelo, justo donde estan los muros invisibles.
static func _poner_paredes(mundo: Node3D, suelo: Rect2, ruta: String) -> void:
	var textura := _cargar(ruta)
	var izquierda := suelo.position.x
	var arriba := suelo.position.y
	var derecha := suelo.end.x
	var abajo := suelo.end.y
	var ancho_total := suelo.size.x + 2.0 * GROSOR_PARED
	var franjas: Array[Dictionary] = [
		{"rect": Rect2(izquierda - GROSOR_PARED, arriba - GROSOR_PARED, ancho_total, GROSOR_PARED), "alto": ALTURA_PARED},
		{"rect": Rect2(izquierda - GROSOR_PARED, abajo, ancho_total, GROSOR_PARED), "alto": ALTURA_PARED_FRONTAL},
		{"rect": Rect2(izquierda - GROSOR_PARED, arriba, GROSOR_PARED, suelo.size.y), "alto": ALTURA_PARED},
		{"rect": Rect2(derecha, arriba, GROSOR_PARED, suelo.size.y), "alto": ALTURA_PARED},
	]
	for franja in franjas:
		var material := _material(Color(0.36, 0.49, 0.58))
		if textura != null:
			material = _material(COLOR_PARED, textura)
			# Ladrillo de 40 px que se repite por cada cara. El eje Z va comprimido por la inclinacion.
			var por_unidad := Proyeccion3D.PIXELES_POR_UNIDAD / float(textura.get_width())
			material.uv1_triplanar = true
			material.uv1_scale = Vector3(por_unidad, por_unidad, por_unidad * sin(Proyeccion3D.inclinacion()))
		_caja(mundo, franja["rect"], 0.0, franja["alto"], material)


## Mostrador del centro: caja con su mantel (el PNG de siempre) como tapa.
static func _poner_mostrador(mundo: Node3D, cuerpo: Node2D) -> void:
	if cuerpo == null:
		return
	var forma := cuerpo.get_node_or_null("Forma") as ColorRect
	if forma == null:
		return
	var rect := Rect2(cuerpo.position + Vector2(forma.offset_left, forma.offset_top), Vector2(forma.offset_right - forma.offset_left, forma.offset_bottom - forma.offset_top))
	forma.visible = false
	_caja(mundo, rect, 0.0, ALTURA_MOSTRADOR, _material(COLOR_MOSTRADOR))
	var textura := _cargar(CARPETA_ARTE + "mostrador_%d.png" % int(rect.size.x))
	if textura != null:
		_tapa(mundo, rect, ALTURA_MOSTRADOR, textura)
	else:
		_caja(mundo, rect, ALTURA_MOSTRADOR, ALTURA_TAPA, _material(Color(0.78, 0.5, 0.42)))


# --- Estaciones -----------------------------------------------------------------------------

## Cada estacion: cuerpo (caja o cilindro) con su arte 2D como tapa, mas algun detalle. Despues apaga su dibujo plano.
static func _poner_estacion(mundo: Node3D, estacion: Estacion) -> void:
	var lado := _lado(estacion)
	var rect := Rect2(estacion.position - lado / 2.0, lado)
	var alto := ALTURA_MOSTRADOR
	if estacion is Meson:
		_poner_meson(mundo, estacion as Meson, rect)
	else:
		var color := Color(0.5, 0.5, 0.5)
		var redondo := false
		if estacion is Surtidor:
			color = Color(0.5, 0.32, 0.18)
			alto = 0.3
		elif estacion is Plancha:
			color = Color(0.2, 0.2, 0.23)
			alto = 0.38
		elif estacion is Freidora:
			color = Color(0.62, 0.42, 0.17)
			alto = 0.45
		elif estacion is Olla:
			color = Color(0.4, 0.38, 0.36)
			alto = 0.42
			redondo = true
		elif estacion is TablaCortar:
			color = Color(0.46, 0.41, 0.37)
			alto = 0.35
		elif estacion is BarraEntrega:
			color = Color(0.33, 0.55, 0.36)
			alto = 0.4
		elif estacion is DispensadorPlatos:
			color = Color(0.76, 0.75, 0.78)
			alto = 0.4
		elif estacion is CestoBasura:
			color = Color(0.42, 0.42, 0.45)
			alto = 0.55
			redondo = true
		if redondo:
			_cilindro(mundo, rect, alto, _material(color))
		else:
			_caja(mundo, rect, 0.0, alto, _material(color))
		var textura := estacion.textura_arte()
		if textura != null:
			_tapa(mundo, rect, alto, textura)
		else:
			# Sin PNG: tapa lisa con el color provisional de la estacion, como antes.
			_caja(mundo, rect, alto, ALTURA_TAPA, _material(estacion.color_placeholder))
		if estacion is Olla:
			_manijas_olla(mundo, rect, alto)
	estacion.arte_3d = true
	estacion.elevacion_3d = _px_de_altura(alto + (ALTURA_TAPA if estacion is Meson else 0.0))
	estacion.queue_redraw()


## Mueble liso de acero. Los mesones pegados se unen: solo se deja borde en los lados libres.
static func _poner_meson(mundo: Node3D, meson: Meson, rect: Rect2) -> void:
	_caja(mundo, rect, 0.0, ALTURA_MOSTRADOR, _material(COLOR_MESON))
	var tope := Rect2(rect.position, rect.size)
	var borde := 7.0
	if not meson._une_izq:
		tope.position.x += borde
		tope.size.x -= borde
	if not meson._une_der:
		tope.size.x -= borde
	if not meson._une_arriba:
		tope.position.y += borde
		tope.size.y -= borde
	if not meson._une_abajo:
		tope.size.y -= borde + 6.0
	_caja(mundo, tope, ALTURA_MOSTRADOR, ALTURA_TAPA, _material(COLOR_TOPE_MESON))


## Dos asas a los lados de la olla.
static func _manijas_olla(mundo: Node3D, rect: Rect2, alto: float) -> void:
	for lado in [-1.0, 1.0]:
		var centro := rect.get_center() + Vector2(lado * rect.size.x * 0.5, 0.0)
		var asa := Rect2(centro - Vector2(10.0, 8.0), Vector2(20.0, 16.0))
		_caja(mundo, asa, alto * 0.55, 0.07, _material(COLOR_MANIJA))


# --- Piezas ---------------------------------------------------------------------------------

## Caja cuya base es "rect" (pixeles del juego) y que sube "alto" unidades desde "desde".
static func _caja(mundo: Node3D, rect: Rect2, desde: float, alto: float, material: Material) -> MeshInstance3D:
	var malla := BoxMesh.new()
	malla.size = Vector3(rect.size.x / Proyeccion3D.PIXELES_POR_UNIDAD, alto, rect.size.y / Proyeccion3D.PIXELES_POR_UNIDAD / sin(Proyeccion3D.inclinacion()))
	malla.material = material
	var instancia := MeshInstance3D.new()
	instancia.mesh = malla
	instancia.position = Proyeccion3D.a_3d(rect.get_center(), desde + alto / 2.0)
	instancia.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if SOMBRAS else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mundo.add_child(instancia)
	return instancia


## Cilindro que cabe en el cuadrado "rect". Se estira en Z igual que el suelo, para que se vea redondo desde la camara.
static func _cilindro(mundo: Node3D, rect: Rect2, alto: float, material: Material) -> MeshInstance3D:
	var malla := CylinderMesh.new()
	var radio := minf(rect.size.x, rect.size.y) / 2.0 / Proyeccion3D.PIXELES_POR_UNIDAD * 0.96
	malla.top_radius = radio
	malla.bottom_radius = radio
	malla.height = alto
	malla.radial_segments = 40
	malla.rings = 1
	malla.material = material
	var instancia := MeshInstance3D.new()
	instancia.mesh = malla
	instancia.scale = Vector3(1.0, 1.0, 1.0 / sin(Proyeccion3D.inclinacion()))
	instancia.position = Proyeccion3D.a_3d(rect.get_center(), alto / 2.0)
	instancia.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if SOMBRAS else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mundo.add_child(instancia)
	return instancia


## Plano con el PNG (vista desde arriba) puesto sobre una caja. Las esquinas transparentes dejan ver lo de abajo.
static func _tapa(mundo: Node3D, rect: Rect2, altura: float, textura: Texture2D) -> MeshInstance3D:
	var material := _material(Color.WHITE, textura)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	var plano := PlaneMesh.new()
	plano.size = Vector2(rect.size.x / Proyeccion3D.PIXELES_POR_UNIDAD, rect.size.y / Proyeccion3D.PIXELES_POR_UNIDAD / sin(Proyeccion3D.inclinacion()))
	plano.material = material
	var instancia := MeshInstance3D.new()
	instancia.mesh = plano
	instancia.position = Proyeccion3D.a_3d(rect.get_center(), altura + SOBRE_TAPA)
	instancia.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mundo.add_child(instancia)
	return instancia


static func _material(color: Color, textura: Texture2D = null) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if textura != null:
		material.albedo_texture = textura
	return material


static func _cargar(ruta: String) -> Texture2D:
	if not ResourceLoader.exists(ruta):
		return null
	return load(ruta) as Texture2D


## Tamano (px) del cuadrado que ocupa la estacion, el mismo de su colision.
static func _lado(estacion: Estacion) -> Vector2:
	var colision := estacion.get_node_or_null("Colision") as CollisionShape2D
	if colision != null and colision.shape is RectangleShape2D:
		return (colision.shape as RectangleShape2D).size
	return Vector2(120.0, 120.0)


## Cuanto sube en pantalla (px) algo de "altura" unidades 3D.
static func _px_de_altura(altura: float) -> float:
	return altura * cos(Proyeccion3D.inclinacion()) * Proyeccion3D.PIXELES_POR_UNIDAD


static func _tamano_suelo(rect: Rect2) -> Vector2:
	return Vector2(rect.size.x / Proyeccion3D.PIXELES_POR_UNIDAD, rect.size.y / Proyeccion3D.PIXELES_POR_UNIDAD / sin(Proyeccion3D.inclinacion()))
