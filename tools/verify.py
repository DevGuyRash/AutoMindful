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
                     "lua/shared/TimedActions/LSMeditateAction.lua", "lua/shared/TimedActions/LSYogaAction.lua",
                     "lua/client/ISMeditation/Mindfulness.lua", "lua/client/LSMoodleManager.lua", "lua/client/ZLSUpdate.lua"):
            references[name] = hashlib.sha256((reference_root / name).read_bytes()).hexdigest()
    command = [lua, "tests/contracts.lua"]
    if reference_root:
        command.append(str(reference_root))
    checks = [check(evidence, "portable-contracts", command)]
    if lifestyle:
        checks.append(check(evidence, "lifestyle-wellness-source", [sys.executable, "tools/extract_wellness_facts.py",
            str(lifestyle.expanduser().resolve()), "--check",
            "mods/AutoMindful/common/media/lua/client/AutoMindful/WellnessFacts.lua"]))
    for name, script in (("scout-memory", "scout_memory.lua"),
                         ("lifestyle-care-journey", "lifestyle_care_journey.lua"),
                         ("lifestyle-restroom", "restroom_care.lua"), ("lifestyle-hygiene", "hygiene_care.lua"),
                         ("ui-contracts", "ui.lua"), ("log-contracts", "log.lua"), ("regressions", "regressions.lua"), ("recovery-steward", "recovery_steward.lua"), ("first-aid", "first_aid.lua"), ("no-lifestyle", "no_lifestyle.lua"), ("coexist", "coexist.lua"), ("kitchen", "kitchen.lua"), ("diet", "diet.lua"), ("decision-status", "decision_status.lua"), ("training-cycle", "training_cycle.lua"),
                         ("training-scheduler-integration", "training_scheduler_integration.lua"),
                         ("tier-targets", "tier_targets.lua"), ("tier-options", "tier_options.lua"),
                         ("wellness-provider", "wellness_provider.lua"),
                         ("tier-goals-integration", "tier_goals_integration.lua"), ("tier-one-shot-witness", "tier_one_shot_witness.lua"),
                         ("hunger-relief", "hunger_relief.lua"), ("hunger-prerequisite", "hunger_prerequisite.lua"), ("practice-care", "practice_care.lua"), ("practice-care-integration", "practice_care_integration.lua"),
                         ("recovery-mode", "recovery_mode.lua"), ("smarter-recovery", "smarter_recovery.lua"), ("strict-recovery-tier", "strict_recovery_tier.lua"), ("sleep-healing", "sleep_healing.lua"), ("walking-handoff", "walking_handoff.lua"),
                         ("progress-contracts", "progress.lua"),
                         ("skills-pane-contracts", "skills_pane.lua"), ("yoga-bar-contracts", "yoga_bar.lua"),
                         ("wellness-guide-contracts", "wellness.lua"), ("zen-moodle", "zen_moodle.lua"),
                         ("completion-hud-contracts", "completion_hud.lua"),
                         ("consumable-contracts", "consumables.lua"), ("supply-policy-contracts", "supply_policy.lua"),
                         ("water-source-contracts", "water_sources.lua"), ("fluid-transfer-contracts", "fluid_transfers.lua"),
                         ("pain-policy", "pain_care.lua"), ("pain-supplies", "pain_supplies.lua"),
                         ("pain-journey", "pain_journey.lua"), ("nearby-contracts", "nearby.lua")):
        suite = [lua, "tests/" + script]
        if game and script in ("water_sources.lua", "fluid_transfers.lua", "tier_options.lua", "sleep_healing.lua"):
            suite.append(str(game.expanduser().resolve() / "media"))
        elif game and reference_root and script == "hygiene_care.lua":
            suite.extend((str(game.expanduser().resolve() / "media"), str(reference_root)))
        elif reference_root and script in ("progress.lua", "restroom_care.lua", "training_scheduler_integration.lua", "tier_targets.lua", "zen_moodle.lua"):
            suite.append(str(reference_root))
        checks.append(check(evidence, name, suite))
    if reference_root:
        native_effects = [lua, "tests/mindfulness_native.lua", str(reference_root)]
        if game:
            native_effects.append(str(game.expanduser().resolve() / "media"))
        checks.append(check(evidence, "lifestyle-mindfulness-effects", native_effects))
    checks.append(check(evidence, "release-contracts", [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-p", "test_release.py"]))
    checks.append(check(evidence, "build-recovery", [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-p", "test_build_recovery.py"]))
    native_scope = "not requested"
    if game:
        game = game.expanduser().resolve()
        checks.append(check(evidence, "stock-queue-handoff", [lua, "tests/stock_queue.lua", str(game / "media")]))
        checks.append(check(evidence, "stock-queue-kahlua-lookup",
                            [lua, "tests/stock_queue.lua", str(game / "media"), "--kahlua-queue-lookup"]))
        checks.append(check(evidence, "stock-native-aim-stop", [lua, "tests/stock_aim.lua", str(game / "media")]))
        checks.append(check(evidence, "stock-scout-route-outcome", [lua, "tests/stock_route_outcome.lua", str(game / "media")]))
        checks.append(check(evidence, "stock-interject", [lua, "tests/stock_interject.lua", str(game / "media")]))
        checks.append(check(evidence, "stock-menu", [lua, "tests/stock_menu.lua", str(game / "media")]))
        checks.append(check(evidence, "stock-pain-action", [lua, "tests/stock_pain.lua", str(game / "media")]))
        checks.append(check(evidence, "stock-supply-loans", [lua, "tests/stock_supply_loans.lua", str(game / "media")]))
        checks.append(check(evidence, "stock-care-ownership", [lua, "tests/stock_care_ownership.lua", str(game / "media")]))
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
                for name, script in (("native-scout-memory", "scout_memory.lua"),
                                     ("native-stock-scout-route-outcome", "stock_route_outcome.lua"),
                                     ("native-lifestyle-care-journey", "lifestyle_care_journey.lua"),
                                     ("native-lifestyle-restroom", "restroom_care.lua"),
                                     ("native-lifestyle-stock-wash", "stock_hygiene.lua"),
                                     ("native-lifestyle-hygiene", "lifestyle_hygiene.lua"),
                                     ("native-contracts", "contracts.lua"), ("native-ui-contracts", "ui.lua"), ("native-log-contracts", "log.lua"), ("native-regressions", "regressions.lua"), ("native-recovery-steward", "recovery_steward.lua"), ("native-first-aid", "first_aid.lua"), ("native-no-lifestyle", "no_lifestyle.lua"), ("native-coexist", "coexist.lua"), ("native-kitchen", "kitchen.lua"), ("native-diet", "diet.lua"), ("native-stock-interject", "stock_interject.lua"),
                                     ("native-decision-status", "decision_status.lua"),
                                     ("native-training-cycle", "training_cycle.lua"),
                                     ("native-training-scheduler-integration", "training_scheduler_integration.lua"),
                                     ("native-tier-targets", "tier_targets.lua"), ("native-tier-options", "tier_options.lua"),
                                     ("native-wellness-provider", "wellness_provider.lua"),
                                     ("native-tier-goals-integration", "tier_goals_integration.lua"), ("native-tier-one-shot-witness", "tier_one_shot_witness.lua"),
                                     ("native-hunger-relief", "hunger_relief.lua"), ("native-hunger-prerequisite", "hunger_prerequisite.lua"), ("native-practice-care", "practice_care.lua"), ("native-practice-care-integration", "practice_care_integration.lua"),
                                     ("native-recovery-mode", "recovery_mode.lua"), ("native-smarter-recovery", "smarter_recovery.lua"), ("native-strict-recovery-tier", "strict_recovery_tier.lua"), ("native-sleep-healing", "sleep_healing.lua"), ("native-walking-handoff", "walking_handoff.lua"),
                                     ("native-lifestyle-mindfulness-effects", "mindfulness_native.lua"),
                                     ("native-skills-pane", "skills_pane.lua"), ("native-yoga-bar", "yoga_bar.lua"),
                                     ("native-wellness-guide", "wellness.lua"), ("native-zen-moodle", "zen_moodle.lua"),
                                     ("native-stock-skills-pane", "stock_skills_pane.lua"),
                                     ("native-stock-menu", "stock_menu.lua"),
                                     ("native-completion-hud-contracts", "completion_hud.lua"),
                                     ("native-stock-queue-handoff", "stock_queue.lua"),
                                     ("native-stock-supply-loans", "stock_supply_loans.lua"),
                                     ("native-stock-care-ownership", "stock_care_ownership.lua"),
                                     ("native-stock-aim-stop", "stock_aim.lua"), ("native-stock-pain-action", "stock_pain.lua"),
                                     ("native-pain-policy", "pain_care.lua"), ("native-pain-supplies", "pain_supplies.lua"),
                                     ("native-pain-journey", "pain_journey.lua"),
                                     ("native-progress-contracts", "progress.lua"), ("native-supply-policy-contracts", "supply_policy.lua"),
                                     ("native-consumable-contracts", "consumables.lua"),
                                     ("native-water-source-contracts", "water_sources.lua"),
                                     ("native-fluid-transfer-contracts", "fluid_transfers.lua"),
                                     ("native-nearby-contracts", "nearby.lua")):
                    if script in ("lifestyle_hygiene.lua", "mindfulness_native.lua") and not reference_root:
                        continue
                    suite_reference = game / "media" if script in ("stock_route_outcome.lua", "stock_hygiene.lua", "stock_supply_loans.lua", "stock_care_ownership.lua", "sleep_healing.lua", "water_sources.lua", "fluid_transfers.lua", "stock_queue.lua", "stock_aim.lua", "stock_pain.lua", "stock_menu.lua", "stock_interject.lua", "stock_skills_pane.lua", "tier_options.lua") else reference_root
                    command = [str(java), "-Xmx512m", "-Djava.awt.headless=true", "-cp", os.pathsep.join((str(classes), str(jar))),
                               "KahluaCheck", str(ROOT), str(suite_reference) if suite_reference else "-", script]
                    if script == "mindfulness_native.lua":
                        command.append(str(game / "media"))
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
