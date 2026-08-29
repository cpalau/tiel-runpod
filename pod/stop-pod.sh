#!/bin/bash
set -e
# Uso: pod/stop-pod.sh <podId>
if [ -z "$1" ]; then echo "Uso: $0 <podId>"; exit 1; fi
if [ -n "$RUNPOD_API_KEY" ]; then KEY="$RUNPOD_API_KEY"
elif [ -f ~/.secrets/runpod_api_key ]; then KEY="$(cat ~/.secrets/runpod_api_key | tr -d '\n')"
else echo "ERROR: falta RUNPOD_API_KEY"; exit 1; fi
echo "Borrando Pod $1..."
curl -s -X DELETE "https://api.runpod.io/v2/pods/$1" -H "Authorization: Bearer ${KEY}" | python3 -m json.tool 2>&1 | head -n 20
echo "Hecho. Verifica: curl -H \"Authorization: Bearer \$RUNPOD_API_KEY\" https://api.runpod.io/v2/pods | jq ."
