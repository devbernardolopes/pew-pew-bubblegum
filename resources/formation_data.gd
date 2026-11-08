@tool
class_name FormationData
extends Resource
## Layout of an immutable formation grid. Every stage wave that points at the
## same resource shares one [Formation] instance and sways in unison.
##
## The grid is either a full rectangle, sized by [member columns] and
## [member rows], or a pixel-art shape read from [member layout]: one pixel per
## cell, where an opaque pixel is a slot and a transparent one is a hole.

## Fraction of the screen height a formation may span vertically.
const MAX_HEIGHT_FRACTION: float = 0.6

## Number of slots per row. Ignored when [member layout] is set.
@export_range(1, 32) var columns: int = 8
## Number of rows of slots; rows extend downwards from the formation's origin.
## Ignored when [member layout] is set.
@export var rows: int = 2
## Optional shape of the formation: one pixel per cell, a pixel with alpha above
## 0.5 is a slot and anything else is a hole. When set, its size replaces
## [member columns] and [member rows]. Keep the import on Lossless.
@export var layout: Texture2D = null:
	set(value):
		layout = value
		_cells_ready = false
## Distance between two neighboring slots, in pixels.
@export var spacing: Vector2 = Vector2(48, 40)
## Width of the horizontal sway, in pixels.
@export var sway_amplitude: float = 40.0
## Angular speed of the sway, in radians per second.
@export var sway_speed: float = 1.2

## Opaque cells of the layout: [code]Vector2i(col, row)[/code] to its pixel color.
## The color is kept for future foe groups, nothing reads it yet.
var _cells: Dictionary = {}
var _cells_ready: bool = false
## Size of the layout image, or zero when there is no readable layout.
var _layout_size: Vector2i = Vector2i.ZERO


## Peak horizontal speed of a slot, in pixels per second. It must stay below a
## foe's [member EntityData.base_speed], or settling foes can never catch it.
func get_peak_slot_speed() -> float:
	return sway_amplitude * sway_speed


## Half the width of a row of slots, in pixels, without the sway.
func get_half_width() -> float:
	return (get_column_count() - 1) * spacing.x / 2.0


## Number of columns of the grid: the layout width when there is a readable
## layout, [member columns] otherwise.
func get_column_count() -> int:
	_ensure_cells()
	if _layout_size.x > 0:
		return _layout_size.x
	return columns


## Number of rows of the grid: the layout height when there is a readable
## layout, [member rows] otherwise.
func get_row_count() -> int:
	_ensure_cells()
	if _layout_size.y > 0:
		return _layout_size.y
	return rows


## Whether the cell at [param row] and [param col] is a slot. Without a layout
## every in-range cell is a slot; outside the grid it is always a hole.
func has_cell(row: int, col: int) -> bool:
	_ensure_cells()
	if row < 0 or row >= get_row_count() or col < 0 or col >= get_column_count():
		return false
	if _layout_size.x <= 0:
		return true
	return _cells.has(Vector2i(col, row))


## The occupied columns of [param row], in ascending order. Empty when the row
## is outside the grid or every one of its cells is a hole.
func get_row_columns(row: int) -> PackedInt32Array:
	_ensure_cells()
	var result: PackedInt32Array = []
	if row < 0 or row >= get_row_count():
		return result
	for col: int in get_column_count():
		if _layout_size.x <= 0 or _cells.has(Vector2i(col, row)):
			result.append(col)
	return result


## Total number of cells a wave can fill.
func get_cell_count() -> int:
	_ensure_cells()
	if _layout_size.x <= 0:
		return get_column_count() * get_row_count()
	return _cells.size()


## Returns the problems found in this formation, each prefixed with
## [code][error][/code] or [code][warning][/code].
func validate() -> PackedStringArray:
	var issues: PackedStringArray = []
	var name: String = WaveData.describe(self)
	_ensure_cells()
	if layout != null:
		if _layout_size.x <= 0:
			issues.append("[error] %s: the layout image is unreadable or empty." % name)
		elif _cells.is_empty():
			issues.append("[error] %s: the layout image has no opaque pixel, so every cell is a hole." % name)
	var width: int = get_column_count()
	if width > 32:
		issues.append("[warning] %s: %d columns is more than the plain grid allows (32)." % [name, width])
	var extent: float = 2.0 * (get_half_width() + sway_amplitude)
	if extent > Helpers.get_game_width():
		issues.append("[warning] %s: the formation spans %.0f px with the sway, wider than the screen (%.0f px)." % [
				name, extent, Helpers.get_game_width()])
	var height: float = float(get_row_count() - 1) * spacing.y
	var max_height: float = Helpers.get_game_height() * MAX_HEIGHT_FRACTION
	if height > max_height:
		issues.append("[warning] %s: %d rows span %.0f px vertically, more than the %.0f px allowed." % [
				name, get_row_count(), height, max_height])
	return issues


## Reads the layout image once: size and opaque cells are cached until the
## layout changes. Falls back to the plain grid when the image is unreadable.
func _ensure_cells() -> void:
	if _cells_ready:
		return
	_cells_ready = true
	_cells.clear()
	_layout_size = Vector2i.ZERO
	if layout == null:
		return
	var source: Image = layout.get_image()
	if source == null or source.is_empty():
		return
	var image: Image = Image.new()
	image.copy_from(source)
	if image.is_compressed() and image.decompress() != OK:
		return
	_layout_size = image.get_size()
	for row: int in _layout_size.y:
		for col: int in _layout_size.x:
			var color: Color = image.get_pixel(col, row)
			if color.a > 0.5:
				_cells[Vector2i(col, row)] = color
