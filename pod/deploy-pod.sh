#!/bin/bash
set -e
# Deploy Pod — Tiel-Coder Q4_K_XL con base eniewold/llama-cpp-runpod + A100 80GB
# Uso: pod/deploy-pod.sh  [GPU_TYPE_ID]
# Requiere: ~/.secrets/runpod_api_key  o  export RUNPOD_API_KEY
# Nota: usa la misma imagen que serverless (cpalau/tiel-runpod:eniewold, handler en 3098).
# Para Pod directo sin handler, cambia image a greyul/runpod-llama-cpp-cuda:latest

GPU_TYPE="${1:-NVIDIA A100-SXM4-80GB}"

if [ -n "$RUNPOD_API_KEY" ]; then KEY="$RUNPOD_API_KEY"
elif [ -f ~/.secrets/runpod_api_key ]; then KEY="$(cat ~/.secrets/runpod_api_key | tr -d '\n')"
else echo "ERROR: falta RUNPOD_API_KEY. Ver KEYS.md"; exit 1; fi

PAYLOAD=$(cat <<JSON
{
  "name": "tiel-coder-pod",
  "image": "cpalau/tiel-runpod:eniewold",
  "gpu": { "id": "${GPU_TYPE}", "count": 1 },
  "disk": 60,
  "ports": ["3098/http", "22/tcp"],
  "env": {
    "LLAMA_ARG_HF_REPO": "peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF",
    "LLAMA_HF_QUANT": "UD-Q4_K_XL",
    "LLAMA_ARG_CTX_SIZE": "262144",
    "LLAMA_ARG_N_PARALLEL": "1",
    "LLAMA_ARG_N_GPU_LAYERS": "999",
    "LLAMA_ARG_N_CPU_MOE": "0",
    "LLAMA_ARG_FLASH_ATTN": "auto"
  }
}
JSON
)

echo "Creando Pod tiel-coder-pod con ${GPU_TYPE} (eniewold, disk 60GB, port 3098)..."
RESP=$(curl -s -X POST https://api.runpod.io/v2/pods \
  -H "Authorization: Bearer ${KEY}" -H "Content-Type: application/json" -d "$PAYLOAD")

echo "$RESP" | python3 -m json.tool 2>&1 | head -n 80

POD_ID=$(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id','') or d.get('pod',{}).get('id',''))" 2>/dev/null || echo "")
if [ -n "$POD_ID" ]; then
  echo ""
  echo "POD_ID=$POD_ID"
  echo "Espera a RUNNING (~2-3 min, primera vez descarga 22.4GB):"
  echo "  curl -H \"Authorization: Bearer \$RUNPOD_API_KEY\" https://api.runpod.io/v2/pods/${POD_ID} | jq .desiredStatus"
  echo "Cuando esté RUNNING (eniewold expone 3098, no 8080):"
  echo "  curl http://${POD_ID}-3098.proxy.runpod.net/v1/models"
  echo "  curl http://${POD_ID}-3098.proxy.runpod.net/v1/chat/completions -H 'Content-Type: application/json' -d '{\"model\":\"tiel-coder\",\"messages\":[{\"role\":\"user\",\"content\":\"hola\"}],\"temperature\":0.6,\"max_tokens\":100}'"
  echo "Para parar: pod/stop-pod.sh ${POD_ID}"
  echo ""
  echo "Nota: la imagen cpalau/tiel-runpod:eniewold debe existir en Docker Hub."
  echo "Si ves IMAGE_NOT_FOUND, haz: podman build -t cpalau/tiel-runpod:eniewold . && podman push cpalau/tiel-runpod:eniewold"
fi
