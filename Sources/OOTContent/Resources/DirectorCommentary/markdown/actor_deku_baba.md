The Deku Baba is a small but very clear **enemy state machine**.

- Dormant: it waits for distance checks against the player.
- Lunging: it rotates toward Link, exposes an attack window, and times out if the player escapes.
- Stunned or dead: its combat profile changes, which is why the same enemy can go from untouchable trap to reward pinata after the right hit.

This style shows up everywhere in OoT: simple actors become expressive because the engine lets them swap collision, damage, and animation behavior per state.
