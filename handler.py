"""
Runpod Serverless handler for Tiel-Coder-35B-A3B GGUF.
- Downloads GGUF to /runpod-volume on first boot (cached thereafter)
- Starts llama-server (OpenAI-compatible) on 127.0.0.1:8000
- Proxies both Runpod queue format and Runpod's /openai/v1/* to llama-server
"""
import os
import time
import subprocess
import threading
import requests
import runpod

MODEL_URL = os.environ.get(
    "MODEL_URL",
    "https://huggingface.co/peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF/resolve/main/Tiel-Coder-35B-A3B-UD-Q4_K_XL.gguf",
)
MODEL_FILENAME = os.environ.get("MODEL_FILENAME", "Tiel-Coder-35B-A3B-UD-Q4_K_XL.gguf")
MODEL_DIR = os.environ.get("MODEL_DIR", "/runpod-volume")
MODEL_PATH = os.path.join(MODEL_DIR, MODEL_FILENAME)
CONTEXT_LENGTH = os.environ.get("CONTEXT_LENGTH", "262144")
LLAMA_PORT = os.environ.get("LLAMA_SERVER_PORT", "8000")
MODEL_NAME = os.environ.get("MODEL_NAME", "Tiel-Coder-35B-A3B-UD-Q4_K_XL")

LLAMA_URL = f"http://127.0.0.1:{LLAMA_PORT}"
download_lock = threading.Lock()
llama_proc = None


def log(msg: str):
    print(f"[tiel-handler] {msg}", flush=True)


def download_model_if_needed():
    os.makedirs(MODEL_DIR, exist_ok=True)
    if os.path.exists(MODEL_PATH) and os.path.getsize(MODEL_PATH) > 1024 * 1024 * 100:
        log(f"Model already cached: {MODEL_PATH} ({os.path.getsize(MODEL_PATH) / 1e9:.2f} GB)")
        return
    log(f"Downloading model to {MODEL_PATH} ...")
    log(f"URL: {MODEL_URL}")
    # Use curl with resume; fallback to python requests
    try:
        subprocess.run(
            ["curl", "-L", "--fail", "--retry", "3", "--retry-delay", "5",
             "-o", MODEL_PATH + ".tmp", MODEL_URL],
            check=True,
        )
        os.rename(MODEL_PATH + ".tmp", MODEL_PATH)
        log(f"Download complete: {os.path.getsize(MODEL_PATH) / 1e9:.2f} GB")
    except Exception as e:
        log(f"curl failed ({e}), trying python download...")
        hf_token = os.environ.get("HF_TOKEN", "")
        headers = {"Authorization": f"Bearer {hf_token}"} if hf_token else {}
        with requests.get(MODEL_URL, headers=headers, stream=True, timeout=300) as r:
            r.raise_for_status()
            with open(MODEL_PATH + ".tmp", "wb") as f:
                for chunk in r.iter_content(chunk_size=8 * 1024 * 1024):
                    if chunk:
                        f.write(chunk)
        os.rename(MODEL_PATH + ".tmp", MODEL_PATH)
        log(f"Download complete (python): {os.path.getsize(MODEL_PATH) / 1e9:.2f} GB")


def start_llama_server():
    global llama_proc
    cmd = [
        "llama-server",
        "-m", MODEL_PATH,
        "--host", "127.0.0.1",
        "--port", LLAMA_PORT,
        "-c", CONTEXT_LENGTH,
        "--jinja",
        "--metrics",
        "-ngl", "99",
        # sampling defaults from model card: temp 1.0 top_p 0.95 top_k 20, but allow override per request
    ]
    # Allow extra args via env
    extra = os.environ.get("LLAMA_EXTRA_ARGS", "")
    if extra:
        cmd.extend(extra.split())
    log(f"Starting llama-server: {' '.join(cmd)}")
    llama_proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    # Stream logs in background
    def stream():
        for line in llama_proc.stdout:
            print(f"[llama-server] {line}", end="", flush=True)
    threading.Thread(target=stream, daemon=True).start()


def wait_for_llama(timeout=300):
    log(f"Waiting for llama-server at {LLAMA_URL}/health ...")
    start = time.time()
    while time.time() - start < timeout:
        try:
            r = requests.get(f"{LLAMA_URL}/health", timeout=2)
            if r.status_code == 200:
                log("llama-server ready")
                return True
            # llama-server also exposes /v1/models when ready
            r2 = requests.get(f"{LLAMA_URL}/v1/models", timeout=2)
            if r2.status_code == 200:
                log("llama-server ready (via /v1/models)")
                return True
        except Exception:
            pass
        if llama_proc and llama_proc.poll() is not None:
            log(f"llama-server exited with code {llama_proc.returncode}")
            raise RuntimeError("llama-server crashed on startup - check VRAM / MODEL_PATH")
        time.sleep(1)
    raise TimeoutError("llama-server did not become ready in time")


# --- Init at import (runs during worker warmup, not per request) ---
try:
    download_model_if_needed()
    start_llama_server()
    wait_for_llama()
except Exception as e:
    log(f"Init failed: {e}")
    raise

# --- Request handling ---

def proxy_chat_completions(payload: dict):
    """Forward to llama-server /v1/chat/completions"""
    # Ensure model field matches what llama-server expects if not provided
    if "model" not in payload:
        payload["model"] = MODEL_NAME
    # Tiel recommended: temperature 0.6 for agentic coding, 1.0 default
    # Don't override if caller provided
    resp = requests.post(f"{LLAMA_URL}/v1/chat/completions", json=payload, timeout=300)
    resp.raise_for_status()
    return resp.json()


def proxy_completions(payload: dict):
    if "model" not in payload:
        payload["model"] = MODEL_NAME
    resp = requests.post(f"{LLAMA_URL}/v1/completions", json=payload, timeout=300)
    resp.raise_for_status()
    return resp.json()


def handler(event):
    """
    Runpod handler. Supports:
    - {"input": {"messages": [...], "temperature": 0.6, ...}}  -> chat
    - {"input": {"prompt": "..."}} -> completions
    - {"input": {"path": "/v1/chat/completions", "payload": {...}}} (zeeb0tt style)
    - {"input": {"openai": {"messages": [...]}}} (alternate)
    """
    try:
        inp = event.get("input", {}) if isinstance(event, dict) else {}
        # Compat: sometimes Runpod wraps openai path
        if "payload" in inp and "path" in inp:
            path = inp.get("path", "")
            payload = inp.get("payload", {})
            if "chat/completions" in path:
                return proxy_chat_completions(payload)
            if "completions" in path:
                return proxy_completions(payload)
            # fallback
            return proxy_chat_completions(payload)

        # Direct OpenAI shape passed as input
        if "messages" in inp:
            return proxy_chat_completions(inp)
        if "prompt" in inp:
            # Heuristic: if prompt looks like chat, still use chat
            return proxy_completions(inp)
        if "openai" in inp and isinstance(inp["openai"], dict):
            return proxy_chat_completions(inp["openai"])

        # If input is empty, return health
        if not inp:
            return {"status": "ok", "model": MODEL_NAME, "llama": LLAMA_URL}

        # Fallback: treat whole input as chat payload
        return proxy_chat_completions(inp)

    except requests.HTTPError as e:
        body = e.response.text[:2000] if e.response is not None else str(e)
        log(f"Upstream error: {body}")
        return {"error": body, "status_code": getattr(e.response, 'status_code', 500)}
    except Exception as e:
        log(f"Handler error: {e}")
        return {"error": str(e)}


runpod.serverless.start({"handler": handler})
