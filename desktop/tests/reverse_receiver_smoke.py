#!/usr/bin/env python3
"""Decode a local HEVC fixture through the phone-initiated connection (no camera required)."""
import argparse
import json
import re
import socket
import struct
import subprocess
import tempfile
import time
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("receiver")
    parser.add_argument("fixture", help="HEVC video file; decoded at its source dimensions")
    parser.add_argument("--ffmpeg", default="ffmpeg")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="phonecam-reverse-") as directory:
        root = Path(directory)
        bitstream = root / "fixture.hevc"
        subprocess.run([args.ffmpeg, "-v", "error", "-i", args.fixture, "-c:v", "copy", "-bsf:v",
                        "hevc_mp4toannexb,hevc_metadata=aud=insert", "-f", "hevc", str(bitstream)], check=True)
        nals = [nal for nal in re.split(b"\x00\x00\x00?\x01", bitstream.read_bytes()) if nal]
        units = []
        for nal in nals:
            if (nal[0] >> 1) & 63 == 35 or not units:
                units.append([])
            units[-1].append(nal)
        assert len(units) >= 10, "Fixture needs ten frames"
        with socket.socket() as reserve:
            reserve.bind(("127.0.0.1", 0))
            port = reserve.getsockname()[1]
        with (root / "receiver.log").open("w+") as log:
            process = subprocess.Popen([args.receiver, "--listen", "--listen-port", str(port), "--no-preview",
                                        "--no-softcam", "--frames", "10", "--snapshot", str(root / "frame.ppm")], stdout=log, stderr=log)
            try:
                deadline = time.monotonic() + 10
                while True:
                    try:
                        phone = socket.create_connection(("127.0.0.1", port), timeout=2)
                        break
                    except OSError:
                        if process.poll() is not None or time.monotonic() >= deadline:
                            raise RuntimeError("Receiver failed to start")
                        time.sleep(.1)
                with phone:
                    phone.settimeout(5)
                    phone.sendall(b"PHONECAM/2\n")

                    def exact(size):
                        data = bytearray()
                        while len(data) < size:
                            chunk = phone.recv(size - len(data))
                            if not chunk:
                                raise RuntimeError("Unexpected receiver EOF")
                            data.extend(chunk)
                        return data

                    def control():
                        channel, reserved, size = struct.unpack("!BBI", exact(6))
                        assert channel == 1 and reserved == 0 and size <= 65535
                        return json.loads(exact(size))

                    def record(channel, body):
                        phone.sendall(struct.pack("!BBI", channel, 0, len(body)) + body)

                    request = control()
                    assert request["type"] == "connect" and request["selected_ladder"]["width"] == 0
                    record(1, json.dumps({"type": "connect_ack", "status": "success", "selected_ladder":
                                          {"width": 1920, "height": 1080, "fps": 60}}).encode())
                    assert control()["type"] == "start"
                    record(1, b'{"type":"start_ack","status":"success"}')
                    sequence = 0
                    for index, unit in enumerate(units[:10]):
                        for ni, nal in enumerate(unit):
                            payloads = [nal]
                            if len(nal) > 1200:
                                kind = (nal[0] >> 1) & 63
                                chunks = [nal[p:p + 1197] for p in range(2, len(nal), 1197)]
                                payloads = [bytes([(nal[0] & 129) | (49 << 1), nal[1], kind |
                                                   (128 if ci == 0 else 0) | (64 if ci == len(chunks)-1 else 0)]) + chunk
                                            for ci, chunk in enumerate(chunks)]
                            for pi, payload in enumerate(payloads):
                                marker = ni == len(unit)-1 and pi == len(payloads)-1
                                rtp = struct.pack("!BBHII", 128, 96 | (128 if marker else 0), sequence & 65535, index * 1500, 0x50434B36)
                                record(2, rtp + payload)
                                sequence += 1
                        # This is a decode/connection smoke test, not a throughput benchmark.
                        time.sleep(.25)
                    result = process.wait(timeout=15)
                log.seek(0)
                output = log.read()
                print(output)
                assert result == 0 and "decode errors 0" in output and (root / "frame.ppm").stat().st_size > 1000
                print("PASS: reverse TCP auto handshake and ten real HEVC decoded frames")
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=5)


if __name__ == "__main__":
    main()
