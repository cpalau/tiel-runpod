#!/bin/bash
set -e
echo "[start.sh] Optional helper - handler.py already handles download + llama-server startup"
echo "MODEL_URL=${MODEL_URL}"
echo "MODEL_DIR=${MODEL_DIR:-/runpod-volume}"
echo "CONTEXT_LENGTH=${CONTEXT_LENGTH:-8192}"
exec python3 -u handler.py
