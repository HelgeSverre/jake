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


def collect_run(client, prefix=None):
    messages = list(prefix or [])
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        msg = client.recv_json(max(0.1, deadline - time.monotonic()))
        messages.append(msg)
        if msg.get("type") == "run_state" and msg.get("running") is False:
            summaries = [m for m in messages if m.get("type") == "summary"]
            assert len(summaries) == 1, messages
            starts = [m["name"] for m in messages if m.get("type") == "task_start"]
            completions = [m for m in messages if m.get("type") == "task_complete"]
            ends = [m["name"] for m in completions]
            assert sorted(starts) == sorted(ends), messages
            assert len(ends) == len(set(ends)), messages
            assert summaries[0]["tasks_run"] == len(completions), messages
            assert summaries[0]["tasks_failed"] == sum(not m["success"] for m in completions), messages
            return messages
    raise AssertionError("run did not release its admission lock")


def run(client, recipe):
    client.send_json({"action": "run", "recipe": recipe, "params": {}, "dryRun": False})


def connect_ready(port, active=False):
    client = WebSocketClient("127.0.0.1", port)
    init = wait_for(client, "init", lambda m: m.get("type") == "init")
    state = wait_for(client, "run state", lambda m: m.get("type") == "run_state")
    assert state["running"] is active, state
    return client, init, state


def main() -> int:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 18450
    jobs = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    client, init, _ = connect_ready(port)
    try:
        names = {r["name"] for r in init["recipes"]}
        assert {"dep", "root", "confirm-task", "slow", "fails"}.issubset(names)

        run(client, "confirm-task")
        prefix = []
        while True:
            msg = client.recv_json()
            prefix.append(msg)
            if msg.get("type") == "confirm":
                client.send_json({"action": "confirm", "confirmId": msg["confirmId"], "approved": True})
                break
        result = collect_run(client, prefix)
        assert any(m.get("line") == "confirmed-output" for m in result), result

        # Repeated execution must reset counters and re-run dependencies.
        for _ in range(8):
            run(client, "root")
            result = collect_run(client)
            assert {m.get("name") for m in result if m.get("type") == "task_complete"} == {"root", "dep"}
            assert any(m.get("line") == "dep-output" for m in result)
            assert any(m.get("line") == "root-output" for m in result)
            assert next(m for m in result if m.get("type") == "summary")["tasks_failed"] == 0

        run(client, "fails")
        result = collect_run(client)
        assert next(m for m in result if m.get("type") == "summary")["tasks_failed"] >= 1

        # Stop during admission, before relying on a task_start notification.
        for _ in range(4):
            run(client, "slow")
            state = client.recv_json()
            assert state.get("type") == "run_state" and state["running"], state
            client.send_json({"action": "stop"})
            result = collect_run(client, [state])
            assert next(m for m in result if m.get("type") == "summary")["tasks_failed"] >= 1

        # Ordinary reconnect and second-tab admission during a cancellable run.
        for _ in range(3):
            run(client, "slow")
            prefix = []
            while True:
                msg = client.recv_json()
                prefix.append(msg)
                if msg.get("type") == "command" and msg.get("task") == "slow":
                    break
            other, _, state = connect_ready(port, active=True)
            try:
                assert state["recipe"] == "slow" and "slow" in state["active_tasks"], state
                run(other, "dep")
                rejection = other.recv_json(2)
                assert rejection.get("type") == "error" and "already running" in rejection.get("message", ""), rejection
            finally:
                other.close()
            client.send_json({"action": "stop"})
            result = collect_run(client, prefix)
            ends = [m for m in result if m.get("type") == "task_complete"]
            assert len(ends) == 1 and ends[0]["name"] == "slow" and not ends[0]["success"], result
            assert any("cancelled by user" in m.get("line", "").lower() for m in result), result
            assert next(m for m in result if m.get("type") == "summary")["tasks_failed"] >= 1
        if jobs > 1:
            run(client, "parallel-slow")
            prefix = []
            commands = set()
            while len(commands) < 2:
                msg = client.recv_json()
                prefix.append(msg)
                if msg.get("type") == "command":
                    commands.add(msg.get("task"))
            other, _, state = connect_ready(port, active=True)
            other.close()
            assert set(state["active_tasks"]) == {"slow-left", "slow-right"}, state
            started = time.monotonic()
            client.send_json({"action": "stop"})
            result = collect_run(client, prefix)
            assert time.monotonic() - started < 3, "all parallel children must stop promptly"
            ends = [m for m in result if m.get("type") == "task_complete"]
            assert {m["name"] for m in ends} == {"parallel-slow", "slow-left", "slow-right"}, result
            assert all(not m["success"] for m in ends), result
    finally:
        client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
