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
    "LLAMA_ARG_HOST": "0.0.0.0",
    "LLAMA_ARG_PORT": "8080",
    "LLAMA_ARGS": "-ngl 99 --jinja --ctx-size 262144"
  }
}
JSON
)
echo "Creando Pod Tiel con greyul --ctx-size..."
RESP=$(curl -s -X POST https://api.runpod.io/v2/pods -H "Authorization: Bearer ${KEY}" -H "Content-Type: application/json" -d "$PAYLOAD")
echo "$RESP" | python3 -m json.tool 2>&1 | head -n 80
POD_ID=$(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id','') or d.get('pod',{}).get('id',''))" 2>/dev/null || echo "")
if [ -n "$POD_ID" ]; then
  echo ""
  echo "POD_ID=$POD_ID"
  echo "https://${POD_ID}-8080.proxy.runpod.net/v1/models"
fi
