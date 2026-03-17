`En_Ko` is a classic OoT pattern: one actor overlay covers **many NPC variants**.

- The params field decides which Kokiri child you got, which message ids to use, and which idle behaviors or schedules should be active.
- Reusing one actor this way kept memory pressure down and let designers populate a whole village without building bespoke code for every child.
- When the game feels "authored" here, a lot of that authorship is really data selection feeding a reusable state machine.
