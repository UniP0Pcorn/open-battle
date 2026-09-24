"""Dependency-free WebSocket relay for transport-neutral open-battle packets.

The relay pairs one host and one client per room, then forwards opaque UTF-8
JSON frames. It never validates or resolves battle commands; the host remains
authoritative. Put TLS, authentication, rate limits, and an origin policy in
front of this experimental server before public deployment.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import socketserver
import struct
import threading


def _accept_key(value: str) -> str:
    digest = hashlib.sha1((value + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()
    return base64.b64encode(digest).decode()


def _read_exact(sock, size: int) -> bytes:
    data = b""
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        if not chunk:
            raise ConnectionError("peer closed")
        data += chunk
    return data


def read_frame(sock) -> str:
    first, second = _read_exact(sock, 2)
    opcode = first & 0x0F
    if opcode == 8:
        raise ConnectionError("peer closed")
    if opcode != 1 or not (second & 0x80):
        raise ValueError("TEXT MASKED FRAME REQUIRED")
    length = second & 0x7F
    if length == 126:
        length = struct.unpack("!H", _read_exact(sock, 2))[0]
    elif length == 127:
        length = struct.unpack("!Q", _read_exact(sock, 8))[0]
    if length > 1024 * 1024:
        raise ValueError("FRAME TOO LARGE")
    mask = _read_exact(sock, 4)
    payload = _read_exact(sock, length)
    return bytes(value ^ mask[index % 4] for index, value in enumerate(payload)).decode("utf-8")


def write_frame(sock, text: str) -> None:
    payload = text.encode("utf-8")
    if len(payload) < 126:
        header = bytes([0x81, len(payload)])
    elif len(payload) <= 0xFFFF:
        header = bytes([0x81, 126]) + struct.pack("!H", len(payload))
    else:
        header = bytes([0x81, 127]) + struct.pack("!Q", len(payload))
    sock.sendall(header + payload)


class RelayStore:
    def __init__(self) -> None:
        self.rooms: dict[str, dict[str, object]] = {}
        self.lock = threading.Lock()

    def join(self, room_id: str, role: str, handler) -> tuple[bool, str]:
        if role not in ("host", "client") or not room_id.strip():
            return False, "INVALID HELLO"
        with self.lock:
            room = self.rooms.setdefault(room_id, {})
            if role in room:
                return False, "ROLE ALREADY CONNECTED"
            if len(room) >= 2:
                return False, "ROOM FULL"
            room[role] = handler
            return True, ""

    def leave(self, room_id: str, role: str, handler) -> None:
        with self.lock:
            room = self.rooms.get(room_id, {})
            if room.get(role) is handler:
                room.pop(role, None)
            if not room:
                self.rooms.pop(room_id, None)

    def other(self, room_id: str, role: str):
        with self.lock:
            return self.rooms.get(room_id, {}).get("client" if role == "host" else "host")


class RelayHandler(socketserver.BaseRequestHandler):
    store: RelayStore

    def setup(self) -> None:
        self.room_id = ""
        self.role = ""

    def handle(self) -> None:
        self.request.settimeout(10)
        try:
            headers = self.request.recv(8192).decode("latin1")
            if "\r\n\r\n" not in headers or not headers.startswith("GET "):
                return
            values = {}
            for line in headers.split("\r\n")[1:]:
                if ":" in line:
                    key, value = line.split(":", 1)
                    values[key.lower().strip()] = value.strip()
            key = values.get("sec-websocket-key", "")
            if not key:
                return
            response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: %s\r\n\r\n" % _accept_key(key)
            self.request.sendall(response.encode("latin1"))
            hello = json.loads(read_frame(self.request))
            if hello.get("type") != "hello":
                raise ValueError("HELLO REQUIRED")
            self.room_id = str(hello.get("room_id", ""))
            self.role = str(hello.get("role", ""))
            joined, reason = self.store.join(self.room_id, self.role, self)
            if not joined:
                write_frame(self.request, json.dumps({"type": "error", "reason": reason}))
                return
            write_frame(self.request, json.dumps({"type": "ready", "room_id": self.room_id}))
            while True:
                message = read_frame(self.request)
                peer = self.store.other(self.room_id, self.role)
                if peer is not None:
                    try:
                        write_frame(peer.request, message)
                    except OSError:
                        pass
        except (ConnectionError, OSError, ValueError, json.JSONDecodeError):
            return
        finally:
            if self.room_id and self.role:
                self.store.leave(self.room_id, self.role, self)


class RelayServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True


def create_server(host: str = "127.0.0.1", port: int = 8766) -> RelayServer:
    server = RelayServer((host, port), RelayHandler)
    RelayHandler.store = RelayStore()
    return server


def main() -> None:
    parser = argparse.ArgumentParser(description="open-battle opaque WebSocket relay")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8766)
    args = parser.parse_args()
    server = create_server(args.host, args.port)
    print(f"open-battle relay listening on {args.host}:{args.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
