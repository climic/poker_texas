extends Node2D
class_name LevelFight

# Number of big rounds. Each round plays every unordered pair once.
@export var G: int = 100

# CSV output path
@export var out_path: String = "C:/Users/14629/Desktop/godot/level_equity2.csv"


# 27 starting hand categories
var HANDS: PackedStringArray = [
	"AA","KK","QQ","JJ","TT","AKs","AKo","AQs","AJs",
	"ATs","99","KQs","AQo","KJs","88","77","AJo","JTs",
	"KQo","QTs","QJs","A9s","ATo","KTs","KJo","A8s","66"
]

# hand -> { "wins":int, "losses":int, "ties":int }
var _stats: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _pb: Transition

func _ready() -> void:
	_rng.randomize()
	_pb = Transition.new()
	_init_stats()
	await _run_simulation()
	_write_csv()
	_print_summary()

# ---------------- Core loop ----------------
func _run_simulation() -> void:
	for r in range(G):
		for i in range(HANDS.size()):
			for j in range(i + 1, HANDS.size()):
				var h1: String = HANDS[i]
				var h2: String = HANDS[j]
				_simulate_pair_once(h1, h2)
		await get_tree().process_frame

# One simulation for h1 vs h2. Random suits and random 5-card board, then showdown.
func _simulate_pair_once(h1:String, h2:String) -> void:
	var used: Dictionary = {}  # set of "rank-suit" strings

	# Hero hole
	var ok1: bool = false
	var c1: Vector2i
	var c2: Vector2i
	for _a in range(64):
		var res1: Array = _sample_hole(h1, used)
		if res1.size() == 2:
			c1 = res1[0]
			c2 = res1[1]
			ok1 = true
			break
	if not ok1:
		return

	# Villain hole
	var ok2: bool = false
	var c8: Vector2i
	var c9: Vector2i
	for _b in range(128):
		var res2: Array = _sample_hole(h2, used)
		if res2.size() == 2:
			c8 = res2[0]
			c9 = res2[1]
			ok2 = true
			break
	if not ok2:
		return

	# Board
	var board: Array[Vector2i] = _draw_unique_cards(5, used)
	if board.size() != 5:
		return
	var c3: Vector2i = board[0]
	var c4: Vector2i = board[1]
	var c5: Vector2i = board[2]
	var c6: Vector2i = board[3]
	var c7: Vector2i = board[4]

	# Evaluate
	var hero7: Array[Vector2i] = [c1, c2, c3, c4, c5, c6, c7]
	var vill7: Array[Vector2i] = [c8, c9, c3, c4, c5, c6, c7]
	var r_hero: Array[int] = _pb._hand_rank(hero7)
	var r_vill: Array[int] = _pb._hand_rank(vill7)
	var cmp:int = _pb._cmp_rank(r_hero, r_vill)

	if cmp > 0:
		_stats[h1]["wins"] = int(_stats[h1]["wins"]) + 1
		_stats[h2]["losses"] = int(_stats[h2]["losses"]) + 1
	elif cmp < 0:
		_stats[h2]["wins"] = int(_stats[h2]["wins"]) + 1
		_stats[h1]["losses"] = int(_stats[h1]["losses"]) + 1
	else:
		_stats[h1]["ties"] = int(_stats[h1]["ties"]) + 1
		_stats[h2]["ties"] = int(_stats[h2]["ties"]) + 1

# ---------------- Sampling helpers ----------------
# Return two Vector2i that fit the code rule, while avoiding collisions with "used"
func _sample_hole(code:String, used:Dictionary) -> Array:
	var info: Dictionary = _parse_hand_code(code)
	var r1:int = int(info["r1"])
	var r2:int = int(info["r2"])
	var tp:String = String(info["tp"])  # "pair" or "s" or "o"

	if tp == "pair":
		for _i in range(64):
			var s1:int = _rng.randi_range(1, 4)
			var s2:int = _rng.randi_range(1, 4)
			if s2 == s1:
				continue
			var a: Vector2i = Vector2i(r1, s1)
			var b: Vector2i = Vector2i(r1, s2)
			if not _used(used, a) and not _used(used, b):
				_mark_used(used, a)
				_mark_used(used, b)
				return [a, b]
		return []
	elif tp == "s":
		for _j in range(64):
			var s:int = _rng.randi_range(1, 4)
			var a2: Vector2i = Vector2i(r1, s)
			var b2: Vector2i = Vector2i(r2, s)
			if not _used(used, a2) and not _used(used, b2):
				_mark_used(used, a2)
				_mark_used(used, b2)
				return [a2, b2]
		return []
	else:
		for _k in range(128):
			var s3:int = _rng.randi_range(1, 4)
			var s4:int = _rng.randi_range(1, 4)
			if s4 == s3:
				continue
			var a3: Vector2i = Vector2i(r1, s3)
			var b3: Vector2i = Vector2i(r2, s4)
			if not _used(used, a3) and not _used(used, b3):
				_mark_used(used, a3)
				_mark_used(used, b3)
				return [a3, b3]
		return []

func _draw_unique_cards(n:int, used:Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var tries:int = 0
	while out.size() < n and tries < 10000:
		tries += 1
		var r:int = _rng.randi_range(1, 13)
		var s:int = _rng.randi_range(1, 4)
		var c: Vector2i = Vector2i(r, s)
		if not _used(used, c):
			_mark_used(used, c)
			out.append(c)
	return out

# ---------------- Parsing helpers ----------------
# Parse codes like AKs, AQo, 99, TT, AJs
func _parse_hand_code(code:String) -> Dictionary:
	code = code.strip_edges()
	var ranks := {
		"A":1, "K":13, "Q":12, "J":11, "T":10,
		"9":9, "8":8, "7":7, "6":6, "5":5, "4":4, "3":3, "2":2
	}
	if code.length() == 2:
		var r:int = int(ranks[code.substr(0,1)])
		return {"r1": r, "r2": r, "tp": "pair"}
	else:
		var r1:int = int(ranks[code.substr(0,1)])
		var r2:int = int(ranks[code.substr(1,1)])
		var suf:String = code.substr(2,1).to_lower()
		var tp:String = "o"
		if suf == "s":
			tp = "s"
		return {"r1": r1, "r2": r2, "tp": tp}

# ---------------- Used-set helpers ----------------
func _key(c:Vector2i) -> String:
	return "%d-%d" % [c.x, c.y]

func _used(used:Dictionary, c:Vector2i) -> bool:
	return used.has(_key(c))

func _mark_used(used:Dictionary, c:Vector2i) -> void:
	used[_key(c)] = true

# ---------------- Stats and output ----------------
func _init_stats() -> void:
	_stats.clear()
	for h in HANDS:
		_stats[h] = {"wins":0, "losses":0, "ties":0}

func _write_csv() -> void:
	var abs:String = ProjectSettings.globalize_path(out_path)
	DirAccess.make_dir_recursive_absolute(abs.get_base_dir())
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if not f:
		push_warning("Cannot open CSV for write: " + out_path)
		return
	f.store_line("hand,wins,losses,ties,total,equity")
	for h in HANDS:
		var st: Dictionary = _stats[h] as Dictionary
		var w:int = int(st["wins"])
		var l:int = int(st["losses"])
		var t:int = int(st["ties"])
		var tot:int = w + l + t
		var equity: float = 0.0
		if tot > 0:
			equity = (w + 0.5 * t) / float(tot)
		f.store_line("%s,%d,%d,%d,%d,%.6f" % [h, w, l, t, tot, equity])
	f.flush()
	f.close()
	print("[LEVEL_FIGHT] CSV saved to:", abs)

func _print_summary() -> void:
	var pairs_per_round:int = (HANDS.size() * (HANDS.size() - 1)) / 2
	print("--- LevelFight summary G=%d pairs_per_round=%d ---" % [G, pairs_per_round])
	for h in HANDS:
		var st: Dictionary = _stats[h] as Dictionary
		var w:int = int(st["wins"])
		var l:int = int(st["losses"])
		var t:int = int(st["ties"])
		var tot:int = w + l + t
		var equity: float = 0.0
		if tot > 0:
			equity = (w + 0.5 * t) / float(tot)
		print("%-4s  W:%5d  L:%5d  T:%5d  N:%5d  Eq: %.4f"
			% [h, w, l, t, tot, equity])
