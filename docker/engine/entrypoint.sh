#!/bin/sh
# Start the Prometheus metrics exporter in the background, then exec the engine.
python3 /app/metrics_exporter.py &
exec /app/seyoawe.linux
