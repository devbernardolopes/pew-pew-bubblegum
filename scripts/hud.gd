class_name Hud
extends CanvasLayer
## Shows reserve ship icons, score / high score / stage labels, a stage banner,
## and the game over overlay.

const ICON_SPACING: float = 32.0
const ICON_SCALE: float = 0.2
const ICON_MARGIN_X: float = 16.0
const ICON_MARGIN_Y: float = 16.0
const OVERLAY_FONT_SIZE: int = 32
const LABEL_FONT_SIZE: int = 20
const BANNER_FONT_SIZE: int = 48
const BANNER_DURATION: float = 2.0

var _icons: Array[Polygon2D] = []
var _overlay: Label = null
var _score_label: Label = null
var _high_score_label: Label = null
var _stage_label: Label = null
var _banner: Label = null
var _banner_timer: float = 0.0


func _ready() -> void:
	GameManager.reserve_ships_changed.connect(_rebuild_icons)
	GameManager.score_changed.connect(_update_score_text)
	GameManager.high_score_changed.connect(_update_high_score_text)
	GameManager.stage_changed.connect(_on_stage_changed)
	GameManager.game_over.connect(_show_game_over)

	_rebuild_icons(GameManager.reserve_ships)
	_create_labels()
	_create_banner()
	_update_score_text(GameManager.score)
	_update_high_score_text(GameManager.high_score)
	_update_stage_text(GameManager.stage)


func _process(delta: float) -> void:
	if _overlay != null and GameManager.is_game_over:
		_update_overlay_text()
	if _banner != null and _banner_timer > 0.0:
		_banner_timer -= delta
		if _banner_timer <= 0.0:
			_banner.visible = false


func _create_labels() -> void:
	_score_label = Label.new()
	_score_label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	add_child(_score_label)

	_high_score_label = Label.new()
	_high_score_label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	add_child(_high_score_label)

	_stage_label = Label.new()
	_stage_label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	add_child(_stage_label)


func _update_score_text(s: int) -> void:
	if _score_label == null:
		return
	_score_label.text = "SCORE  %06d" % s
	_score_label.position = Vector2(16.0, 8.0)


func _update_high_score_text(s: int) -> void:
	if _high_score_label == null:
		return
	_high_score_label.text = "HIGH SCORE  %06d" % s
	_high_score_label.position = Vector2(Helpers.get_game_width() / 2.0 - 100.0, 8.0)


func _update_stage_text(s: int) -> void:
	if _stage_label == null:
		return
	_stage_label.text = "STAGE  %d" % s
	_stage_label.position = Vector2(Helpers.get_game_width() - 160.0, 8.0)


func _create_banner() -> void:
	_banner = Label.new()
	_banner.anchor_left = 0.0
	_banner.anchor_right = 1.0
	_banner.anchor_top = 0.0
	_banner.anchor_bottom = 1.0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", BANNER_FONT_SIZE)
	_banner.visible = false
	add_child(_banner)


func _rebuild_icons(reserve: int) -> void:
	for icon: Polygon2D in _icons:
		icon.queue_free()
	_icons.clear()
	for i: int in reserve:
		var polygon: PackedVector2Array = Helpers.get_polygon(Helpers.VISUAL.TRIANGLE)
		var icon: Polygon2D = Polygon2D.new()
		icon.polygon = polygon
		icon.scale = Vector2.ONE * ICON_SCALE
		icon.color = Color(0.3019608, 1, 1, 1)
		icon.modulate.a = 0.6
		add_child(icon)
		_icons.append(icon)
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


func _on_stage_changed(s: int) -> void:
	_update_stage_text(s)
	if _banner != null:
		_banner.text = "STAGE %d" % s
		_banner.visible = true
		_banner_timer = BANNER_DURATION


func _update_overlay_text() -> void:
	if _overlay == null:
		return
	var ratio_percent: float = GameManager.get_hit_ratio() * 100.0
	var ratio_str: String = "%.1f" % ratio_percent
	var text: String = "GAME OVER\n\nSCORE  %d\n" % GameManager.score
	if GameManager.is_new_high_score:
		text += "NEW HIGH SCORE!\n"
	text += "\nSHOTS FIRED  %d\nHITS  %d\nHIT RATIO  %s%%" % [
		GameManager.shots_fired, GameManager.shots_hit, ratio_str
	]
	if GameManager.time_since_end() >= int(GameManager.RESTART_DELAY * 1000.0):
		text += "\n\nPRESS FIRE TO RESTART"
	_overlay.text = text
