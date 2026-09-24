"""Small dependency-free room advertisement directory for open-battle.

The directory stores only public, expiring connection metadata.  It never
handles battle commands, credentials, or reconnect tokens; ENet remains the
authoritative game transport.  Put TLS and an access policy in front of this
process when exposing it to the Internet.
"""

from __future__ import annotations

import argparse
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlparse

MAX_BODY = 64 * 1024


def validate(record: dict, now: int | None = None) -> str:
    required = ("version", "room_id", "host", "address", "port", "edition", "mission_id", "expires_at")
    missing = next((field for field in required if field not in record), None)
    if missing:
        return f"MISSING {missing.upper()}"
    if int(record.get("version", 0)) != 1 or not str(record["room_id"]).strip() or not str(record["mission_id"]).strip():
        return "INVALID ROOM ADVERTISEMENT"
    host = record["host"]
    if not isinstance(host, dict) or not str(host.get("account_id", "")).strip():
        return "INVALID HOST RECORD"
    fingerprint = str(host.get("fingerprint", ""))
    if len(fingerprint) != 64 or any(char not in "0123456789abcdefABCDEF" for char in fingerprint):
        return "INVALID HOST FINGERPRINT"
    address = str(record["address"]).strip()
    if not address or any(char.isspace() for char in address) or "/" in address or "\\" in address:
        return "INVALID ENDPOINT"
    try:
        port = int(record["port"])
        edition = int(record["edition"])
        expires_at = int(record["expires_at"])
    except (TypeError, ValueError):
        return "INVALID ROOM ADVERTISEMENT"
    if not 1024 <= port <= 65535:
        return "INVALID PORT"
    if edition <= 0 or expires_at <= 0:
        return "INVALID ROOM ADVERTISEMENT"
    if now is not None and expires_at <= now:
        return "ROOM ADVERTISEMENT EXPIRED"
    return ""


class DirectoryStore:
    def __init__(self) -> None:
        self._records: dict[str, dict] = {}
        self._lock = threading.Lock()

    def put(self, record: dict, now: int | None = None) -> None:
        error = validate(record, now if now is not None else int(time.time()))
        if error:
            raise ValueError(error)
        with self._lock:
            self._prune_locked(int(time.time()))
            self._records[str(record["room_id"])] = json.loads(json.dumps(record))

    def get(self, room_id: str) -> dict | None:
        with self._lock:
            self._prune_locked(int(time.time()))
            record = self._records.get(room_id)
            return json.loads(json.dumps(record)) if record else None

    def all(self) -> list[dict]:
        with self._lock:
            self._prune_locked(int(time.time()))
            return [json.loads(json.dumps(record)) for record in self._records.values()]

    def delete(self, room_id: str, fingerprint: str) -> bool:
        with self._lock:
            record = self._records.get(room_id)
            if not record or str(record.get("host", {}).get("fingerprint", "")) != fingerprint:
                return False
            del self._records[room_id]
            return True

    def _prune_locked(self, now: int) -> None:
        for room_id, record in list(self._records.items()):
            if int(record.get("expires_at", 0)) <= now:
                del self._records[room_id]


class Handler(BaseHTTPRequestHandler):
    store: DirectoryStore

    def _send(self, status: int, payload: object) -> None:
        body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        path = urlparse(self.path).path
        if path == "/v1/rooms":
            self._send(200, {"rooms": self.store.all()})
            return
        prefix = "/v1/rooms/"
        if path.startswith(prefix) and path != prefix:
            record = self.store.get(unquote(path[len(prefix) :]))
            self._send(200, record) if record else self._send(404, {"error": "ROOM NOT FOUND"})
            return
        self._send(404, {"error": "NOT FOUND"})

    def do_POST(self) -> None:  # noqa: N802
        if urlparse(self.path).path != "/v1/rooms":
            self._send(404, {"error": "NOT FOUND"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > MAX_BODY:
                raise ValueError("INVALID BODY SIZE")
            record = json.loads(self.rfile.read(length).decode("utf-8"))
            if not isinstance(record, dict):
                raise ValueError("INVALID JSON")
            self.store.put(record)
        except (ValueError, json.JSONDecodeError, UnicodeDecodeError) as error:
            self._send(400, {"error": str(error)})
            return
        self._send(201, record)

    def do_DELETE(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        prefix = "/v1/rooms/"
        fingerprint = parse_qs(parsed.query).get("fingerprint", [""])[0]
        if not parsed.path.startswith(prefix) or not fingerprint:
            self._send(400, {"error": "FINGERPRINT REQUIRED"})
            return
        if self.store.delete(unquote(parsed.path[len(prefix) :]), fingerprint):
            self._send(200, {"ok": True})
        else:
            self._send(403, {"error": "ROOM OWNER MISMATCH"})

    def log_message(self, _format: str, *_args: object) -> None:
        return


def create_server(host: str = "127.0.0.1", port: int = 8765) -> ThreadingHTTPServer:
    store = DirectoryStore()

    class BoundHandler(Handler):
        pass

    BoundHandler.store = store
    return ThreadingHTTPServer((host, port), BoundHandler)


def main() -> None:
    parser = argparse.ArgumentParser(description="open-battle room advertisement directory")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    server = create_server(args.host, args.port)
    print(f"open-battle room directory listening on {args.host}:{args.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
