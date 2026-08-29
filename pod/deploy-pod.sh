#!/bin/bash
set -e
# Deploy Pod real — Tiel-Coder Q4_K_XL con greyul + A100 80GB (ver runpod.yaml)
# Uso: pod/deploy-pod.sh  [GPU_TYPE_ID]
# Requiere: ~/.secrets/runpod_api_key  o  export RUNPOD_API_KEY
# GPU por defecto: NVIDIA A100-SXM4-80GB ($1.59/h, MEDIUM). Alternativas:
#   "NVIDIA A40" ($0.44/h), "NVIDIA RTX PRO 6000 Blackwell Server Edition" ($2.09/h, 96GB)

GPU_TYPE="${1:-NVIDIA A100-SXM4-80GB}"
VOL_ID="l1lelwqilk"
DC_ID="EU-RO-1"

if [ -n "$RUNPOD_API_KEY" ]; then KEY="$RUNPOD_API_KEY"
elif [ -f ~/.secrets/runpod_api_key ]; then KEY="$(cat ~/.secrets/runpod_api_key | tr -d '\n')"
else echo "ERROR: falta RUNPOD_API_KEY. Ver KEYS.md"; exit 1; fi

PAYLOAD=$(cat <<JSON
{
  "name": "tiel-coder-pod",
  "imageName": "greyul/runpod-llama-cpp-cuda:latest",
  "gpuTypeId": "${GPU_TYPE}",
  "dataCenterId": "${DC_ID}",
  "containerDiskInGb": 20,
  "volumeId": "${VOL_ID}",
  "volumeMountPath": "/runpod-volume",
  "ports": "8080/http,22/tcp",
  "env": {
    "HF_REPO": "peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF",
    "HF_FILE": "Tiel-Coder-35B-A3B-UD-Q4_K_XL.gguf",
    "MODELS_DIR": "/runpod-volume/models",
    "LLAMA_ARG_HOST": "0.0.0.0",
    "LLAMA_ARG_PORT": "8080",
    "LLAMA_ARGS": "-ngl 99 --jinja --context-size 262144"
  }
}
JSON
)

echo "Creando Pod tiel-coder-pod con ${GPU_TYPE} en ${DC_ID}..."
RESP=$(curl -s -X POST https://api.runpod.io/v2/pods \
  -H "Authorization: Bearer ${KEY}" -H "Content-Type: application/json" -d "$PAYLOAD")

echo "$RESP" | python3 -m json.tool 2>&1 | head -n 80

POD_ID=$(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id','') or d.get('pod',{}).get('id',''))" 2>/dev/null || echo "")
if [ -n "$POD_ID" ]; then
  echo ""
  echo "POD_ID=$POD_ID"
  echo "Espera a RUNNING (~2-3 min, primera vez descarga 22.4GB a volumen):"
  echo "  curl -H \"Authorization: Bearer \$RUNPOD_API_KEY\" https://api.runpod.io/v2/pods/${POD_ID} | jq .desiredStatus"
  echo ""
  echo "Cuando esté RUNNING, prueba:"
  echo "  curl http://\${POD_ID}-8080.proxy.runpod.net/v1/models"
  echo "  curl http://\${POD_ID}-8080.proxy.runpod.net/v1/chat/completions -H 'Content-Type: application/json' -d '{\"model\":\"tiel-coder\",\"messages\":[{\"role\":\"user\",\"content\":\"hola\"}],\"temperature\":0.6,\"max_tokens\":100}'"
  echo ""
  echo "Para parar y no pagar idle: pod/stop-pod.sh ${POD_ID}"
fi
