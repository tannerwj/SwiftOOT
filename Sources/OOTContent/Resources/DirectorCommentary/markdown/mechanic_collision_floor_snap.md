Movement is grounded because the player controller asks collision questions every frame.

- Where is the floor under the next position?
- Did the attempted move cross a wall plane?
- How much should the controller correct before the player tunnels through geometry?

That probing is what makes OoT's rooms feel solid. The camera and actor systems can be expressive because collision keeps the player's movement anchored to believable space.
