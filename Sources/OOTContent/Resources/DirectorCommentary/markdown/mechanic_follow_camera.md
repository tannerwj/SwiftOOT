OoT's default camera is always balancing three goals:

1. keep Link readable,
2. preserve the sense of space around him,
3. avoid clipping straight through nearby geometry.

The result is a camera that constantly smooths, snaps, and compromises. It looks simple when it works, but under the hood it is continuously reacting to player heading, scene bounds, and presentation overrides.
