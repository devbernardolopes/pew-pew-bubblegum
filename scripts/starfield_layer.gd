class_name StarfieldLayer
extends Parallax2D
## A parallax layer made of procedurally generated pixel stars.
##
## The layer builds a seamless star texture in [method _ready] and repeats it
## with [member Parallax2D.repeat_size], so [member Parallax2D.autoscroll] can
## drift it forever. No external texture is needed.
##
## Give each layer its own [member Parallax2D.autoscroll] and
## [member Parallax2D.scroll_scale] to create depth: distant layers move slowly,
## close layers move faster. The texture starts at the top-left corner, as
## [Parallax2D] expects for seamless repeating.

@export_group("Stars")
## Number of stars in one tile of the starfield.
@export var star_count: int = 90
## Smallest star size, in pixels.
@export var star_size_min: int = 1
## Largest star size, in pixels.
@export var star_size_max: int = 1
## Lowest star opacity.
@export_range(0.0, 1.0) var alpha_min: float = 0.25
## Highest star opacity.
@export_range(0.0, 1.0) var alpha_max: float = 0.55
## Main star colour.
@export var star_color: Color = Color(0.55, 0.65, 0.9)
## Colour used by the occasional accent star.
@export var accent_color: Color = Color(1.0, 0.55, 0.8)
## Chance for a star to use [member accent_color] instead of [member star_color].
@export_range(0.0, 1.0) var accent_chance: float = 0.0

@export_group("Streaks")
## Chance for a star to become a short vertical streak.
@export_range(0.0, 1.0) var streak_chance: float = 0.0
## Height of a streak, in pixels. The star's width is kept.
@export var streak_length: int = 4

@export_group("Warp")
## Multiplier applied to [member autoscroll] during the stage banner.
@export var autoscroll_boost: float = 10.0
## Multiplier applied to [member scroll_scale] during the stage banner.
@export var scroll_scale_boost: float = 2.0


@export_group("Random")
## Seed for the star layout. Use a different value for every layer.
@export var rng_seed: int = 1


func _ready() -> void:
	var game_size: Vector2i = Vector2i(
			int(Helpers.get_game_width()),
			int(Helpers.get_game_height()))
	if game_size.x <= 0 or game_size.y <= 0:
		push_error("StarfieldLayer needs a positive game size.")
		return

	var image: Image = _build_image(game_size)
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = "Stars"
	sprite.centered = false
	sprite.position = Vector2.ZERO
	sprite.texture = ImageTexture.create_from_image(image)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)

	# The repeat must be applied after the star sprite exists so the child is
	# included in the repeated canvas. repeat_size also enables autoscroll.
	repeat_size = Vector2(game_size)
	repeat_times = 2


var _base_autoscroll: Vector2 = Vector2.ZERO
var _base_scroll_scale: Vector2 = Vector2.ONE
var _boost_active: bool = false


func apply_boost() -> void:
	if _boost_active:
		return
	_boost_active = true
	_base_autoscroll = autoscroll
	_base_scroll_scale = scroll_scale
	autoscroll = autoscroll * autoscroll_boost
	scroll_scale = scroll_scale * scroll_scale_boost


func clear_boost() -> void:
	if not _boost_active:
		return
	_boost_active = false
	autoscroll = _base_autoscroll
	scroll_scale = _base_scroll_scale


func _build_image(game_size: Vector2i) -> Image:
	var image: Image = Image.create_empty(game_size.x, game_size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = rng_seed

	var min_size: int = maxi(1, mini(star_size_min, star_size_max))
	var max_size: int = maxi(min_size, maxi(star_size_min, star_size_max))
	var low_alpha: float = minf(alpha_min, alpha_max)
	var high_alpha: float = maxf(alpha_min, alpha_max)

	for _i: int in star_count:
		var size: int = rng.randi_range(min_size, max_size)
		var _position: Vector2i = Vector2i(
				rng.randi_range(0, game_size.x - 1),
				rng.randi_range(0, game_size.y - 1))
		var color: Color = star_color
		if accent_chance > 0.0 and rng.randf() < accent_chance:
			color = accent_color
		color.a = rng.randf_range(low_alpha, high_alpha)

		var height: int = size
		if streak_chance > 0.0 and rng.randf() < streak_chance:
			height = maxi(size, streak_length)
		_fill_wrapped(image, Rect2i(_position, Vector2i(size, height)), color)
	return image


## Fills a rectangle and its wrapped copies, so stars crossing a tile edge also
## appear on the opposite edge and the repeat has no visible seam.
func _fill_wrapped(image: Image, rect: Rect2i, color: Color) -> void:
	var bounds: Rect2i = Rect2i(Vector2i.ZERO, image.get_size())
	var width: int = image.get_width()
	var height: int = image.get_height()
	for offset_x: int in [-width, 0, width]:
		for offset_y: int in [-height, 0, height]:
			var wrapped: Rect2i = Rect2i(
					rect.position + Vector2i(offset_x, offset_y),
					rect.size)
			var clipped: Rect2i = wrapped.intersection(bounds)
			if clipped.size.x > 0 and clipped.size.y > 0:
				image.fill_rect(clipped, color)
