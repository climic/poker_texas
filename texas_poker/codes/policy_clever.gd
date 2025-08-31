extends Node2D
class_name PolicyClever

# Parallel toggles: if enabled and the condition is met, we choose to RAISE; otherwise this rule does nothing.
@export var raise_on_pocket_pair: bool = true    # Raise if hole cards form a pair (c1 and c2 have the same rank)
@export var raise_on_board_match: bool = true    # Postflop (t2=2/3/4): raise if any board card shares rank with either hole card

# Raise sizing: pick a point within the legal interval (need, Bmax] at the given ratio
@export var raise_ratio: float = 0.60  # 0.6 ≈ “big raise”, tunable

# Returns [alpha, beta, gamma, x]
func clever_policy() -> Array:
	# No available stack -> default to check/call
	if Globals.B1 <= 0:
		return [0, 1, 0, 0]

	# Compute legal interval
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
	var high:int = bmax

	# --- Rule triggers ---
	var want_raise: bool = false

	# Hole pair? (Vector2i.x holds the rank)
	var r1:int = Globals.c1.x
	var r2:int = Globals.c2.x
	if raise_on_pocket_pair and r1 == r2:
		want_raise = true

	# Postflop: any board card matches either hole-card rank?
	if not want_raise and raise_on_board_match and Globals.t2 >= 2:
		var board:Array[Vector2i] = [Globals.c3, Globals.c4, Globals.c5]
		if Globals.t2 >= 3:
			board.append(Globals.c6)
		if Globals.t2 >= 4:
			board.append(Globals.c7)
		for c in board:
			var br:int = c.x
			if br == r1 or br == r2:
				want_raise = true
				break

	# Action decision
	if want_raise and can_raise:
		var span:int = high - low
		var pos:float = clamp(raise_ratio, 0.0, 1.0)
		var x:int = low + int(floor(float(span) * pos))
		if x < low:
			x = low
		if x > high:
			x = high
		return [0, 0, 1, x]  # raise
	else:
		return [0, 1, 0, 0]  # otherwise: check/call
