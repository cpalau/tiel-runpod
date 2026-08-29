#!/bin/bash
set -e
# Crea endpoint serverless Runpod para Tiel-Coder via API
# Uso: echo "tu-key" > ~/.secrets/runpod_api_key && chmod 600 ~/.secrets/runpod_api_key && ./create_endpoint.sh
# o: RUNPOD_API_KEY="..." ./create_endpoint.sh

if [ -n "$RUNPOD_API_KEY" ]; then
  KEY="$RUNPOD_API_KEY"
elif [ -f ~/.secrets/runpod_api_key ]; then
  KEY="$(cat ~/.secrets/runpod_api_key | tr -d '\n')"
else
  echo "ERROR: No hay RUNPOD_API_KEY. Haz:"
  echo "  mkdir -p ~/.secrets && echo -n 'tu-nueva-key' > ~/.secrets/runpod_api_key && chmod 600 ~/.secrets/runpod_api_key"
  echo "  # o export RUNPOD_API_KEY='...' (no lo pegues en el chat)"
  exit 1
fi

if [ ${#KEY} -lt 20 ]; then echo "Key parece corta"; exit 1; fi

echo "Creando Network Volume (si no existe)..."
VOL_RESP=$(curl -s -X POST https://api.runpod.io/v2/networkvolumes \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"name":"tiel-models","size":100,"dataCenterId":"EU-RO-1"}' || true)
echo "$VOL_RESP" | head -c 500; echo

VOL_ID=$(echo "$VOL_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id') or d.get('networkVolume',{}).get('id') or '')" 2>/dev/null || echo "")
echo "VOL_ID=$VOL_ID"

echo ""
echo "Creando endpoint serverless (GitHub cpalau/tiel-runpod)..."
PAYLOAD=$(cat <<JSON
{
  "name": "tiel-coder-q4xl",
  "type": "QUEUE",
  "gpuTypeIds": ["AMPERE_80", "ADA_6000_PRO", "HOPPER_80"],
  "workersMin": 0,
  "workersMax": 2,
  "idleTimeout": 5,
  "scalerType": "QUEUE_DELAY",
  "scalerValue": 2,
  "containerDiskInGb": 60,
  "volumeMountPath": "/runpod-volume",
  "networkVolumeId": "$VOL_ID",
  "flashboot": "FLASHBOOT",
  "timeout": 600000,
  "env": {
    "MODEL_URL": "https://huggingface.co/peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF/resolve/main/Tiel-Coder-35B-A3B-UD-Q4_K_XL.gguf",
    "MODEL_FILENAME": "Tiel-Coder-35B-A3B-UD-Q4_K_XL.gguf",
    "MODEL_DIR": "/runpod-volume",
    "MODEL_NAME": "Tiel-Coder-35B-A3B-UD-Q4_K_XL",
    "CONTEXT_LENGTH": "262144",
    "LLAMA_SERVER_PORT": "8000",
    "FLASH_ATTENTION": "1",
    "SPLIT_MODE": "2",
    "CACHE_QUANTIZATION": "q8_0",
    "MAX_NUM_SEQS": "4",
    "LLAMA_EXTRA_ARGS": "--flash-attn --split-mode 2"
  },
  "githubRepo": "cpalau/tiel-runpod",
  "githubBranch": "main",
  "dockerfilePath": "Dockerfile"
}
JSON
)
echo "$PAYLOAD" | python3 -m json.tool | head -n 50

RESP=$(curl -s -X POST https://api.runpod.io/v2/endpoints \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "$PAYLOAD" || true)
echo ""
echo "RESPUESTA:"
echo "$RESP" | python3 -m json.tool 2>/dev/null | head -n 100 || echo "$RESP" | head -c 2000

EP_ID=$(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id') or d.get('endpoint',{}).get('id') or '')" 2>/dev/null || echo "")
if [ -n "$EP_ID" ]; then
  echo ""
  echo "ENDPOINT_ID=$EP_ID"
  echo "Actualizando opencode.json..."
  python3 <<PY
import json, pathlib
p = pathlib.Path.home() / ".config/opencode/opencode.json"
j = json.loads(p.read_text())
j["provider"]["runpod-tiel"]["options"]["baseURL"] = f"https://api.runpod.ai/v2/$EP_ID/openai/v1"
p.write_text(json.dumps(j, indent=2))
print(f"Actualizado baseURL a https://api.runpod.ai/v2/$EP_ID/openai/v1")
PY
  echo "Hecho. Prueba: curl -H \"Authorization: Bearer \$KEY\" https://api.runpod.ai/v2/$EP_ID/openai/v1/models"
else
  echo ""
  echo "No se pudo crear via API automáticamente (Runpod cambia schema). Hazlo manual:"
  echo "  https://console.runpod.io/serverless -> New Endpoint -> Import GitHub cpalau/tiel-runpod"
  echo "  GPU: A100 80GB (fallback RTX PRO 6000 96GB + H100), Disk 60GB, Volume /runpod-volume, Env como arriba"
fi