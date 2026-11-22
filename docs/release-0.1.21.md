# AutoMindful 0.1.21

- Visits a permitted, usable Lifestyle toilet and returns to the original training spot; if none can be used, waits for Lifestyle to allow ground relief.
- Uses fragrance only when it can remove the current negative hygiene moodle, otherwise uses the game’s Wash Yourself option at an eligible source. Does not wash apparel.
- Takes stock painkillers at 10/100 if there is no active dose. Repeats only above 10 after confirmed effects expire; uncertainty does not open a retry.
- Uses Lifestyle's actual Yoga endurance setting, without requiring recovery to 95%. An already-running meditation can finish if boredom rises and there is no usable reading; Lifestyle's normal limit still applies to beginning the next session.
- Shows what a care break is waiting for, and the Stop callback does not claim how it was invoked. Safe wait, cancellation, supply-loan and original-spot behavior remain in place.
