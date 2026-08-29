# API Keys - Dónde ponerlas

## Runpod API Key
**Para tu máquina local (opencode, scripts, test):**
```bash
mkdir -p ~/.secrets
echo -n "tu-runpod-api-key" > ~/.secrets/runpod_api_key
chmod 600 ~/.secrets/runpod_api_key
export RUNPOD_API_KEY="$(cat ~/.secrets/runpod_api_key)"
```

**Para el endpoint de Runpod (en la consola web):**
No necesitas ponerla en el endpoint. El handler no la usa. Solo la usas tú para llamar al endpoint.

## HuggingFace Token
**Solo si el modelo fuera gated** (Tiel-Coder es MIT, no lo necesitas). Si lo necesitas:
```bash
echo -n "hf_tu-token" > ~/.secrets/huggingface_token
chmod 600 ~/.secrets/huggingface_token
```
Y en el endpoint de Runpod, añade la variable:
```
HF_TOKEN=hf_tu-token
```

## Dónde se usa cada una
- `~/.secrets/runpod_api_key` → opencode.json, create_endpoint.sh, test curl
- `HF_TOKEN` → solo en el endpoint de Runpod (si modelo gated)
- `RUNPOD_API_KEY` → variable de entorno para opencode y scripts

## Seguridad
- **Nunca** pegues las keys en el chat
- **Nunca** las guardes en `.env` que subas a git
- Usa `~/.secrets/` con permisos `600`
- En opencode.json usa `{env:RUNPOD_API_KEY}` o `{file:~/.secrets/runpod_api_key}`