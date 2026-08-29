# Tiel-Coder-35B-A3B UD-Q4_K_XL 22.4GB — Runpod (Serverless + Pod)

Deploy para `peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF` tier `UD-Q4_K_XL 22.4GB` (4-bit, 35B MoE, 3.4B activos).
Imagen pre-hecha `greyul/runpod-llama-cpp-cuda:latest` — ya trae `llama-server` + CUDA, no hay build custom.

## Modelo

- 35B MoE (256 expertos, 8 activos/token), híbrido SSM/attention, 2 KV heads → cache pequeño.
- Sampling: `temperature 1.0, top_p 0.95, top_k 20` (default). Para coding agéntico `temperature 0.6`.
- Chat template Sharp dentro del GGUF → se aplica solo con `--jinja`.
- Contexto nativo **262144 tokens** (256k). Extensible a 1M con YaRN.
- Fits: `22.4GB snug 24GB, comfy 32GB` — con 262k necesitas 80GB para holgado.

## Qué hace cada archivo

| Archivo | Qué es | Para qué sirve |
|---|---|---|
| `runpod.yaml` | Referencia de configuración (no se ejecuta solo) | Copiar valores a Runpod Console o usar con `deploy.sh` / `pod/deploy-pod.sh` |
| `.env.example` | Plantilla de variables de entorno | Copia a `.env` y pega en Runpod Console → Environment Variables |
| `.env` | Tu copia local (no va a git) | Mismo que arriba, ignorado por `.gitignore` |
| `KEYS.md` | Guía de dónde poner `RUNPOD_API_KEY` / `HF_TOKEN` | `~/.secrets/runpod_api_key` → opencode + scripts |
| `deploy.sh` | Crea/actualiza endpoint **Serverless** vía API | `./deploy.sh` (necesita `~/.secrets/runpod_api_key`) |
| `pod/deploy-pod.sh` | Crea **Pod** real vía API | `pod/deploy-pod.sh` |
| `pod/stop-pod.sh` | Borra el Pod | `pod/stop-pod.sh <podId>` |
| `archive/custom-handler/` | Build custom antiguo (`Dockerfile` + `handler.py`) | Backup por si `greyul` falla — ver `archive/README.md` |
| `.gitignore` | Qué no subir | `.env`, `*.gguf`, `__pycache__` |
| `README.md` | Este fichero | Docs |

## Deploy Serverless (recomendado si uso < 10h/día)

Pay-per-second, `$0` idle con `workers_min=0`. Cold start 22-60s primera vez (descarga 22.4GB a volumen).

```bash
# 1. API key (una vez)
mkdir -p ~/.secrets && echo -n "tu-key" > ~/.secrets/runpod_api_key && chmod 600 ~/.secrets/runpod_api_key
export RUNPOD_API_KEY="$(cat ~/.secrets/runpod_api_key)"

# 2. Deploy (usa runpod.yaml)
./deploy.sh
# → crea endpoint tiel-coder-q4xl, A100 80GB + fallback RTX PRO 6000 96GB + H100, volumen l1lelwqilk

# 3. Test
export ENDPOINT_ID="..." # te lo imprime deploy.sh
curl -X POST https://api.runpod.ai/v2/$ENDPOINT_ID/runsync \
 -H "Authorization: Bearer $RUNPOD_API_KEY" -H "Content-Type: application/json" \
 -d '{"input":{"path":"/v1/chat/completions","payload":{"model":"tiel-coder","messages":[{"role":"user","content":"Escribe is_prime(n) en python"}],"temperature":0.6,"max_tokens":512}}}' --max-time 120
```

O manual en Console: `Serverless → New Endpoint →` pega valores de `runpod.yaml` sección `serverless`.

## Deploy Pod real (24/7, sin cold start)

Paga por hora aunque idle. Sin colas, latencia estable. Mismo volumen `l1lelwqilk` — no re-descarga si ya está cacheado.

```bash
pod/deploy-pod.sh
# → crea Pod en EU-RO-1 con A100-SXM4-80GB, monta l1lelwqilk en /runpod-volume
# → cuando esté RUNNING:
curl http://<pod-id>-8080.proxy.runpod.net/v1/chat/completions \
 -H "Content-Type: application/json" \
 -d '{"model":"tiel-coder","messages":[{"role":"user","content":"hola"}],"temperature":0.6,"max_tokens":100}'

# Parar (evita gasto):
pod/stop-pod.sh <podId>
```

O manual: `Pods → Deploy →` imagen `greyul/runpod-llama-cpp-cuda:latest`, GPU `A100-SXM4-80GB`, Volume `tiel-models`, env de `runpod.yaml` sección `pod`.

## Elegir máquina (Pod)

| GPU Pod | VRAM | Disponib. | $/h Secure | Cuándo |
|---|---|---|---|---|
| `A40` | 48GB | HIGH | $0.44 | Pruebas baratas, snug para 262k |
| **`A100-SXM4-80GB`** | **80GB** | **MEDIUM** | **$1.59** | **Recomendado — 262k holgado** |
| `RTX PRO 6000 Blackwell` | 96GB | HIGH | $2.09 | Premium, YaRN 1M sin tocar nada |
| `H100 80GB` | 80GB | HIGH | $3.29 | Overkill salvo throughput extremo |

Edita `runpod.yaml → pod.gpuTypeId` y `pod/deploy-pod.sh → GPU_TYPE` para cambiar.

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

Para Pod cambia `baseURL` a `http://<pod-id>-8080.proxy.runpod.net/v1`.

Luego `export RUNPOD_API_KEY` y en opencode `/models` → `runpod-tiel/Tiel-Coder-35B-A3B-UD-Q4_K_XL` (usa `temperature 0.6` para coding).

## Coste

- Serverless: A100 $2.72/h activo, RTX PRO 6000 $3.49/h activo, $0 idle. 1h/día A100 ~$82/mes vs Pod 24/7 ~$1160/mes. Break-even ~9h/día.
- Pod: A100-SXM $1.59/h siempre (idle también). $1.59*730 = $1160/mes si 24/7, pero $0 si lo paras.

## YaRN 1M (opcional)

Si necesitas >262k, cambia `LLAMA_ARGS` a:
```
-ngl 99 --jinja --context-size 1048576 --rope-scaling yarn --rope-freq-base 1000000 --yarn-orig-ctx 262144
```
Necesita 80GB+ (A100 80GB mínimo, mejor 96GB).

## Archive

`archive/custom-handler/` conserva el build custom anterior (`Dockerfile` + `handler.py` con `runpod.serverless.start`) por si `greyul` deja de mantenerse. Ver `archive/custom-handler/README.md`.
