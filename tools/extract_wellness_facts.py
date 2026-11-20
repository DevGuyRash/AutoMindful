"""Generate factual, display-only Wellness data from a checked local Lifestyle install.

No mod code is executed or copied. Supply the directory containing 42/mod.info
and common/media/lua, or use --check to compare the committed add-on data.
"""
import argparse
import hashlib
from pathlib import Path
import re

VERSION = "0.4.0.3"
PINS = {
    "client/ISMeditation/Mindfulness.lua": "dd3798faeea58e67093deb21276aa7f995a5b15982cb50c848ab956afc8c2952",
    "shared/TimedActions/LSMeditateAction.lua": "a0aea45b7d13286ad5efeff9f215fd5280d4d9fc799cdcb6929688ebb323a610",
    "client/ISMeditation/ZenWellnessContextMenu.lua": "8510da30c9c59ddc6e7275e6d23019d78fe7cf42d6608dfc7c77bfad01daa2f6",
    "shared/TimedActions/LSYogaAction.lua": "00430eadeba1d79ee592697de1a6ccec3de1e9f5b6f5a3de423d3fe410102e32",
    "shared/LSUtil.lua": "4e6b73720eefcafd828773067327664aa854228a6080705cf948c9cecc149ddb",
    "client/LSEffects/LSPerTenMinutes.lua": "d4555e319a83042f8e1179a5f0aa593c1c33cdee942b0632b57fafa92ded1dbd",
    "client/LSMoodleManager.lua": "7fd07315ac820143f47db01ac8f3c4fc8f5f7b80241ddb4da47c69a362ac8eee",
}


def exact(pattern, source, label, flags=0):
    matches = re.findall(pattern, source, flags)
    if len(matches) != 1:
        raise ValueError(f"Unexpected upstream shape for {label}")
    return matches[0]


def derive(root):
    metadata = (root / "42/mod.info").read_text(encoding="utf-8").splitlines()
    if metadata.count("id=LifestyleHobbies") != 1 or metadata.count(f"modversion={VERSION}") != 1:
        raise ValueError(f"Expected official LifestyleHobbies {VERSION}")
    source = []
    for name, digest in PINS.items():
        contents = (root / "common/media/lua" / name).read_bytes()
        if hashlib.sha256(contents).hexdigest() != digest:
            raise ValueError(f"Unverified upstream source: {name}")
        source.append(contents.decode("utf-8-sig").replace("\r\n", "\n"))
    mind, meditation, menu, yoga, util, ten_minutes, moodles = source

    block = exact(r"local function getMeditationLevelTable\(\)\s+return \{\s*(.*?)\n\s*\}\s*end",
                  mind, "Mindfulness duration table", re.S)
    times = {}
    row = r'\s*\{lvl=(\d+),trait="(disciplined|none)",duration=(\d+),effect=\d+(?:\.\d+)?\},\s*'
    for line in block.splitlines():
        match = re.fullmatch(row, line)
        if not match:
            raise ValueError("Unrecognized Mindfulness row")
        rank, trait, minutes = match.groups()
        key = (int(rank), trait)
        if key in times or not 0 < int(minutes) <= 1000:
            raise ValueError("Duplicate or invalid Mindfulness duration")
        times[key] = int(minutes)
    if set(times) != {(rank, trait) for rank in range(3, 11) for trait in ("none", "disciplined")}:
        raise ValueError("Incomplete Mindfulness durations")
    first = 1 + int(exact(r"if \(self\.skillLevel > (\d+)\) and \(self\.mindfulState < 0\.6\) then",
                          meditation, "first Mindfulness rank"))
    second = 1 + int(exact(r"if \(skillLevel > (\d+)\) and \(mindfulState < 0\.4\)",
                           meditation, "Strong Mindfulness rank"))
    third = int(exact(r"if \(skillLevel == (\d+)\) and \(mindfulState < 0\.6\)",
                      meditation, "Perfect Mindfulness rank"))
    if not 3 <= first < second < third <= 10:
        raise ValueError("Invalid Mindfulness unlock order")
    duration = exact(r"if durationSO == 1 then\s+MindfulDurationMultiplier = ([\d.]+)\s+"
                     r"elseif durationSO == 3 then\s+MindfulDurationMultiplier = ([\d.]+)",
                     mind, "sandbox duration mode")

    block = exact(r"local function getYogaActionValues\(level\).*?local t = \{\s*(.*?)\n\s*\}",
                  menu, "Yoga rank table", re.S)
    sequences = {}
    row = r'\s*l(\d+) = \{"(Beginner|Intermediate|Advanced|Master)",\d+,(\d+),(\d+)\},\s*'
    for line in block.splitlines():
        match = re.fullmatch(row, line)
        if not match:
            raise ValueError("Unrecognized Yoga row")
        rank, group, efficiency, poses = match.groups()
        rank, efficiency, poses = int(rank), int(efficiency), int(poses)
        if rank in sequences or not (0 < efficiency <= 6 and 0 < poses <= 20):
            raise ValueError("Duplicate or invalid Yoga rank")
        sequences[rank] = (group, efficiency, poses)
    if set(sequences) != set(range(11)):
        raise ValueError("Incomplete Yoga ranks")
    step, cap = map(int, exact(r"ZombRand\(100\)\+1\+(\d+)\*self\.skillLevel <= math\.min\((\d+),",
                               yoga, "Yoga pose fall roll"))
    if not 0 < step <= cap <= 100:
        raise ValueError("Unrecognized Yoga fall calculation")
    no_fall_rank = (cap + step - 1) // step

    # Check the fresh grant, actual cooldown registration and displayed Moodle floor.
    # Do not reduce timing to decimal closed-form math: native Lua repeatedly
    # subtracts a binary double, which matters at the 0.20 boundary.
    grant = float(exact(
        r'if self\.skillLevel ~= 0 and not self\.doFailState then '
        r'self\.playerData\.LSMoodles\["Zen"\]\.Value = ([\d.]+)\*self\.efficiency;',
        yoga, "successful Yoga Zen grant"))
    exact(r"\bo\.efficiency = (Args\[3\])", yoga, "Yoga efficiency source")
    registered = exact(r"\[10\] = \{\s*\{ -- moodles\s*(.*?)\s*\},", util, "10 minute moodle list", re.S)
    if registered.strip() != '"Zen",':
        raise ValueError("Unrecognized Zen cooldown registration")
    exact(r"Events\.EveryTenMinutes\.Add\((LSEveryTenMinutes)\)", ten_minutes, "Zen decay event")
    delta, cutoff = map(float, exact(
        r"\.Value = playerData\.LSMoodles\[value\]\.Value - ([\d.]+)\s*end\s*"
        r"if playerData\.LSMoodles\[value\] and \(playerData\.LSMoodles\[value\]\.Value < ([\d.]+)\) then"
        r"\s*playerData\.LSMoodles\[value\]\.Value = 0",
        ten_minutes, "Zen clock step and cutoff"))
    min_level = float(exact(r"elseif value >= ([\d.]+) then\s*return 1", moodles, "Moodle activation floor"))
    if not 0 < delta < min_level <= cutoff <= grant <= 1.0:
        raise ValueError("Unrecognized Zen decay thresholds")
    zen_ticks = {}
    for efficiency in sorted({row[1] for row in sequences.values()}):
        value = grant * efficiency
        if value > 1:
            raise ValueError("Unrecognized Zen starting value")
        for tick in range(1, 201):
            value -= delta
            if value < cutoff:
                zen_ticks[efficiency] = tick
                break
        else:
            raise ValueError("Unrecognized Zen expiry")

    actions, aliases = exact(
        r"local function getMeditationActionValues\(level\)\s*--[^\n]*\s*local t = \{\s*(.*?)"
        r"\n\s*\}\s*([^\n]+)\s*return t\[level\]",
        menu, "active meditation actions", re.S)
    lengths = {}
    for line in actions.splitlines():
        action = re.fullmatch(r"\s*\[(\d+)\]\s*=\s*\{\{[^{}]*\},\s*\d+,\s*(\d+),.*\},\s*", line)
        if not action or int(action[1]) in lengths:
            raise ValueError("Unrecognized meditation action duration row")
        lengths[int(action[1])] = int(action[2])
    if not re.fullmatch(r"(?:\s*t\[\d+\]\s*=\s*t\[\d+\]\s*;)+\s*", aliases):
        raise ValueError("Unrecognized meditation aliases")
    for alias, origin in re.findall(r"t\[(\d+)\]\s*=\s*t\[(\d+)\]", aliases):
        alias, origin = int(alias), int(origin)
        if alias in lengths or origin not in lengths:
            raise ValueError("Unrecognized duration alias")
        lengths[alias] = lengths[origin]
    if set(lengths) != set(range(11)) or min(lengths.values()) <= 0 or any(
            lengths[rank] < lengths[rank - 1] for rank in range(1, 11)):
        raise ValueError("Unexpected meditation action durations")
    exact(r"function LSMeditateAction:getDuration\(\)\s*if self.character:isTimedActionInstant\(\) then"
          r"\s*return 1\s*end\s*return (self.length)", meditation, "meditation native session length")
    exact(r"\bo\.length = (length)", meditation, "meditation constructor session length")
    exact(r"return actionType, levelArgs\[2\], (levelArgs\[3\]), levelArgs\[4\]", menu, "stock action length field")

    pool_text = exact(r"local function getActionTable\(playerSkill, actionTable\)\s*local t = \{\s*(.*?)"
                      r"\n\s*\}\s*for _, v in pairs\(t\) do\s*if v.lvl <= playerSkill",
                      yoga, "Yoga pose pool ladder", re.S)
    poses, seen_poses = {}, set()
    for line in pool_text.splitlines():
        row = re.fullmatch(r'\s*\{lvl=(\d+),anims=\{("[\w]+"(?:,"[\w]+")*)\}\},\s*', line)
        if not row or int(row[1]) in poses:
            raise ValueError("Unrecognized Yoga pose pool row")
        names = re.findall(r'"(\w+)"', row[2])
        if len(set(names)) != len(names) or seen_poses.intersection(names):
            raise ValueError("Unexpected duplicate Yoga pose")
        seen_poses.update(names)
        poses[int(row[1])] = len(names)
    if set(poses) != {0} | {r for r in range(1, 11) if sequences[r][0] != sequences[r - 1][0]}:
        raise ValueError("Yoga pose ladder and ranks do not agree")
    exact(r"if self.animVars.parent or self.poseCount < (self.poseLimit) then", yoga, "nominal pose target")
    exact(r"function LSYogaAction:reduceXP\(\)[^\n]*\n\s*if (self.skillLevel >= 10 or self.gainedXP == 0) then return",
          yoga, "Yoga cancellation penalty")
    cap_text = exact(r"local function getLevelLimit\(key\)\s*local t = \{\s*(.*?)\n\s*\}\s*return t\[key\]",
                     yoga, "Yoga completion bonus limits", re.S)
    bonus = {}
    for line in cap_text.splitlines():
        row = re.fullmatch(r"\s*\[(\d+)\]\s*=\s*(\d+),\s*", line)
        if not row or int(row[1]) in bonus:
            raise ValueError("Unrecognized Yoga completion bonus cap row")
        bonus[int(row[1])] = int(row[2])
    if set(bonus) != set(range(10)) or min(bonus.values()) <= 0:
        raise ValueError("Incomplete Yoga completion bonus")
    exact(r"local limit = getLevelLimit\(self.skillLevel\)\s*bonusXP = (math.min\(limit, bonusXP\))",
          yoga, "Yoga finish bonus bound")

    def lua_dict(values):
        return "{" + ",".join(f"[{key}]={value}" for key, value in sorted(values.items())) + "}"

    output = [
        "-- Generated by tools/extract_wellness_facts.py; no upstream code included.",
        "return {",
        f'    version="{VERSION}",',
        f"    meditationUnlocks={{{first},{second},{third}}},",
        f"    durationScale={{{duration[0]},1,{duration[1]}}},",
        "    duration={",
    ]
    for rank in range(3, 11):
        output.append(f'        [{rank}]={{{times[rank,"none"]},{times[rank,"disciplined"]}}},')
    output += ["    },", f"    meditationLengths={lua_dict(lengths)},",
               f"    noFallRank={no_fall_rank},", "    zenTickMinutes=10,",
               f"    zenTicks={lua_dict(zen_ticks)},", f"    yogaNewPoses={lua_dict(poses)},",
               f"    yogaCompletionCap={lua_dict(bonus)},", "    yoga={"]
    for rank, (group, efficiency, poses) in sorted(sequences.items()):
        output.append(f'        [{rank}]={{"{group}",{efficiency},{poses}}},')
    return "\n".join(output + ["    },", "}", ""])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("lifestyle", type=Path)
    parser.add_argument("--check", type=Path, help="Check existing data instead of printing the generated Lua")
    options = parser.parse_args()
    try:
        result = derive(options.lifestyle)
        if options.check:
            if options.check.read_bytes() != result.encode():
                raise ValueError("Display facts differ from the checked official source")
            print("Lifestyle Wellness data matches the pinned source")
        else:
            print(result, end="")
    except (OSError, UnicodeError, ValueError) as error:
        parser.exit(1, f"Wellness data: {error}\n")


if __name__ == "__main__":
    main()
