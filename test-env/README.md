# Local Test Environment

A minimal Docker Compose setup for testing LiteLLM locally with [Ollama](https://ollama.com) (CPU-friendly model) and [Open WebUI](https://github.com/open-webui/open-webui).

## Services

| Service | URL | Description |
|---------|-----|-------------|
| Open WebUI | http://localhost:3000 | Chat UI — start here |
| LiteLLM Proxy | http://localhost:4000 | OpenAI-compatible API gateway |
| Ollama | http://localhost:11434 | Local model runner |
| PostgreSQL | localhost:5432 | LiteLLM database |

## Quick Start

From the repository root:

```bash
docker compose -f docker-compose.test.yml up
```

The first run downloads the `llama3.2:1b` model (~1 GB) automatically via the `ollama-pull` service. Once LiteLLM passes its health check, Open WebUI starts and is available at **http://localhost:3000**.

> Auth is disabled (`WEBUI_AUTH=False`) for convenience. Remove that env var or set it to `"True"` to enable logins.

## LiteLLM API Key

The test master key is `sk-test-1234`. Use it if you want to call the proxy directly:

```bash
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-test-1234" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama3.2",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

## Configuration

The LiteLLM config is in `test-env/litellm-config.yaml`. Add or change models there and restart the `litellm` service:

```bash
docker compose -f docker-compose.test.yml restart litellm
```

## Tear Down

```bash
docker compose -f docker-compose.test.yml down
```

To also remove persisted data (Ollama models, DB, WebUI state):

```bash
docker compose -f docker-compose.test.yml down -v
```
