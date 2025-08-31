extends Node2D
class_name DrawCard

var rng := RandomNumberGenerator.new()

func _init(seed:int = 0) -> void:
	if seed != 0:
		rng.seed = seed
	else:
		rng.randomize()

func shuffle_and_assign_cards9() -> void:
	# rank 1..13, suit 1..4 （Vector2i(rank, suit)）
	var deck: Array[Vector2i] = []
	for r in range(1, 14):
		for s in range(1, 5):
			deck.append(Vector2i(r, s))

	for i in range(deck.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := deck[i]
		deck[i] = deck[j]
		deck[j] = tmp

	Globals.c1 = deck[0]
	Globals.c2 = deck[1]
	Globals.c3 = deck[2]
	Globals.c4 = deck[3]
	Globals.c5 = deck[4]
	Globals.c6 = deck[5]
	Globals.c7 = deck[6]
	Globals.c8 = deck[7]
	Globals.c9 = deck[8]
