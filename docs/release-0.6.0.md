# Second Nature 0.6.0

- **Every recipe:** the kitchen now makes any dish the game has, not only soups and stews: stir fries, roasts, salads, sandwiches, burgers, tacos, burritos, pies, cakes, muffins, pasta, rice, omelettes, pizza, oatmeal and more, including recipes from other mods. It picks the base and ingredients nearby that make the best dish for the diet goal, uses what spoils first, adds one spice, and cooks it only when it needs cooking. Salads, sandwiches and burgers need no stove.
- **Cooking level counts:** rotten food goes into a recipe only from Cooking 7, as the game allows, at a sliver of its value; a new switch turns that off. Ingredients the game wants cooked first (bacon, eggs, fillets) go in cooked.
- **Safe:** never poison, alcohol, burnt or sealed food, never raw meat or eggs in a dish that is not cooked, never the frying pan in the survivor's hands, and never fishing chum. What a dish did not use goes back to the fridge.
- **Cooking crafts:** the kitchen also uses the game's cooking crafts when they lead to a better meal: an omelette in a pan, a pie crust (and the dough before it), a pot of pasta or rice, cake batter, bread dough, an opened can, sliced bread, a hot dog, and other mods' cooking crafts. Only recipes the survivor has learned and has the skill for, at a counter when the craft needs one, and never with a favourite, held-back or spoiled item.
- **Logs say why:** `dish.none` and `craft.look` record why no dish or craft was chosen.
- **Could make now:** the Kitchen tab lists the dishes the kitchen could make from what is nearby, best first, and the cooking crafts it could do, or says why there is no dish yet (no pot or bowl, nothing a recipe takes, no free stove, no running water, not enough ingredients).
- **First aid:** wounds are treated in the order of the game's own doctor menu, the most dangerous first (bleeding, the neck before an arm; glass and bullets; infections; deep wounds; fractures; burns; dirty dressings), with everything a wound needs fetched first: tweezers or a suture needle holder, disinfectant, a needle and thread, a splint or plank with ripped sheets, clean or sterile dressings. Stitches and splints come off when the game allows. Borrowed things go back to their shelf or are placed back on their floor square.
- **Clean and sterile dressings:** between wounds, dirty bandages and rags are washed in clean water and sterilized with disinfectant, vodka or whiskey, or, with no alcohol around, boiled: the largest pot nearby is filled, heated on any heat the kitchen drives, topped up as it runs low, and put back afterwards.
- **Pasta and rice from an empty pot:** the pot or saucepan is fetched and filled at a clean tap, then the craft and the dish follow. Crafts are planned up to four in a row.
- **Hot drinks:** coffee or tea while mildly thirsty, one spoon, heated, kept to drink.
- **Things put back, room made:** tools a craft borrows and lasting ingredients a dish borrows go back where they came from. When there is too much to carry, a few heavy carried things are set down near the kitchen and picked up again afterwards.
- **Beside Auto All:** while one of Auto All's jobs runs, Autopilot keeps to urgent needs, and a running relief practice gives way, so Auto All's exercise loop (and its other jobs) are no longer held up.
- **Fixes:**
  - Painkillers in a parked vehicle or on a body are found where it is. Before, Autopilot walked out to the same vehicle again and again.
  - No pause after standing up for yoga, and the survivor is no longer sat straight back down.
  - No flicker during a chase, and no sleep interrupt loop.
  - Toilet care is no longer mistaken for the player walking, and it interrupts a relief practice.
  - Dry pasta is no longer eaten raw when it could be cooked.
