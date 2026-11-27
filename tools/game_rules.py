"""Check Second Nature's copy of the game's nutrition rules against the installed game.

Nutrition.lua runs B42's own rules forward (zombie.characters.BodyDamage.Nutrition,
and the protein band in IsoGameCharacter$XP.AddXP). The values are read live from
the survivor; the rules are constants of the game. This reads those constants from
projectzomboid.jar with javap, so a game update that changes one fails here instead
of quietly making every forecast wrong.
"""

import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
CLIENT = ROOT / "mods/AutoMindful/common/media/lua/client"
NUTRITION = "zombie.characters.BodyDamage.Nutrition"
XP = "zombie.characters.IsoGameCharacter$XP"

# Each rule and where the game keeps it: a constant field, or a literal in a method.
# A rule given as "a/b" is checked as the ratio (the game stores a multiplier).
EXPECTED = [
    ("decay.carbs", NUTRITION, "field", "carbohydratesDecreraseMale"),
    ("decay.fat", NUTRITION, "field", "lipidsDecreraseMale"),
    ("decay.protein", NUTRITION, "field", "proteinsDecreraseMale"),
    ("burn.resting", NUTRITION, "field", "caloriesDecreaseMaleNormal"),
    ("burn.running", NUTRITION, "field", "caloriesDecreaseMaleExercise"),
    ("burn.asleep", NUTRITION, "field", "caloriesDecreaseMaleSleeping"),
    ("gain.line", NUTRITION, "field", "caloriesToGainWeightMale"),
    ("gain.full", NUTRITION, "field", "caloriesToGainWeightMaxMale"),
    ("gain.rate", NUTRITION, "field", "weightGain"),
    ("loss.full", NUTRITION, "field", "caloriesDecreaseMax"),
    ("loss.rate", NUTRITION, "field", "weightLoss"),
    ("burn.walking/burn.running", NUTRITION, "updateCalories", None),
    ("burn.sprinting/burn.running", NUTRITION, "updateCalories", None),
    ("gain.slow", NUTRITION, "updateWeight", None),
    ("gain.fast", NUTRITION, "updateWeight", None),
    ("gain.perKg", NUTRITION, "updateWeight", None),
    ("gain.rich", NUTRITION, "updateWeight", None),
    ("gain.richer", NUTRITION, "updateWeight", None),
    ("loss.perKg", NUTRITION, "updateWeight", None),
    ("loss.from", NUTRITION, "updateWeight", None),
    ("calories.low", NUTRITION, "setCalories", None),
    ("calories.high", NUTRITION, "setCalories", None),
    ("macros.low", NUTRITION, "setCarbohydrates", None),
    ("macros.high", NUTRITION, "setCarbohydrates", None),
    ("weight.floor", NUTRITION, "setWeight", None),
    ("bands.1", NUTRITION, "applyTraitFromWeight", None),
    ("bands.2", NUTRITION, "applyTraitFromWeight", None),
    ("bands.3", NUTRITION, "applyTraitFromWeight", None),
    ("bands.4", NUTRITION, "applyTraitFromWeight", None),
    ("bands.5", NUTRITION, "applyTraitFromWeight", None),
    ("protein.bonus", XP, "AddXP", None),
    ("protein.bonusTop", XP, "AddXP", None),
    ("protein.penalty", XP, "AddXP", None),
]

# Prints every rule (and each band's upper weight) as one JSON object.
DUMP = r'''
package.path = "%s/?.lua;" .. package.path
local Nutrition = require "AutoMindful/Nutrition"
local out = {}
for group, values in pairs(Nutrition.rules) do
    for key, value in pairs(values) do out[#out + 1] = string.format('"%%s.%%s": %%.17g', group, key, value) end
end
for index, band in ipairs(Nutrition.bands) do
    if band.upTo < math.huge then out[#out + 1] = string.format('"bands.%%d": %%.17g', index, band.upTo) end
end
print("{" .. table.concat(out, ", ") .. "}")
'''

NUMBER = re.compile(r"//\s*(?:float|double|int|long)\s+(-?[0-9.]+(?:E-?[0-9]+)?)[fdl]?\b|\b(?:sipush|bipush)\s+(-?[0-9]+)")


def disassemble(javap: str, jar: Path, cls: str):
    text = subprocess.run([javap, "-c", "-p", "-constants", "-cp", str(jar), cls],
                          check=True, capture_output=True, text=True).stdout
    fields = {name: float(value) for name, value in re.findall(
        r"^\s+private final (?:float|int|double) (\w+) = (-?[0-9.]+(?:E-?[0-9]+)?)[fd]?;$", text, re.M)}
    methods, current = {}, None
    for line in text.splitlines():
        header = re.match(r"^  \S.*?\b(\w+)\(.*\);$", line)
        if header:
            current = methods.setdefault(header.group(1), set())
        elif current is not None:
            for match in NUMBER.finditer(line):
                current.add(float(match.group(1) or match.group(2)))
    return fields, methods


def same(a: float, b: float) -> bool:
    return abs(a - b) <= 1e-6 * max(1.0, abs(a), abs(b))


def ours(rules: dict, key: str) -> float:
    if "/" in key:
        top, bottom = key.split("/")
        return rules[top] / rules[bottom]
    return rules[key]


def check(game: Path) -> list[str]:
    jar = game / "projectzomboid.jar"
    javap = shutil.which("javap")
    lua = shutil.which("lua5.1")
    if not jar.is_file() or not javap or not lua:
        raise RuntimeError("Needs the installed game JAR, a JDK's javap and lua5.1")
    rules = json.loads(subprocess.run([lua, "-e", DUMP % CLIENT.as_posix()], check=True,
                                      capture_output=True, text=True).stdout)
    disassembled = {cls: disassemble(javap, jar, cls) for cls in {NUTRITION, XP}}
    problems = []
    for key, cls, where, field in EXPECTED:
        value = ours(rules, key)
        fields, methods = disassembled[cls]
        if where == "field":
            found = fields.get(field)
            if found is None or not same(found, value):
                problems.append(f"{key} = {value:g}, but {cls}.{field} is {found}")
        elif not any(same(literal, value) for literal in methods.get(where, ())):
            problems.append(f"{key} = {value:g} is not among the numbers in {cls}.{where}")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("game", type=Path, help="Project Zomboid install folder holding projectzomboid.jar")
    options = parser.parse_args()
    problems = check(options.game.expanduser().resolve())
    for problem in problems:
        print("MISMATCH", problem)
    print(f"{len(EXPECTED) - len(problems)} of {len(EXPECTED)} nutrition rules match the installed game")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
