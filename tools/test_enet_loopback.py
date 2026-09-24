"""Run two real Godot processes through ENet; uses synthetic in-memory identities."""
from __future__ import annotations
import argparse
import json
import os
import socket
import subprocess
import tempfile
import time
from pathlib import Path


def run(godot: Path, project: Path) -> dict:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    with tempfile.TemporaryDirectory(prefix="open-battle-enet-") as directory:
        output = Path(directory)
        processes = []
        logs = []
        try:
            for role in ("host", "client"):
                log = (output / f"{role}.log").open("w", encoding="utf-8")
                logs.append(log)
                process = subprocess.Popen([str(godot.resolve()), "--headless", "--path", str(project.resolve()), "--script", "res://tests/enet_probe.gd", "--", role, str(port), str(output)], stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
                processes.append(process)
                if role == "host":
                    deadline = time.monotonic() + 15
                    while not (output / "listening.json").exists():
                        if process.poll() is not None or time.monotonic() > deadline:
                            raise RuntimeError("host failed to listen")
                        time.sleep(0.02)
            for process in processes:
                if process.wait(timeout=30) != 0:
                    raise RuntimeError("Godot network probe failed")
            results = {role: json.loads((output / f"{role}.json").read_text(encoding="utf-8")) for role in ("host", "client")}
            if not all(result["ok"] for result in results.values()) or results["host"]["hash"] != results["client"]["hash"]:
                raise RuntimeError(f"network states differ: {results}")
            return results
        except Exception:
            for log in logs:
                log.flush()
            for path in output.glob("*.log"):
                print(path.name + "\n" + path.read_text(encoding="utf-8", errors="replace"))
            for path in output.glob("*.json"):
                print(path.name + ": " + path.read_text(encoding="utf-8"))
            raise
        finally:
            for process in processes:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
            for log in logs:
                log.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    print(json.dumps(run(args.godot, args.project), indent=2))
