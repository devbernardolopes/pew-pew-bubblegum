class_name Hud
extends CanvasLayer
## Shows reserve ship icons and the game over overlay.

const ICON_SPACING: float = 32.0
const ICON_SCALE: float = 0.2
const ICON_MARGIN_X: float = 16.0
const ICON_MARGIN_Y: float = 16.0
const OVERLAY_FONT_SIZE: int = 32

var _icons: Array[Polygon2D] = []
var _overlay: Label = null


func _ready() -> void:
	GameManager.reserve_ships_changed.connect(_rebuild_icons)
	GameManager.game_over.connect(_show_game_over)
	_rebuild_icons(GameManager.reserve_ships)


func _rebuild_icons(reserve: int) -> void:
	# Clear existing icons.
	for icon: Polygon2D in _icons:
		icon.queue_free()
	_icons.clear()
	# Build one icon per reserve ship.
	for i: int in reserve:
		var polygon: PackedVector2Array = Helpers.get_polygon(Helpers.VISUAL.TRIANGLE)
		var icon: Polygon2D = Polygon2D.new()
		icon.polygon = polygon
		icon.scale = Vector2.ONE * ICON_SCALE
		icon.color = Color(0.3019608, 1, 1, 1)
		icon.modulate.a = 0.6
		add_child(icon)
		_icons.append(icon)
	# Position icons at the bottom-left.
	var y: float = Helpers.get_game_height() - ICON_MARGIN_Y - Helpers.ENTITY_WIDTH * ICON_SCALE
	for i: int in _icons.size():
		_icons[i].position = Vector2(ICON_MARGIN_X + i * ICON_SPACING, y)


func _show_game_over() -> void:
	if _overlay != null:
		return
	_overlay = Label.new()
	_overlay.anchor_left = 0.0
	_overlay.anchor_right = 1.0
	_overlay.anchor_top = 0.0
	_overlay.anchor_bottom = 1.0
	_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_overlay.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay.add_theme_font_size_override("font_size", OVERLAY_FONT_SIZE)
	add_child(_overlay)
	_update_overlay_text()


func _process(delta: float) -> void:
	if _overlay != null and GameManager.is_game_over:
		_update_overlay_text()


func _update_overlay_text() -> void:
	if _overlay == null:
		return
	var ratio_percent: float = GameManager.get_hit_ratio() * 100.0
	var ratio_str: String = "%.1f" % ratio_percent
	var text: String = "GAME OVER\n\nSHOTS FIRED  %d\nHITS  %d\nHIT RATIO  %s%%" % [
		GameManager.shots_fired, GameManager.shots_hit, ratio_str
	]
	if GameManager.time_since_end() >= int(GameManager.RESTART_DELAY * 1000.0):
		text += "\n\nPRESS FIRE TO RESTART"
	_overlay.text = text
