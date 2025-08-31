extends Node2D
class_name Graph

# Prefab cell (ideally a Control/ColorRect as root; Node2D also works)
@export var grid_scene: PackedScene

# Screen & origin
@export var screen_w: int = 1800
@export var screen_h: int = 1200
@export var margin: int = 100                    # origin offset from left/bottom
@export var use_globals_origin: bool = true      # if true, try to read Globals.position as origin

# X-axis binning (0..x_max, grouped by bin_width)
@export var x_max: int = 500
@export var bin_width: int = 5

# Visuals & stacking
@export var cell_width_ratio: float = 0.8        # cell width ratio inside each bin
@export var y_step_px: float = 12.0              # vertical step per stacked cell (pixels)

# —— Internal state ——
var _origin: Vector2 = Vector2.ZERO
var _bin_count: int = 0
var _bin_span: float = 0.0
var _counts: Array[int] = []     # stacked count per bin

func _ready() -> void:
	_setup_origin()
	_setup_bins()
	_clear_cells()

# External (signal) API: start a new series; we don't use G here, just clear
func reset(_total:int) -> void:
	_setup_origin()
	_clear_cells()

# External (signal) API: record one finished match and spawn a cell
func add_result(ended_hand:int) -> void:
	if grid_scene == null:
		push_warning("graph.gd: grid_scene is not set; cannot spawn a cell.")
		return

	var h:int = clamp(ended_hand, 0, x_max)

	# Map hand count to bin:
	#   1..bin_width   -> bin 0
	#   bin_width+1..2*bin_width -> bin 1
	#   ...
	#   0 also maps to bin 0
	var bin_idx:int = 0
	if h > 0:
		bin_idx = int(floor(float(h - 1) / float(bin_width)))
	bin_idx = clamp(bin_idx, 0, _bin_count - 1)

	# Increase this bin's stack and compute the level (starting from 1)
	_counts[bin_idx] += 1
	var level:int = _counts[bin_idx]

	# Bin geometry
	var bin_left: float = _origin.x + float(bin_idx) * _bin_span
	var w: float = _bin_span * cell_width_ratio
	var x_left: float = bin_left + (_bin_span - w) * 0.5

	# In Godot Y grows downward; to stack upwards, subtract on Y
	var y_top: float = _origin.y - float(level) * y_step_px

	# Instantiate and place the cell
	var g := grid_scene.instantiate()
	if g is Control:
		var ctrl := g as Control
		ctrl.set_anchors_preset(Control.PRESET_TOP_LEFT)
		ctrl.position = Vector2(x_left, y_top)
		# A reasonable visual height (not tied to 1/G): 0.8 of y_step
		ctrl.size = Vector2(w, max(1.0, y_step_px * 0.8))
		add_child(ctrl)
	elif g is Node2D:
		var node := g as Node2D
		# Place near the top edge of the intended bar
		node.position = Vector2(x_left + w * 0.5, y_top)
		add_child(node)
	else:
		if "position" in g:
			g.set("position", Vector2(x_left, y_top))
		add_child(g)

# —— Internals: origin, binning, clear ——
func _setup_origin() -> void:
	# Default origin: offset from left/bottom by margin (note: Y axis goes down)
	_origin = Vector2(float(margin), float(screen_h - margin))
	if use_globals_origin:
		# Try to read from Globals.position (if present)
		var p = Globals.get("position")
		if typeof(p) == TYPE_VECTOR2:
			_origin = p

func _setup_bins() -> void:
	_bin_count = int(ceil(float(x_max) / float(bin_width)))
	if _bin_count <= 0:
		_bin_count = 1
	_bin_span = float(screen_w - 2 * margin) / float(_bin_count)
	_counts.resize(_bin_count)
	for i in range(_bin_count):
		if typeof(_counts[i]) == TYPE_NIL:
			_counts[i] = 0

func _clear_cells() -> void:
	for c in get_children():
		c.queue_free()
	for i in range(_bin_count):
		_counts[i] = 0
