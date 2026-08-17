#!/bin/bash
# Reproduces the local LLM coding-assistant setup: LM Studio + GLM-4.7-Flash
# (hand-tuned for MoE-aware GPU offload) + a routing/penalty proxy + Cline
# and Continue.dev in VS Code.
#
# Prerequisites this script does NOT install:
#   - LM Studio desktop app + `lms` CLI (https://lmstudio.ai)
#   - VS Code with the `code` CLI on PATH
#   - An NVIDIA GPU with the CUDA backend LM Studio downloads for itself
#
# Safe to re-run: writes are idempotent (overwrites configs, restarts
# services). Model downloads are skipped if already present.
set -euo pipefail

echo "== Checking prerequisites =="
command -v lms >/dev/null || { echo "lms CLI not found (install LM Studio first)"; exit 1; }
command -v code >/dev/null || { echo "VS Code 'code' CLI not found"; exit 1; }
command -v systemctl >/dev/null || { echo "systemd not found (this setup is systemd --user based)"; exit 1; }

mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user" "$HOME/.continue"

echo "== Installing VS Code extensions =="
code --install-extension saoudrizwan.claude-dev
code --install-extension continue.continue

echo "== Downloading models (skips if already present) =="
lms get "zai-org/glm-4.7-flash" --gguf -y || true
lms get "text-embedding-nomic-embed-text-v1.5" --gguf -y || true

# Locate the GGUF file and the llama.cpp CUDA backend LM Studio downloaded
# for itself -- versioned directory names change with LM Studio updates, so
# resolve them instead of hardcoding.
GLM_GGUF=$(find "$HOME/.lmstudio/models" -iname "GLM-4.7-Flash-Q4_K_M.gguf" | head -1)
LLAMA_SERVER=$(find "$HOME/.lmstudio/extensions/backends" -maxdepth 1 -iname "llama.cpp-linux-x86_64-nvidia-cuda12-*" -type d | head -1)/llama-server
CUDA_VENDOR_DIR=$(find "$HOME/.lmstudio/extensions/backends/vendor" -maxdepth 1 -iname "linux-llama-cuda12-vendor-*" -type d | head -1)

if [ -z "$GLM_GGUF" ] || [ ! -f "$LLAMA_SERVER" ] || [ -z "$CUDA_VENDOR_DIR" ]; then
    echo "Could not resolve GGUF/llama-server/CUDA vendor paths -- check LM Studio install" >&2
    exit 1
fi
echo "GLM GGUF:      $GLM_GGUF"
echo "llama-server:  $LLAMA_SERVER"
echo "CUDA vendor:   $CUDA_VENDOR_DIR"

echo "== Writing scripts =="

cat > "$HOME/.local/bin/lmstudio-load-models.sh" <<'EOF'
#!/bin/sh
# Wait for the LM Studio server to actually be ready to accept load
# commands (the socket can open slightly before llmster is ready),
# then load the default models used by aider/hindsight.
#
# GLM-4.7-Flash is NOT loaded here -- it runs as its own hand-tuned
# llama-server (glm-llama-server.service, MoE-aware GPU offload) instead of
# through lms load, since `lms load` only supports a naive whole-layer GPU
# split that leaves this MoE model almost entirely CPU-bound. See
# lmstudio-penalty-proxy.py for how requests get routed to it.
export PATH="$HOME/.lmstudio/bin:$PATH"

for i in $(seq 1 30); do
    if lms status 2>/dev/null | grep -q "Server:  *ON"; then
        break
    fi
    sleep 1
done

lms load "text-embedding-nomic-embed-text-v1.5" --identifier "text-embedding-nomic-embed-text-v1.5" --ttl 86400 -y
EOF
chmod +x "$HOME/.local/bin/lmstudio-load-models.sh"

cat > "$HOME/.local/bin/llm-use-coder" <<'EOF'
#!/bin/sh
# Switch to GLM-4.7-Flash for Cline.
#
# GLM runs as its own hand-tuned llama-server (glm-llama-server.service) on
# port 1236, using --n-gpu-layers 999 --n-cpu-moe 29 -- MoE-aware GPU
# offload that `lms load` can't do (it only supports a naive whole-layer
# split, which left this model almost entirely CPU-bound: ~0% GPU
# utilization vs ~30-35% with this config, and ~740 tok/s vs much slower
# prompt processing on a 5K-token prompt).
#
# lmstudio-penalty-proxy.py (port 1234, what Cline/Continue point to) routes
# GLM requests to port 1236 and everything else to LM Studio's normal
# managed server on 1235, and injects a frequency/presence penalty into
# every request (neither Cline nor Continue send one, and without it local
# models are prone to repetition loops on longer agentic tasks).
export PATH="$HOME/.lmstudio/bin:$PATH"
lms unload --all
lms load "text-embedding-nomic-embed-text-v1.5" --identifier "text-embedding-nomic-embed-text-v1.5" --ttl 86400 -y
systemctl --user start glm-llama-server.service
EOF
chmod +x "$HOME/.local/bin/llm-use-coder"

cat > "$HOME/.local/bin/lmstudio-penalty-proxy.py" <<'EOF'
#!/usr/bin/env python3
"""
Transparent reverse proxy in front of LM Studio.

Two jobs:

1. Neither Cline nor Continue send a repeat/frequency/presence penalty in
   their requests, and LM Studio exposes no way to set a server-side default
   for one (no CLI flag, no config file, no persisted per-model load
   setting). Without it, local models are prone to falling into repetition
   loops on longer agentic tasks (confirmed empirically: a test prompt
   looped indefinitely without a penalty, vs. terminating cleanly with
   frequency/presence penalty 0.3). Injected into every /v1/chat/completions
   request that doesn't already set one.

2. GLM-4.7-Flash is a mixture-of-experts model. LM Studio's own GPU-offload
   picks a naive whole-layer split (N full layers on GPU, rest on CPU) with
   no way to control it via `lms load`, leaving it almost entirely
   CPU-bound. A hand-launched llama-server on port 1236 uses
   --n-gpu-layers 999 --n-cpu-moe 29, keeping all attention/dense compute on
   GPU and only offloading 29 of 46 MoE expert blocks to CPU -- confirmed to
   raise GPU utilization from ~0% to ~30-35% and prompt-processing throughput
   to ~740 tok/s on a 5K-token prompt. Requests naming the GLM model route
   there; everything else (embeddings, any other model) goes to LM Studio's
   normal managed server on port 1235.

Listens on 1234 (what Cline/Continue are already configured to hit).
"""
import http.server
import json
import urllib.request
import urllib.error

LISTEN_PORT = 1234
LMSTUDIO_UPSTREAM = "http://127.0.0.1:1235"
GLM_UPSTREAM = "http://127.0.0.1:1236"
GLM_MODEL_NAMES = {"zai-org/glm-4.7-flash", "glm-4.7-flash", "glm"}
DEFAULT_FREQUENCY_PENALTY = 0.3
DEFAULT_PRESENCE_PENALTY = 0.3


class ProxyHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _pick_upstream(self, payload):
        model = (payload or {}).get("model", "")
        if model in GLM_MODEL_NAMES:
            return GLM_UPSTREAM
        return LMSTUDIO_UPSTREAM

    def _proxy(self, method):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length else b""

        upstream = LMSTUDIO_UPSTREAM
        if self.path == "/v1/chat/completions" and body:
            try:
                payload = json.loads(body)
                payload.setdefault("frequency_penalty", DEFAULT_FREQUENCY_PENALTY)
                payload.setdefault("presence_penalty", DEFAULT_PRESENCE_PENALTY)
                upstream = self._pick_upstream(payload)
                body = json.dumps(payload).encode()
            except (json.JSONDecodeError, UnicodeDecodeError):
                pass

        headers = {
            k: v for k, v in self.headers.items()
            if k.lower() not in ("host", "content-length")
        }
        headers["Content-Length"] = str(len(body))

        req = urllib.request.Request(
            upstream + self.path, data=body, headers=headers, method=method
        )
        try:
            with urllib.request.urlopen(req) as resp:
                self.send_response(resp.status)
                has_content_length = False
                for k, v in resp.getheaders():
                    if k.lower() in ("transfer-encoding", "connection"):
                        continue
                    if k.lower() == "content-length":
                        has_content_length = True
                    self.send_header(k, v)
                # Streaming responses (SSE) arrive with no Content-Length.
                # Without either Content-Length or chunked framing, an
                # HTTP/1.1 keep-alive client has no way to know where the
                # body ends -- lenient clients tolerate it (treat connection
                # idle as EOF), but strict ones (e.g. Node's undici, what
                # Cline uses) wait for proper framing and eventually give up
                # with a body timeout. Re-chunk explicitly so it's correct
                # for every client.
                if not has_content_length:
                    self.send_header("Transfer-Encoding", "chunked")
                self.end_headers()
                while True:
                    chunk = resp.read(65536)
                    if not chunk:
                        break
                    if not has_content_length:
                        self.wfile.write(b"%x\r\n" % len(chunk))
                        self.wfile.write(chunk)
                        self.wfile.write(b"\r\n")
                    else:
                        self.wfile.write(chunk)
                if not has_content_length:
                    self.wfile.write(b"0\r\n\r\n")
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            resp_body = e.read()
            for k, v in e.headers.items():
                if k.lower() not in ("transfer-encoding", "connection", "content-length"):
                    self.send_header(k, v)
            self.send_header("Content-Length", str(len(resp_body)))
            self.end_headers()
            self.wfile.write(resp_body)

    def do_GET(self):
        if self.path == "/v1/models":
            self._merged_models()
            return
        self._proxy("GET")

    def _merged_models(self):
        merged = []
        try:
            with urllib.request.urlopen(LMSTUDIO_UPSTREAM + "/v1/models", timeout=3) as resp:
                data = json.loads(resp.read())
                merged.extend(data.get("data", []))
        except (urllib.error.URLError, json.JSONDecodeError, TimeoutError):
            pass
        try:
            with urllib.request.urlopen(GLM_UPSTREAM + "/v1/models", timeout=3) as resp:
                data = json.loads(resp.read())
                # llama-server reports its model by raw file path; only keep
                # it if nothing already advertises a clean GLM id.
                if not any(d.get("id") in GLM_MODEL_NAMES for d in merged):
                    merged.append({"id": "zai-org/glm-4.7-flash", "object": "model", "owned_by": "llamacpp"})
        except (urllib.error.URLError, json.JSONDecodeError, TimeoutError):
            pass
        body = json.dumps({"data": merged, "object": "list"}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        self._proxy("POST")

    def do_OPTIONS(self):
        self._proxy("OPTIONS")

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    server = http.server.ThreadingHTTPServer(("127.0.0.1", LISTEN_PORT), ProxyHandler)
    print(f"Proxy listening on {LISTEN_PORT}, LM Studio -> {LMSTUDIO_UPSTREAM}, GLM -> {GLM_UPSTREAM}")
    server.serve_forever()
EOF
chmod +x "$HOME/.local/bin/lmstudio-penalty-proxy.py"

echo "== Writing systemd user services =="

cat > "$HOME/.config/systemd/user/lmstudio-server.service" <<EOF
[Unit]
Description=LM Studio local inference server (llmster)
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$HOME/.lmstudio/bin/lms server start -p 1235
ExecStop=$HOME/.lmstudio/bin/lms server stop

[Install]
WantedBy=default.target
EOF

cat > "$HOME/.config/systemd/user/lmstudio-models.service" <<EOF
[Unit]
Description=Preload default LM Studio models (coder + embeddings) for aider/hindsight
After=lmstudio-server.service
Requires=lmstudio-server.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$HOME/.local/bin/lmstudio-load-models.sh

[Install]
WantedBy=default.target
EOF

cat > "$HOME/.config/systemd/user/glm-llama-server.service" <<EOF
[Unit]
Description=Hand-tuned llama-server for GLM-4.7-Flash (MoE-aware GPU offload)
After=network.target

[Service]
Type=simple
Environment=LD_LIBRARY_PATH=$CUDA_VENDOR_DIR
ExecStart=$LLAMA_SERVER \\
  --model $GLM_GGUF \\
  --host 127.0.0.1 --port 1236 \\
  --ctx-size 49152 \\
  --n-gpu-layers 999 \\
  --n-cpu-moe 29 \\
  --flash-attn auto \\
  --jinja \\
  --threads 20 \\
  --parallel 1
Restart=on-failure

[Install]
WantedBy=default.target
EOF

cat > "$HOME/.config/systemd/user/lmstudio-penalty-proxy.service" <<EOF
[Unit]
Description=Penalty-injection + GLM-routing proxy in front of LM Studio (1234 -> 1235/1236)
After=lmstudio-server.service glm-llama-server.service
Requires=lmstudio-server.service glm-llama-server.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 $HOME/.local/bin/lmstudio-penalty-proxy.py
Restart=on-failure

[Install]
WantedBy=default.target
EOF

echo "== Writing Continue.dev config =="

cat > "$HOME/.continue/config.yaml" <<'EOF'
name: Main Config
version: 1.0.0
schema: v1
models:
  - name: GLM-4.7-Flash (LM Studio)
    provider: lmstudio
    model: zai-org/glm-4.7-flash
    apiBase: http://127.0.0.1:1234/v1
    contextLength: 49152
    roles:
      - chat
      - edit
      - apply
    defaultCompletionOptions:
      frequencyPenalty: 0.3
      presencePenalty: 0.3
  - name: Nomic Embed (LM Studio)
    provider: lmstudio
    model: text-embedding-nomic-embed-text-v1.5
    apiBase: http://127.0.0.1:1234/v1
    roles:
      - embed

context:
  - provider: codebase
  - provider: file
  - provider: folder
  - provider: diff
  - provider: terminal
  - provider: problems
EOF

cat > "$HOME/.continue/.continuerc.json" <<'EOF'
{
  "disableIndexing": false
}
EOF

echo "== Enabling and starting services =="
systemctl --user daemon-reload
systemctl --user enable --now lmstudio-server.service
systemctl --user enable --now glm-llama-server.service
systemctl --user enable --now lmstudio-penalty-proxy.service
systemctl --user enable --now lmstudio-models.service

echo "== Done =="
echo "In Cline / Continue.dev, point the LM Studio provider at http://127.0.0.1:1234/v1"
echo "and select model 'zai-org/glm-4.7-flash'."
echo "Check status with: systemctl --user status glm-llama-server lmstudio-penalty-proxy lmstudio-server"
