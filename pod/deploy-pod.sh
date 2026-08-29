#!/bin/bash
set -e
# Deploy Pod — Tiel-Coder Q4_K_XL con greyul (simple, probado) + A100 80GB
# Uso: pod/deploy-pod.sh  [GPU_TYPE_ID]
# Requiere: ~/.secrets/runpod_api_key  o  export RUNPOD_API_KEY

GPU_TYPE="${1:-NVIDIA A100-SXM4-80GB}"

if [ -n "$RUNPOD_API_KEY" ]; then KEY="$RUNPOD_API_KEY"
elif [ -f ~/.secrets/runpod_api_key ]; then KEY="$(cat ~/.secrets/runpod_api_key | tr -d '\n')"
else echo "ERROR: falta RUNPOD_API_KEY. Ver KEYS.md"; exit 1; fi

PAYLOAD=$(cat <<JSON
{
  "name": "tiel-coder-pod",
  "image": "shennguyenrs/llama-cpp-server-cuda12:b9994",
  "gpu": { "id": "${GPU_TYPE}", "count": 1 },
  "disk": 60,
  "ports": ["8080/http", "22/tcp"],
  "env": {
    "HF_REPO": "peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF",
    "HF_FILE": "Tiel-Coder-35B-A3B-UD-Q4_K_XL.gguf",
    "MODELS_DIR": "/workspace/models",
    "LLAMA_ARG_HOST": "0.0.0.0",
    "LLAMA_ARG_PORT": "8080",
    "LLAMA_ARGS": "-ngl 99 --jinja --ctx-size 262144 --flash-attn auto --cache-type-k q8_0 --cache-type-v q8_0"
  }
}
JSON
)

echo "Creando Pod tiel-coder-pod con ${GPU_TYPE} (shennguyenrs b9994, 1 mes, disk 60GB, port 8080)..."
RESP=$(curl -s -X POST https://api.runpod.io/v2/pods \
  -H "Authorization: Bearer ${KEY}" -H "Content-Type: application/json" -d "$PAYLOAD")

echo "$RESP" | python3 -m json.tool 2>&1 | head -n 80

POD_ID=$(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id','') or d.get('pod',{}).get('id',''))" 2>/dev/null || echo "")
if [ -n "$POD_ID" ]; then
  echo ""
  echo "POD_ID=$POD_ID"
  echo "Espera a RUNNING (~2-3 min, primera vez descarga 22.4GB):"
  echo "  curl -H \"Authorization: Bearer \$RUNPOD_API_KEY\" https://api.runpod.io/v2/pods/${POD_ID} | jq .desiredStatus"
  echo "Cuando esté RUNNING:"
  echo "  curl http://${POD_ID}-8080.proxy.runpod.net/v1/models"
  echo "  curl http://${POD_ID}-8080.proxy.runpod.net/v1/chat/completions -H 'Content-Type: application/json' -d '{\"model\":\"tiel-coder\",\"messages\":[{\"role\":\"user\",\"content\":\"hola\"}],\"temperature\":0.6,\"max_tokens\":100}'"
  echo "Para parar: pod/stop-pod.sh ${POD_ID}"
fi
