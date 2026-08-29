# Tiel-Coder-35B-A3B GGUF - Runpod Serverless

Endpoint serverless para `peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF` tier `UD-Q4_K_XL 22.4GB`.

## Modelo
- 35B MoE (3.4B activos), 256 expertos, 2 KV heads -> KV cache pequeño
- Sampling recomendado: `temperature 0.6` para coding agéntico (`1.0` default), `top_p 0.95`, `top_k 20`
- Prompt: llama.cpp aplica plantilla Sharp automáticamente con `--jinja`

## Archivos
- `Dockerfile` - build `llama.cpp` con CUDA 12.4
- `handler.py` - descarga a `/runpod-volume` (cache), lanza `llama-server :8000`, proxya OpenAI
- `requirements.txt` - `runpod`

## Deploy (GitHub, sin Docker Hub)

1. Crea repo privado en GitHub y push:
```bash
cd ~/tiel-runpod
git init && git add . && git commit -m "Tiel Runpod handler"
gh repo create tiel-runpod --private --source=. --push
```

2. Runpod Console -> Serverless -> New Endpoint
   - Build from GitHub: selecciona tu repo, branch main, Dockerfile Path `Dockerfile`
   - GPU: **`A100 80GB` (principal) + fallback `RTX PRO 6000 96GB` + `H100 80GB`** — para 262k holgado y 1M con YaRN. Evita `A6000 48GB` si quieres el máximo sin compromiso. Container Disk `60GB`
   - Network Volume: crea uno 100GB y móntalo en `/runpod-volume`
   - Env vars (máximo nativo 262k, descomenta YaRN para 1M):
     ```
     MODEL_URL=https://huggingface.co/peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF/resolve/main/Tiel-Coder-35B-A3B-UD-Q4_K_XL.gguf
     MODEL_FILENAME=Tiel-Coder-35B-A3B-UD-Q4_K_XL.gguf
     MODEL_DIR=/runpod-volume
     CONTEXT_LENGTH=262144
     MODEL_NAME=Tiel-Coder-35B-A3B-UD-Q4_K_XL
     # Para 1M: añade LLAMA_EXTRA_ARGS con YaRN (ver abajo)
     # LLAMA_EXTRA_ARGS=--rope-scaling yarn --rope-freq-base 1000000 --yarn-orig-ctx 262144
     ```
   - Workers: Min 0, Max 2, Idle 5s, FlashBoot on
   - Deploy -> copia `ENDPOINT_ID`

3. Test:
```bash
export RUNPOD_API_KEY="tu-key"
export ENDPOINT_ID="tu-id"
curl -X POST https://api.runpod.ai/v2/$ENDPOINT_ID/openai/v1/chat/completions \
 -H "Authorization: Bearer $RUNPOD_API_KEY" -H "Content-Type: application/json" \
 -d '{"model":"Tiel-Coder-35B-A3B-UD-Q4_K_XL","messages":[{"role":"user","content":"Escribe una función python is_prime(n)"}],"temperature":0.6,"max_tokens":512}' --max-time 120
# vía queue nativo:
curl -X POST https://api.runpod.ai/v2/$ENDPOINT_ID/runsync \
 -H "Authorization: Bearer $RUNPOD_API_KEY" -H "Content-Type: application/json" \
 -d '{"input":{"messages":[{"role":"user","content":"hola"}],"temperature":0.6,"max_tokens":256}}' --max-time 120
```

## Conectar a opencode

Añade en `~/.config/opencode/opencode.json` dentro de `provider`:

```json
"runpod-tiel": {
  "npm": "@ai-sdk/openai-compatible",
  "name": "Runpod Tiel Coder",
  "options": {
    "baseURL": "https://api.runpod.ai/v2/YOUR_ENDPOINT_ID/openai/v1",
    "apiKey": "{env:RUNPOD_API_KEY}"
  },
  "models": {
    "Tiel-Coder-35B-A3B-UD-Q4_K_XL": {
      "name": "Tiel Coder Q4_K_XL (Runpod)",
      "limit": { "context": 262144, "output": 65536 }
    }
  }
}
```

Luego `export RUNPOD_API_KEY` y en opencode `/models` selecciona `runpod-tiel/Tiel-Coder-35B-A3B-UD-Q4_K_XL`.

## Coste (serverless, $0 idle con Min 0)
- A6000 48GB: $1.22/h activo — justo para 262k
- **A100 80GB: $2.74/h** — recomendado para 262k holgado
- **RTX PRO 6000 96GB: $4.00/h** — ideal para 262k + margen 1M YaRN
- H100 80GB: $4.18/h, H200 141GB $5.58/h, B200 $8.64/h — overkill salvo batch enorme
- Ej: 1h/día en A100 ~ $82/mes vs Pod A100 $1140/mes 24/7. Break-even A100 ~9h/día.

## Máquina potente + YaRN 1M (opcional)
Si quieres 1M efectivo, deja `CONTEXT_LENGTH=1048576` y añade `LLAMA_EXTRA_ARGS=--rope-scaling yarn --rope-freq-base 1000000 --yarn-orig-ctx 262144` (o el flag que exponga tu build de llama.cpp). Solo usa YaRN si realmente necesitas >262k, empeora un poco prompts cortos. Necesita GPU 80GB+.
