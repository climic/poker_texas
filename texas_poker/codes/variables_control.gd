extends Node2D
class_name VariablesControl

# Editable in Inspector; keep them as positive integers
@export var M: int = 100          # Effective stack per player at match start
@export var blind_b: int = 1      # Small blind size

func _ready() -> void:
	# Push current Inspector values into Globals at startup.
	Globals.M = M
	Globals.blind_b = blind_b
	# Initialize player's off-table stack here (B2/B3 are left as-is on purpose).
	Globals.B1 = M
