extends Node2D

var t1: int = 0
var t2: int = 0
var t3: int = 0

var c1: Vector2i = Vector2i(0, 0) # player hole 1
var c2: Vector2i = Vector2i(0, 0) # player hole 2
var c3: Vector2i = Vector2i(0, 0) # flop 1
var c4: Vector2i = Vector2i(0, 0) # flop 2
var c5: Vector2i = Vector2i(0, 0) # flop 3
var c6: Vector2i = Vector2i(0, 0) # turn
var c7: Vector2i = Vector2i(0, 0) # river
var c8: Vector2i = Vector2i(0, 0) # opponent hole 1
var c9: Vector2i = Vector2i(0, 0) # opponent hole 2
  
var B1: int = 0
var B2: int = 0
var B3: int = 0

var M: int = 5       
var blind_b: int = 1  


func set_cards9(v1:Vector2i, v2:Vector2i, v3:Vector2i, v4:Vector2i, v5:Vector2i, v6:Vector2i, v7:Vector2i, v8:Vector2i, v9:Vector2i) -> void:
	c1 = v1; c2 = v2; c3 = v3; c4 = v4; c5 = v5; c6 = v6; c7 = v7; c8 = v8; c9 = v9

func set_cards9_by_ints(r1:int,s1:int, r2:int,s2:int, r3:int,s3:int, r4:int,s4:int, r5:int,s5:int, r6:int,s6:int, r7:int,s7:int, r8:int,s8:int, r9:int,s9:int) -> void:
	c1 = Vector2i(r1, s1)
	c2 = Vector2i(r2, s2)
	c3 = Vector2i(r3, s3)
	c4 = Vector2i(r4, s4)
	c5 = Vector2i(r5, s5)
	c6 = Vector2i(r6, s6)
	c7 = Vector2i(r7, s7)
	c8 = Vector2i(r8, s8)
	c9 = Vector2i(r9, s9)


func set_cards9_from_array(cards:Array) -> void:
	c1 = cards[0]; c2 = cards[1]; c3 = cards[2]; c4 = cards[3]; c5 = cards[4]
	c6 = cards[5]; c7 = cards[6]; c8 = cards[7]; c9 = cards[8]


func set_time(_t1:int, _t2:int, _t3:int) -> void:
	t1 = _t1; t2 = _t2; t3 = _t3


func set_chips(_B1:int, _B2:int, _B3:int) -> void:
	B1 = _B1; B2 = _B2; B3 = _B3
