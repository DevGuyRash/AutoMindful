"""Build first, then check contracts in Lua 5.1 and optionally installed Kahlua."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

from build import ROOT, build


def fingerprint() -> str:
    digest = hashlib.sha256()
    for directory in ("mods", "tests", "tools"):
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


def verify(evidence: Path, game: Path | None, lifestyle: Path | None) -> bool:
    evidence = evidence.expanduser().resolve()
    evidence.mkdir(parents=True, exist_ok=False)
    source_before = fingerprint()
    build(evidence / "package")
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
    native_scope = "not requested"
    if game:
        game = game.expanduser().resolve()
        java, jar = game / "jre64/bin/java", game / "projectzomboid.jar"
        compiler = shutil.which("javac")
        if not java.is_file() or not jar.is_file() or not compiler:
            raise RuntimeError("Native check requires the installed game JAR, bundled JVM and JDK 25 javac")
        with tempfile.TemporaryDirectory(prefix="automindful-kahlua-") as temporary:
            classes = Path(temporary)
            checks.append(check(evidence, "native-compile", [compiler, "--release", "25", "-cp", str(jar),
                "-d", str(classes), str(ROOT / "tools/KahluaCheck.java")]))
            if checks[-1]["passed"]:
                env = {key: value for key, value in os.environ.items() if key not in {
                    "JAVA_TOOL_OPTIONS", "JDK_JAVA_OPTIONS", "_JAVA_OPTIONS", "JAVA_OPTS", "CLASSPATH", "LD_PRELOAD"}}
                command = [str(java), "-Xmx512m", "-Djava.awt.headless=true", "-cp", os.pathsep.join((str(classes), str(jar))),
                           "KahluaCheck", str(ROOT)]
                if reference_root:
                    command.append(str(reference_root))
                checks.append(check(evidence, "native-contracts", command, cwd=game, env=env))
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
    parser.add_argument("--lifestyle", type=Path, help="Installed Lifestyle mod root; read without modification")
    parser.add_argument("--evidence", type=Path, default=Path.home() / ".local/state/app-verification/AutoMindful" /
                        time.strftime("verify-%Y%m%d-%H%M%S", time.gmtime()))
    args = parser.parse_args()
    raise SystemExit(0 if verify(args.evidence, args.game, args.lifestyle) else 1)
