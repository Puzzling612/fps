# bt.gd — a minimal, allocation-free Behavior Tree.
#
# Nodes are stateless and receive the agent (the enemy) at tick time, so a tree
# can be built once and ticked every decision step. Conditions/Actions wrap a
# Callable, which keeps the tree declarative without a subclass explosion.
#
# Status: SUCCESS / FAILURE / RUNNING.
class_name BT
extends RefCounted

const SUCCESS := 0
const FAILURE := 1
const RUNNING := 2

# ── Base node ──
class BTNode extends RefCounted:
	func tick(_agent) -> int:
		return BT.FAILURE

# ── Composite: Selector (OR) — first child that doesn't FAIL wins ──
class Selector extends BTNode:
	var children: Array = []
	func _init(c: Array = []) -> void:
		children = c
	func tick(agent) -> int:
		for ch in children:
			var s: int = ch.tick(agent)
			if s != BT.FAILURE:
				return s
		return BT.FAILURE

# ── Composite: Sequence (AND) — fails on first non-SUCCESS ──
class Sequence extends BTNode:
	var children: Array = []
	func _init(c: Array = []) -> void:
		children = c
	func tick(agent) -> int:
		for ch in children:
			var s: int = ch.tick(agent)
			if s != BT.SUCCESS:
				return s
		return BT.SUCCESS

# ── Leaf: Condition — Callable(agent) -> bool ──
class Condition extends BTNode:
	var fn: Callable
	func _init(f: Callable) -> void:
		fn = f
	func tick(agent) -> int:
		return BT.SUCCESS if fn.call(agent) else BT.FAILURE

# ── Leaf: Action — Callable(agent) -> int status (or bool) ──
class Action extends BTNode:
	var fn: Callable
	func _init(f: Callable) -> void:
		fn = f
	func tick(agent) -> int:
		var r = fn.call(agent)
		if typeof(r) == TYPE_BOOL:
			return BT.SUCCESS if r else BT.FAILURE
		return int(r)

# ── Decorator: Inverter ──
class Inverter extends BTNode:
	var child: BTNode
	func _init(c: BTNode) -> void:
		child = c
	func tick(agent) -> int:
		var s: int = child.tick(agent)
		if s == BT.SUCCESS: return BT.FAILURE
		if s == BT.FAILURE: return BT.SUCCESS
		return s
