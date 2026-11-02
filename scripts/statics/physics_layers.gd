class_name PhysicsLayers
extends RefCounted

## Bit masks for the named 2D physics layers in Project Settings.
## For each pair of interacting things, exactly one side lists the other in
## its mask, otherwise every hit fires twice.
const UNIVERSE: int = 1
const FRIEND: int = 2
const FOE: int = 4
const FRIEND_PROJECTILE: int = 8
const FOE_PROJECTILE: int = 16
