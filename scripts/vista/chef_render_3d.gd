class_name ChefRender3D
extends Node2D
## Muestra un chef 3D (ChefModelo3D) dentro del juego 2D. El chef vive en su propio mundo 3D, dentro de un
## SubViewport pequeno con fondo transparente, y la imagen se pone en pantalla como un Sprite2D. Asi el nodo 2D
## del chef (colisiones, interaccion, orden de dibujo) sigue igual que antes y solo cambia lo que se ve.
## Cada chef lleva su propio viewport de unos 384 x 384 px: es barato, no hay un 3D a pantalla completa.

## Lado, en pixeles del juego, de la imagen que ocupa el chef en pantalla.
const LADO_PANTALLA: float = 256.0
## Lado real del viewport: mayor que el de pantalla para que se vea nitido en monitores grandes.
const LADO_VIEWPORT: int = 384
## Los pies quedan a esta distancia (px) bajo el centro del nodo del chef, igual que en el sprite 2D.
const PIE_Y: float = 30.0

var modelo: ChefModelo3D = null

var _vista: SubViewport = null
var _sprite: Sprite2D = null


func construir(numero_jugador: int) -> void:
	_vista = SubViewport.new()
	_vista.size = Vector2i(LADO_VIEWPORT, LADO_VIEWPORT)
	_vista.transparent_bg = true
	_vista.own_world_3d = true
	_vista.msaa_3d = Viewport.MSAA_4X
	_vista.gui_disable_input = true
	_vista.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vista)
	var mundo := Node3D.new()
	mundo.name = "Mundo3D"
	_vista.add_child(mundo)
	_crear_ambiente(mundo)
	_crear_luz(mundo)
	_crear_camara(mundo)
	_crear_sombra(mundo)
	modelo = ChefModelo3D.new()
	modelo.name = "Chef3D"
	mundo.add_child(modelo)
	modelo.construir(numero_jugador)
	_sprite = Sprite2D.new()
	_sprite.texture = _vista.get_texture()
	_sprite.scale = Vector2.ONE * (LADO_PANTALLA / float(LADO_VIEWPORT))
	_sprite.position = Vector2(0.0, PIE_Y)
	_sprite.show_behind_parent = true
	add_child(_sprite)


## Pasa el estado del chef al modelo. Ver ChefModelo3D.animar para el significado de cada parametro.
func animar(delta: float, velocidad: float, cargando: bool, cortando: bool, golpe: float, sacudida: float, direccion: Vector2) -> void:
	if modelo != null:
		modelo.animar(delta, velocidad, cargando, cortando, golpe, sacudida, direccion)


func _crear_ambiente(mundo: Node3D) -> void:
	var ambiente := Environment.new()
	# Con fondo transparente en el viewport, "color de limpieza" deja ver lo que hay detras.
	ambiente.background_mode = Environment.BG_CLEAR_COLOR
	ambiente.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	ambiente.ambient_light_color = Color(0.82, 0.84, 0.92)
	ambiente.ambient_light_energy = 0.62
	var entorno := WorldEnvironment.new()
	entorno.environment = ambiente
	mundo.add_child(entorno)


## Luz de frente y de lado, para que se note el volumen sin dejar zonas negras.
func _crear_luz(mundo: Node3D) -> void:
	var luz := DirectionalLight3D.new()
	luz.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	luz.light_color = Color(1.0, 0.97, 0.9)
	luz.light_energy = 1.0
	luz.shadow_enabled = false
	mundo.add_child(luz)


func _crear_camara(mundo: Node3D) -> void:
	var camara := Camera3D.new()
	mundo.add_child(camara)
	Proyeccion3D.configurar_camara(camara, LADO_PANTALLA, Vector2.ZERO)
	camara.current = true


## Sombra de contacto: un disco oscuro y difuso en el suelo (los sprites 2D ya traian una dibujada).
func _crear_sombra(mundo: Node3D) -> void:
	var degradado := Gradient.new()
	degradado.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	degradado.colors = PackedColorArray([Color(0.08, 0.05, 0.04, 0.55), Color(0.08, 0.05, 0.04, 0.35), Color(0.08, 0.05, 0.04, 0.0)])
	var textura := GradientTexture2D.new()
	textura.gradient = degradado
	textura.width = 128
	textura.height = 128
	textura.fill = GradientTexture2D.FILL_RADIAL
	textura.fill_from = Vector2(0.5, 0.5)
	textura.fill_to = Vector2(1.0, 0.5)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = textura
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var plano := PlaneMesh.new()
	plano.size = Vector2(1.05, 1.05)
	plano.material = material
	var sombra := MeshInstance3D.new()
	sombra.mesh = plano
	sombra.position = Vector3(0.0, 0.01, 0.0)
	sombra.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mundo.add_child(sombra)
