class_name SombreadosFondo
extends RefCounted
## Código de los shaders del fondo 3D del menú (FondoMenu3D). Todo es procedural: sin imágenes ni licencias.
## Los identificadores del GLSL van sin tildes a propósito.

## Funciones de ruido compartidas. Los shaders que las usan llevan la línea //RUIDO y FondoMenu3D la reemplaza por este texto.
const RUIDO: String = """
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float ruido(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * ruido(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}
"""

## Pared: zócalo de azulejos de talavera, friso tricolor y yeso envejecido arriba.
const PARED: String = """
shader_type spatial;

uniform vec3 yeso_claro : source_color = vec3(0.40, 0.15, 0.10);
uniform vec3 yeso_oscuro : source_color = vec3(0.17, 0.065, 0.055);
uniform vec3 azulejo_base : source_color = vec3(0.07, 0.17, 0.46);
uniform vec3 azulejo_motivo : source_color = vec3(0.95, 0.86, 0.64);
uniform float altura_zocalo = 0.95;
uniform float lado_azulejo = 0.36;

varying vec3 pos_mundo;
//RUIDO


void vertex() {
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = pos_mundo.xy;
	vec3 color;
	float rugosidad = 0.95;
	float grano = fbm(p * 7.0);
	if (p.y < altura_zocalo) {
		vec2 celda = p / lado_azulejo;
		vec2 id = floor(celda);
		vec2 f = fract(celda) - 0.5;
		float borde = 0.5 - max(abs(f.x), abs(f.y));
		float lechada = smoothstep(0.012, 0.04, borde);
		float rombo = abs(f.x) + abs(f.y);
		float anillo = 1.0 - smoothstep(0.012, 0.032, abs(rombo - 0.30));
		float punto = 1.0 - smoothstep(0.05, 0.075, length(f));
		float esquina = 1.0 - smoothstep(0.10, 0.13, length(abs(f) - vec2(0.5)));
		float marca = clamp(anillo + punto + esquina, 0.0, 1.0);
		vec3 base = azulejo_base * (0.85 + 0.35 * hash(id));
		color = mix(base, azulejo_motivo, marca);
		color += vec3(0.07) * (1.0 - smoothstep(0.0, 0.5, length(f)));
		color = mix(vec3(0.09, 0.07, 0.06), color, lechada);
		rugosidad = mix(0.9, 0.28, lechada);
	} else {
		float manchas = fbm(p * 0.8 + 3.0);
		color = mix(yeso_claro, yeso_oscuro, smoothstep(0.25, 0.75, manchas));
		color *= 0.76 + 0.45 * grano;
		float yz = p.y - altura_zocalo;
		if (yz < 0.05) {
			color = vec3(0.34, 0.19, 0.10) * (0.8 + 0.4 * grano);
		} else if (yz < 0.21) {
			float w = 0.2;
			vec2 q = vec2(mod(p.x, w) - w * 0.5, yz - 0.13);
			float rb = abs(q.x) + abs(q.y) * 1.25;
			float k = mod(floor(p.x / w), 3.0);
			vec3 tono = k < 0.5 ? vec3(0.88, 0.24, 0.15) : (k < 1.5 ? vec3(0.97, 0.75, 0.18) : vec3(0.16, 0.38, 0.9));
			float dentro = 1.0 - smoothstep(0.07, 0.085, rb);
			color = mix(color * 0.8, tono, dentro);
		}
	}
	ALBEDO = color;
	ROUGHNESS = rugosidad;
}
"""

## Madera de tablones con veta y juntas. Los tablones corren a lo largo de X.
const MADERA: String = """
shader_type spatial;

uniform vec3 clara : source_color = vec3(0.68, 0.43, 0.22);
uniform vec3 oscura : source_color = vec3(0.32, 0.18, 0.09);
uniform float ancho_tablon = 0.46;

varying vec3 pos_obj;
//RUIDO


void vertex() {
	pos_obj = VERTEX;
}

void fragment() {
	vec3 p = pos_obj;
	float a = p.z + p.y;
	float tablon = floor(a / ancho_tablon);
	float local = fract(a / ancho_tablon);
	float veta = fbm(vec2(p.x * 1.5 + tablon * 7.3, a * 24.0));
	vec3 color = mix(oscura, clara, smoothstep(0.2, 0.8, veta));
	color *= 0.82 + 0.3 * hash(vec2(tablon, 3.0));
	float junta = smoothstep(0.0, 0.03, local) * smoothstep(1.0, 0.97, local);
	color *= mix(0.3, 1.0, junta);
	ALBEDO = color;
	ROUGHNESS = 0.5 + 0.3 * (1.0 - veta);
}
"""

## Cobre estilizado: sin reflejos reales, con un entorno falso (cálido arriba, oscuro abajo) y borde brillante.
const COBRE: String = """
shader_type spatial;

uniform vec3 cobre : source_color = vec3(0.88, 0.46, 0.22);

varying vec3 pos_obj;

void vertex() {
	pos_obj = VERTEX;
}

void fragment() {
	vec3 n_mundo = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	float cielo = smoothstep(-0.5, 0.9, n_mundo.y);
	vec3 entorno = mix(vec3(0.08, 0.04, 0.03), vec3(1.0, 0.74, 0.46), cielo);
	float martillado = 0.9 + 0.1 * sin(pos_obj.y * 70.0 + pos_obj.x * 40.0);
	ALBEDO = cobre * 0.38 * martillado;
	METALLIC = 0.55;
	ROUGHNESS = 0.32;
	EMISSION = cobre * entorno * 0.42 + vec3(1.0, 0.78, 0.55) * fresnel * 0.3;
}
"""

## Banderines de papel picado: se mecen con el viento, llevan el rombo oscuro y brillan un poco con la luz de atrás.
const BANDERIN: String = """
shader_type spatial;
render_mode cull_disabled;

uniform float viento = 1.0;
uniform float brillo = 1.0;

varying vec3 color_v;
//RUIDO


void vertex() {
	color_v = COLOR.rgb;
	float t = TIME * 1.7 + UV2.x;
	float colgado = UV.y;
	VERTEX.x += sin(t) * 0.05 * colgado * viento;
	VERTEX.z += sin(t * 1.3 + 1.2) * 0.09 * colgado * viento;
	VERTEX.y += (cos(t) - 1.0) * 0.012 * colgado * viento;
}

void fragment() {
	vec2 c = vec2(UV.x - 0.5, UV.y - 0.34);
	float rombo = abs(c.x) + abs(c.y) * 0.95;
	float marca = 1.0 - smoothstep(0.115, 0.135, rombo);
	float fibra = 0.94 + 0.06 * hash(floor(UV * 90.0));
	vec3 col = mix(color_v, color_v * 0.2, marca) * fibra * brillo;
	ALBEDO = col;
	ROUGHNESS = 0.9;
	EMISSION = col * 0.28;
}
"""

## Masa asada (arepa, empanada): dorado con manchas tostadas.
const MASA: String = """
shader_type spatial;

uniform vec3 masa : source_color = vec3(0.97, 0.77, 0.36);
uniform vec3 tostado : source_color = vec3(0.60, 0.31, 0.09);
uniform float escala = 5.0;
uniform float cantidad = 0.55;

varying vec3 pos_obj;
//RUIDO


void vertex() {
	pos_obj = VERTEX;
}

void fragment() {
	float n = fbm(pos_obj.xz * escala + pos_obj.y * 3.0 + 11.0);
	float m = smoothstep(cantidad - 0.1, cantidad + 0.1, n);
	vec3 color = mix(masa, tostado, m * 0.85);
	color *= 0.9 + 0.2 * hash(floor(pos_obj.xz * 45.0));
	ALBEDO = color;
	ROUGHNESS = 0.78;
}
"""

## Mazorca de maíz: granos en filas alternadas.
const MAIZ: String = """
shader_type spatial;

varying vec3 pos_obj;

void vertex() {
	pos_obj = VERTEX;
}

void fragment() {
	float ang = atan(pos_obj.z, pos_obj.x) / 6.2832 * 16.0;
	vec2 g = vec2(ang, pos_obj.y * 22.0);
	g.y += mod(floor(g.x), 2.0) * 0.5;
	vec2 f = fract(g) - 0.5;
	float grano = 1.0 - smoothstep(0.28, 0.5, length(f * vec2(1.0, 0.9)));
	ALBEDO = mix(vec3(0.5, 0.32, 0.04), vec3(1.0, 0.82, 0.16), grano);
	ROUGHNESS = 0.4;
}
"""

## Cerámica vidriada con bandas de color (jarras y platos de talavera).
const CERAMICA: String = """
shader_type spatial;

uniform vec3 base : source_color = vec3(0.95, 0.9, 0.78);
uniform vec3 banda : source_color = vec3(0.12, 0.3, 0.8);
uniform float frecuencia = 7.0;

varying vec3 pos_obj;

void vertex() {
	pos_obj = VERTEX;
}

void fragment() {
	float y = pos_obj.y * frecuencia;
	float franja = smoothstep(0.34, 0.4, fract(y)) - smoothstep(0.6, 0.66, fract(y));
	float puntos = 1.0 - smoothstep(0.08, 0.12, length(fract(vec2(atan(pos_obj.z, pos_obj.x) * 2.5, y)) - 0.5));
	ALBEDO = mix(base, banda, clamp(franja + puntos * 0.6, 0.0, 1.0));
	ROUGHNESS = 0.22;
	SPECULAR = 0.7;
}
"""

## Haz de luz de la ventana (aditivo, sin sombras).
const HAZ: String = """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

uniform vec3 tinte : source_color = vec3(0.55, 0.7, 1.0);
uniform float intensidad = 0.3;

void fragment() {
	float lado = pow(clamp(1.0 - abs(UV.x - 0.5) * 2.0, 0.0, 1.0), 1.7);
	float largo = pow(clamp(1.0 - UV.y, 0.0, 1.0), 1.1) * smoothstep(0.0, 0.06, UV.y);
	float respiro = 0.88 + 0.12 * sin(TIME * 0.6 + UV.y * 4.0);
	ALBEDO = tinte * intensidad * lado * largo * respiro;
}
"""

## Cristal de la ventana: degradado nocturno que brilla más arriba.
const CRISTAL: String = """
shader_type spatial;
render_mode unshaded;

void fragment() {
	float h = 1.0 - UV.y;
	vec3 abajo = vec3(0.05, 0.09, 0.26);
	vec3 arriba = vec3(0.30, 0.52, 1.0);
	float luna = 1.0 - smoothstep(0.0, 0.5, length(UV - vec2(0.72, 0.2)));
	ALBEDO = mix(abajo, arriba, pow(h, 1.4)) + vec3(0.35, 0.4, 0.5) * luna * luna;
}
"""

## Post-proceso 2D: viñeta, velo oscuro tras el título y los botones, base oscura para el aviso y atenuación general.
const POST: String = """
shader_type canvas_item;

uniform float atenuacion : hint_range(0.0, 1.0) = 0.0;
uniform float vineta : hint_range(0.0, 1.0) = 0.6;
uniform float velo_central : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec2 c = UV - vec2(0.5);
	float borde = smoothstep(0.32, 0.85, length(c * vec2(1.0, 1.2))) * vineta;
	float elipse = exp(-(pow(c.x / 0.2, 2.0) + pow((c.y - 0.04) / 0.5, 2.0)));
	float suelo = smoothstep(0.82, 1.0, UV.y) * 0.5;
	float a = clamp(borde + elipse * velo_central + suelo + atenuacion, 0.0, 0.92);
	COLOR = vec4(0.03, 0.012, 0.02, a);
}
"""
