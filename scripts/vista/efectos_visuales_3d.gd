class_name EfectosVisuales3D
extends EfectosVisuales
## Version 3D de los efectos de la partida. Hace lo mismo que EfectosVisuales (vapor y humo en las estaciones que
## cocinan, migas al cortar, chispas al ganar puntos) pero con particulas 3D: el vapor sube por el eje vertical y
## se abre en volumen, las migas son cubitos que giran y caen con gravedad, y las chispas salen en todas
## direcciones. Todo se dibuja en una capa 3D transparente a pantalla completa que usa la misma camara inclinada
## que los chefs, asi cada efecto cae justo sobre su estacion 2D. Los puntos flotantes siguen siendo texto 2D.
## Solo escucha senales: no cambia nada de la logica. Se elige en EscenaCocinaView segun Proyeccion3D.ANIMACIONES_3D.

const ANCHO_PANTALLA: float = 1920.0
const ALTO_PANTALLA: float = 1080.0
## Altura (unidades 3D) sobre la estacion desde donde sale el vapor.
const ALTURA_VAPOR: float = 0.5
## Las velocidades 2D de antes (px/s) se pasan a unidades/s con este factor para los movimientos horizontales.
const FACTOR_HORIZONTAL: float = 1.25 / Proyeccion3D.PIXELES_POR_UNIDAD

var _mundo: Node3D = null
var _malla_nube: QuadMesh = null
var _malla_chispa: QuadMesh = null
var _malla_miga: BoxMesh = null


func _ready() -> void:
	_construir_capa()
	_malla_nube = _crear_quad(EfectosVisuales.textura("particula.png"), 0.32)
	_malla_chispa = _crear_quad(EfectosVisuales.textura("chispa.png"), 0.48)
	_malla_miga = _crear_cubo()


## Misma conexion que EfectosVisuales.vincular, pero hacia los efectos 3D.
func vincular(sesion: GameSession, estaciones: Array[Estacion]) -> void:
	for estacion in estaciones:
		if estacion is BarraEntrega:
			_barra = estacion
		var coccion := estacion as EstacionCoccion
		if coccion != null:
			_preparar_vapor_3d(coccion)
		var tabla := estacion as TablaCortar
		if tabla != null:
			tabla.corte_iniciado.connect(_migas_3d.bind(tabla))
	sesion.puntuacion.puntaje_cambiado.connect(_al_cambiar_puntaje_3d)


# --- Capa 3D --------------------------------------------------------------------------------

func _construir_capa() -> void:
	var contenedor := SubViewportContainer.new()
	contenedor.stretch = true
	contenedor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	contenedor.size = Vector2(ANCHO_PANTALLA, ALTO_PANTALLA)
	add_child(contenedor)
	var vista := SubViewport.new()
	vista.transparent_bg = true
	vista.own_world_3d = true
	vista.msaa_3d = Viewport.MSAA_2X
	vista.gui_disable_input = true
	vista.handle_input_locally = false
	contenedor.add_child(vista)
	_mundo = Node3D.new()
	_mundo.name = "Mundo3D"
	vista.add_child(_mundo)
	var ambiente := Environment.new()
	ambiente.background_mode = Environment.BG_CLEAR_COLOR
	ambiente.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	ambiente.ambient_light_color = Color(0.85, 0.86, 0.92)
	ambiente.ambient_light_energy = 0.7
	var entorno := WorldEnvironment.new()
	entorno.environment = ambiente
	_mundo.add_child(entorno)
	var luz := DirectionalLight3D.new()
	luz.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	luz.light_energy = 1.0
	luz.shadow_enabled = false
	_mundo.add_child(luz)
	var camara := Camera3D.new()
	_mundo.add_child(camara)
	Proyeccion3D.configurar_camara(camara, ALTO_PANTALLA, Vector2(ANCHO_PANTALLA, ALTO_PANTALLA) / 2.0)
	camara.current = true


## Cuadro que siempre mira a la camara, con la textura de particula (cuadro blanco si falta el PNG).
func _crear_quad(textura: Texture2D, lado: float) -> QuadMesh:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if textura != null:
		material.albedo_texture = textura
	var malla := QuadMesh.new()
	malla.size = Vector2(lado, lado)
	malla.material = material
	return malla


## Cubito con sombreado de caricatura para las migas.
func _crear_cubo() -> BoxMesh:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var malla := BoxMesh.new()
	malla.size = Vector3(0.07, 0.07, 0.07)
	malla.material = material
	return malla


func _crear_emisor(posicion: Vector3, malla: Mesh) -> CPUParticles3D:
	var emisor := CPUParticles3D.new()
	emisor.position = posicion
	emisor.mesh = malla
	emisor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mundo.add_child(emisor)
	return emisor


# --- Vapor y humo de las estaciones de coccion ----------------------------------------------

func _preparar_vapor_3d(coccion: EstacionCoccion) -> void:
	var emisor := _crear_emisor(Proyeccion3D.a_3d(coccion.position, ALTURA_VAPOR), _malla_nube)
	emisor.emitting = false
	emisor.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	emisor.emission_sphere_radius = 0.12
	emisor.direction = Vector3.UP
	emisor.spread = 25.0
	emisor.gravity = Vector3(0.0, Proyeccion3D.altura_de_pixeles(20.0), 0.0)
	emisor.color_ramp = _rampa(0.25)
	coccion.estado_cambiado.connect(_al_cambiar_estado_3d.bind(coccion, emisor))
	_ajustar_vapor_3d(emisor, coccion.estado)


func _al_cambiar_estado_3d(nuevo: EstacionCoccion.Estado, coccion: EstacionCoccion, emisor: CPUParticles3D) -> void:
	_ajustar_vapor_3d(emisor, nuevo)
	if nuevo == EstacionCoccion.Estado.LISTO:
		_destello_3d(coccion.position, Color(1.0, 0.95, 0.7), 8)


## Mismos valores que el vapor 2D. Las velocidades (px/s en pantalla) se convierten a unidades 3D de altura.
func _ajustar_vapor_3d(emisor: CPUParticles3D, estado: EstacionCoccion.Estado) -> void:
	match estado:
		EstacionCoccion.Estado.VACIA:
			emisor.emitting = false
			return
		EstacionCoccion.Estado.PROCESANDO:
			_configurar_vapor_3d(emisor, 6, 1.4, 20.0, 35.0, 0.5, 0.9, Color(1.0, 1.0, 1.0, 0.7))
		EstacionCoccion.Estado.LISTO:
			_configurar_vapor_3d(emisor, 10, 1.4, 30.0, 50.0, 0.6, 1.0, Color(1.0, 0.95, 0.75, 0.85))
		EstacionCoccion.Estado.PELIGRO:
			_configurar_vapor_3d(emisor, 14, 0.9, 40.0, 70.0, 0.6, 1.0, Color(0.6, 0.6, 0.62, 0.9))
		EstacionCoccion.Estado.QUEMADO:
			_configurar_vapor_3d(emisor, 14, 1.8, 35.0, 60.0, 0.8, 1.4, Color(0.14, 0.12, 0.12, 0.95))
	emisor.emitting = true


func _configurar_vapor_3d(emisor: CPUParticles3D, cantidad: int, vida: float, v_min: float, v_max: float, e_min: float, e_max: float, color: Color) -> void:
	emisor.amount = cantidad
	emisor.lifetime = vida
	emisor.initial_velocity_min = Proyeccion3D.altura_de_pixeles(v_min)
	emisor.initial_velocity_max = Proyeccion3D.altura_de_pixeles(v_max)
	emisor.scale_amount_min = e_min
	emisor.scale_amount_max = e_max
	emisor.color = color


# --- Migas y chispas ------------------------------------------------------------------------

## Cubitos que saltan de la tabla, giran y caen.
func _migas_3d(tabla: TablaCortar) -> void:
	var emisor := _crear_emisor(Proyeccion3D.a_3d(tabla.position, 0.2), _malla_miga)
	emisor.one_shot = true
	emisor.amount = 10
	emisor.lifetime = 0.55
	emisor.explosiveness = 1.0
	emisor.direction = Vector3.UP
	emisor.spread = 55.0
	emisor.gravity = Vector3(0.0, -Proyeccion3D.altura_de_pixeles(500.0), 0.0)
	emisor.initial_velocity_min = Proyeccion3D.altura_de_pixeles(90.0)
	emisor.initial_velocity_max = Proyeccion3D.altura_de_pixeles(170.0)
	emisor.particle_flag_rotate_y = true
	emisor.angular_velocity_min = -540.0
	emisor.angular_velocity_max = 540.0
	emisor.scale_amount_min = 0.8
	emisor.scale_amount_max = 1.4
	emisor.color = Color(0.96, 0.86, 0.58)
	emisor.emitting = true
	_autodestruir(emisor, 1.1)


func _destello_3d(punto: Vector2, color: Color, cantidad: int) -> void:
	var emisor := _crear_emisor(Proyeccion3D.a_3d(punto, 0.15), _malla_chispa)
	emisor.one_shot = true
	emisor.amount = cantidad
	emisor.lifetime = 0.8
	emisor.explosiveness = 1.0
	emisor.direction = Vector3.UP
	emisor.spread = 120.0
	emisor.gravity = Vector3(0.0, -Proyeccion3D.altura_de_pixeles(260.0), 0.0)
	emisor.initial_velocity_min = 120.0 * FACTOR_HORIZONTAL
	emisor.initial_velocity_max = 260.0 * FACTOR_HORIZONTAL
	emisor.scale_amount_min = 0.35
	emisor.scale_amount_max = 0.7
	emisor.color = color
	emisor.color_ramp = _rampa(0.7, true)
	emisor.emitting = true
	_autodestruir(emisor, 1.3)


func _al_cambiar_puntaje_3d(_puntos: int, cambio: int) -> void:
	if cambio == 0:
		return
	var punto := _posicion_barra()
	if cambio > 0:
		_destello_3d(punto, Color(1.0, 0.85, 0.3), 16)
		_texto_flotante("+%d" % cambio, punto, COLOR_GANA)
	else:
		_texto_flotante("%d" % cambio, punto, COLOR_PIERDE)
