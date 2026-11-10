"""Publish a verified stage through the locally signed-in desktop Steam client."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from build import ROOT
from workshop import checked_stage, workshop_id


def publish(game: Path, stage: Path, item_id: str) -> None:
    item_id = workshop_id(item_id)
    record = checked_stage(stage)
    jar, java = game / "projectzomboid.jar", game / "jre64/bin/java"
    compiler = shutil.which("javac")
    if not jar.is_file() or not java.is_file() or not compiler:
        raise ValueError("Desktop publishing requires the installed game and JDK 25 javac")
    environment = {key: value for key, value in os.environ.items() if key not in {
        "JAVA_TOOL_OPTIONS", "JDK_JAVA_OPTIONS", "_JAVA_OPTIONS", "CLASSPATH", "LD_PRELOAD",
        "STEAM_USERNAME", "STEAM_CONFIG_VDF"}}
    environment.update(LD_LIBRARY_PATH=f"{game}:{game / 'natives'}:{game / 'jre64/lib'}",
        SteamAppId="108600", SteamGameId="108600")
    with tempfile.TemporaryDirectory(prefix="automindful-desktop-publish-") as temporary:
        root = Path(temporary)
        notes = root / "notes.txt"
        notes.write_text(record["changeNote"], encoding="utf-8")
        subprocess.run([compiler, "--release", "25", "-cp", str(jar), "-d", temporary,
            str(ROOT / "tools/SteamWorkshopBootstrap.java")], check=True, timeout=60)
        subprocess.run([str(java), "--enable-native-access=ALL-UNNAMED", "-Djava.awt.headless=true",
            "-Dzomboid.steam=1", f"-Djava.library.path={game / 'natives'}", "-cp",
            os.pathsep.join((temporary, str(jar))), "SteamWorkshopBootstrap", "update", str(stage),
            str(root / "cache"), item_id, str(notes)], cwd=game, env=environment,
            check=True, timeout=180)
    print(f"Published {record['tag']} to Workshop item {item_id} using the desktop Steam session")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", required=True, type=Path)
    parser.add_argument("--stage", required=True, type=Path)
    parser.add_argument("--item-id", required=True)
    args = parser.parse_args()
    try:
        publish(args.game.expanduser().resolve(), args.stage.resolve(), args.item_id)
    except (ValueError, RuntimeError, OSError, subprocess.SubprocessError) as failure:
        parser.exit(1, str(failure) + "\n")
