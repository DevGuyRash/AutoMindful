"""Run an owned Lifestyle loopback server and optionally advertise client-only mods."""

import argparse
import json
import os
from pathlib import Path
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as handle:
        handle.bind(("127.0.0.1", 0))
        return handle.getsockname()[1]


def launch(game: Path, lifestyle: Path, evidence: Path, client_mods: list[Path]) -> int:
    game, lifestyle, evidence = game.resolve(), lifestyle.resolve(), evidence.resolve()
    if not (game / "projectzomboid.jar").is_file() or not (lifestyle / "42/mod.info").is_file():
        raise ValueError("Supply an installed game and Lifestyle mod root")
    evidence.mkdir(parents=True, exist_ok=False)
    evidence.chmod(0o700)
    cache = evidence / "server-cache"
    mods = cache / "mods"
    mods.mkdir(parents=True)
    shutil.copytree(lifestyle, mods / "lifestyle", copy_function=os.link)
    mod_ids = ["LifestyleHobbies"]
    for mod in client_mods:
        mod = mod.resolve()
        nonclient = [path for path in mod.rglob("*.lua") if "/media/lua/client/" not in path.as_posix()]
        if nonclient:
            raise ValueError(f"Advertised client mod has non-client Lua: {mod}")
        shutil.copytree(mod, mods / mod.name)
        mod_ids.append(next(line[3:].strip() for line in (mod / "42/mod.info").read_text().splitlines() if line.startswith("id=")))
    database = tempfile.TemporaryDirectory(prefix="automindful-server-db-", dir="/dev/shm")
    (cache / "db").symlink_to(database.name, target_is_directory=True)
    server_dir = cache / "Server"
    server_dir.mkdir()
    port, udp = free_port(), free_port()
    while port == udp:
        udp = free_port()
    (server_dir / "AutoMindfulProbe.ini").write_text(
        f"DefaultPort={port}\nUDPPort={udp}\nMods={';'.join(mod_ids)}\nWorkshopItems=\n"
        "DoLuaChecksum=false\nPublic=false\nUPnP=false\nOpen=true\nAutoCreateUserInWhiteList=true\n"
        "MaxPlayers=4\nPVP=false\nPauseEmpty=true\nMap=Muldraugh, KY\nRCONPassword=\nPassword=\n"
        "SleepAllowed=true\nSleepNeeded=false\nSpawnPoint=11778,6749,0\n"
        "BackupsOnStart=false\nBackupsOnVersionChange=false\n"
        "ItemNumbersLimitPerContainer=0\n", encoding="utf-8")
    (server_dir / "AutoMindfulProbe_SandboxVars.lua").write_text(
        "SandboxVars = { VERSION=6, Zombies=6, StarterKit=true, ZombieConfig={"
        "PopulationMultiplier=0,PopulationStartMultiplier=0,PopulationPeakMultiplier=0} }\n")
    fifo = evidence / "server-console.in"
    os.mkfifo(fifo, 0o600)
    console = os.open(fifo, os.O_RDWR)
    admin, password = "mindful_admin_" + secrets.token_hex(4), secrets.token_urlsafe(32)
    env = {key: value for key, value in os.environ.items() if key not in {
        "JAVA_TOOL_OPTIONS", "JDK_JAVA_OPTIONS", "_JAVA_OPTIONS", "JAVA_OPTS", "CLASSPATH", "LD_PRELOAD"}}
    env["LD_LIBRARY_PATH"] = f"{game}:{game / 'natives'}:{game / 'jre64/lib'}"
    process = None
    reader = None
    state = {"ownerPid": os.getpid(), "host": "127.0.0.1", "port": port, "udpPort": udp,
        "cache": str(cache), "status": "starting", "serverMods": mod_ids, "checksum": False}
    state_file = evidence / "server-session.json"

    def save_state() -> None:
        state_file.write_text(json.dumps(state, indent=2) + "\n")

    try:
        process = subprocess.Popen([str(game / "jre64/bin/java"), "-Xms512m", "-Xmx2048m", "-XX:+UseZGC",
            "--enable-native-access=ALL-UNNAMED", "--add-exports=java.base/jdk.internal.misc=ALL-UNNAMED",
            "-Djava.awt.headless=true", "-Dzomboid.steam=0", "-Djava.library.path=.:natives", "-cp", ".:projectzomboid.jar",
            "zombie.network.GameServer", f"-cachedir={cache}", "-nosteam", "-servername", "AutoMindfulProbe",
            "-ip", "127.0.0.1", "-port", str(port), "-udpport", str(udp), "-adminusername", admin,
            "-adminpassword", password], cwd=game, env=env, stdin=console, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
        state["serverPid"] = process.pid
        save_state()

        def capture() -> None:
            with (evidence / "server.log").open("w", encoding="utf-8") as output:
                for line in process.stdout:
                    output.write(line.replace(password, "<ephemeral-test-password>"))
                    output.flush()
                    if "SERVER STARTED" in line:
                        state["status"] = "ready"
                        save_state()

        reader = threading.Thread(target=capture, name="automindful-server-log")
        reader.start()
        print(json.dumps(state), flush=True)
        return process.wait()
    finally:
        if process is not None and process.poll() is None:
            os.write(console, b"quit\n")
            try:
                process.wait(timeout=20)
            except subprocess.TimeoutExpired:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=10)
        os.close(console)
        if reader is not None:
            reader.join(timeout=10)
            if reader.is_alive():
                raise RuntimeError("Server log reader did not finish")
        if process is not None:
            process.stdout.close()
            state["status"], state["exitCode"] = "stopped", process.returncode
            save_state()
        (cache / "db").unlink()
        database.cleanup()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", required=True, type=Path)
    parser.add_argument("--lifestyle", required=True, type=Path)
    parser.add_argument("--evidence", required=True, type=Path)
    parser.add_argument("--client-mod", action="append", type=Path, default=[])
    args = parser.parse_args()
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    raise SystemExit(launch(args.game, args.lifestyle, args.evidence.expanduser(), args.client_mod))
