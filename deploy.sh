#!/bin/bash
set -e
# Deploy Serverless — Tiel-Coder Q4_K_XL con imagen greyul (pre-hecha, sin build)
# Uso: ./deploy.sh
# Requiere: ~/.secrets/runpod_api_key  o  export RUNPOD_API_KEY

if [ -n "$RUNPOD_API_KEY" ]; then KEY="$RUNPOD_API_KEY"
elif [ -f ~/.secrets/runpod_api_key ]; then KEY="$(cat ~/.secrets/runpod_api_key | tr -d '\n')"
else echo "ERROR: falta RUNPOD_API_KEY. Ver KEYS.md"; exit 1; fi

VOL_ID="l1lelwqilk"  # tiel-models 100GB EU-RO-1 (ya creado). Si no existe, créalo: POST /v2/network-volumes

PAYLOAD=$(cat <<JSON
{
  "name": "tiel-coder-q4xl",
  "type": "QUEUE",
  "image": "greyul/runpod-llama-cpp-cuda:latest",
  "gpu": { "pools": ["AMPERE_80", "BLACKWELL_96", "ADA_80_PRO"] },
  "scaling": { "type": "QUEUE_DELAY", "queueDelay": 2 },
  "workers": { "min": 0, "max": 2, "idleTimeout": 5 },
  "disk": 60,
  "networkVolumes": ["${VOL_ID}"],
  "flashboot": "FLASHBOOT",
  "timeout": 600000,
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

echo "Creando endpoint serverless tiel-coder-q4xl (greyul)..."
RESP=$(curl -s -X POST https://api.runpod.io/v2/serverless \
  -H "Authorization: Bearer ${KEY}" -H "Content-Type: application/json" -d "$PAYLOAD")

echo "$RESP" | python3 -m json.tool 2>&1 | head -n 60

ID=$(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null || echo "")
if [ -n "$ID" ]; then
  echo ""
  echo "ENDPOINT_ID=$ID"
  echo "Actualizando ~/.config/opencode/opencode.json..."
  python3 <<PY
import json, pathlib
p = pathlib.Path.home() / ".config/opencode/opencode.json"
j = json.loads(p.read_text())
j["provider"]["runpod-tiel"]["options"]["baseURL"] = f"https://api.runpod.ai/v2/${ID}/openai/v1"
p.write_text(json.dumps(j, indent=2))
print(f"baseURL -> https://api.runpod.ai/v2/${ID}/openai/v1")
PY
  echo "Test: curl -H \"Authorization: Bearer \$RUNPOD_API_KEY\" https://api.runpod.ai/v2/${ID}/health"
else
  echo "Fallo. Revisa volumen l1lelwqilk y que la imagen greyul exista."
fi
