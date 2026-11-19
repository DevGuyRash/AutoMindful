# AutoMindful 0.1.16

- When training yields to a queued workout, drink, or another ordinary action, AutoMindful releases its temporary queue hooks. Later changes from the game or other mods remain visible to that player. Hooks intentionally installed on that specific player are preserved, even if they originally used the stock function.
- This replaces the local 0.1.15 candidate. It retains the Yoga rank row directly below Meditation, distinct context icons with stock fallbacks, and the other training and supply changes since public 0.1.5.

## Verification

The regression uses unmodified Build 42 queue/base Lua in the installed Kahlua interpreter. It changes class methods **after** a handoff and checks actual lookup, not interpreter-specific `rawget` results. It also exercises inherited and explicit player hooks, a deferred native head, exact foreign-action order, once-only starts, and an unknown native action. Java/player action handles are doubles in this test; it is not a gameplay or Workshop acceptance receipt.

Portable CI additionally models the installed raw lookup contract for these queue instances only. The normal Lua and installed Kahlua runs keep their real lookup implementations.
