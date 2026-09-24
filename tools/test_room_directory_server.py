import json
import threading
import unittest
from urllib.request import Request, urlopen

from tools.room_directory_server import create_server, validate


class RoomDirectoryServerTests(unittest.TestCase):
    def setUp(self):
        self.server = create_server("127.0.0.1", 0)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = f"http://127.0.0.1:{self.server.server_port}"
        self.record = {"version": 1, "room_id": "room-1", "host": {"version": 1, "account_id": "host", "fingerprint": "a" * 64}, "address": "203.0.113.5", "port": 24567, "edition": 11, "mission_id": "control_center", "expires_at": 4102444800}

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def request(self, method, path, payload=None):
        body = json.dumps(payload).encode() if payload is not None else None
        return urlopen(Request(self.base + path, data=body, method=method, headers={"Content-Type": "application/json"}))

    def test_publish_list_delete_and_expiry_validation(self):
        self.assertEqual(validate(self.record, 4102444700), "")
        response = self.request("POST", "/v1/rooms", self.record)
        self.assertEqual(response.status, 201)
        response = self.request("GET", "/v1/rooms")
        self.assertEqual(response.read().decode().count("room-1"), 1)
        response = self.request("DELETE", "/v1/rooms/room-1?fingerprint=" + "a" * 64)
        self.assertEqual(response.status, 200)

    def test_owner_mismatch_and_bad_record_are_rejected(self):
        bad = dict(self.record)
        bad["port"] = 80
        with self.assertRaises(Exception):
            self.request("POST", "/v1/rooms", bad)
        self.request("POST", "/v1/rooms", self.record)
        with self.assertRaises(Exception):
            self.request("DELETE", "/v1/rooms/room-1?fingerprint=" + "b" * 64)


if __name__ == "__main__":
    unittest.main()
