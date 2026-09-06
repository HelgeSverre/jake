#!/usr/bin/env python3
"""Run benign Web UI lifecycle checks against sequential and parallel servers."""
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
from urllib.request import urlopen


def main():
    binary = str(Path(sys.argv[1]).resolve())
    fixture = Path(__file__).resolve().parent
    for jobs in (1, 2):
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            port = probe.getsockname()[1]
        with tempfile.TemporaryFile(mode="w+") as log:
            process = subprocess.Popen(
                [binary, "--web", "--verbose", "-j", str(jobs), "--port", str(port), "-f", str(fixture / "Jakefile")],
                env={**os.environ, "CI": "1"}, stdout=log, stderr=log,
            )
            try:
                deadline = time.monotonic() + 10
                while True:
                    try:
                        with urlopen(f"http://127.0.0.1:{port}/", timeout=1) as response:
                            assert b"Jake Web UI" in response.read()
                        with urlopen(f"http://127.0.0.1:{port}/api/status", timeout=1) as response:
                            assert b'"status":"ok"' in response.read()
                        break
                    except OSError:
                        if process.poll() is not None or time.monotonic() >= deadline:
                            raise
                        time.sleep(0.05)
                subprocess.run([sys.executable, str(fixture / "websocket_e2e.py"), str(port), str(jobs)], check=True, timeout=60)
                print(f"  Web UI lifecycle and state with -j{jobs} ............. PASS")
            except BaseException:
                log.seek(0)
                print(log.read(), file=sys.stderr)
                raise
            finally:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == "__main__":
    main()
