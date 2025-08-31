extends Node2D
class_name Transition

# ======================= Single step action (Player / Hero) =======================
func apply_player_action(alpha:int, beta:int, gamma:int, x:int) -> void:
	# If hero stack is zero at decision time -> go straight to showdown/settlement
	if Globals.B1 == 0:
		final_results()
		return

	var player_is_first: bool = _is_player_first_to_act()

	# 1) Fold
	if alpha == 1:
		_start_new_hand()
		return

	# 2) Commit chips
	var diff:int = Globals.B3 - Globals.B2
	var need:int = (diff if diff > 0 else 0)
	var R:int = 0
	if beta == 1:
		R = need
	elif gamma == 1:
		R = x
	Globals.B1 -= R
	Globals.B2 += R

	# If opponent’s effective stack hits zero after our action -> settle immediately
	if _opp_stack() == 0:
		final_results()
		return

	# 3) Advance (t1,t2,t3) correctly
	if player_is_first:
		# Hero is first to act: t3 must go 1 -> 2 (let the other player act)
		Globals.t3 = 2
	else:
		# Hero is second to act (t3 == 2 here)
		if beta == 1:
			# Call/Check closes the street
			_enter_next_stage_or_showdown()
		elif gamma == 1:
			# Second-to-act raise -> still t3=2; now first actor must respond
			Globals.t3 = 2
		# Fold already returned above

# ======================= Single step action (Opponent / Villain) =======================
func apply_opponent_action(alpha_p:int, beta_p:int, gamma_p:int, x_p:int) -> void:
	# If opponent’s effective stack is zero at decision time -> settle immediately
	if _opp_stack() == 0:
		final_results()
		return

	var player_is_first: bool = _is_player_first_to_act()
	var opp_is_first: bool = not player_is_first

	# 1) Opponent folds
	if alpha_p == 1:
		# Hero wins the whole pot on fold
		Globals.B1 += (Globals.B2 + Globals.B3)
		_start_new_hand()
		return

	# 2) Commit chips
	var diffp:int = Globals.B2 - Globals.B3
	var need_p:int = (diffp if diffp > 0 else 0)
	var Rp:int = 0
	if beta_p == 1:
		Rp = need_p
	elif gamma_p == 1:
		Rp = x_p
	Globals.B3 += Rp

	# If hero stack hits zero after opponent’s action -> settle immediately
	if Globals.B1 == 0:
		final_results()
		return

	# 3) Advance (t1,t2,t3) correctly
	if opp_is_first:
		# Opponent is first to act: t3 must go 1 -> 2 (let the other player act)
		Globals.t3 = 2
	else:
		# Opponent is second to act (t3 == 2 here)
		if beta_p == 1:
			_enter_next_stage_or_showdown()
		elif gamma_p == 1:
			# Second-to-act raise -> still t3=2; now first actor must respond
			Globals.t3 = 2

# ======================= Showdown / Settlement =======================
func final_results() -> void:
	# Build 7-card sets: hero(2)+board(5), villain(2)+board(5)
	var board: Array[Vector2i] = [Globals.c3, Globals.c4, Globals.c5, Globals.c6, Globals.c7]
	var hero:  Array[Vector2i] = [Globals.c1, Globals.c2]
	var vill:  Array[Vector2i] = [Globals.c8, Globals.c9]

	var hero7: Array[Vector2i] = []
	hero7.append_array(hero)
	hero7.append_array(board)

	var vill7: Array[Vector2i] = []
	vill7.append_array(vill)
	vill7.append_array(board)

	var r_hero: Array[int] = _hand_rank(hero7)
	var r_vill: Array[int] = _hand_rank(vill7)

	var cmp:int = _cmp_rank(r_hero, r_vill)
	var pot:int = Globals.B2 + Globals.B3

	if cmp > 0:
		# Hero wins entire pot
		Globals.B1 += pot
	elif cmp == 0:
		# Split; odd chip to the button (t1 odd => hero is button/SB)
		var half:int = pot / 2
		var odd:int = pot % 2
		Globals.B1 += half
		if _is_player_button():
			Globals.B1 += odd
	# Villain wins: B1 unchanged

	_start_new_hand()

# ======================= Utilities: who acts first / stage advance / stacks / new hand =======================
# Is hero first to act in the current street?
# t1 odd => hero is SB; preflop (t2==1) SB acts second; postflop SB acts first
func _is_player_first_to_act() -> bool:
	var player_is_sb: bool = ((Globals.t1 % 2) == 1)
	if Globals.t2 == 1:
		return not player_is_sb  # preflop: non-SB acts first
	else:
		return player_is_sb      # postflop: SB acts first

# On matched bets (or check-check), move to the next street; on river, go to showdown
func _enter_next_stage_or_showdown() -> void:
	if Globals.t2 < 4:
		Globals.t2 += 1
		Globals.t3 = 1
	else:
		final_results()

# Opponent’s effective off-table stack = 2M - (B1 + B2 + B3)
func _opp_stack() -> int:
	return 2 * Globals.M - (Globals.B1 + Globals.B2 + Globals.B3)

# Start a new hand: clear pot -> (t1+1,1,1) -> deal 9 cards -> post small blind (Globals.blind_b)
func _start_new_hand() -> void:
	# Clear pot
	Globals.B2 = 0
	Globals.B3 = 0

	# Advance time
	Globals.t1 += 1
	Globals.t2 = 1
	Globals.t3 = 1

	# Deal cards (requires draw_card.gd with class_name DrawCard)
	var dealer := DrawCard.new()
	dealer.shuffle_and_assign_cards9()

	# Post SB: odd t1 -> hero posts SB; even t1 -> opponent posts SB
	var b:int = Globals.blind_b
	if (Globals.t1 % 2) == 1:
		Globals.B1 -= b
		Globals.B2 = b
		Globals.B3 = 0
	else:
		Globals.B2 = 0
		Globals.B3 = b

# Is hero the button? (your rule: t1 odd => hero is button/SB)
func _is_player_button() -> bool:
	return (Globals.t1 % 2) == 1

# ======================= 7-card hand evaluation (best 5) =======================
# Return an int array like [category, main values..., kickers...], compared lexicographically.
# Categories: 9=straight flush, 8=four of a kind, 7=full house, 6=flush,
#             5=straight, 4=three of a kind, 3=two pair, 2=one pair, 1=high card
func _hand_rank(cards7: Array[Vector2i]) -> Array[int]:
	var vals: Array[int] = []
	var suits: Array[int] = []
	for c in cards7:
		vals.append(_rank_to_val(c.x))
		suits.append(c.y)

	# Counts and suit buckets (strongly typed Array[int])
	var cnt: Dictionary = {}
	var suit_map: Dictionary = {
		1: [] as Array[int],
		2: [] as Array[int],
		3: [] as Array[int],
		4: [] as Array[int]
	}
	for i in range(cards7.size()):
		var v:int = vals[i]
		var s:int = suits[i]
		if not cnt.has(v):
			cnt[v] = 0
		cnt[v] = int(cnt[v]) + 1
		var arr: Array[int] = suit_map[s] as Array[int]
		arr.append(v)
		suit_map[s] = arr

	# Straight flush
	var sf:int = _best_straight_flush(suit_map)
	if sf > 0:
		return [9, sf]

	# Grouping by multiplicity
	var keys:Array[int] = _dict_keys_int(cnt)
	keys = _sorted_desc(keys)
	var quads:Array[int] = []
	var trips:Array[int] = []
	var pairs:Array[int] = []
	var singles:Array[int] = []
	for v in keys:
		var c:int = int(cnt[v])
		if c == 4:
			quads.append(v)
		elif c == 3:
			trips.append(v)
		elif c == 2:
			pairs.append(v)
		else:
			singles.append(v)

	# Four of a kind  (fix: kicker from max of singles/pairs/trips if present)
	if quads.size() > 0:
		var cand:Array[int] = []
		if singles.size() > 0:
			cand.append(singles[0])
		if pairs.size() > 0:
			cand.append(pairs[0])
		if trips.size() > 0:
			cand.append(trips[0]) # e.g., AAAA + KKK -> kicker K
		cand = _sorted_desc(cand)
		var kicker:int = 0
		if cand.size() > 0:
			kicker = cand[0]
		return [8, quads[0], kicker]

	# Full house  (fix: pair component = max( second triplet , best pair ))
	if trips.size() > 0:
		if pairs.size() > 0 or trips.size() > 1:
			var t:int = trips[0]
			var p_cands:Array[int] = []
			if trips.size() > 1:
				p_cands.append(trips[1])   # use second triplet as the "pair" candidate
			if pairs.size() > 0:
				p_cands.append(pairs[0])   # or the best real pair
			p_cands = _sorted_desc(p_cands)
			var p:int = 0
			if p_cands.size() > 0:
				p = p_cands[0]
			return [7, t, p]

	# Flush (take highest 5)
	var flush_vals:Array[int] = _best_flush_values(suit_map)
	if flush_vals.size() == 5:
		return [6, flush_vals[0], flush_vals[1], flush_vals[2], flush_vals[3], flush_vals[4]]

	# Straight
	var uniq_for_straight:Array[int] = _unique_vals_for_straight(vals)
	var straight_high:int = _best_straight(uniq_for_straight)
	if straight_high > 0:
		return [5, straight_high]

	# Three of a kind
	if trips.size() > 0:
		var pool:Array[int] = _merge_desc(singles, pairs)
		var ks:Array[int] = _top_n(pool, 2)
		while ks.size() < 2:
			ks.append(0)
		var out:Array[int] = [4, trips[0]]
		out.append_array(ks)
		return out

	# Two pair  (fix: kicker = max(third pair, best single) if available)
	if pairs.size() >= 2:
		var p_hi:int = pairs[0]
		var p_lo:int = pairs[1]
		var kick_cands:Array[int] = []
		if pairs.size() >= 3:
			kick_cands.append(pairs[2])
		if singles.size() > 0:
			kick_cands.append(singles[0])
		kick_cands = _sorted_desc(kick_cands)
		var kick:int = 0
		if kick_cands.size() > 0:
			kick = kick_cands[0]
		return [3, p_hi, p_lo, kick]

	# One pair
	if pairs.size() == 1:
		var ks1:Array[int] = _top_n(singles, 3)
		while ks1.size() < 3:
			ks1.append(0)
		var out1:Array[int] = [2, pairs[0]]
		out1.append_array(ks1)
		return out1

	# High card
	var highs:Array[int] = _sorted_desc(_unique_vals_no_ace_low(vals))
	highs = _top_n(highs, 5)
	while highs.size() < 5:
		highs.append(0)
	var out2:Array[int] = [1]
	out2.append_array(highs)
	return out2


# Compare two rank arrays: >0 hero better; <0 villain better; =0 equal
func _cmp_rank(a: Array[int], b: Array[int]) -> int:
	var n:int = a.size()
	if b.size() > n:
		n = b.size()
	for i in range(n):
		var ai:int = 0
		var bi:int = 0
		if i < a.size():
			ai = a[i]
		if i < b.size():
			bi = b[i]
		if ai > bi:
			return 1
		if ai < bi:
			return -1
	return 0


# ======== Poker evaluation helpers (strong typing, no ternaries) ========
func _rank_to_val(r:int) -> int:
	# Map Ace rank (1) to 14 for high; straights handle A-low separately
	if r == 1:
		return 14
	return r

# Unique values for straight detection (includes Ace as 1 if Ace exists)
func _unique_vals_for_straight(vals:Array[int]) -> Array[int]:
	var seen := {}
	var out:Array[int] = []
	for v in vals:
		if not seen.has(v):
			seen[v] = true
			out.append(v)
	var has_ace:bool = false
	for v in out:
		if v == 14:
			has_ace = true
			break
	if has_ace:
		out.append(1)
	return out

# Unique values for non-straight comparisons (no Ace-low duplicate)
func _unique_vals_no_ace_low(vals:Array[int]) -> Array[int]:
	var seen := {}
	var out:Array[int] = []
	for v in vals:
		if not seen.has(v):
			seen[v] = true
			out.append(v)
	return out

func _sorted_desc(arr:Array[int]) -> Array[int]:
	var a := arr.duplicate()
	a.sort()
	a.reverse()
	return a

func _dict_keys_int(d:Dictionary) -> Array[int]:
	var ks:Array[int] = []
	for k in d.keys():
		ks.append(int(k))
	return ks

func _merge_desc(a:Array[int], b:Array[int]) -> Array[int]:
	var m:Array[int] = []
	m.append_array(a)
	m.append_array(b)
	m = _sorted_desc(m)
	return m

func _top_n(arr:Array[int], n:int) -> Array[int]:
	var a := _sorted_desc(arr)
	var out:Array[int] = []
	var limit:int = n
	if a.size() < n:
		limit = a.size()
	for i in range(limit):
		out.append(a[i])
	return out

# Best straight-flush top card within any single suit; 0 if none
func _best_straight_flush(suit_map:Dictionary) -> int:
	for s in [1,2,3,4]:
		var vals_s: Array[int] = suit_map[s] as Array[int]
		if vals_s.size() >= 5:
			var uniq: Array[int] = _unique_vals_for_straight(vals_s)
			var high: int = _best_straight(uniq)
			if high > 0:
				return high
	return 0

# Return the highest 5 values of a flush (desc). Empty array if no flush.
func _best_flush_values(suit_map:Dictionary) -> Array[int]:
	for s in [1,2,3,4]:
		var vals_s: Array[int] = suit_map[s] as Array[int]
		if vals_s.size() >= 5:
			var uniq: Array[int] = _unique_vals_no_ace_low(vals_s)
			uniq = _sorted_desc(uniq)
			var out: Array[int] = []
			for i in range(5):
				out.append(uniq[i])
			return out
	return []

# Straight on unique, sorted values (may include both 1 and 14). Returns top card, 0 if none.
func _best_straight(uniq_vals:Array[int]) -> int:
	var a := uniq_vals.duplicate()
	a.sort()  # ascending
	var best:int = 0
	var run:int = 1
	for i in range(1, a.size()):
		if a[i] == a[i - 1] + 1:
			run += 1
			if run >= 5:
				best = a[i]  # track top card
		elif a[i] != a[i - 1]:
			run = 1
	return best
