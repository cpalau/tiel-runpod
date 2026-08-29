#!/bin/bash
set -e
GPU_TYPE="${1:-NVIDIA A100-SXM4-80GB}"
if [ -n "$RUNPOD_API_KEY" ]; then KEY="$RUNPOD_API_KEY"
elif [ -f ~/.secrets/runpod_api_key ]; then KEY="$(cat ~/.secrets/runpod_api_key | tr -d '\n')"
else echo "ERROR: falta RUNPOD_API_KEY"; exit 1; fi
PAYLOAD=$(cat <<JSON
{
  "name": "tiel-coder-pod",
  "image": "greyul/runpod-llama-cpp-cuda:latest",
  "gpu": { "id": "${GPU_TYPE}", "count": 1 },
  "disk": 60,
  "ports": ["8080/http", "22/tcp"],
  "startSsh": true,
  "env": {
    "HF_REPO": "peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF",
    "HF_FILE": "Tiel-Coder-35B-A3B-UD-Q4_K_XL.gguf",
    "MODELS_DIR": "/workspace/models",
    "LLAMA_ARGS": "--host 0.0.0.0 --port 8080 --ctx-size 262144 -ngl 99 --jinja"
  }
}
JSON
)
echo "Creando Pod Tiel greyul --ctx-size + host/port..."
curl -s -X POST https://api.runpod.io/v2/pods -H "Authorization: Bearer ${KEY}" -H "Content-Type: application/json" -d "$PAYLOAD" | python3 -m json.tool | head -n 30
