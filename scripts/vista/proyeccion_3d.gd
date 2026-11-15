class_name Proyeccion3D
extends RefCounted
## Puente entre el mundo 2D del juego (pixeles) y el mundo 3D de las animaciones.
##
## El juego sigue siendo 2D: fisicas, colisiones, estaciones y HUD no cambian. Lo unico que es 3D son las
## animaciones (el chef y los efectos), que se dibujan con una camara ortografica inclinada. Para que lo 3D
## caiga exactamente donde esta el objeto 2D se usa esta correspondencia:
##   - 100 px del juego = 1 unidad 3D.
##   - El suelo se estira por 1 / sen(inclinacion) en Z, y asi la camara inclinada lo muestra 1:1 con los pixeles.
##   - Cada unidad de altura (Y) sube cos(inclinacion) * 100 px en la pantalla.
## Si se cambia la inclinacion, todo sigue alineado: solo cambia cuanto "se ve" la altura de los modelos.

## Interruptor general. En false el juego vuelve a usar los sprites 2D y las particulas 2D de antes.
const ANIMACIONES_3D: bool = true

const PIXELES_POR_UNIDAD: float = 100.0
## Angulo de la camara respecto al horizonte: 90 seria vista cenital pura y menos de 45 ya parece de lado.
const INCLINACION_GRADOS: float = 50.0
const DISTANCIA_CAMARA: float = 30.0


static func inclinacion() -> float:
	return deg_to_rad(INCLINACION_GRADOS)


## Punto del suelo 2D (en pixeles) a posicion 3D, con una altura opcional en unidades.
static func a_3d(punto: Vector2, altura: float = 0.0) -> Vector3:
	return Vector3(punto.x / PIXELES_POR_UNIDAD, altura, punto.y / PIXELES_POR_UNIDAD / sin(inclinacion()))


## Donde cae un punto 3D en la pantalla del juego (en pixeles). Es la inversa de a_3d.
static func a_pantalla(punto: Vector3) -> Vector2:
	var angulo := inclinacion()
	return Vector2(punto.x, punto.z * sin(angulo) - punto.y * cos(angulo)) * PIXELES_POR_UNIDAD


## Unidades de altura 3D necesarias para subir "pixeles" en la pantalla.
## Sirve para convertir velocidades y gravedades de las particulas 2D de antes.
static func altura_de_pixeles(pixeles: float) -> float:
	return pixeles / PIXELES_POR_UNIDAD / cos(inclinacion())


## Deja la camara ortografica mirando el centro (en pixeles del juego) de una vista de "alto_px" de alto.
## El centro de la imagen 3D queda exactamente sobre ese punto del suelo 2D.
static func configurar_camara(camara: Camera3D, alto_px: float, centro_px: Vector2) -> void:
	var angulo := inclinacion()
	camara.projection = Camera3D.PROJECTION_ORTHOGONAL
	camara.keep_aspect = Camera3D.KEEP_HEIGHT
	camara.size = alto_px / PIXELES_POR_UNIDAD
	camara.near = 0.05
	camara.far = 80.0
	camara.position = a_3d(centro_px) + Vector3(0.0, sin(angulo), cos(angulo)) * DISTANCIA_CAMARA
	camara.rotation = Vector3(-angulo, 0.0, 0.0)
