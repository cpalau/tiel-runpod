#!/bin/bash
set -e
GPU_TYPE="${1:-NVIDIA A100-SXM4-80GB}"
if [ -n "$RUNPOD_API_KEY" ]; then KEY="$RUNPOD_API_KEY"
elif [ -f ~/.secrets/runpod_api_key ]; then KEY="$(cat ~/.secrets/runpod_api_key | tr -d '\n')"
else echo "ERROR: falta RUNPOD_API_KEY"; exit 1; fi
PAYLOAD=$(cat <<JSON
{
  "name": "tiel-coder-pod",
  "image": "ghcr.io/ggml-org/llama.cpp:server-cuda",
  "gpu": { "id": "${GPU_TYPE}", "count": 1 },
  "disk": 60,
  "ports": ["8080/http", "22/tcp"],
  "startSsh": true,
  "args": "--hf-repo peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF:UD-Q4_K_XL --host 0.0.0.0 --port 8080 --ctx-size 262144 -ngl 99 --jinja"
}
JSON
)
echo "Creando Pod Tiel ghcr latest..."
curl -s -X POST https://api.runpod.io/v2/pods -H "Authorization: Bearer ${KEY}" -H "Content-Type: application/json" -d "$PAYLOAD" | python3 -m json.tool | head -n 30
