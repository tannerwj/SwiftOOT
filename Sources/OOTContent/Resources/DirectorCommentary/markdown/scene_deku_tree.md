Inside the Deku Tree, puzzle flow is mostly **scene data plus specialized actors**.

- Entrances, room transitions, and trigger volumes live in the scene description, so the dungeon can hand camera moves and room loading off to generic engine systems.
- Puzzle pieces like webs, scrub ambushes, ladders, and chests are actors layered on top of that data-driven shell.
- That split is one reason OoT dungeons are readable in the decomp: the room file says *where* things happen, while the actor overlay says *how* the gimmick behaves.
