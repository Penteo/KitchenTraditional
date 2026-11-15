@tool
extends EditorScript
## Verificacion automatica de las animaciones 3D (sin interfaz).
## Como ejecutarla: abrir este script y usar Archivo > Ejecutar (Ctrl+Mayus+X). El resultado sale en la pestana Salida.
## No forma parte del juego: se excluye del build.

var _total: int = 0
var _fallos: int = 0


func _run() -> void:
	print("=== Verificacion de animaciones 3D ===")
	_probar_proyeccion()
	_probar_chef()
	print("=== %d comprobaciones, %d fallos ===" % [_total, _fallos])


func _ok(condicion: bool, descripcion: String) -> void:
	_total += 1
	if not condicion:
		_fallos += 1
	print("%s %s" % ["OK   " if condicion else "FALLA", descripcion])


func _probar_proyeccion() -> void:
	for punto in [Vector2(0, 0), Vector2(960, 540), Vector2(1380, 840), Vector2(-120, 75)]:
		var vuelta := Proyeccion3D.a_pantalla(Proyeccion3D.a_3d(punto))
		_ok(vuelta.distance_to(punto) < 0.01, "suelo %s: a_3d y a_pantalla son inversas" % punto)
	var subida := Proyeccion3D.a_pantalla(Proyeccion3D.a_3d(Vector2.ZERO, 1.0)).y
	_ok(is_equal_approx(subida, -100.0 * cos(Proyeccion3D.inclinacion())), "una unidad de altura sube cos(inclinacion) * 100 px")
	_ok(is_equal_approx(Proyeccion3D.altura_de_pixeles(50.0) * cos(Proyeccion3D.inclinacion()) * 100.0, 50.0), "altura_de_pixeles(50) sube 50 px en pantalla")
	var camara := Camera3D.new()
	Proyeccion3D.configurar_camara(camara, 256.0, Vector2.ZERO)
	_ok(camara.projection == Camera3D.PROJECTION_ORTHOGONAL, "la camara es ortografica")
	_ok(is_equal_approx(camara.size, 2.56), "la camara muestra 256 px de alto")
	camara.free()


func _probar_chef() -> void:
	for numero in [1, 2]:
		var chef := ChefModelo3D.new()
		chef.construir(numero)
		var reposo := _pose(chef, 0.0, false, false, 0.0, 0.0, Vector2.DOWN)
		_ok(absf(reposo["pierna_izq"]) < 0.01, "J%d en reposo: las piernas no se mueven" % numero)
		_ok(not reposo["cuchillo_visible"], "J%d en reposo: sin cuchillo" % numero)
		var balanceo_maximo := 0.0
		var en_oposicion := true
		for i in 60:
			chef.animar(1.0 / 60.0, 1.0, false, false, 0.0, 0.0, Vector2.RIGHT)
			var paso := chef.pose_actual()
			balanceo_maximo = maxf(balanceo_maximo, absf(paso["pierna_izq"]))
			en_oposicion = en_oposicion and is_equal_approx(paso["pierna_izq"], -paso["pierna_der"])
		_ok(balanceo_maximo > 0.3, "J%d al caminar: las piernas se balancean (maximo %.2f rad)" % [numero, balanceo_maximo])
		_ok(en_oposicion, "J%d al caminar: una pierna va en oposicion a la otra" % numero)
		_ok(chef.pose_actual()["yaw"] > 0.5, "J%d al caminar a la derecha: gira hacia la derecha" % numero)
		var cargando := _pose(chef, 0.0, true, false, 0.0, 0.0, Vector2.RIGHT, 1.0)
		_ok(cargando["brazo_izq"] < -0.8 and cargando["brazo_der"] < -0.8, "J%d cargando: los dos brazos van al frente" % numero)
		var cortando := _pose(chef, 0.0, false, true, 1.0, 0.0, Vector2.RIGHT, 1.0)
		_ok(cortando["cuchillo_visible"], "J%d cortando: aparece el cuchillo" % numero)
		chef.free()


## Deja al modelo estabilizarse "segundos" con los parametros dados y devuelve su pose.
func _pose(chef: ChefModelo3D, velocidad: float, cargando: bool, cortando: bool, golpe: float, sacudida: float, direccion: Vector2, segundos: float = 1.0) -> Dictionary:
	var pasos := int(segundos * 60.0)
	for i in maxi(pasos, 1):
		chef.animar(1.0 / 60.0, velocidad, cargando, cortando, golpe, sacudida, direccion)
	return chef.pose_actual()
