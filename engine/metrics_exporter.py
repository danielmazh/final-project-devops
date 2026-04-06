"""Lightweight Prometheus exporter sidecar for seyoawe-engine.

Runs on port 9113, probes the engine's Flask server on 8080 every 15 s,
and exposes standard process metrics plus an engine_up gauge.
"""

import socket
import time
import threading

from prometheus_client import Gauge, Histogram, start_http_server

METRICS_PORT = 9113
ENGINE_HOST = "127.0.0.1"
ENGINE_PORT = 8080
PROBE_INTERVAL = 15

engine_up = Gauge(
    "seyoawe_engine_up",
    "1 if the engine TCP socket on :8080 is accepting connections, 0 otherwise",
)
probe_duration = Histogram(
    "seyoawe_engine_probe_duration_seconds",
    "Time spent probing the engine's TCP socket",
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0),
)


def _probe_loop():
    while True:
        start = time.monotonic()
        try:
            with socket.create_connection((ENGINE_HOST, ENGINE_PORT), timeout=2):
                engine_up.set(1)
        except OSError:
            engine_up.set(0)
        finally:
            probe_duration.observe(time.monotonic() - start)
        time.sleep(PROBE_INTERVAL)


if __name__ == "__main__":
    start_http_server(METRICS_PORT)
    threading.Thread(target=_probe_loop, daemon=True).start()
    # Block forever — let the engine (PID 1) handle signals.
    threading.Event().wait()
