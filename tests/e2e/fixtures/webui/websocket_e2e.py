#!/usr/bin/env python3

import base64
import hashlib
import json
import os
import socket
import struct
import sys
import time


class WebSocketClient:
    def __init__(self, host: str, port: int) -> None:
        self.host = host
        self.port = port
        self.sock = socket.create_connection((host, port), timeout=10)
        self.sock.settimeout(10)
        self._buffer = b""
        self._handshake()

    def _read_exact(self, size: int) -> bytes:
        while len(self._buffer) < size:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise RuntimeError("unexpected end of stream")
            self._buffer += chunk
        data = self._buffer[:size]
        self._buffer = self._buffer[size:]
        return data

    def _handshake(self) -> None:
        key = base64.b64encode(os.urandom(16)).decode("ascii")
        request = (
            f"GET /ws HTTP/1.1\r\n"
            f"Host: {self.host}:{self.port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n"
            "\r\n"
        )
        self.sock.sendall(request.encode("ascii"))

        response = b""
        while b"\r\n\r\n" not in response:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise RuntimeError("websocket handshake failed")
            response += chunk

        header_bytes, _, remaining = response.partition(b"\r\n\r\n")
        self._buffer = remaining

        header_lines = header_bytes.decode("ascii").split("\r\n")
        if "101" not in header_lines[0]:
            raise RuntimeError(f"unexpected handshake response: {header_lines[0]}")

        headers = {}
        for line in header_lines[1:]:
            if ":" not in line:
                continue
            name, value = line.split(":", 1)
            headers[name.strip().lower()] = value.strip()

        expected_accept = base64.b64encode(
            hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii")).digest()
        ).decode("ascii")
        actual_accept = headers.get("sec-websocket-accept")
        if actual_accept != expected_accept:
            raise RuntimeError("invalid websocket accept key")

    def send_json(self, payload) -> None:
        data = json.dumps(payload).encode("utf-8")
        mask = os.urandom(4)
        masked = bytes(byte ^ mask[i % 4] for i, byte in enumerate(data))

        first = bytes([0x81])
        length = len(data)
        if length < 126:
            header = bytes([0x80 | length])
        elif length < 65536:
            header = bytes([0x80 | 126]) + struct.pack("!H", length)
        else:
            header = bytes([0x80 | 127]) + struct.pack("!Q", length)

        self.sock.sendall(first + header + mask + masked)

    def recv_json(self, timeout: float = 10.0):
        self.sock.settimeout(timeout)

        while True:
            first_two = self._read_exact(2)
            opcode = first_two[0] & 0x0F
            masked = (first_two[1] & 0x80) != 0
            length = first_two[1] & 0x7F

            if length == 126:
                length = struct.unpack("!H", self._read_exact(2))[0]
            elif length == 127:
                length = struct.unpack("!Q", self._read_exact(8))[0]

            if masked:
                mask = self._read_exact(4)
            else:
                mask = None

            payload = self._read_exact(length) if length else b""
            if mask is not None:
                payload = bytes(byte ^ mask[i % 4] for i, byte in enumerate(payload))

            if opcode == 0x9:
                self._send_pong(payload)
                continue
            if opcode == 0x8:
                raise RuntimeError("server closed websocket")
            if opcode != 0x1:
                continue

            return json.loads(payload.decode("utf-8"))

    def _send_pong(self, payload: bytes) -> None:
        mask = os.urandom(4)
        masked = bytes(byte ^ mask[i % 4] for i, byte in enumerate(payload))
        first = bytes([0x8A])
        length = len(payload)
        if length < 126:
            header = bytes([0x80 | length])
        elif length < 65536:
            header = bytes([0x80 | 126]) + struct.pack("!H", length)
        else:
            header = bytes([0x80 | 127]) + struct.pack("!Q", length)
        self.sock.sendall(first + header + mask + masked)

    def close(self) -> None:
        try:
            self.send_json({"action": "stop"})
        except Exception:
            pass
        self.sock.close()


def wait_for(client: WebSocketClient, label: str, predicate, timeout: float = 10.0):
    deadline = time.time() + timeout
    seen = []
    while time.time() < deadline:
        remaining = max(0.1, deadline - time.time())
        try:
            msg = client.recv_json(remaining)
        except TimeoutError as exc:
            raise AssertionError(f"timed out waiting for {label}; seen={seen!r}") from exc
        seen.append(msg)
        if predicate(msg):
            return msg
    raise AssertionError(f"timed out waiting for {label}; seen={seen!r}")


def main() -> int:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 18450
    client = WebSocketClient("127.0.0.1", port)
    try:
        init_msg = wait_for(
            client,
            "init message",
            lambda msg: msg.get("type") == "init",
        )
        recipe_names = {recipe["name"] for recipe in init_msg.get("recipes", [])}
        expected = {"dep", "root", "confirm-task", "slow"}
        if not expected.issubset(recipe_names):
            raise AssertionError(f"missing recipes in init payload: {expected - recipe_names}")

        client.send_json({"action": "run", "recipe": "confirm-task", "params": {}, "dryRun": False})
        wait_for(client, "confirm task start", lambda msg: msg.get("type") == "task_start" and msg.get("name") == "confirm-task")
        confirm_msg = wait_for(client, "confirm prompt", lambda msg: msg.get("type") == "confirm" and msg.get("task") == "confirm-task")
        client.send_json({"action": "confirm", "confirmId": confirm_msg["confirmId"], "approved": True})
        wait_for(client, "confirm command event", lambda msg: msg.get("type") == "command" and msg.get("task") == "confirm-task")
        wait_for(client, "confirm output", lambda msg: msg.get("type") == "output" and msg.get("task") == "confirm-task" and msg.get("line") == "confirmed-output")
        wait_for(client, "confirm completion", lambda msg: msg.get("type") == "task_complete" and msg.get("name") == "confirm-task" and msg.get("success") is True)
        wait_for(client, "confirm summary", lambda msg: msg.get("type") == "summary" and msg.get("tasks_failed") == 0)

        client.send_json({"action": "run", "recipe": "root", "params": {}, "dryRun": False})
        wait_for(client, "root task start", lambda msg: msg.get("type") == "task_start" and msg.get("name") == "root")
        wait_for(client, "dependency task start", lambda msg: msg.get("type") == "task_start" and msg.get("name") == "dep")
        wait_for(client, "dependency command event", lambda msg: msg.get("type") == "command" and msg.get("task") == "dep")
        wait_for(client, "dependency output", lambda msg: msg.get("type") == "output" and msg.get("task") == "dep" and msg.get("line") == "dep-output")
        wait_for(client, "dependency completion", lambda msg: msg.get("type") == "task_complete" and msg.get("name") == "dep" and msg.get("success") is True)
        wait_for(client, "root command event", lambda msg: msg.get("type") == "command" and msg.get("task") == "root")
        wait_for(client, "root output", lambda msg: msg.get("type") == "output" and msg.get("task") == "root" and msg.get("line") == "root-output")
        wait_for(client, "root completion", lambda msg: msg.get("type") == "task_complete" and msg.get("name") == "root" and msg.get("success") is True)
        wait_for(client, "root summary", lambda msg: msg.get("type") == "summary" and msg.get("tasks_failed") == 0)

        client.send_json({"action": "run", "recipe": "slow", "params": {}, "dryRun": False})
        wait_for(client, "slow task start", lambda msg: msg.get("type") == "task_start" and msg.get("name") == "slow")
        wait_for(client, "slow command event", lambda msg: msg.get("type") == "command" and msg.get("task") == "slow")
        client.send_json({"action": "stop"})
        wait_for(client, "cancel output", lambda msg: msg.get("type") == "output" and msg.get("task") == "slow" and "cancelled by user" in msg.get("line", "").lower())
        wait_for(client, "cancel completion", lambda msg: msg.get("type") == "task_complete" and msg.get("name") == "slow" and msg.get("success") is False)
        wait_for(client, "cancel summary", lambda msg: msg.get("type") == "summary" and msg.get("tasks_failed", 0) >= 1)
    finally:
        client.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
