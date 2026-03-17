Queen Gohma's fight lives in a **dedicated boss scene**, not the same scene bundle as the rest of the dungeon.

- That keeps the arena camera, collision, cutscene setup, and boss-only assets isolated from ordinary room traversal.
- Scene transitions are doing real gameplay work here: entering the boss room is effectively loading a different ruleset, not just opening a new door.
- Boss scenes like this are part of how OoT keeps complicated encounters manageable on limited memory.
