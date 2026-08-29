# Tiel-Coder-35B-A3B UD-Q4_K_XL (22.4GB) - Runpod Serverless with llama.cpp
# Build llama.cpp with CUDA, proxy OpenAI-compatible API via handler.py
FROM nvidia/cuda:12.4.1-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y \
    python3 python3-pip git cmake build-essential curl \
    libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Build llama.cpp with CUDA (server binary)
RUN git clone https://github.com/ggml-org/llama.cpp /tmp/llama.cpp \
    && cmake -S /tmp/llama.cpp -B /tmp/llama.cpp/build \
        -DGGML_CUDA=ON \
        -DLLAMA_CURL=ON \
        -DCMAKE_BUILD_TYPE=Release \
    && cmake --build /tmp/llama.cpp/build --config Release -j$(nproc) \
    && cp /tmp/llama.cpp/build/bin/llama-server /usr/local/bin/llama-server \
    && cp /tmp/llama.cpp/build/bin/llama-cli /usr/local/bin/llama-cli 2>/dev/null || true \
    && rm -rf /tmp/llama.cpp

WORKDIR /app

COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

COPY handler.py .
COPY start.sh .
RUN chmod +x start.sh

# Runpod expects handler to be started via CMD
CMD ["python3", "-u", "handler.py"]
