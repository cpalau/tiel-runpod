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
RESP=$(curl -s -X POST https://api.runpod.io/v2/pods -H "Authorization: Bearer ${KEY}" -H "Content-Type: application/json" -d "$PAYLOAD")
echo "$RESP" | python3 -m json.tool 2>&1 | head -n 80
POD_ID=$(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id','') or d.get('pod',{}).get('id',''))" 2>/dev/null || echo "")
if [ -n "$POD_ID" ]; then
  echo ""
  echo "POD_ID=$POD_ID"
  echo "Espera a RUNNING (descarga 22.4GB, 2-3 min):"
  echo "  curl -H \"Authorization: Bearer \$RUNPOD_API_KEY\" https://api.runpod.io/v2/pods/${POD_ID} | jq .desiredStatus"
  echo "Cuando esté RUNNING:"
  echo "  curl https://${POD_ID}-8080.proxy.runpod.net/v1/models"
  echo "  curl https://${POD_ID}-8080.proxy.runpod.net/v1/chat/completions -H 'Content-Type: application/json' -d '{\"model\":\"tiel-coder\",\"messages\":[{\"role\":\"user\",\"content\":\"hola\"}],\"temperature\":0.6,\"max_tokens\":100}'"
  echo "Para parar: pod/stop-pod.sh ${POD_ID}"
fi
