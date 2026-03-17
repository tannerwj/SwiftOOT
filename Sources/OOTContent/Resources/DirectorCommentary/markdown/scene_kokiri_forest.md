Kokiri Forest is a good reminder that "open world" on N64 usually meant **carefully staged chunks**, not one giant always-live map.

- The original scene is split into separate rooms, which lets the engine swap geometry and object banks as Link moves between loading boundaries.
- A lot of the village feel comes from data tables: scene headers, exits, paths, and object lists do more of the work than custom scene code.
- That structure is why this area makes such a good bootstrap scene for SwiftOOT too: it exercises traversal, NPCs, messages, and room-level rendering without needing dungeon-specific hacks first.
