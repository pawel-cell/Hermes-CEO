---
name: openrouter-image-generation
description: Generate images via OpenRouter using direct chat-completions calls (gpt-5.4-image-2, gpt-5-image, gemini-3-pro-image, etc.) — POST to /chat/completions with modalities=["image","text"], decode the base64 data URL, save to disk, return the file path.
when_to_use: User asks to generate, create, draw, render, or make an image / picture / artwork / illustration / poster / logo / icon — or when a multi-step task needs a generated visual asset.
---

# OpenRouter Image Generation

Use OpenRouter's `/api/v1/chat/completions` endpoint with an image-capable model and `modalities: ["image","text"]`. The response returns the image as a base64 `data:image/png;...` URL inside `message.images[0].image_url.url`. Decode it, save it, return the absolute path.

## Setup

1. Get an OpenRouter API key at https://openrouter.ai/keys
2. Set it in the environment:
   ```bash
   export OPENROUTER_API_KEY=sk-or-v1-...
   ```
3. The helper script at `scripts/genimg.py` handles the rest.

## When to use which model

| Model ID | Cost (1024x1024) | Speed | Use for |
|---|---|---|---|
| `openai/gpt-5.4-image-2` | ~$0.22 | 60-90s | Default — highest quality, polished output, follows complex prompts |
| `openai/gpt-5-image` | ~$0.04 | ~30s | Cheap iteration with high quality |
| `openai/gpt-5-image-mini` | ~$0.04 | ~25s | Fastest OpenAI option, decent for drafts |
| `google/gemini-3-pro-image-preview` | varies | ~30s | Photo-real, alternative aesthetic |
| `google/gemini-3.1-flash-image-preview` | cheaper | fast | Quick Google option |
| `google/gemini-2.5-flash-image` | cheaper | fast | Older but reliable Google |

Default to `openai/gpt-5.4-image-2` unless the user asks for cheaper / faster or a specific aesthetic.

Run `python3 scripts/genimg.py --list-models` to see the current list.

## The HTTP call (under the hood)

`POST https://openrouter.ai/api/v1/chat/completions`

```json
{
  "model": "openai/gpt-5.4-image-2",
  "messages": [{"role": "user", "content": "<image prompt>"}],
  "modalities": ["image", "text"]
}
```

`modalities: ["image","text"]` is **REQUIRED** — without it the model returns a text description instead of an image.

## Response shape

```json
{
  "choices": [{
    "message": {
      "role": "assistant",
      "content": null,
      "images": [
        {"type": "image_url", "image_url": {"url": "data:image/png;base64,iVBOR..."}}
      ]
    },
    "finish_reason": "stop"
  }],
  "usage": {
    "cost_details": {"upstream_inference_cost": 0.22}
  }
}
```

Multiple images are possible — iterate over `message.images[]`.

## Reference script

`scripts/genimg.py` does the whole flow. Examples:

```bash
# Default (gpt-5.4-image-2, ./genimg.png)
python3 scripts/genimg.py "a cyberpunk skyline at sunset"

# Cheaper model + custom output path
python3 scripts/genimg.py "minimalist red fox logo" \
  --model openai/gpt-5-image \
  --out ~/Desktop/fox.png

# List known models
python3 scripts/genimg.py --list-models
```

Stdout: one absolute path per generated image.
Stderr: e.g. `# cost: $0.2291 (openai/gpt-5.4-image-2)`.

## Delivery to user

- **CLI mode**: print the absolute path in plain text. Do NOT emit `MEDIA:` tags — those only render on messaging platforms (Telegram/Discord/Slack), on CLI they show as literal text.
- **Messaging platforms**: include `MEDIA:/absolute/path.png` in the message body — the platform attaches it natively.
- **Always** verify the file: check size > 1000 bytes and run `file <path>` to confirm "PNG image data".

## Pitfalls

- **Stale OpenRouter docs**: the public docs reference `openai/gpt-image-1` as the server-tool default. That ID does NOT exist on OpenRouter and calls fail with "invalid model ID". Use the IDs in the table above.
- **Don't use the `openrouter:image_generation` server tool** unless you specifically need an LLM to autonomously decide *whether* to generate. For "make me an image of X" workflows, direct calls are simpler, deterministic, cheaper, and avoid the orchestrator hallucinating fake `/mnt/data/0.png` paths in its content.
- **`modalities` is mandatory** — omitting it returns a text description with no `images[]` field.
- **Timeouts**: high-quality generation takes 30-120s. Default HTTP timeouts (often 60s) are too short. The helper script uses 300s by default.
- **Cost ceiling**: gpt-5.4-image-2 is ~$0.22/image. Confirm with the user before batching many high-quality images. Use gpt-5-image / mini for drafts.
- **Aspect ratio / size**: direct chat-completions does NOT reliably honor a `size` parameter — most models return 1024x1024 regardless. Workarounds:
  - Mention dimensions inside the prompt itself ("ultra-wide 16:9 banner composition…") — sometimes works
  - Post-process with Pillow / ImageMagick to crop or pad
  - Use the dedicated OpenAI Images API directly (bypass OpenRouter) for strict `size` control
- **Transparent / background**: there's no separate `background: transparent` flag — say "transparent background" or "isolated on white" in the prompt.
- **Text rendering**: modern models (gpt-5.4 / gemini-3-pro) render short headlines reliably. Avoid long body text — it still corrupts under ~5 words.

## Verification

After generating, ALWAYS:
1. `ls -la <path>` — confirm non-zero size
2. `file <path>` — should say "PNG image data" with dimensions
3. Optional: call a vision model to confirm content matches the prompt — useful on first runs, skip during fast iteration.
