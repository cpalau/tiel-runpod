# Archive: Build custom handler (obsoleto)

Este build custom (`Dockerfile` + `handler.py`) compilaba `llama.cpp` con CUDA y hacía de proxy
OpenAI para Runpod Serverless. Fue reemplazado por la imagen pre-hecha `greyul/runpod-llama-cpp-cuda:latest`
que ya trae `llama-server` y gestiona la descarga/cache del GGUF automáticamente.

Se conserva aquí como fallback si `greyul` deja de mantenerse. Para reactivarlo:

```bash
git checkout main -- Dockerfile handler.py requirements.txt start.sh .dockerignore
# o
cp -r archive/custom-handler/* .
```

Ver commit a8a4300 para la última versión conservadora (`-ngl 99 --jinja`).
