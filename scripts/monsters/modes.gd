extends RefCounted
## Shared enums for the monster brains. Kept in lock-step with Monster.State / Monster.Mode
## (scripts/monster.gd); a separate file so the brains need not preload monster.gd, which
## preloads them. New values are only ever appended (the ints cross the wire).

enum State { WANDER, CHASE, STUNNED, SEDATED }
## The Service Dog's own modes (service_dog_brain.gd) are the DOG_* tail: appended, never renumbered.
enum Mode { IDLE, WANDER, LISTEN, RUSH, SEARCH, STALK, STUNNED, RETREAT, SEDATED, CHARGE, ECHO, WAIL,
	DOG_SEEK, DOG_APPROACH, DOG_OFFER, DOG_WARN, DOG_REAR, DOG_RETRIEVE }
