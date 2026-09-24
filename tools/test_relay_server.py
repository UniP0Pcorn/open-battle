import base64
import hashlib
import json
import os
import socket
import struct
import threading
import unittest

from tools.relay_server import create_server


def connect(port):
    sock = socket.create_connection(("127.0.0.1", port))
    key = base64.b64encode(os.urandom(16)).decode()
    sock.sendall(("GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n" % key).encode())
    response = sock.recv(4096)
    expected = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
    if b"101 Switching Protocols" not in response or expected.encode() not in response:
        raise AssertionError("websocket handshake failed")
    return sock


def send(sock, value):
    payload = json.dumps(value).encode()
    mask = os.urandom(4)
    encoded = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))
    sock.sendall(bytes([0x81, 0x80 | len(payload)]) + mask + encoded)


def receive(sock):
    first, second = sock.recv(2)
    length = second & 0x7F
    mask = b""
    if second & 0x80:
        mask = sock.recv(4)
    payload = sock.recv(length)
    if mask:
        payload = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))
    return json.loads(payload.decode())


class RelayTests(unittest.TestCase):
    def setUp(self):
        self.server = create_server("127.0.0.1", 0)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def test_pairs_and_forwards_opaque_packets(self):
        host = connect(self.server.server_address[1])
        client = connect(self.server.server_address[1])
        send(host, {"type": "hello", "room_id": "room-a", "role": "host"})
        self.assertEqual(receive(host)["type"], "ready")
        send(client, {"type": "hello", "room_id": "room-a", "role": "client"})
        self.assertEqual(receive(client)["type"], "ready")
        packet = {"kind": "COMMAND", "damage": 999, "dice": [6, 6]}
        send(host, packet)
        self.assertEqual(receive(client), packet)
        host.close()
        client.close()

    def test_room_and_role_isolation(self):
        first = connect(self.server.server_address[1])
        second = connect(self.server.server_address[1])
        send(first, {"type": "hello", "room_id": "room-b", "role": "host"})
        receive(first)
        send(second, {"type": "hello", "room_id": "room-b", "role": "host"})
        self.assertEqual(receive(second)["type"], "error")
        first.close()
        second.close()


if __name__ == "__main__":
    unittest.main()
