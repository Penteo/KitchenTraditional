class_name ChefModelo3D
extends Node3D
## Chef en 3D hecho solo con formas primitivas (esferas, capsulas, cilindros), sin modelos ni imagenes externas:
## no hay nada que licenciar (RNF-06). Se ve como los sprites de antes: sombreado de caricatura y contorno oscuro.
## El jugador 1 lleva gorro de chef y delantal azul; el jugador 2, sombrero de paja y delantal rojo.
##
## Se anima por codigo (sin AnimationPlayer): caminar, reposo con respiracion, cargar un item con los dos brazos,
## cortar con cuchillo, sacudir la cabeza en una accion invalida y un pequeno rebote al tomar o soltar un item.
## Solo muestra; ChefView es quien sabe el estado del chef y llama a animar() cada fotograma.
##
## Convencion: el modelo mira hacia +Z (hacia la camara cuando el chef mira "abajo" en pantalla).
## "Izquierdo" y "derecho" se refieren al lado de la pantalla, no al del personaje.

const ESCALA_MODELO: float = 0.92
## Zancadas completas por segundo al correr a toda velocidad (los sprites 2D hacian 4 fotogramas a 12 fps).
const ZANCADAS_POR_SEGUNDO: float = 3.0
const SUAVIZADO_POSE: float = 14.0
const SUAVIZADO_GIRO: float = 16.0
## Mismas frecuencias que usaba ChefView en 2D para el golpe de corte y la sacudida.
const FRECUENCIA_CORTE: float = 22.0
const FRECUENCIA_SACUDIDA: float = 34.0
const ALTURA_CADERA: float = 0.42
const GROSOR_CONTORNO: float = 0.022
## Con la camara inclinada, alzar un poco la cabeza y el sombrero deja ver la cara.
const CABEZA_ALZADA: float = -0.18
const SOMBRERO_ALZADO: float = -0.3

const CODIGO_CONTORNO: String = """
shader_type spatial;
render_mode unshaded, cull_front;

uniform float grosor = 0.022;

void vertex() {
	VERTEX += NORMAL * grosor;
}

void fragment() {
	ALBEDO = vec3(0.17, 0.09, 0.05);
}
"""

const COLOR_BATA := Color(0.97, 0.96, 0.92)
const COLOR_PANTALON := Color(0.9, 0.88, 0.82)
const COLOR_ZAPATO := Color(0.35, 0.22, 0.13)
const COLOR_PELO := Color(0.22, 0.12, 0.06)
const COLOR_OJO := Color(0.1, 0.06, 0.05)
const COLOR_MEJILLA := Color(0.95, 0.5, 0.45)
const COLOR_ACERO := Color(0.86, 0.89, 0.93)
const COLOR_MANGO := Color(0.4, 0.25, 0.15)

static var _material_contorno: ShaderMaterial = null

var _construido: bool = false
var _numero_jugador: int = 1
var _raiz: Node3D = null
var _cuerpo: Node3D = null
var _torso: MeshInstance3D = null
var _cabeza: Node3D = null
var _sombrero: Node3D = null
var _pierna_izq: Node3D = null
var _pierna_der: Node3D = null
var _brazo_izq: Node3D = null
var _brazo_der: Node3D = null
var _cuchillo: Node3D = null

var _tiempo: float = 0.0
var _fase_paso: float = 0.0
var _yaw: float = 0.0
var _peso_caminar: float = 0.0
var _peso_carga: float = 0.0
var _peso_corte: float = 0.0
var _pulso: float = 0.0


## Arma el cuerpo. Se llama una vez, despues de crear el nodo.
func construir(numero_jugador: int) -> void:
	if _construido:
		return
	_construido = true
	_numero_jugador = numero_jugador
	scale = Vector3.ONE * ESCALA_MODELO
	_raiz = Node3D.new()
	_raiz.name = "Raiz"
	add_child(_raiz)
	var azul := numero_jugador == 1
	var piel := Color(0.89, 0.66, 0.47) if azul else Color(0.78, 0.53, 0.35)
	var delantal := Color(0.16, 0.41, 0.97) if azul else Color(0.85, 0.25, 0.16)
	_construir_piernas()
	_construir_cuerpo(delantal)
	_construir_cabeza(piel)
	_construir_brazos(piel)
	if azul:
		_construir_gorro(delantal)
	else:
		_construir_sombrero_paja(delantal)
	_construir_cuchillo()


## Un pequeno rebote del cuerpo: ChefView lo pide al tomar o soltar un item.
func pulso() -> void:
	_pulso = 1.0


## Avanza la animacion. ChefView ya conoce el estado del chef y se lo pasa:
##  velocidad: 0 a 1, fraccion de la velocidad maxima.
##  cargando: lleva un item en las manos.
##  cortando: esta cortando en una tabla.
##  golpe: 0 a 1, fuerza del golpe de corte en este instante.
##  sacudida: 0 a 1, intensidad del "no" de una accion invalida (baja hasta 0 sola).
##  direccion: hacia donde mira, en el plano 2D del juego (x a la derecha, y hacia abajo).
func animar(delta: float, velocidad: float, cargando: bool, cortando: bool, golpe: float, sacudida: float, direccion: Vector2) -> void:
	if not _construido:
		return
	_tiempo += delta
	var suavizado := 1.0 - exp(-delta * SUAVIZADO_POSE)
	_peso_caminar = lerpf(_peso_caminar, clampf(velocidad, 0.0, 1.0), suavizado)
	_peso_carga = lerpf(_peso_carga, 1.0 if cargando else 0.0, suavizado)
	_peso_corte = lerpf(_peso_corte, 1.0 if cortando else 0.0, suavizado)
	_pulso = maxf(0.0, _pulso - delta * 5.0)
	_fase_paso = fposmod(_fase_paso + delta * TAU * ZANCADAS_POR_SEGUNDO * _peso_caminar, TAU)
	# El chef gira suavemente hacia donde mira, en lugar de saltar entre tres vistas.
	if direccion != Vector2.ZERO:
		_yaw = lerp_angle(_yaw, atan2(direccion.x, direccion.y), 1.0 - exp(-delta * SUAVIZADO_GIRO))
	_raiz.rotation.y = _yaw
	_aplicar_pose(golpe, sacudida)


## Valores de la pose actual (para las pruebas automaticas).
func pose_actual() -> Dictionary:
	return {
		"pierna_izq": _pierna_izq.rotation.x,
		"pierna_der": _pierna_der.rotation.x,
		"brazo_izq": _brazo_izq.rotation.x,
		"brazo_der": _brazo_der.rotation.x,
		"cuchillo_visible": _cuchillo.visible,
		"yaw": _raiz.rotation.y,
		"cabeza_yaw": _cabeza.rotation.y,
	}


func _aplicar_pose(golpe: float, sacudida: float) -> void:
	var caminar := _peso_caminar
	var carga := _peso_carga
	var corte := _peso_corte
	var paso := sin(_fase_paso)
	var rebote := absf(paso)
	var respiro := sin(_tiempo * 2.4)

	# Piernas: se balancean en oposicion.
	_pierna_izq.rotation.x = paso * 0.75 * caminar
	_pierna_der.rotation.x = -paso * 0.75 * caminar

	# Cuerpo: sube y baja con cada paso, se inclina al avanzar y se agacha para cortar.
	var inclinacion := 0.11 * caminar + 0.2 * corte
	_cuerpo.position.y = ALTURA_CADERA + rebote * 0.05 * caminar - 0.05 * corte - 0.03 * golpe * corte + 0.04 * sin(_pulso * PI)
	_cuerpo.rotation = Vector3(inclinacion, 0.0, paso * 0.07 * caminar)
	var apretar := sin(_pulso * PI) * 0.12
	_torso.scale = Vector3(1.0 + 0.012 * respiro + apretar * 0.5, 1.0 + 0.02 * respiro - apretar, 1.0 + 0.012 * respiro + apretar * 0.5)

	# Cabeza: contrarresta la inclinacion, mira hacia abajo al cortar y dice "no" en una accion invalida.
	var no := sin(_tiempo * FRECUENCIA_SACUDIDA) * sacudida
	_cabeza.rotation = Vector3(CABEZA_ALZADA - inclinacion * 0.6 + 0.25 * corte + sin(_tiempo * 1.7) * 0.02 * (1.0 - caminar), no * 0.6, no * 0.12)
	# El sombrero se mueve un poco detras de la cabeza.
	_sombrero.rotation = Vector3(SOMBRERO_ALZADO - (0.05 if _numero_jugador == 2 else 0.0) + sin(_fase_paso * 2.0 + 1.0) * 0.05 * caminar, 0.0, sin(_fase_paso + 0.6) * 0.06 * caminar)

	# Brazos. Al caminar se balancean en oposicion a las piernas.
	var braceo := paso * 0.85 * caminar * (1.0 - carga)
	var x_izq := -braceo
	var x_der := braceo
	var z_izq := 0.1
	var z_der := -0.1
	# Cargando: los dos brazos al frente, juntos, subiendo un poco con cada paso.
	var x_carga := -1.2 + rebote * 0.06 * caminar + respiro * 0.02
	x_izq = lerpf(x_izq, x_carga, carga)
	x_der = lerpf(x_der, x_carga, carga)
	z_izq = lerpf(z_izq, -0.3, carga)
	z_der = lerpf(z_der, 0.3, carga)
	# Cortando: el brazo derecho sube y baja con el cuchillo y el izquierdo sostiene el ingrediente.
	var elevacion := 1.0 - golpe
	x_der = lerpf(x_der, lerpf(-1.35, -2.45, elevacion), corte)
	z_der = lerpf(z_der, 0.1, corte)
	x_izq = lerpf(x_izq, -0.95 + 0.06 * sin(_tiempo * FRECUENCIA_CORTE), corte)
	z_izq = lerpf(z_izq, -0.2, corte)
	_brazo_izq.rotation = Vector3(x_izq, 0.0, z_izq)
	_brazo_der.rotation = Vector3(x_der, 0.0, z_der)
	_cuchillo.visible = corte > 0.35


# --- Construccion del cuerpo -----------------------------------------------------------------

func _construir_piernas() -> void:
	_pierna_izq = _crear_pierna(0.11)
	_pierna_der = _crear_pierna(-0.11)


func _crear_pierna(x: float) -> Node3D:
	var pierna := Node3D.new()
	pierna.position = Vector3(x, ALTURA_CADERA, 0.0)
	_raiz.add_child(pierna)
	_parte(pierna, _capsula(0.08, 0.34), COLOR_PANTALON, Vector3(0.0, -0.18, 0.0))
	var zapato := _parte(pierna, _capsula(0.07, 0.26), COLOR_ZAPATO, Vector3(0.0, -0.35, 0.05))
	zapato.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	return pierna


func _construir_cuerpo(delantal: Color) -> void:
	# El cuerpo gira alrededor de la cadera, asi la inclinacion al caminar sale natural.
	_cuerpo = Node3D.new()
	_cuerpo.position = Vector3(0.0, ALTURA_CADERA, 0.0)
	_raiz.add_child(_cuerpo)
	_torso = _parte(_cuerpo, _esfera(0.25, 0.56), COLOR_BATA, Vector3(0.0, 0.28, 0.0))
	var peto := _parte(_cuerpo, _esfera(0.17, 0.4), delantal, Vector3(0.0, 0.25, 0.2), false)
	peto.scale = Vector3(1.0, 1.0, 0.45)
	# Panuelo del cuello con el color del delantal.
	var panuelo := _parte(_cuerpo, _esfera(0.1, 0.08), delantal, Vector3(0.0, 0.55, 0.12), false)
	panuelo.scale = Vector3(1.4, 1.0, 1.0)


func _construir_cabeza(piel: Color) -> void:
	_cabeza = Node3D.new()
	_cabeza.position = Vector3(0.0, 0.76, 0.0)
	_cuerpo.add_child(_cabeza)
	_parte(_cabeza, _esfera(0.24, 0.46), piel, Vector3.ZERO)
	# El pelo cubre la parte de atras y los costados; por delante se ve la cara.
	_parte(_cabeza, _esfera(0.245, 0.46), COLOR_PELO, Vector3(0.0, 0.01, -0.045))
	for lado in [-1.0, 1.0]:
		_parte(_cabeza, _esfera(0.03, 0.045), COLOR_OJO, Vector3(0.085 * lado, 0.02, 0.212), false)
		var mejilla := _parte(_cabeza, _esfera(0.04, 0.05), COLOR_MEJILLA, Vector3(0.14 * lado, -0.05, 0.172), false)
		mejilla.scale = Vector3(1.0, 0.8, 0.45)
	_parte(_cabeza, _esfera(0.035, 0.05), piel.darkened(0.06), Vector3(0.0, -0.02, 0.238), false)
	var boca := _parte(_cabeza, _capsula(0.011, 0.07), COLOR_OJO, Vector3(0.0, -0.095, 0.212), false)
	boca.rotation_degrees = Vector3(0.0, 0.0, 90.0)


func _construir_brazos(piel: Color) -> void:
	_brazo_izq = _crear_brazo(0.27, piel)
	_brazo_der = _crear_brazo(-0.27, piel)


func _crear_brazo(x: float, piel: Color) -> Node3D:
	var brazo := Node3D.new()
	brazo.position = Vector3(x, 0.46, 0.0)
	_cuerpo.add_child(brazo)
	_parte(brazo, _capsula(0.065, 0.3), COLOR_BATA, Vector3(0.0, -0.13, 0.0))
	_parte(brazo, _esfera(0.07, 0.14), piel, Vector3(0.0, -0.29, 0.0))
	return brazo


## Gorro de chef blanco con banda del color del delantal (jugador 1).
func _construir_gorro(banda: Color) -> void:
	_sombrero = Node3D.new()
	_sombrero.position = Vector3(0.0, 0.13, -0.02)
	_cabeza.add_child(_sombrero)
	_parte(_sombrero, _cilindro(0.205, 0.205, 0.1), COLOR_BATA, Vector3(0.0, 0.04, 0.0), false)
	_parte(_sombrero, _cilindro(0.209, 0.209, 0.026), banda, Vector3(0.0, 0.04, 0.0), false)
	_parte(_sombrero, _esfera(0.19, 0.26), COLOR_BATA, Vector3(0.0, 0.22, 0.0))
	for desplazamiento in [Vector3(0.14, 0.17, 0.0), Vector3(-0.14, 0.17, 0.0), Vector3(0.0, 0.17, 0.13), Vector3(0.0, 0.17, -0.13)]:
		_parte(_sombrero, _esfera(0.12, 0.2), COLOR_BATA, desplazamiento)


## Sombrero de paja de ala ancha con cinta del color del delantal (jugador 2).
func _construir_sombrero_paja(cinta: Color) -> void:
	_sombrero = Node3D.new()
	_sombrero.position = Vector3(0.0, 0.09, -0.02)
	_cabeza.add_child(_sombrero)
	var paja := Color(0.91, 0.85, 0.66)
	_parte(_sombrero, _cilindro(0.33, 0.33, 0.03), paja.darkened(0.25), Vector3(0.0, -0.005, 0.0), false)
	_parte(_sombrero, _cilindro(0.318, 0.318, 0.035), paja, Vector3(0.0, 0.01, 0.0), false)
	_parte(_sombrero, _esfera(0.19, 0.26), paja, Vector3(0.0, 0.09, 0.0))
	_parte(_sombrero, _cilindro(0.193, 0.193, 0.04), cinta, Vector3(0.0, 0.05, 0.0), false)


func _construir_cuchillo() -> void:
	# Va en la mano derecha y sigue la direccion del brazo: al levantar el brazo hacia el frente, la hoja apunta adelante.
	_cuchillo = Node3D.new()
	_cuchillo.position = Vector3(0.0, -0.29, 0.0)
	_cuchillo.visible = false
	_brazo_der.add_child(_cuchillo)
	_parte(_cuchillo, _cilindro(0.02, 0.02, 0.12), COLOR_MANGO, Vector3(0.0, -0.02, 0.0), false)
	var hoja := MeshInstance3D.new()
	var malla := BoxMesh.new()
	malla.size = Vector3(0.02, 0.2, 0.07)
	hoja.mesh = malla
	hoja.material_override = _material(COLOR_ACERO, false)
	hoja.position = Vector3(0.0, -0.17, 0.0)
	_cuchillo.add_child(hoja)


# --- Mallas y materiales ---------------------------------------------------------------------

func _parte(padre: Node3D, malla: Mesh, color: Color, posicion: Vector3, contorno: bool = true) -> MeshInstance3D:
	var instancia := MeshInstance3D.new()
	instancia.mesh = malla
	instancia.material_override = _material(color, contorno)
	instancia.position = posicion
	instancia.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if Escenario3D.SOMBRAS else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	padre.add_child(instancia)
	return instancia


func _material(color: Color, contorno: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if contorno:
		material.next_pass = _contorno()
	return material


## El contorno es una segunda pasada: la misma malla un poco inflada, de adentro hacia afuera y en color oscuro.
static func _contorno() -> ShaderMaterial:
	if _material_contorno == null:
		var sombreado := Shader.new()
		sombreado.code = CODIGO_CONTORNO
		_material_contorno = ShaderMaterial.new()
		_material_contorno.shader = sombreado
		_material_contorno.set_shader_parameter("grosor", GROSOR_CONTORNO)
	return _material_contorno


func _esfera(radio: float, alto: float) -> SphereMesh:
	var malla := SphereMesh.new()
	malla.radius = radio
	malla.height = alto
	malla.radial_segments = 24
	malla.rings = 12
	return malla


func _capsula(radio: float, alto: float) -> CapsuleMesh:
	var malla := CapsuleMesh.new()
	malla.radius = radio
	malla.height = alto
	malla.radial_segments = 16
	malla.rings = 4
	return malla


func _cilindro(radio_superior: float, radio_inferior: float, alto: float) -> CylinderMesh:
	var malla := CylinderMesh.new()
	malla.top_radius = radio_superior
	malla.bottom_radius = radio_inferior
	malla.height = alto
	malla.radial_segments = 24
	malla.rings = 1
	return malla
