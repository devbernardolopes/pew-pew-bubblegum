class_name CombatGate
extends RefCounted
## A static-only ceasefire gate: named locks that stop one or both teams from
## firing, so several systems can close the gate without stomping each other.
## Locks are keyed by [param reason]; locking the same reason again overwrites
## its flags. The gate never touches projectiles already in flight.
##
## Statics survive a scene reload, so the level clears the gate in
## [code]StageDirector._ready[/code] and on game over.

## reason (StringName) -> {"friend": bool, "foe": bool}
static var _locks: Dictionary = {}


## Replaces (or adds) the lock named [param reason], covering the teams given.
static func lock(reason: StringName, lock_friend: bool = true, lock_foe: bool = true) -> void:
	_locks[reason] = {"friend": lock_friend, "foe": lock_foe}


## Removes only the lock named [param reason]; other locks stay.
static func unlock(reason: StringName) -> void:
	_locks.erase(reason)


## Removes every lock.
static func clear() -> void:
	_locks.clear()


## Whether a lock named [param reason] currently exists, whatever it covers.
static func is_locked(reason: StringName) -> bool:
	return _locks.has(reason)


## Whether [param team] may fire right now: false when any lock covers it.
## [code]NEUTRAL[/code] is always open.
static func is_open_for(team: Helpers.TEAM) -> bool:
	if team == Helpers.TEAM.NEUTRAL:
		return true
	for reason: StringName in _locks:
		var flags: Dictionary = _locks[reason] as Dictionary
		if team == Helpers.TEAM.FRIEND and bool(flags.get("friend", false)):
			return false
		if team == Helpers.TEAM.FOE and bool(flags.get("foe", false)):
			return false
	return true
