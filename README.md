# Tiel-Coder-35B-A3B UD-Q4_K_XL 22.4GB — Runpod (Serverless + Pod)

Deploy para `peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF` tier `UD-Q4_K_XL 22.4GB` (4-bit, 35B MoE, 3.4B activos).
Base: **[eniewold/llama-cpp-runpod](https://github.com/eniewold/llama-cpp-runpod)** (`ghcr.io/ggml-org/llama.cpp:server-cuda`, CUDA 12.8+, rebuild auto). Expone API OpenAI `/v1/models,/v1/chat/completions,/v1/completions` con streaming.

## Modelo

- 35B MoE (256 expertos, 8 activos/token), híbrido SSM/attention, 2 KV heads → cache pequeño.
- Sampling: `temperature 1.0, top_p 0.95, top_k 20` (default). Para coding agéntico `temperature 0.6`.
- Chat template Sharp dentro del GGUF → se aplica solo con `--jinja` (lo hace `llama-server` vía `LLAMA_ARG_*`).
- Contexto nativo **262144 tokens** (256k). Extensible a 1M con YaRN.
- Fits: `22.4GB snug 24GB, comfy 32GB` — con 262k necesitas 80GB para holgado.

## Qué hace cada archivo

| Archivo | Qué es | Para qué sirve |
|---|---|---|
| `Dockerfile` | `FROM ghcr.io/ggml-org/llama.cpp:server-cuda` + `src/` | Build de Runpod (no hay pull directo, se buildea desde GitHub) |
| `src/start.sh` | Arranca `llama-server` en `3098` y luego `handler.py` | Combina `LLAMA_ARG_HF_REPO:LLAMA_HF_QUANT` → `llama-server`, resuelve cache, espera `/health` |
| `src/handler.py` | `runpod.serverless.start` async, `concurrency 8` | Recibe `job["input"]`, delega a `engine.py` (OpenAI client → `localhost:3098`) |
| `src/engine.py` | Adaptador OpenAI | Normaliza `prompt`/`messages`/`openai_route` → `client.chat.completions.create` |
| `src/utils.py` | `JobInput` parser | Extrae `llm_input`, `stream`, `openai_route` |
| `.runpod/hub.json` | Definición del template Runpod Hub | UI de Runpod: Model, Quantization, Context Size, GPU Layers… (ya parcheado para Tiel) |
| `runpod.yaml` | Referencia de config (no se ejecuta solo) | Copiar a Console o usar con `deploy.sh` / `pod/deploy-pod.sh` |
| `.env.example` | Plantilla `LLAMA_ARG_HF_REPO`, `LLAMA_HF_QUANT`, `LLAMA_ARG_CTX_SIZE` | Copia a `.env` y pega en Console → Environment Variables |
| `KEYS.md` | Dónde poner `RUNPOD_API_KEY` / `HF_TOKEN` | `~/.secrets/runpod_api_key` |
| `deploy.sh` | Crea endpoint **Serverless** vía API | `./deploy.sh` (necesita `~/.secrets/runpod_api_key`) |
| `pod/deploy-pod.sh` | Crea **Pod** real vía API (usa `greyul` para Pod, ver abajo) | `pod/deploy-pod.sh` |
| `pod/stop-pod.sh` | Borra el Pod | `pod/stop-pod.sh <podId>` |
| `archive/custom-handler/` | Build custom antiguo | Backup por si `eniewold` falla |
| `.gitignore` | Qué no subir | `.env`, `*.gguf` |

## Deploy Serverless (eniewold, recomendado si < 10h/día)

Pay-per-second, `$0` idle con `workers_min=0`. Cold start descarga 22.4GB a volumen (usa cache si `LLAMA_CACHED_MODEL`).

```bash
# 1. API key
mkdir -p ~/.secrets && echo -n "tu-key" > ~/.secrets/runpod_api_key && chmod 600 ~/.secrets/runpod_api_key
export RUNPOD_API_KEY="$(cat ~/.secrets/runpod_api_key)"

# 2. Deploy (lee runpod.yaml, usa imagen cpalau/tiel-runpod:eniewold)
./deploy.sh
# → crea endpoint tiel-coder-q4xl, A100 80GB + fallback, volumen l1lelwqilk

# 3. Test (eniewold acepta 3 formatos)
curl -X POST https://api.runpod.ai/v2/$ENDPOINT_ID/runsync \
 -H "Authorization: Bearer $RUNPOD_API_KEY" -H "Content-Type: application/json" \
 -d '{"input":{"messages":[{"role":"user","content":"Escribe is_prime(n) en python"}],"temperature":0.6,"max_tokens":200}}' --max-time 120

# OpenAI route directo:
curl -X POST https://api.runpod.ai/v2/$ENDPOINT_ID/runsync \
 -H "Authorization: Bearer $RUNPOD_API_KEY" -H "Content-Type: application/json" \
 -d '{"input":{"openai_route":"/v1/chat/completions","openai_input":{"model":"any","messages":[{"role":"user","content":"hola"}],"temperature":0.6,"max_tokens":100}}}'
```

O manual en Console: `Serverless → New Endpoint → Import Git Repository → cpalau/tiel-runpod` → env de `runpod.yaml` sección `serverless`.

**Variables eniewold para Tiel:**
```
LLAMA_ARG_HF_REPO=peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF
LLAMA_HF_QUANT=UD-Q4_K_XL
LLAMA_ARG_CTX_SIZE=262144
LLAMA_ARG_N_PARALLEL=1
LLAMA_ARG_N_GPU_LAYERS=999
LLAMA_ARG_N_CPU_MOE=0
LLAMA_ARG_FLASH_ATTN=auto
```

## Deploy Pod real (24/7, sin cold start, con greyul)

Para Pod no usamos `eniewold` (serverless handler) sino `greyul/runpod-llama-cpp-cuda:latest` que expone `8080` directo — más simple para Pod.

```bash
pod/deploy-pod.sh
# → Pod A100-SXM4-80GB EU-RO-1, monta l1lelwqilk en /runpod-volume
# → RUNNING (~2-3 min, primera vez descarga 22.4GB):
curl http://<podId>-8080.proxy.runpod.net/v1/models
curl http://<podId>-8080.proxy.runpod.net/v1/chat/completions -H "Content-Type: application/json" \
 -d '{"model":"tiel-coder","messages":[{"role":"user","content":"hola"}],"temperature":0.6,"max_tokens":100}'

pod/stop-pod.sh <podId>  # para no pagar idle
```

O manual: `Pods → Deploy →` imagen `greyul/runpod-llama-cpp-cuda:latest`, GPU `A100-SXM4-80GB`, Volume `tiel-models`, env de `runpod.yaml` sección `pod`.

## Elegir máquina (Pod)

| GPU Pod | VRAM | Disponib. | $/h Secure | Cuándo |
|---|---|---|---|---|
| `A40` | 48GB | HIGH | $0.44 | Pruebas baratas, snug 262k |
| **`A100-SXM4-80GB`** | **80GB** | **MEDIUM** | **$1.59** | **Recomendado — 262k holgado** |
| `RTX PRO 6000 Blackwell` | 96GB | HIGH | $2.09 | Premium, YaRN 1M |
| `H100 80GB` | 80GB | HIGH | $3.29 | Overkill |

Edita `runpod.yaml → pod.gpuTypeId` y `pod/deploy-pod.sh → GPU_TYPE`.

## Conectar a opencode

`~/.config/opencode/opencode.json` provider `runpod-tiel` ya está creado:

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

`deploy.sh` lo actualiza solo. Luego `export RUNPOD_API_KEY` y en opencode `/models` → `runpod-tiel/Tiel-Coder-35B-A3B-UD-Q4_K_XL` (temp 0.6).

## Coste

- Serverless: A100 $2.72/h activo, RTX PRO 6000 $3.49/h activo, $0 idle. 1h/día A100 ~$82/mes vs Pod 24/7 ~$1160/mes. Break-even ~9h/día.
- Pod: $1.59/h siempre. Para 1M YaRN necesitas 96GB.

## YaRN 1M

En `LLAMA_SERVER_CMD_ARGS` añade `--rope-scaling yarn --rope-freq-base 1000000 --yarn-orig-ctx 262144` y sube `LLAMA_ARG_CTX_SIZE=1048576`. Necesita 80GB+.

## Archive

`archive/custom-handler/` conserva el build anterior. `README.eniewold.md` es el README original de eniewold.
