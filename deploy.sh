#!/bin/bash
set -e
# Deploy Serverless — Tiel-Coder Q4_K_XL con base eniewold/llama-cpp-runpod
# Uso: ./deploy.sh
# Requiere: ~/.secrets/runpod_api_key  o  export RUNPOD_API_KEY
# Nota: la imagen se buildea desde GitHub cpalau/tiel-runpod (Dockerfile eniewold). No hay pull de ghcr.

if [ -n "$RUNPOD_API_KEY" ]; then KEY="$RUNPOD_API_KEY"
elif [ -f ~/.secrets/runpod_api_key ]; then KEY="$(cat ~/.secrets/runpod_api_key | tr -d '\n')"
else echo "ERROR: falta RUNPOD_API_KEY. Ver KEYS.md"; exit 1; fi

VOL_ID="l1lelwqilk"  # tiel-models 100GB EU-RO-1

PAYLOAD=$(cat <<JSON
{
  "name": "tiel-coder-q4xl",
  "type": "QUEUE",
  "image": "cpalau/tiel-runpod:eniewold",
  "gpu": { "pools": ["AMPERE_80", "BLACKWELL_96", "ADA_80_PRO"] },
  "scaling": { "type": "QUEUE_DELAY", "queueDelay": 2 },
  "workers": { "min": 0, "max": 2, "idleTimeout": 5 },
  "disk": 60,
  "networkVolumes": ["${VOL_ID}"],
  "flashboot": "FLASHBOOT",
  "timeout": 600000,
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

echo "Creando endpoint serverless tiel-coder-q4xl (eniewold)..."
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
# opencode habla a Runpod via handler que proxya a 3098/v1, pero endpoint ya es OpenAI
# Si usas eniewold, el handler acepta {"input":{"messages":[...]}} y {"input":{"openai_route":...}}
# Para opencode directo vía /openai/v1, usa baseURL https://api.runpod.ai/v2/${ID}/openai/v1
p.write_text(json.dumps(j, indent=2))
print(f"baseURL -> https://api.runpod.ai/v2/${ID}/openai/v1")
PY
  echo "Test: curl -H \"Authorization: Bearer \$RUNPOD_API_KEY\" https://api.runpod.ai/v2/${ID}/health"
  echo "Chat: curl -X POST https://api.runpod.ai/v2/${ID}/runsync -H \"Authorization: Bearer \$RUNPOD_API_KEY\" -H 'Content-Type: application/json' -d '{\"input\":{\"messages\":[{\"role\":\"user\",\"content\":\"hola\"}],\"stream\":false}}'"
else
  echo "Fallo. Verifica volumen l1lelwqilk y que el repo cpalau/tiel-runpod sea público y tenga Dockerfile eniewold."
fi
