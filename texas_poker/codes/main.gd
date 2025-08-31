extends Node2D
class_name Main

# —— Signals (connect them to the Graph node in the editor if needed) ——
signal series_started(total:int)      # Suggest connect to Graph.reset(total:int)
signal match_finished(end_hand:int)   # Suggest connect to Graph.add_result(ended_hand:int)

var pb: Transition
var _started: bool = false

# Use policy switch (true -> use clever_policy from a "clever" node)
@export var policy_open: bool = false

# Cached reference to the clever policy node (optional)
@onready var _clever := get_node_or_null("clever") as PolicyClever

# ---------- Player policy parameters (Inspector) ----------
@export var pf: float = 0.05  # fold probability
@export var pc: float = 0.70  # call/check probability
@export var pr: float = 0.25  # raise probability (only when legal; will be renormalized)

# Raise sizing (used only after choosing "raise"; should sum to 1)
@export var prs: float = 0.50 # small raise: 30% point in raise interval
@export var prb: float = 0.30 # big raise:   60% point in raise interval
@export var pra: float = 0.20 # all-in:      upper bound of raise interval

# ---------- Opponent policy parameters (Inspector) ----------
@export var pf_o: float = 0.05
@export var pc_o: float = 0.70
@export var pr_o: float = 0.25

@export var prs_o: float = 0.50
@export var prb_o: float = 0.30
@export var pra_o: float = 0.20

# ---------- Matches & scoreboard ----------
@export var G: int = 1  # number of full matches to simulate
var _player_match_wins: int = 0
var _opponent_match_wins: int = 0
var _match_index: int = 0

# ---------- CSV export (R-friendly) ----------
@export var out_path: String = "C:/Users/14629/Desktop/godot/data_6.csv"
var _rows: PackedStringArray = PackedStringArray()

func _start_recording(total:int) -> void:
	_rows.clear()
	_rows.append("end_hand,winner") # winner: player=1, opponent=0
	var abs := ProjectSettings.globalize_path(out_path)
	print("[DATA] writing to:", abs, " | total matches:", total)

func _record_match(end_hand:int, player_won:bool) -> void:
	var w := (1 if player_won else 0)
	_rows.append("%d,%d" % [end_hand, w])

func _finish_recording() -> void:
	# Ensure directory exists (safe if already exists)
	var abs := ProjectSettings.globalize_path(out_path)
	DirAccess.make_dir_recursive_absolute(abs.get_base_dir())

	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_rows))
		f.flush()
		f.close()
		print("[DATA] saved to:", abs, " | rows:", _rows.size())
	else:
		push_warning("[DATA] cannot open file for write: " + out_path)

# RNG
@onready var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	pb = Transition.new()

func _process(_delta: float) -> void:
	if not _started:
		_started = true
		_run_match()  # start as coroutine

# ---------------- Main loop: run G matches; print per-match summary; export CSV ----------------
func _run_match() -> void:
	_match_index = 0
	_player_match_wins = 0
	_opponent_match_wins = 0

	var total:int = int(G)
	if total <= 0:
		total = 1

	_start_recording(total)     # CSV header & notice
	series_started.emit(total)  # inform Graph (if connected in editor)

	while _match_index < total:
		_reset_match_state()  # per-match reset: t=(1,1,1), deal 9 cards, post SB

		var end_hand:int = -1
		var winner_str:String = ""  # "Player wins" / "Opponent wins"

		while true:
			var outcome:Dictionary = await simulate_one_hand_async()
			end_hand = int(outcome["ended_t1"])

			var pa:int = outcome["player_after"]
			var oa:int = outcome["opp_after"]

			if pa <= 0:
				# player busts -> opponent wins the match
				_opponent_match_wins += 1
				winner_str = "Opponent wins"
				break
			elif oa <= 0:
				# opponent busts -> player wins the match
				_player_match_wins += 1
				winner_str = "Player wins"
				break

			await get_tree().process_frame  # let UI breathe

		# Record a row & notify Graph
		var player_won := (winner_str == "Player wins")
		_record_match(end_hand, player_won)
		match_finished.emit(end_hand)

		# Per-match summary only
		print("Match %d | %s | ended at hand %d | score Player %d : %d Opponent"
			% [_match_index + 1, winner_str, end_hand, _player_match_wins, _opponent_match_wins])

		_match_index += 1
		await get_tree().process_frame

	print("[SUMMARY] total=%d | player_wins=%d | opponent_wins=%d"
		% [total, _player_match_wins, _opponent_match_wins])

	_finish_recording()  # write CSV

# ---------- Per-match reset: set t=(1,1,1), stacks from M, deal cards, post SB ----------
func _reset_match_state() -> void:
	var M:int = Globals.M
	var b:int = Globals.blind_b

	Globals.B1 = M
	Globals.B2 = 0
	Globals.B3 = 0
	Globals.t1 = 1
	Globals.t2 = 1
	Globals.t3 = 1

	var dealer := DrawCard.new()
	dealer.shuffle_and_assign_cards9()

	# Hand 1: player is small blind -> deduct from B1 and post to B2
	Globals.B1 -= b
	Globals.B2 = b
	Globals.B3 = 0

# ---------------- Simulate a single hand (async) ----------------
# Returns: {result, player_after, opp_after, ended_t1}
func simulate_one_hand_async() -> Dictionary:
	var hand_id:int = Globals.t1
	var winner:String = ""

	var step_guard:int = 500
	var snap_cards:Array[Vector2i] = []
	var snap_B1:int = 0
	var snap_B2:int = 0
	var snap_B3:int = 0

	while step_guard > 0:
		step_guard -= 1

		# If t1 changed, the hand has finished (by fold or showdown)
		if Globals.t1 != hand_id:
			break

		# Snapshot before action (used to reconstruct the settlement moment)
		snap_cards = [
			Globals.c1, Globals.c2,
			Globals.c3, Globals.c4, Globals.c5, Globals.c6, Globals.c7,
			Globals.c8, Globals.c9
		]
		snap_B1 = Globals.B1
		snap_B2 = Globals.B2
		snap_B3 = Globals.B3

		var actor:String = _who_acts_now()

		if actor == "player":
			var a:Array = _policy_player()
			var alpha:int = a[0]
			var beta:int  = a[1]
			var gamma:int = a[2]
			var x:int     = a[3]
			var folded:bool = (alpha == 1)

			pb.apply_player_action(alpha, beta, gamma, x)

			if folded:
				winner = "opponent_win"
			else:
				await get_tree().process_frame
		else:
			var ap:Array = _policy_opponent()
			var alpha_p:int = ap[0]
			var beta_p:int  = ap[1]
			var gamma_p:int = ap[2]
			var x_p:int     = ap[3]
			var folded_p:bool = (alpha_p == 1)

			pb.apply_opponent_action(alpha_p, beta_p, gamma_p, x_p)

			if folded_p:
				winner = "player_win"
			else:
				await get_tree().process_frame

	# —— Settle using the snapshot (pot = B2 + B3 at snapshot time) —— #
	var pot:int = snap_B2 + snap_B3
	var ended_t1:int = hand_id

	if winner == "":
		# Showdown: evaluate with snapshot cards
		var hero7:Array[Vector2i] = [snap_cards[0], snap_cards[1], snap_cards[2], snap_cards[3], snap_cards[4], snap_cards[5], snap_cards[6]]
		var vill7:Array[Vector2i] = [snap_cards[7], snap_cards[8], snap_cards[2], snap_cards[3], snap_cards[4], snap_cards[5], snap_cards[6]]
		var r_hero:Array[int] = pb._hand_rank(hero7)
		var r_vill:Array[int] = pb._hand_rank(vill7)
		var cmp:int = pb._cmp_rank(r_hero, r_vill)
		if cmp > 0:
			winner = "player_win"
		elif cmp < 0:
			winner = "opponent_win"
		else:
			winner = "tie"

	var b1_after:int = snap_B1
	if winner == "player_win":
		b1_after += pot
	elif winner == "tie":
		var half:int = pot / 2
		var odd:int = pot % 2
		b1_after += half
		# Odd chip goes to the button (t1 odd => player had the button)
		if (ended_t1 % 2) == 1:
			b1_after += odd

	var opp_after:int = 2 * Globals.M - b1_after

	return {
		"result": winner,
		"player_after": b1_after,
		"opp_after": opp_after,
		"ended_t1": ended_t1
	}

# ---------------- Player policy (probabilistic or clever) ----------------
# Returns [alpha, beta, gamma, x]
func _policy_player() -> Array:
	# If policy switch is ON and clever node is valid, delegate first
	if policy_open and _clever and _clever.has_method("clever_policy"):
		var res = _clever.clever_policy()
		if typeof(res) == TYPE_ARRAY and res.size() == 4:
			return res
	# Fallback to the original probabilistic policy

	if Globals.B1 <= 0:
		return [0, 1, 0, 0]

	var need:int = Globals.B3 - Globals.B2
	if need < 0:
		need = 0

	var remaining:int = 2 * Globals.M - (Globals.B1 + Globals.B2 + Globals.B3)
	if remaining < 0:
		remaining = 0

	var bmax:int = Globals.B1
	if remaining < bmax:
		bmax = remaining

	var can_raise: bool = (Globals.t3 == 1) and (bmax > need)
	var low:int = need + 1

	var pf_loc: float = pf
	var pc_loc: float = pc
	var pr_loc: float = pr
	if not can_raise:
		pr_loc = 0.0
	var sump: float = pf_loc + pc_loc + pr_loc
	if sump <= 0.0:
		return [0, 1, 0, 0]
	pf_loc /= sump
	pc_loc /= sump
	pr_loc /= sump

	var u: float = _rng.randf()
	if u < pf_loc:
		return [1, 0, 0, 0]
	u -= pf_loc
	if u < pc_loc:
		return [0, 1, 0, 0]

	var s_sum: float = prs + prb + pra
	var prs_loc: float = prs
	var prb_loc: float = prb
	var pra_loc: float = pra
	if s_sum <= 0.0:
		prs_loc = 1.0
		prb_loc = 0.0
		pra_loc = 0.0
	else:
		prs_loc /= s_sum
		prb_loc /= s_sum
		pra_loc /= s_sum

	var high:int = bmax
	if high < low:
		return [0, 1, 0, 0]
	var span:int = high - low
	var x_small:int = low + int(floor(float(span) * 0.30))
	var x_big:int   = low + int(floor(float(span) * 0.60))
	if x_small < low:
		x_small = low
	if x_big < low:
		x_big = low
	if x_small > high:
		x_small = high
	if x_big > high:
		x_big = high

	var ur: float = _rng.randf()
	var x:int = 0
	if ur < prs_loc:
		x = x_small
	else:
		ur -= prs_loc
		if ur < prb_loc:
			x = x_big
		else:
			x = high

	return [0, 0, 1, x]

# ---------------- Opponent probabilistic policy ----------------
# Returns [alpha', beta', gamma', x']
func _policy_opponent() -> Array:
	var s_opp:int = 2 * Globals.M - (Globals.B1 + Globals.B2 + Globals.B3)
	if s_opp <= 0:
		return [0, 1, 0, 0]

	var need_p:int = Globals.B2 - Globals.B3
	if need_p < 0:
		need_p = 0

	var bmax_opp:int = s_opp
	if Globals.B1 < bmax_opp:
		bmax_opp = Globals.B1

	var can_raise: bool = (Globals.t3 == 1) and (bmax_opp > need_p)
	var low:int = need_p + 1

	var pf_loc: float = pf_o
	var pc_loc: float = pc_o
	var pr_loc: float = pr_o
	if not can_raise:
		pr_loc = 0.0
	var sump: float = pf_loc + pc_loc + pr_loc
	if sump <= 0.0:
		return [0, 1, 0, 0]
	pf_loc /= sump
	pc_loc /= sump
	pr_loc /= sump

	var u: float = _rng.randf()
	if u < pf_loc:
		return [1, 0, 0, 0]
	u -= pf_loc
	if u < pc_loc:
		return [0, 1, 0, 0]

	var s_sum: float = prs_o + prb_o + pra_o
	var prs_loc: float
	var prb_loc: float
	var pra_loc: float
	if s_sum <= 0.0:
		prs_loc = 1.0
		prb_loc = 0.0
		pra_loc = 0.0
	else:
		prs_loc = prs_o / s_sum
		prb_loc = prb_o / s_sum
		pra_loc = pra_o / s_sum

	var high:int = bmax_opp
	if high < low:
		return [0, 1, 0, 0]
	var span:int = high - low
	var x_p_small:int = low + int(floor(float(span) * 0.30))
	var x_p_big:int   = low + int(floor(float(span) * 0.60))
	if x_p_small < low:
		x_p_small = low
	if x_p_big < low:
		x_p_big = low
	if x_p_small > high:
		x_p_small = high
	if x_p_big > high:
		x_p_big = high

	var ur: float = _rng.randf()
	var x_p:int = 0
	if ur < prs_loc:
		x_p = x_p_small
	else:
		ur -= prs_loc
		if ur < prb_loc:
			x_p = x_p_big
		else:
			x_p = high  # all-in at the upper bound

	return [0, 0, 1, x_p]

# ---------------- Actor determination ----------------
# Rules:
# - t1 odd  => player is small blind (button); even => opponent is small blind
# - t2 == 1 => SB acts second; t2 > 1 => SB acts first
# - t3 == 1 => first actor's turn; t3 == 2 => second actor's turn
func _who_acts_now() -> String:
	var player_is_sb:bool = (Globals.t1 % 2) == 1
	var player_first:bool
	if Globals.t2 == 1:
		player_first = not player_is_sb
	else:
		player_first = player_is_sb

	if Globals.t3 == 1:
		if player_first:
			return "player"
		return "opponent"
	else:
		if player_first:
			return "opponent"
		return "player"
