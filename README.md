# Tiel-Coder-35B-A3B GGUF - Runpod Serverless

Endpoint serverless para `peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF` tier `UD-Q4_K_XL 22.4GB`.

## Modelo
- 35B MoE (3.4B activos), 256 expertos, 2 KV heads -> KV cache pequeño
- Sampling recomendado: `temperature 0.6` para coding agéntico (`1.0` default), `top_p 0.95`, `top_k 20`
- Prompt: llama.cpp aplica plantilla Sharp automáticamente con `--jinja`
- Contexto nativo: **262144 tokens** (256k). Extensible a 1M con YaRN.

## Archivos
- `Dockerfile` - build `llama.cpp` con CUDA 12.4 (multi-stage, optimizado)
- `handler.py` - descarga a `/runpod-volume` (cache), lanza `llama-server :8000`, proxya OpenAI
- `requirements.txt` - `runpod`
- `runpod.yaml` - configuración del endpoint (referencia)
- `.env.example` - variables de entorno con valores óptimos

## Optimizaciones
- **Flash Attention**: reduce VRAM ~10-15%, mejora throughput
- **Split Mode 2**: optimizado para MoE (256 expertos)
- **Cache Quantization q8_0**: ahorra ~30% VRAM vs f16 para KV cache
- **Max Num Seqs 4**: 4 secuencias en paralelo (ajustar si OOM)
- **FlashBoot**: cold start rápido (sub-200ms en endpoints recientes)

## Deploy (GitHub mirror + Forgejo)

1. Crea repo privado en Forgejo y push:
```bash
cd ~/proyectos/runpod/Tiel-Coder-35B-A3B-UD-Q4_K_XL
git init && git add . && git commit -m "feat: Tiel Coder 35B-A3B Q4_K_XL 22.4GB - Runpod serverless"
git remote add origin https://git.tail70a578.ts.net/cristian/Tiel-Coder-35B-A3B-UD-Q4_K_XL.git
git push -u origin main
```

2. Mirror a GitHub (para Runpod):
```bash
git remote add github https://github.com/cpalau/tiel-runpod.git
git push github main
```

3. Runpod Console -> Serverless -> New Endpoint
   - Build from GitHub: `cpalau/tiel-runpod`, branch `main`, Dockerfile Path `Dockerfile`
   - GPU: `A100 80GB` (principal) + fallback `RTX PRO 6000 96GB` + `H100 80GB`
   - Container Disk: `60GB`
   - Network Volume: crea uno 100GB y móntalo en `/runpod-volume`
   - Env vars (ver `.env.example` para completo):
     ```
     MODEL_URL=https://huggingface.co/peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF/resolve/main/Tiel-Coder-35B-A3B-UD-Q4_K_XL.gguf
     MODEL_FILENAME=Tiel-Coder-35B-A3B-UD-Q4_K_XL.gguf
     MODEL_DIR=/runpod-volume
     CONTEXT_LENGTH=262144
     MODEL_NAME=Tiel-Coder-35B-A3B-UD-Q4_K_XL
     FLASH_ATTENTION=1
     SPLIT_MODE=2
     CACHE_QUANTIZATION=q8_0
     MAX_NUM_SEQS=4
     LLAMA_EXTRA_ARGS=--flash-attn --split-mode 2
     ```
   - Workers: Min 0, Max 2, Idle 5s, FlashBoot on, Timeout 600s
   - Deploy -> copia `ENDPOINT_ID`

4. Test:
```bash
export RUNPOD_API_KEY="tu-key"
export ENDPOINT_ID="tu-id"
# OpenAI-compatible
curl -X POST https://api.runpod.ai/v2/$ENDPOINT_ID/openai/v1/chat/completions \
 -H "Authorization: Bearer $RUNPOD_API_KEY" -H "Content-Type: application/json" \
 -d '{"model":"Tiel-Coder-35B-A3B-UD-Q4_K_XL","messages":[{"role":"user","content":"Escribe una función python is_prime(n)"}],"temperature":0.6,"max_tokens":512}' --max-time 120
# Queue nativo
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
Si quieres 1M efectivo, deja `CONTEXT_LENGTH=1048576` y añade `LLAMA_EXTRA_ARGS=--rope-scaling yarn --rope-freq-base 1000000 --yarn-orig-ctx 262144`. Solo usa YaRN si realmente necesitas >262k, empeora un poco prompts cortos. Necesita GPU 80GB+.