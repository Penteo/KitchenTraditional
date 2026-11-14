class_name FondoMenu3D
extends Control
## Fondo 3D del menú: una cocina santandereana de noche con banderines tricolor, luces de bombillos, ollas de
## cobre y comida típica sobre un mostrador de madera. Se arma solo con formas primitivas y shaders (sin
## modelos ni imágenes), igual que la intro. Vive detrás de la interfaz: MenuController lo crea una vez, lo
## muestra en las pantallas del menú y lo apaga durante la partida para no gastar GPU.
## Los shaders están en SombreadosFondo.

## Grupo con el que Pantalla sabe que ya hay un fondo 3D visible y no dibuja el fondo plano.
const GRUPO: StringName = &"fondo_menu_3d"

const CAMARA_BASE := Vector3(0.0, 1.5, 7.4)
const CAMARA_MIRA := Vector3(0.0, 1.45, 0.0)
## Cuánto se mueve la cámara sola (deriva) y con el ratón (paralaje), en unidades de mundo.
const DERIVA := Vector2(0.20, 0.06)
const PARALAJE := Vector2(0.30, 0.15)
const SUAVIZADO_PARALAJE: float = 3.0
const DURACION_FUNDIDO: float = 0.6
## Profundidad (z) de las ollas y cucharones colgados: cerca de la pared para que sus sombras queden pegadas.
const Z_COLGANTES: float = -1.72

const ROJO := Color(0.90, 0.25, 0.16)
const AMARILLO := Color(0.98, 0.76, 0.18)
const AZUL := Color(0.16, 0.38, 0.92)

var _vista: SubViewport
var _mundo: Node3D
var _camara: Camera3D
var _post: ColorRect
var _velo: ColorRect
var _tiempo: float = 0.0
var _mouse: Vector2 = Vector2.ZERO
var _mouse_suave: Vector2 = Vector2.ZERO
var _bombillos: Array[StandardMaterial3D] = []
var _luces: Array[OmniLight3D] = []
var _energia_luces: Array[float] = []
var _tween_atenuacion: Tween
var _tween_velo: Tween
var _shaders: Dictionary = {}
var _textura_halo: GradientTexture2D
var _material_cuerda: StandardMaterial3D
var _rng := RandomNumberGenerator.new()


## True si hay un fondo 3D visible (las pantallas del menú no necesitan dibujar el suyo).
static func hay_activo(arbol: SceneTree) -> bool:
	var nodo := arbol.get_first_node_in_group(GRUPO) as FondoMenu3D
	return nodo != null and nodo.is_visible_in_tree()


func _ready() -> void:
	add_to_group(GRUPO)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rng.seed = 20261114
	_textura_halo = _crear_textura_halo()
	_material_cuerda = _mat(Color(0.14, 0.09, 0.06), 1.0)
	_material_cuerda.cull_mode = BaseMaterial3D.CULL_DISABLED
	_construir_vista()
	_construir_ambiente()
	_construir_luces()
	_construir_pared()
	_construir_mostrador()
	_construir_ventana()
	_construir_estante()
	_construir_ollas_colgantes()
	_construir_guirnaldas()
	_construir_bombillos()
	_construir_comida()
	_construir_particulas()
	_construir_camara()
	_construir_post()
	activar(false)


## Enciende o apaga el fondo. Apagado no se dibuja ni se actualiza (cero costo durante la partida).
func activar(valor: bool) -> void:
	var estaba := visible
	visible = valor
	set_process(valor)
	set_process_input(valor)
	_vista.render_target_update_mode = SubViewport.UPDATE_ALWAYS if valor else SubViewport.UPDATE_DISABLED
	if valor and not estaba:
		_velo.color.a = 1.0
		if _tween_velo != null:
			_tween_velo.kill()
		_tween_velo = create_tween()
		_tween_velo.tween_property(_velo, "color:a", 0.0, DURACION_FUNDIDO)


## Oscurece el fondo (0 = brillante, 1 = casi negro). Las pantallas con mucho texto piden un valor mayor.
func atenuar(valor: float, duracion: float = 0.45) -> void:
	if _tween_atenuacion != null:
		_tween_atenuacion.kill()
	var material := _post.material as ShaderMaterial
	if duracion <= 0.0 or not is_inside_tree():
		material.set_shader_parameter("atenuacion", valor)
		return
	var actual: float = material.get_shader_parameter("atenuacion")
	_tween_atenuacion = create_tween()
	_tween_atenuacion.tween_method(_fijar_atenuacion, actual, valor, duracion)


func _fijar_atenuacion(valor: float) -> void:
	(_post.material as ShaderMaterial).set_shader_parameter("atenuacion", valor)


func _input(evento: InputEvent) -> void:
	var movimiento := evento as InputEventMouseMotion
	if movimiento == null:
		return
	var tamano := get_viewport_rect().size
	if tamano.x <= 0.0 or tamano.y <= 0.0:
		return
	_mouse = ((movimiento.position / tamano) * 2.0 - Vector2.ONE).clamp(-Vector2.ONE, Vector2.ONE)


func _process(delta: float) -> void:
	_tiempo += delta
	_mouse_suave = _mouse_suave.lerp(_mouse, 1.0 - exp(-delta * SUAVIZADO_PARALAJE))
	var deriva := Vector3(sin(_tiempo * 0.21) * DERIVA.x, sin(_tiempo * 0.33 + 1.0) * DERIVA.y, 0.0)
	var paralaje := Vector3(_mouse_suave.x * PARALAJE.x, -_mouse_suave.y * PARALAJE.y, 0.0)
	_camara.position = CAMARA_BASE + deriva + paralaje
	_camara.look_at(CAMARA_MIRA)
	for i in _bombillos.size():
		_bombillos[i].emission_energy_multiplier = 2.6 + 0.35 * sin(_tiempo * 6.0 + i * 1.9) * sin(_tiempo * 2.3 + i)
	for i in _luces.size():
		_luces[i].light_energy = _energia_luces[i] * (1.0 + 0.07 * sin(_tiempo * 5.0 + i * 2.1) + 0.03 * sin(_tiempo * 13.0 + i))


# ---------------------------------------------------------------------------
# Vista, ambiente, luces y cámara
# ---------------------------------------------------------------------------

func _construir_vista() -> void:
	var contenedor := SubViewportContainer.new()
	contenedor.stretch = true
	contenedor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(contenedor)
	contenedor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vista = SubViewport.new()
	_vista.own_world_3d = true
	_vista.msaa_3d = Viewport.MSAA_4X
	_vista.gui_disable_input = true
	_vista.handle_input_locally = false
	contenedor.add_child(_vista)
	_mundo = Node3D.new()
	_mundo.name = "Mundo3D"
	_vista.add_child(_mundo)


func _construir_ambiente() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.025, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.72, 0.55)
	env.ambient_light_energy = 0.38
	var entorno := WorldEnvironment.new()
	entorno.environment = env
	_mundo.add_child(entorno)


func _construir_luces() -> void:
	# Luz fría de la ventana: da las sombras largas sobre el mostrador y la pared.
	var ventana := DirectionalLight3D.new()
	ventana.rotation_degrees = Vector3(-38.0, -40.0, 0.0)
	ventana.light_color = Color(0.62, 0.74, 1.0)
	ventana.light_energy = 0.85
	ventana.shadow_enabled = true
	ventana.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	ventana.directional_shadow_max_distance = 16.0
	ventana.shadow_bias = 0.04
	ventana.shadow_normal_bias = 1.2
	_mundo.add_child(ventana)
	# Relleno azul desde la derecha, para separar las formas del fondo cálido.
	var relleno := OmniLight3D.new()
	relleno.position = Vector3(6.0, 2.0, 2.0)
	relleno.light_color = Color(0.35, 0.5, 1.0)
	relleno.light_energy = 0.5
	relleno.omni_range = 10.0
	_mundo.add_child(relleno)


func _construir_camara() -> void:
	_camara = Camera3D.new()
	_camara.fov = 42.0
	_camara.position = CAMARA_BASE
	_mundo.add_child(_camara)
	_camara.current = true
	_camara.look_at(CAMARA_MIRA)


## Capa 2D sobre el 3D: viñeta, velo tras el título y los botones, base oscura para el aviso y fundido de entrada.
func _construir_post() -> void:
	_post = ColorRect.new()
	_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post.material = _sombreado(SombreadosFondo.POST)
	(_post.material as ShaderMaterial).set_shader_parameter("atenuacion", 0.0)
	add_child(_post)
	_post.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_velo = ColorRect.new()
	_velo.color = Color(0.0, 0.0, 0.0, 1.0)
	_velo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_velo)
	_velo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# ---------------------------------------------------------------------------
# Escenario
# ---------------------------------------------------------------------------

func _construir_pared() -> void:
	var plano := QuadMesh.new()
	plano.size = Vector2(28.0, 12.0)
	_pieza(plano, _sombreado(SombreadosFondo.PARED), Vector3(0.0, 3.0, -2.0))


func _construir_mostrador() -> void:
	var tapa := _sombreado(SombreadosFondo.MADERA)
	_pieza(_caja(Vector3(16.0, 0.16, 2.9)), tapa, Vector3(0.0, -0.08, -0.55))
	var cuerpo := _sombreado(SombreadosFondo.MADERA)
	cuerpo.set_shader_parameter("clara", Color(0.40, 0.23, 0.12))
	cuerpo.set_shader_parameter("oscura", Color(0.16, 0.09, 0.05))
	_pieza(_caja(Vector3(15.6, 2.4, 2.6)), cuerpo, Vector3(0.0, -1.36, -0.7))


func _construir_ventana() -> void:
	var centro := Vector3(-4.6, 3.2, -1.93)
	var marco := _mat(Color(0.30, 0.17, 0.09), 0.7)
	var vidrio := QuadMesh.new()
	vidrio.size = Vector2(1.9, 2.5)
	_pieza(vidrio, _sombreado(SombreadosFondo.CRISTAL), centro)
	_pieza(_caja(Vector3(2.15, 0.14, 0.18)), marco, centro + Vector3(0.0, 1.32, 0.05))
	_pieza(_caja(Vector3(2.35, 0.12, 0.3)), marco, centro + Vector3(0.0, -1.34, 0.1))
	_pieza(_caja(Vector3(0.14, 2.76, 0.18)), marco, centro + Vector3(-1.0, 0.0, 0.05))
	_pieza(_caja(Vector3(0.14, 2.76, 0.18)), marco, centro + Vector3(1.0, 0.0, 0.05))
	_pieza(_caja(Vector3(0.07, 2.5, 0.1)), marco, centro + Vector3(0.0, 0.0, 0.04))
	_pieza(_caja(Vector3(1.9, 0.07, 0.1)), marco, centro + Vector3(0.0, 0.0, 0.04))
	_haz_de_luz(1.7, 8.0, -1.35, 0.30)
	_haz_de_luz(1.0, 7.0, 0.35, 0.2)


## Haz que sale de la ventana en diagonal, en la misma dirección de la luz direccional.
func _haz_de_luz(ancho: float, largo: float, z: float, intensidad: float) -> void:
	var plano := QuadMesh.new()
	plano.size = Vector2(ancho, largo)
	var material := _sombreado(SombreadosFondo.HAZ)
	material.set_shader_parameter("intensidad", intensidad)
	var direccion := Vector3(0.636, -0.772, 0.0)
	var haz := _pieza(plano, material, Vector3(-4.3, 3.7, z) + direccion * (largo * 0.5), Vector3(0.0, 0.0, 39.5))
	haz.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _construir_estante() -> void:
	var madera := _sombreado(SombreadosFondo.MADERA)
	madera.set_shader_parameter("clara", Color(0.52, 0.31, 0.15))
	madera.set_shader_parameter("oscura", Color(0.24, 0.13, 0.07))
	_pieza(_caja(Vector3(3.6, 0.1, 0.55)), madera, Vector3(4.1, 1.6, -1.7))
	for x: float in [2.45, 5.75]:
		_pieza(_caja(Vector3(0.1, 0.38, 0.45)), madera, Vector3(x, 1.38, -1.72))
	var bases: Array[Color] = [
		Color(0.93, 0.88, 0.74), Color(0.86, 0.28, 0.18), Color(0.97, 0.77, 0.2),
		Color(0.18, 0.44, 0.32), Color(0.78, 0.42, 0.25), Color(0.2, 0.36, 0.8),
	]
	var bandas: Array[Color] = [
		Color(0.12, 0.3, 0.8), Color(0.96, 0.9, 0.75), Color(0.14, 0.3, 0.75),
		Color(0.95, 0.88, 0.7), Color(0.96, 0.9, 0.75), Color(0.98, 0.8, 0.25),
	]
	var altos: Array[float] = [0.55, 0.42, 0.62, 0.48, 0.58, 0.4]
	var radios: Array[float] = [0.19, 0.17, 0.2, 0.18, 0.19, 0.16]
	var tapa_madera := _mat(Color(0.36, 0.2, 0.1), 0.7)
	for i in 6:
		var material := _sombreado(SombreadosFondo.CERAMICA)
		material.set_shader_parameter("base", bases[i])
		material.set_shader_parameter("banda", bandas[i])
		material.set_shader_parameter("frecuencia", 5.0 + i)
		var x := 2.75 + i * 0.5
		var base_y := 1.65
		_pieza(_torno(_perfil_jarra(radios[i], altos[i])), material, Vector3(x, base_y, -1.72))
		_pieza(_esfera(0.045), tapa_madera, Vector3(x, base_y + altos[i] + 0.03, -1.72))


func _construir_ollas_colgantes() -> void:
	var cobre := _sombreado(SombreadosFondo.COBRE)
	var hierro := _mat(Color(0.07, 0.07, 0.08), 0.6)
	var madera := _mat(Color(0.45, 0.27, 0.13), 0.7)
	var y_riel := 4.25
	_pieza(_cilindro(0.03, 0.03, 3.9), hierro, Vector3(4.05, y_riel, Z_COLGANTES), Vector3(0.0, 0.0, 90.0))
	var xs: Array[float] = [3.15, 3.85, 4.6, 5.3]
	var radios: Array[float] = [0.42, 0.55, 0.4, 0.32]
	var altos: Array[float] = [0.5, 0.62, 0.46, 0.38]
	var y_borde := 3.45
	for i in xs.size():
		var olla := _pieza(_torno(_perfil_olla(radios[i], altos[i])), cobre, Vector3(xs[i], y_borde - altos[i], Z_COLGANTES))
		olla.rotation_degrees.y = 25.0 * i
		var largo := y_riel - (y_borde + 0.08)
		_pieza(_cilindro(0.012, 0.012, largo), hierro, Vector3(xs[i], y_borde + 0.08 + largo * 0.5, Z_COLGANTES))
		var argolla := TorusMesh.new()
		argolla.inner_radius = 0.045
		argolla.outer_radius = 0.07
		_pieza(argolla, hierro, Vector3(xs[i], y_borde + 0.04, Z_COLGANTES), Vector3(90.0, 0.0, 0.0))
		# Asas laterales de la olla.
		var asa := TorusMesh.new()
		asa.inner_radius = 0.025
		asa.outer_radius = 0.05
		for lado: float in [-1.0, 1.0]:
			_pieza(asa, cobre, Vector3(xs[i] + (radios[i] + 0.03) * lado, y_borde - altos[i] * 0.2, Z_COLGANTES), Vector3(90.0, 0.0, 0.0))
	# Cucharones colgados a la izquierda del riel.
	for i in 2:
		var x := 2.45 + i * 0.28
		_pieza(_cilindro(0.016, 0.016, 0.95), madera, Vector3(x, 3.72, Z_COLGANTES))
		_pieza(_esfera(0.08), madera, Vector3(x, 3.2, Z_COLGANTES), Vector3.ZERO, null, Vector3(1.0, 0.45, 0.9))
		_pieza(_cilindro(0.012, 0.012, 0.3), hierro, Vector3(x, 4.05, Z_COLGANTES))


# ---------------------------------------------------------------------------
# Banderines y bombillos
# ---------------------------------------------------------------------------

func _construir_guirnaldas() -> void:
	var colores: Array[Color] = [ROJO, AMARILLO, AZUL]
	_guirnalda(Vector3(-9.0, 5.1, 1.4), Vector3(9.0, 5.1, 1.4), 1.35, 24, 1.5, colores, 1.0, true)
	_guirnalda(Vector3(-9.0, 5.2, -0.3), Vector3(9.0, 5.2, -0.3), 1.2, 28, 1.05, colores, 0.9, true)
	_guirnalda(Vector3(-9.5, 4.5, -1.6), Vector3(9.5, 4.7, -1.6), 0.9, 30, 0.8, colores, 0.55, false)


func _guirnalda(a: Vector3, b: Vector3, caida: float, cantidad: int, escala: float, colores: Array[Color], brillo: float, con_sombra: bool) -> void:
	var cuerda := _pieza(_malla_cuerda(a, b, caida, 0.014), _material_cuerda, Vector3.ZERO)
	var material := _sombreado(SombreadosFondo.BANDERIN)
	material.set_shader_parameter("brillo", brillo)
	var banderines := _pieza(_malla_banderines(a, b, caida, cantidad, escala, colores), material, Vector3.ZERO)
	if not con_sombra:
		cuerda.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		banderines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _construir_bombillos() -> void:
	_cadena_luces(Vector3(-9.0, 5.35, 0.4), Vector3(9.0, 5.35, 0.4), 1.3, 18, 4)


func _cadena_luces(a: Vector3, b: Vector3, caida: float, cantidad: int, luces_cada: int) -> void:
	_pieza(_malla_cuerda(a, b, caida, 0.011), _material_cuerda, Vector3.ZERO)
	var casquillo := _mat(Color(0.08, 0.07, 0.06), 0.6)
	var material_halo := _material_halo(Color(1.0, 0.72, 0.38, 0.55))
	var plano := QuadMesh.new()
	plano.size = Vector2(0.95, 0.95)
	for i in cantidad:
		var p := _punto_cuerda(a, b, caida, (float(i) + 0.5) / cantidad)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(1.0, 0.82, 0.5)
		material.emission_enabled = true
		material.emission = Color(1.0, 0.74, 0.36)
		material.emission_energy_multiplier = 2.6
		_bombillos.append(material)
		var posicion := p + Vector3(0.0, -0.12, 0.0)
		var bulbo := _pieza(_esfera(0.07), material, posicion)
		bulbo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_pieza(_cilindro(0.028, 0.034, 0.08), casquillo, p + Vector3(0.0, -0.045, 0.0))
		var halo := _pieza(plano, material_halo, posicion)
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if i % luces_cada == luces_cada / 2:
			var luz := OmniLight3D.new()
			luz.position = posicion + Vector3(0.0, -0.3, 0.3)
			luz.light_color = Color(1.0, 0.62, 0.28)
			luz.light_energy = 1.5
			luz.omni_range = 8.0
			_mundo.add_child(luz)
			_luces.append(luz)
			_energia_luces.append(luz.light_energy)


# ---------------------------------------------------------------------------
# Comida sobre el mostrador
# ---------------------------------------------------------------------------

func _construir_comida() -> void:
	_olla_de_mute(Vector3(-2.6, 0.0, -0.3))
	_tabla_con_ingredientes(Vector3(-4.15, 0.0, 0.2))
	_plato_de_arepas(Vector3(2.45, 0.0, 0.1))
	_plato_de_empanadas(Vector3(4.1, 0.0, -0.25))
	_cuenco_de_aji(Vector3(3.3, 0.0, 0.6))


func _olla_de_mute(pos: Vector3) -> void:
	var raiz := Node3D.new()
	raiz.position = pos
	_mundo.add_child(raiz)
	var barro := _mat(Color(0.74, 0.37, 0.2), 0.85)
	_pieza(_torno(_perfil_olla_barro()), barro, Vector3.ZERO, Vector3.ZERO, raiz)
	for lado: float in [-1.0, 1.0]:
		var asa := TorusMesh.new()
		asa.inner_radius = 0.045
		asa.outer_radius = 0.1
		_pieza(asa, barro, Vector3(0.6 * lado, 0.55, 0.0), Vector3(90.0, 0.0, 0.0), raiz)
	var caldo := _mat(Color(0.72, 0.36, 0.1), 0.25)
	caldo.emission_enabled = true
	caldo.emission = Color(0.4, 0.17, 0.03)
	_pieza(_cilindro(0.455, 0.455, 0.012), caldo, Vector3(0.0, 0.742, 0.0), Vector3.ZERO, raiz)
	var papa := _mat(Color(0.88, 0.72, 0.42), 0.8)
	var carne := _mat(Color(0.5, 0.22, 0.13), 0.7)
	var maiz := _sombreado(SombreadosFondo.MAIZ)
	var trozos: Array[Vector3] = [Vector3(-0.2, 0.76, 0.1), Vector3(0.12, 0.77, -0.18), Vector3(0.2, 0.76, 0.16), Vector3(-0.1, 0.76, -0.24), Vector3(0.0, 0.77, 0.0)]
	for i in trozos.size():
		_pieza(_esfera(0.09), papa if i % 2 == 0 else carne, trozos[i], Vector3.ZERO, raiz, Vector3(1.0, 0.8, 0.9))
	_pieza(_cilindro(0.06, 0.06, 0.3), maiz, Vector3(-0.05, 0.78, 0.22), Vector3(0.0, 20.0, 90.0), raiz)
	_pieza(_cilindro(0.06, 0.06, 0.28), maiz, Vector3(0.16, 0.78, -0.02), Vector3(0.0, 100.0, 90.0), raiz)
	_vapor(pos + Vector3(0.0, 0.9, 0.0))


func _tabla_con_ingredientes(pos: Vector3) -> void:
	var raiz := Node3D.new()
	raiz.position = pos
	raiz.rotation_degrees = Vector3(0.0, 14.0, 0.0)
	_mundo.add_child(raiz)
	var tabla := _sombreado(SombreadosFondo.MADERA)
	tabla.set_shader_parameter("clara", Color(0.82, 0.6, 0.34))
	tabla.set_shader_parameter("oscura", Color(0.5, 0.32, 0.16))
	_pieza(_caja(Vector3(1.6, 0.08, 1.0)), tabla, Vector3(0.0, 0.04, 0.0), Vector3.ZERO, raiz)
	var papa := _mat(Color(0.82, 0.64, 0.38), 0.85)
	var posiciones: Array[Vector3] = [Vector3(-0.45, 0.19, 0.0), Vector3(-0.15, 0.17, 0.22), Vector3(-0.2, 0.17, -0.25)]
	for i in posiciones.size():
		_pieza(_esfera(0.15), papa, posiciones[i], Vector3(0.0, 40.0 * i, 0.0), raiz, Vector3(1.2, 0.9, 1.0))
	var queso := PrismMesh.new()
	queso.size = Vector3(0.6, 0.34, 0.26)
	var color_queso := _mat(Color(0.98, 0.82, 0.24), 0.45)
	_pieza(queso, color_queso, Vector3(0.45, 0.17, 0.05), Vector3(90.0, 0.0, 0.0), raiz)
	var hueco := _mat(Color(0.75, 0.55, 0.1), 0.6)
	for p: Vector3 in [Vector3(0.35, 0.2, 0.19), Vector3(0.55, 0.12, 0.19)]:
		_pieza(_esfera(0.03), hueco, p, Vector3.ZERO, raiz)
	var maiz := _sombreado(SombreadosFondo.MAIZ)
	_pieza(_cilindro(0.09, 0.07, 0.62), maiz, Vector3(-0.1, 0.17, 0.0), Vector3(0.0, 70.0, 90.0), raiz)
	var metal := _mat(Color(0.68, 0.68, 0.72), 0.3, 0.85)
	_pieza(_caja(Vector3(0.62, 0.012, 0.09)), metal, Vector3(0.7, 0.09, -0.34), Vector3(0.0, 8.0, 0.0), raiz)
	_pieza(_caja(Vector3(0.26, 0.05, 0.08)), _mat(Color(0.1, 0.07, 0.05), 0.6), Vector3(0.28, 0.11, -0.3), Vector3(0.0, 8.0, 0.0), raiz)


func _plato_de_arepas(pos: Vector3) -> void:
	var raiz := Node3D.new()
	raiz.position = pos
	_mundo.add_child(raiz)
	_pieza(_torno(_perfil_plato(0.7)), _material_plato(), Vector3.ZERO, Vector3.ZERO, raiz)
	for i in 2:
		var masa := _sombreado(SombreadosFondo.MASA)
		masa.set_shader_parameter("escala", 4.0 + i)
		_pieza(_cilindro(0.42, 0.44, 0.11), masa, Vector3(0.0, 0.1 + i * 0.12, 0.0), Vector3(0.0, 30.0 * i, 0.0), raiz)
	var queso := _mat(Color(0.99, 0.84, 0.3), 0.4)
	_pieza(_caja(Vector3(0.52, 0.03, 0.4)), queso, Vector3(0.0, 0.28, 0.0), Vector3(0.0, 25.0, 0.0), raiz)


func _plato_de_empanadas(pos: Vector3) -> void:
	var raiz := Node3D.new()
	raiz.position = pos
	_mundo.add_child(raiz)
	_pieza(_torno(_perfil_plato(0.8)), _material_plato(), Vector3.ZERO, Vector3.ZERO, raiz)
	var posiciones: Array[Vector3] = [Vector3(-0.22, 0.14, 0.12), Vector3(0.25, 0.14, 0.05), Vector3(0.0, 0.3, -0.12)]
	for i in posiciones.size():
		var masa := _sombreado(SombreadosFondo.MASA)
		masa.set_shader_parameter("masa", Color(0.98, 0.7, 0.28))
		masa.set_shader_parameter("escala", 5.0 + i)
		_pieza(_esfera(0.3), masa, posiciones[i], Vector3(0.0, 35.0 * i - 20.0, 0.0), raiz, Vector3(1.0, 0.4, 0.68))


func _cuenco_de_aji(pos: Vector3) -> void:
	var raiz := Node3D.new()
	raiz.position = pos
	_mundo.add_child(raiz)
	_pieza(_torno(_perfil_plato(0.3, 0.14)), _material_plato(), Vector3.ZERO, Vector3.ZERO, raiz)
	var aji := _mat(Color(0.8, 0.12, 0.06), 0.2)
	aji.emission_enabled = true
	aji.emission = Color(0.35, 0.04, 0.02)
	_pieza(_cilindro(0.2, 0.2, 0.01), aji, Vector3(0.0, 0.085, 0.0), Vector3.ZERO, raiz)


func _material_plato() -> ShaderMaterial:
	var material := _sombreado(SombreadosFondo.CERAMICA)
	material.set_shader_parameter("base", Color(0.95, 0.9, 0.78))
	material.set_shader_parameter("banda", Color(0.12, 0.3, 0.8))
	material.set_shader_parameter("frecuencia", 9.0)
	return material


# ---------------------------------------------------------------------------
# Partículas
# ---------------------------------------------------------------------------

func _construir_particulas() -> void:
	var material := _material_halo(Color(1.0, 0.92, 0.75, 0.9))
	material.billboard_keep_scale = true
	var punto := QuadMesh.new()
	punto.size = Vector2(0.05, 0.05)
	punto.material = material
	var degradado := Gradient.new()
	degradado.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	degradado.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	var polvo := CPUParticles3D.new()
	polvo.position = Vector3(-1.0, 1.7, -0.3)
	polvo.amount = 90
	polvo.lifetime = 9.0
	polvo.preprocess = 9.0
	polvo.mesh = punto
	polvo.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	polvo.emission_box_extents = Vector3(5.0, 2.4, 1.6)
	polvo.direction = Vector3(0.3, 0.5, 0.0)
	polvo.spread = 180.0
	polvo.gravity = Vector3.ZERO
	polvo.initial_velocity_min = 0.02
	polvo.initial_velocity_max = 0.09
	polvo.scale_amount_min = 0.5
	polvo.scale_amount_max = 1.6
	polvo.color_ramp = degradado
	polvo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mundo.add_child(polvo)


func _vapor(pos: Vector3) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = _textura_halo
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var nube := QuadMesh.new()
	nube.size = Vector2(0.55, 0.55)
	nube.material = material
	var degradado := Gradient.new()
	degradado.set_color(0, Color(1.0, 0.96, 0.9, 0.0))
	degradado.set_color(1, Color(1.0, 0.96, 0.9, 0.0))
	degradado.add_point(0.25, Color(1.0, 0.96, 0.9, 0.5))
	var crecer := Curve.new()
	crecer.add_point(Vector2(0.0, 0.5))
	crecer.add_point(Vector2(1.0, 2.6))
	var vapor := CPUParticles3D.new()
	vapor.position = pos
	vapor.amount = 36
	vapor.lifetime = 3.8
	vapor.preprocess = 3.8
	vapor.mesh = nube
	vapor.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	vapor.emission_sphere_radius = 0.28
	vapor.direction = Vector3.UP
	vapor.spread = 10.0
	vapor.gravity = Vector3(0.0, 0.2, 0.0)
	vapor.initial_velocity_min = 0.3
	vapor.initial_velocity_max = 0.55
	vapor.scale_amount_curve = crecer
	vapor.color_ramp = degradado
	vapor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mundo.add_child(vapor)


# ---------------------------------------------------------------------------
# Mallas y materiales
# ---------------------------------------------------------------------------

## Punto de una cuerda que cuelga entre a y b (parábola con la caída indicada en el centro).
func _punto_cuerda(a: Vector3, b: Vector3, caida: float, t: float) -> Vector3:
	var p := a.lerp(b, t)
	p.y -= caida * 4.0 * t * (1.0 - t)
	return p


## Cuerda delgada de sección cuadrada que sigue la parábola de colgado.
func _malla_cuerda(a: Vector3, b: Vector3, caida: float, radio: float, pasos: int = 36) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var anillos: Array[PackedVector3Array] = []
	var normales: Array[PackedVector3Array] = []
	for i in pasos + 1:
		var centro := _punto_cuerda(a, b, caida, float(i) / pasos)
		var anillo := PackedVector3Array()
		var normal := PackedVector3Array()
		for k in 4:
			var ang := TAU * k / 4.0 + PI / 4.0
			var dir := Vector3(0.0, sin(ang), cos(ang))
			anillo.append(centro + dir * radio)
			normal.append(dir)
		anillos.append(anillo)
		normales.append(normal)
	for i in pasos:
		for k in 4:
			var k2 := (k + 1) % 4
			var quad: Array[Vector2i] = [Vector2i(i, k), Vector2i(i, k2), Vector2i(i + 1, k2), Vector2i(i, k), Vector2i(i + 1, k2), Vector2i(i + 1, k)]
			for v in quad:
				st.set_normal(normales[v.x][v.y])
				st.add_vertex(anillos[v.x][v.y])
	return st.commit()


## Todos los banderines de una cuerda en una sola malla. El color va en el vértice y la fase del viento en UV2.
func _malla_banderines(a: Vector3, b: Vector3, caida: float, cantidad: int, escala: float, colores: Array[Color]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ancho := 0.36 * escala
	var alto := 0.42 * escala
	# Triángulos del banderín en coordenadas (u, v): rectángulo arriba y dos puntas abajo.
	var tri: Array[Vector2] = [
		Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 0.62),
		Vector2(0.0, 0.0), Vector2(1.0, 0.62), Vector2(0.0, 0.62),
		Vector2(0.0, 0.62), Vector2(0.5, 0.62), Vector2(0.25, 0.94),
		Vector2(0.5, 0.62), Vector2(1.0, 0.62), Vector2(0.75, 0.94),
	]
	for i in cantidad:
		var raiz := _punto_cuerda(a, b, caida, (float(i) + 0.5) / cantidad)
		raiz.z += _rng.randf_range(-0.02, 0.02)
		var giro := Basis(Vector3.UP, _rng.randf_range(-0.45, 0.45)) * Basis(Vector3.BACK, _rng.randf_range(-0.08, 0.08))
		var color := colores[i % colores.size()] * _rng.randf_range(0.92, 1.05)
		color.a = 1.0
		var fase := _rng.randf_range(0.0, TAU)
		var normal := giro * Vector3.BACK
		for uv in tri:
			st.set_color(color)
			st.set_uv(uv)
			st.set_uv2(Vector2(fase, 0.0))
			st.set_normal(normal)
			st.add_vertex(raiz + giro * Vector3((uv.x - 0.5) * ancho, -uv.y * alto, 0.0))
	return st.commit()


## Superficie de revolución (ollas, jarras, platos). El perfil va de abajo hacia arriba como (radio, altura):
## primero por fuera y, si está abierto, de vuelta por dentro, para que las normales apunten bien.
func _torno(perfil: Array[Vector2], segmentos: int = 40) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tramos := perfil.size() - 1
	var normales: Array[Vector2] = []
	for i in tramos:
		var d := perfil[i + 1] - perfil[i]
		normales.append(Vector2(d.y, -d.x).normalized())
	for i in tramos:
		var n_ini := normales[i]
		var n_fin := normales[i]
		if i > 0 and normales[i - 1].dot(normales[i]) > 0.75:
			n_ini = (normales[i - 1] + normales[i]).normalized()
		if i < tramos - 1 and normales[i + 1].dot(normales[i]) > 0.75:
			n_fin = (normales[i + 1] + normales[i]).normalized()
		for s in segmentos:
			var c0 := Vector2(cos(TAU * s / segmentos), sin(TAU * s / segmentos))
			var c1 := Vector2(cos(TAU * (s + 1) / segmentos), sin(TAU * (s + 1) / segmentos))
			var u0 := float(s) / segmentos
			var u1 := float(s + 1) / segmentos
			# Orden de las esquinas: B1, B0, A0 y B1, A0, A1 (A = anillo de abajo, B = anillo de arriba).
			_vertice_torno(st, perfil[i + 1], n_fin, c1, u1)
			_vertice_torno(st, perfil[i + 1], n_fin, c0, u0)
			_vertice_torno(st, perfil[i], n_ini, c0, u0)
			_vertice_torno(st, perfil[i + 1], n_fin, c1, u1)
			_vertice_torno(st, perfil[i], n_ini, c0, u0)
			_vertice_torno(st, perfil[i], n_ini, c1, u1)
	return st.commit()


func _vertice_torno(st: SurfaceTool, punto: Vector2, normal: Vector2, ciclo: Vector2, u: float) -> void:
	st.set_normal(Vector3(normal.x * ciclo.x, normal.y, normal.x * ciclo.y))
	st.set_uv(Vector2(u, punto.y))
	st.add_vertex(Vector3(punto.x * ciclo.x, punto.y, punto.x * ciclo.y))


func _perfil_jarra(r: float, h: float) -> Array[Vector2]:
	return [
		Vector2(0.0, 0.0), Vector2(r * 0.85, 0.0), Vector2(r, h * 0.12), Vector2(r * 1.03, h * 0.5),
		Vector2(r * 0.92, h * 0.82), Vector2(r * 0.55, h * 0.92), Vector2(r * 0.5, h), Vector2(0.0, h),
	]


func _perfil_olla(r: float, h: float) -> Array[Vector2]:
	return [
		Vector2(0.0, 0.0), Vector2(r * 0.88, 0.0), Vector2(r * 0.98, h * 0.08), Vector2(r * 1.0, h * 0.5),
		Vector2(r * 1.0, h * 0.94), Vector2(r * 1.06, h * 0.98), Vector2(r * 1.06, h), Vector2(0.0, h),
	]


func _perfil_olla_barro() -> Array[Vector2]:
	return [
		Vector2(0.0, 0.0), Vector2(0.3, 0.0), Vector2(0.45, 0.06), Vector2(0.58, 0.26), Vector2(0.62, 0.44),
		Vector2(0.57, 0.64), Vector2(0.5, 0.78), Vector2(0.53, 0.84), Vector2(0.53, 0.87), Vector2(0.47, 0.87),
		Vector2(0.46, 0.74), Vector2(0.0, 0.74),
	]


## Plato hondo (o cuenco) con borde: radio y alto del borde.
func _perfil_plato(r: float, alto: float = 0.1) -> Array[Vector2]:
	return [
		Vector2(0.0, 0.0), Vector2(r * 0.6, 0.0), Vector2(r * 0.8, alto * 0.4), Vector2(r, alto),
		Vector2(r * 0.97, alto * 1.05), Vector2(r * 0.8, alto * 0.55), Vector2(r * 0.55, alto * 0.18), Vector2(0.0, alto * 0.18),
	]


func _crear_textura_halo() -> GradientTexture2D:
	var degradado := Gradient.new()
	degradado.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	degradado.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.28), Color(1, 1, 1, 0)])
	var textura := GradientTexture2D.new()
	textura.gradient = degradado
	textura.width = 128
	textura.height = 128
	textura.fill = GradientTexture2D.FILL_RADIAL
	textura.fill_from = Vector2(0.5, 0.5)
	textura.fill_to = Vector2(1.0, 0.5)
	return textura


## Material aditivo con la textura del halo, siempre de cara a la cámara (brillos de bombillos y motas de polvo).
func _material_halo(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_texture = _textura_halo
	material.albedo_color = color
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return material


## Crea el material de un shader de SombreadosFondo. Reemplaza //RUIDO por las funciones de ruido y
## comparte el Shader entre materiales iguales.
func _sombreado(codigo: String) -> ShaderMaterial:
	if not _shaders.has(codigo):
		var shader := Shader.new()
		shader.code = codigo.replace("//RUIDO", SombreadosFondo.RUIDO)
		_shaders[codigo] = shader
	var material := ShaderMaterial.new()
	material.shader = _shaders[codigo] as Shader
	return material


func _mat(color: Color, rugosidad: float = 0.85, metalico: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = rugosidad
	material.metallic = metalico
	return material


func _caja(tam: Vector3) -> BoxMesh:
	var malla := BoxMesh.new()
	malla.size = tam
	return malla


func _cilindro(radio_sup: float, radio_inf: float, alto: float) -> CylinderMesh:
	var malla := CylinderMesh.new()
	malla.top_radius = radio_sup
	malla.bottom_radius = radio_inf
	malla.height = alto
	malla.radial_segments = 40
	malla.rings = 1
	return malla


func _esfera(radio: float) -> SphereMesh:
	var malla := SphereMesh.new()
	malla.radius = radio
	malla.height = radio * 2.0
	malla.radial_segments = 24
	malla.rings = 12
	return malla


func _pieza(malla: Mesh, material: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, padre: Node3D = null, escala: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var instancia := MeshInstance3D.new()
	instancia.mesh = malla
	instancia.material_override = material
	instancia.position = pos
	instancia.rotation_degrees = rot
	instancia.scale = escala
	var destino: Node3D = padre if padre != null else _mundo
	destino.add_child(instancia)
	return instancia
