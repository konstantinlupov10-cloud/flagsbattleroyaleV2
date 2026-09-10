extends Node2D
class_name FlameEffect
## A stylised anime-style flame that sits above a flag while it's on fire --
## bright yellow core, orange midriff, red wispy tips on a transparent
## ground, with hard cel-shaded colour bands and sharp licking tongues that
## curl over at the top (reference: classic 2D "anime fire" loops).
##
## It's a single scrolling-noise shader on one quad, not a particle system:
## two noise octaves scroll upward, a vertical falloff keeps the fire dense
## at the base and wispy at the tips, and the combined value is quantised
## into yellow / orange / red bands so it reads as drawn flame rather than a
## soft glow. Cheap enough to run one per on-fire flag; drawn only while
## visible (Flag toggles that with the FIRE state).

const SHADER_CODE := """
shader_type canvas_item;

uniform sampler2D noise : repeat_enable, filter_linear;
uniform float speed = 0.85;
uniform float detail = 2.1;
uniform vec3 col_hot : source_color = vec3(1.0, 0.95, 0.15);
uniform vec3 col_mid : source_color = vec3(1.0, 0.42, 0.02);
uniform vec3 col_low : source_color = vec3(0.86, 0.03, 0.02);

void fragment() {
	vec2 uv = UV;
	float t = TIME * speed;

	float n1 = texture(noise, uv * vec2(1.0, 0.7) + vec2(0.0, -t)).r;
	float n2 = texture(noise, uv * vec2(detail, detail * 0.6) + vec2(0.02 * sin(t * 2.0), -t * 1.9)).r;
	float n = n1 * 0.62 + n2 * 0.38;

	// UV.y: 0 at top, 1 at the base. Flame is strong at the base and must
	// die out toward the top; the noise carves the licking edge.
	float base = UV.y;
	float strength = n + base * 1.35 - 1.18;

	// pull the sides in so the column tapers instead of filling the quad
	float squeeze = mix(0.42, 0.02, base);
	float edge = smoothstep(0.0, 0.22, UV.x - squeeze) * smoothstep(1.0, 1.0 - 0.22, UV.x + squeeze);
	strength *= edge;

	if (strength < 0.02) discard;

	vec3 c;
	if (strength > 0.5) c = col_hot;
	else if (strength > 0.26) c = col_mid;
	else c = col_low;

	float a = smoothstep(0.02, 0.09, strength);
	COLOR = vec4(c, a);
}
"""

var _sprite: Sprite2D

## The shader, noise texture, blank quad texture and even the ShaderMaterial
## are identical for every flame (nothing varies per instance -- size is
## baked into the Sprite2D transform, animation is driven by the shader's
## own TIME), so they're built once and shared. Compiling the shader per
## flag was a multi-second spawn stall with a full roster.
static var _shared_mat: ShaderMaterial
static var _shared_quad: Texture2D

static func _shared() -> Array:
	if _shared_mat == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		noise.frequency = 0.035
		noise.fractal_octaves = 4
		noise.fractal_lacunarity = 2.1
		var noise_tex := NoiseTexture2D.new()
		noise_tex.width = 160
		noise_tex.height = 160
		noise_tex.seamless = true
		noise_tex.noise = noise

		var shader := Shader.new()
		shader.code = SHADER_CODE
		_shared_mat = ShaderMaterial.new()
		_shared_mat.shader = shader
		_shared_mat.set_shader_parameter("noise", noise_tex)

		var blank := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		blank.fill(Color(1, 1, 1, 1))
		_shared_quad = ImageTexture.create_from_image(blank)
	return [_shared_mat, _shared_quad]

func configure(flame_width: float, flame_height: float) -> void:
	var w: float = maxf(12.0, flame_width)
	var h: float = maxf(16.0, flame_height)
	var shared: Array = _shared()

	_sprite = Sprite2D.new()
	_sprite.texture = shared[1]
	_sprite.material = shared[0]
	_sprite.centered = false
	_sprite.scale = Vector2(w / 4.0, h / 4.0)
	# anchor the quad's bottom edge on this node's origin (the flag's top)
	_sprite.position = Vector2(-w * 0.5, -h)
	add_child(_sprite)
