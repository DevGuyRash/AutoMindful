# AutoMindful 0.1.19

- When a native walk home fails after a care trip, AutoMindful waits briefly and can try again twice. It resolves the original square afresh and asks the game's pathfinder, not an alternate tile.
- A truly blocked or inaccessible destination still stops the session. The mod waits for other real actions to finish without taking their place in the queue. Manual movement, Stop, aim, danger or switching scouting off still take precedence over another retry.
- Supplies continue to follow their original return rules. Retrying the route does not reread, reborrow or reuse a spent supply.
