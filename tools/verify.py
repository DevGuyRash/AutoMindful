"""Build first, then check contracts in Lua 5.1 and optionally installed Kahlua."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

from build import ROOT, build


def fingerprint() -> str:
    digest = hashlib.sha256()
    for directory in ("mods", "tests", "tools", "workshop", ".github"):
        for path in sorted((ROOT / directory).rglob("*")):
            if path.is_file() and "__pycache__" not in path.parts:
                digest.update(path.relative_to(ROOT).as_posix().encode())
                digest.update(path.read_bytes())
    return digest.hexdigest()


def check(evidence: Path, name: str, command: list[str], *, cwd: Path = ROOT, env=None) -> dict:
    started = time.monotonic()
    log = evidence / f"{name}.log"
    with log.open("w", encoding="utf-8") as output:
        result = subprocess.run(command, cwd=cwd, env=env, stdout=output, stderr=subprocess.STDOUT, timeout=180)
    passed = result.returncode == 0
    print(f"{name}: {'PASS' if passed else 'FAIL'}", flush=True)
    return {"name": name, "passed": passed, "exitCode": result.returncode,
            "elapsedSeconds": round(time.monotonic() - started, 3), "log": str(log)}


def verify(evidence: Path, game: Path | None, lifestyle: Path | None, tag: str | None = None) -> bool:
    evidence = evidence.expanduser().resolve()
    evidence.mkdir(parents=True, exist_ok=False)
    source_before = fingerprint()
    build(evidence / "package", tag)
    lua = shutil.which("lua5.1")
    if not lua:
        raise RuntimeError("Lua 5.1 (lua5.1) is required")
    reference_root = None
    references = {}
    if lifestyle:
        reference_root = lifestyle.expanduser().resolve() / "common/media"
        for name in ("perks.txt", "lua/client/Helper/HSMng.lua", "lua/client/ISMeditation/ZenWellnessContextMenu.lua",
                     "lua/shared/TimedActions/LSMeditateAction.lua", "lua/shared/TimedActions/LSYogaAction.lua"):
            references[name] = hashlib.sha256((reference_root / name).read_bytes()).hexdigest()
    command = [lua, "tests/contracts.lua"]
    if reference_root:
        command.append(str(reference_root))
    checks = [check(evidence, "portable-contracts", command)]
    for name, script in (("ui-contracts", "ui.lua"), ("progress-contracts", "progress.lua"),
                         ("skills-pane-contracts", "skills_pane.lua"), ("yoga-bar-contracts", "yoga_bar.lua"),
                         ("completion-hud-contracts", "completion_hud.lua"),
                         ("endurance-journey-contracts", "endurance_journey.lua"),
                         ("consumable-contracts", "consumables.lua"), ("supply-policy-contracts", "supply_policy.lua"),
                         ("water-source-contracts", "water_sources.lua"), ("fluid-transfer-contracts", "fluid_transfers.lua"),
                         ("pain-policy", "pain_care.lua"), ("pain-supplies", "pain_supplies.lua"),
                         ("pain-journey", "pain_journey.lua"), ("nearby-contracts", "nearby.lua")):
        suite = [lua, "tests/" + script]
        if game and script in ("water_sources.lua", "fluid_transfers.lua"):
            suite.append(str(game.expanduser().resolve() / "media"))
        elif reference_root and script == "progress.lua":
            suite.append(str(reference_root))
        checks.append(check(evidence, name, suite))
    checks.append(check(evidence, "release-contracts", [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-p", "test_release.py"]))
    checks.append(check(evidence, "build-recovery", [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-p", "test_build_recovery.py"]))
    native_scope = "not requested"
    if game:
        game = game.expanduser().resolve()
        checks.append(check(evidence, "stock-queue-handoff", [lua, "tests/stock_queue.lua", str(game / "media")]))
        checks.append(check(evidence, "stock-queue-kahlua-lookup",
                            [lua, "tests/stock_queue.lua", str(game / "media"), "--kahlua-queue-lookup"]))
        checks.append(check(evidence, "stock-native-aim-stop", [lua, "tests/stock_aim.lua", str(game / "media")]))
        checks.append(check(evidence, "stock-context-icons", [lua, "tests/stock_context_icons.lua", str(game / "media")]))
        checks.append(check(evidence, "stock-pain-action", [lua, "tests/stock_pain.lua", str(game / "media")]))
        checks.append(check(evidence, "stock-skills-pane", [lua, "tests/stock_skills_pane.lua", str(game / "media")]))
        java, jar = game / "jre64/bin/java", game / "projectzomboid.jar"
        compiler = shutil.which("javac")
        if not java.is_file() or not jar.is_file() or not compiler:
            raise RuntimeError("Native check requires the installed game JAR, bundled JVM and JDK 25 javac")
        with tempfile.TemporaryDirectory(prefix="automindful-kahlua-") as temporary:
            classes = Path(temporary)
            checks.append(check(evidence, "native-compile", [compiler, "--release", "25", "-cp", str(jar),
                "-d", str(classes), str(ROOT / "tools/KahluaCheck.java"), str(ROOT / "tools/SteamWorkshopBootstrap.java")]))
            if checks[-1]["passed"]:
                env = {key: value for key, value in os.environ.items() if key not in {
                    "JAVA_TOOL_OPTIONS", "JDK_JAVA_OPTIONS", "_JAVA_OPTIONS", "JAVA_OPTS", "CLASSPATH", "LD_PRELOAD"}}
                for name, script in (("native-contracts", "contracts.lua"), ("native-ui-contracts", "ui.lua"),
                                     ("native-skills-pane", "skills_pane.lua"), ("native-yoga-bar", "yoga_bar.lua"),
                                     ("native-stock-skills-pane", "stock_skills_pane.lua"),
                                     ("native-stock-context-icons", "stock_context_icons.lua"),
                                     ("native-completion-hud-contracts", "completion_hud.lua"),
                                     ("native-endurance-journey-contracts", "endurance_journey.lua"),
                                     ("native-stock-queue-handoff", "stock_queue.lua"),
                                     ("native-stock-aim-stop", "stock_aim.lua"), ("native-stock-pain-action", "stock_pain.lua"),
                                     ("native-pain-policy", "pain_care.lua"), ("native-pain-supplies", "pain_supplies.lua"),
                                     ("native-pain-journey", "pain_journey.lua"),
                                     ("native-progress-contracts", "progress.lua"), ("native-supply-policy-contracts", "supply_policy.lua"),
                                     ("native-consumable-contracts", "consumables.lua"),
                                     ("native-water-source-contracts", "water_sources.lua"),
                                     ("native-fluid-transfer-contracts", "fluid_transfers.lua"),
                                     ("native-nearby-contracts", "nearby.lua")):
                    suite_reference = game / "media" if script in ("water_sources.lua", "fluid_transfers.lua", "stock_queue.lua", "stock_aim.lua", "stock_pain.lua", "stock_context_icons.lua", "stock_skills_pane.lua") else reference_root
                    command = [str(java), "-Xmx512m", "-Djava.awt.headless=true", "-cp", os.pathsep.join((str(classes), str(jar))),
                               "KahluaCheck", str(ROOT), str(suite_reference) if suite_reference else "-", script]
                    checks.append(check(evidence, name, command, cwd=game, env=env))
        native_scope = "Installed Kahlua interpreter. Game, player, queue, mood and XP receiver boundaries are explicit doubles."
    stable = source_before == fingerprint()
    report = {"passed": stable and all(item["passed"] for item in checks), "sourceStable": stable,
              "sourceSha256": source_before, "checks": checks, "nativeScope": native_scope,
              "upstreamSha256": references,
              "progressionScope": "With --lifestyle, real upstream menu/action/hidden-skill Lua and raw perk metadata run under an accelerated action clock. This is not native gameplay or multiplayer progression."}
    (evidence / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Report: {evidence / 'report.json'}", flush=True)
    return report["passed"]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", type=Path)
    parser.add_argument("--tag", help="Require the package version to match this stable release tag")
    parser.add_argument("--lifestyle", type=Path, help="Installed Lifestyle mod root; read without modification")
    parser.add_argument("--evidence", type=Path, default=Path.home() / ".local/state/app-verification/AutoMindful" /
                        time.strftime("verify-%Y%m%d-%H%M%S", time.gmtime()))
    args = parser.parse_args()
    raise SystemExit(0 if verify(args.evidence, args.game, args.lifestyle, args.tag) else 1)
