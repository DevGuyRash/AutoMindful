# Supply selection

AutoMindful compares safe, usable portions for the survivor's current hunger and thirst. It uses the same rule for inventory, worn hydration equipment, permitted nearby items, and clean world-water sources. Nearby sources, empty vessels, and opening tools remain unavailable when adjacent collection is off.

## Choose useful restoration

1. Filter unsafe, inaccessible, rejected, or unusable supplies using native requirements. Opening recipes must have their required tools.
2. Address a native critical need before an ordinary comfort need. When both are critical, hydration comes first.
3. Predict a portion from the current remaining effects. When both needs still require restoration and a source restores both, stop the portion when the first need is satisfied, then reassess the survivor. Tiny residual changes do not force repeated microscopic sips.
4. Compare how much of the primary need the portion restores, add a bounded benefit for helping the other need, and account for worsening or unnecessarily overfilling the other need. A tiny dual-purpose item does not receive an automatic preference.
5. For equally useful hydration, prefer the largest current reserve. For otherwise equal food choices, prefer fewer opening, transfer, and return steps. Calories are not a consumption target or a selection priority.
6. Recheck after collection, opening, and fluid transfer. Return borrowed remainders, tools, and attributable empty containers. Finish the triggered care need when usable supplies remain; continue training without stock while native conditions still permit it.

The largest reserve means the amount available now, not the container's capacity. Native plumbing exposes its current water availability. Inventory fluid properties already describe their current contents. Food opening estimates come from native output metadata and are replaced by the opened item's actual properties before consumption.

The comparison uses primary coverage `P`, secondary coverage `S`, and the predicted effect on the other need. Its utility is `P + min(P, S) - penalty`; coverage is capped at one. The penalty measures added deficit or excess restoration of the other need, relative to that need or the normal comfort threshold of `0.15`. The shared restored cutoff is `0.01`, so normal need regeneration during actions cannot trap food care in tiny hydration portions. At a native critical stage, primary coverage takes priority over utility. A candidate with negative utility remains available if it is the only safe way to restore the primary need. This permits milk as sole hydration without making it the default drink for a survivor who is already fed.

## Examples

These quantities illustrate the installed native water and cow-milk effects. The selection rule uses each actual item's effects rather than recognizing item names.

| Current needs and supplies | Choice |
| --- | --- |
| Thirst `0.20`; owned `0.5 L` water and permitted nearby `5 L` water | Use the larger source and drink about `0.4 L`. |
| Hunger and thirst `0.20`; `1 L` milk and a large sink | About `0.4 L` milk restores both. |
| Hunger `0`, thirst `0.20`; milk and a sink | Prefer the sink and preserve the nourishing milk. |
| Hunger `0.15`, thirst `0.20`; milk and water | About `0.3 L` milk restores hunger first; plain water can finish the remaining thirst. |
| Hunger `0.20`, thirst `0.15`; milk and adequate plain food | About `0.3 L` milk restores thirst first; a small food portion can finish the remaining hunger. |
| Both needs `0.20`; an item restoring only `0.005` of each and adequate water | Adequate water wins over the tiny dual-purpose portion. |
| Hunger `0.15`; owned snack restoring `0.05` and nearby meal restoring `0.60` | Take a quarter of the nearby meal rather than relying on the inadequate snack first. |
| Hunger `0.15`; owned food restoring `0.20` and nearby meal restoring `0.60` | Both are adequate; prefer the convenient owned food. |
| Thirst with milk as the only safe hydration | Use a necessary milk portion, subject to native drinking restrictions. |

This policy manages hunger and thirst. It does not optimize calories, body weight, food spoilage schedules, or every mood effect. Native fullness and action restrictions still apply, and actual needs can change during an action.

## Bulk liquids and empty vessels

A safe liquid can supply hunger or thirst even when its container cannot be used for native portable drinking. AutoMindful pairs that source with a clean empty drinking vessel. It checks native transfer compatibility, capacity, ownership, and reach before queuing the game's measured fluid-transfer action. Carried-bag supplies are available without adjacent collection. Nearby vessels require that option, just like nearby food.

The portion calculation uses the amount that fits in the selected vessel. Source ranking still uses the source's full remaining reserve. A large source does not receive extra credit merely because a larger vessel is available. Transfer, pickup, opening, and return work contribute to the existing convenience comparison. Direct clean world-water drinking remains available without a vessel when the game supports it.

Existing drinks are never discarded or topped up automatically. An empty vessel must be unsealed, able to receive fluid, and usable for native drinking. Every component must belong to the native beverage or water categories. Any taint, poison, alcohol, hazardous component, or positive sickness effect rejects the mixture, regardless of dilution. Food containers also retain their normal spoilage, freezing, and cooking checks. AutoMindful inspects component properties because the tested game's combined fluid properties can omit component sickness effects.

The source and vessel have separate return records. An empty bottle borrowed from a shelf returns to that shelf after drinking, while a borrowed bucket returns to its own container with the remaining liquid. Ground origins retain their recorded position. If a transfer is interrupted, the actual partial contents stay in their respective containers. A filled vessel that becomes unsafe is returned without drinking, dumping, or mixing its contents back into the source. Normal blocked-return notices still apply.

If no suitable empty vessel is available, the report explains the missing requirement. The loop can continue training through noncritical needs, use another safe supply, or stop when a real blocking condition requires it.

## Zomboid's automatic drinking

These preferences control AutoMindful's care actions. Zomboid's separate **Automatically drink water when thirsty** option can consume carried water before the next care break. AutoMindful preserves that option. If you want its care actions to control source selection exclusively, disable the game's automatic drinking option yourself under **Options > Accessibility**. In multiplayer, the server still governs its normal drinking behavior.

The tested native `AutoDrink` hook suppresses automatic drinking whenever any callback is registered; it is not a filter for one survivor. AutoMindful does not register that global hook or temporarily change a user's global preference. Native tests checked the normal automatic-drinking interaction and repeated controlled source-selection journeys with the option disabled only in a disposable test cache.
