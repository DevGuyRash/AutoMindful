"""Run the packaged mod on a private Xvfb display with a disposable game cache."""

import argparse
import json
import os
from pathlib import Path
import select
import shutil
import signal
import subprocess
import sys
import zipfile

from build import build


def play(game: Path, lifestyle: Path, evidence: Path, resume: bool, extra: list[Path]) -> int:
    game, lifestyle, evidence = game.resolve(), lifestyle.resolve(), evidence.resolve()
    if not (game / "projectzomboid.jar").is_file():
        raise ValueError("--game must contain projectzomboid.jar")
    if not (lifestyle / "42/mod.info").is_file():
        raise ValueError("--lifestyle must point to the installed Lifestyle mod root")
    if resume:
        state = json.loads((evidence / "session.json").read_text())
        if state["game"] != str(game) or state["cache"] != str(evidence / "cache"):
            raise ValueError("Saved session identity does not match")
        for key in ("ownerPid", "clientPid", "displayPid"):
            try:
                os.kill(state[key], 0)
            except ProcessLookupError:
                continue
            raise RuntimeError("Previous session is still running")
        launch = state["launch"] + 1
    else:
        evidence.mkdir(parents=True, exist_ok=False)
        launch = 1
    archive = build(evidence / f"package-{launch}")
    cache = evidence / "cache"
    installed = cache / "mods/AutoMindful"
    if installed.exists():
        shutil.rmtree(installed)
    with zipfile.ZipFile(archive) as package:
        for name in package.namelist():
            target = cache / Path(name).relative_to("Contents")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(package.read(name))
    lifestyle_link = cache / "mods/lifestyle"
    if lifestyle_link.is_symlink():
        lifestyle_link.unlink()
    if not lifestyle_link.exists():
        shutil.copytree(lifestyle, lifestyle_link, copy_function=os.link)
    mod_ids = ["LifestyleHobbies", "AutoMindful"]
    for mod in extra:
        target = cache / "mods" / mod.name
        if target.is_symlink():
            target.unlink()
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(mod.resolve(), target)
        info = mod / "42/mod.info"
        mod_ids.append(next(line[3:].strip() for line in info.read_text().splitlines() if line.startswith("id=")))
    (cache / "mods/reset-mods-42_00.txt").write_text("This disposable cache has an explicit Build 42 mod selection.\n")
    (cache / "mods/default.txt").write_text("VERSION = 1,\nmods\n{\n" +
        "".join(f"    mod = {mod_id},\n" for mod_id in mod_ids) + "}\nmaps\n{\n}\n")
    if not resume:
        (cache / "options.ini").write_text(
            "version=8\nwidth=1280\nheight=900\nfullScreen=false\nborderless=false\n"
            "tutorialDone=true\ndoneNewSaveFolder=true\n")
    owned = []
    try:
        with (evidence / f"display-{launch}.log").open("wb") as display_log, (evidence / f"client-{launch}.log").open("wb") as game_log:
            read_fd, write_fd = os.pipe()
            try:
                display = subprocess.Popen(["Xvfb", "-displayfd", str(write_fd), "-screen", "0", "1280x900x24", "-nolisten", "tcp"],
                    pass_fds=(write_fd,), stdout=display_log, stderr=subprocess.STDOUT)
                owned.append(display)
                os.close(write_fd)
                write_fd = None
                if not select.select([read_fd], [], [], 10)[0]:
                    raise RuntimeError("Private display did not become ready")
                display_name = ":" + os.read(read_fd, 32).decode().strip()
            finally:
                os.close(read_fd)
                if write_fd is not None:
                    os.close(write_fd)
            env = {key: value for key, value in os.environ.items() if key not in {
                "JAVA_TOOL_OPTIONS", "JDK_JAVA_OPTIONS", "_JAVA_OPTIONS", "JAVA_OPTS", "CLASSPATH", "LD_PRELOAD"}}
            env.update(DISPLAY=display_name, LD_LIBRARY_PATH=f"{game}:{game / 'natives'}:{game / 'jre64/lib'}")
            client = subprocess.Popen([str(game / "jre64/bin/java"), "-Xms512m", "-Xmx2048m", "-XX:+UseZGC",
                "--enable-native-access=ALL-UNNAMED", "--add-exports=java.base/jdk.internal.misc=ALL-UNNAMED",
                "-Dzomboid.steam=0", "-Djava.library.path=.:natives", "-cp", ".:projectzomboid.jar",
                "zombie.gameStates.MainScreenState", f"-cachedir={cache}", "-nosteam", "-nosound", "-novoip",
                "-modfolders", "mods"], cwd=game, env=env, stdout=game_log, stderr=subprocess.STDOUT)
            owned.append(client)
            state = {"ownerPid": os.getpid(), "clientPid": client.pid, "displayPid": display.pid,
                "display": display_name, "game": str(game), "cache": str(cache), "launch": launch}
            (evidence / "session.json").write_text(json.dumps(state, indent=2) + "\n")
            print(json.dumps(state), flush=True)
            return client.wait()
    finally:
        for process in reversed(owned):
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=10)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", required=True, type=Path)
    parser.add_argument("--lifestyle", required=True, type=Path)
    parser.add_argument("--evidence", required=True, type=Path)
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--extra-mod", action="append", type=Path, default=[])
    args = parser.parse_args()
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    raise SystemExit(play(args.game, args.lifestyle, args.evidence.expanduser(), args.resume, args.extra_mod))
