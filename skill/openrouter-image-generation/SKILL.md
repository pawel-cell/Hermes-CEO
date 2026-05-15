---
name: openrouter-image-generation
description: Generate images via OpenRouter using direct chat-completions calls with modalities=["image","text"]; decode base64 data URL responses, save PNGs to disk, and return file paths.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [openrouter, image-generation, images, png, creative]
    related_skills: [comfyui, marketing-graphic-svg]
---

# OpenRouter Image Generation

## Overview

Use OpenRouter's `/api/v1/chat/completions` endpoint with an image-capable model and `modalities: ["image", "text"]`. The response returns the image as a base64 `data:image/png;...` URL inside `message.images[0].image_url.url`. Decode it, save it, and return the absolute path.

Use the helper script at `scripts/genimg.py` for the full flow.

## When to Use

Use this skill when the user asks to generate, create, draw, render, or make an image, picture, artwork, illustration, poster, logo, icon, or when a multi-step task needs a generated visual asset.

Don't use this skill for image editing from an existing input image unless the selected OpenRouter model explicitly supports image inputs for that workflow.

## Setup

1. Get an OpenRouter API key at https://openrouter.ai/keys
2. Set it in the environment or Hermes env file:
   ```bash
   export OPENROUTER_API_KEY=sk-or-v1-...
   # or add it to ~/.hermes/.env
   ```
3. Run the helper:
   ```bash
   python3 scripts/genimg.py "a cyberpunk skyline at sunset"
   ```

## Model Selection

| Model ID | Cost | Speed | Use for |
|---|---:|---:|---|
| `openai/gpt-5.4-image-2` | ~$0.22 | 60-90s | Default — highest quality, polished output, follows complex prompts |
| `openai/gpt-5-image` | ~$0.04 | ~30s | Cheap iteration with high quality |
| `openai/gpt-5-image-mini` | ~$0.04 | ~25s | Fastest OpenAI option, decent for drafts |
| `google/gemini-3-pro-image-preview` | varies | ~30s | Photoreal, alternative aesthetic |
| `google/gemini-3.1-flash-image-preview` | cheaper | fast | Quick Google option |
| `google/gemini-2.5-flash-image` | cheaper | fast | Older but reliable Google |

Default to `openai/gpt-5.4-image-2` unless the user asks for cheaper/faster or a specific aesthetic.

Run:
```bash
python3 scripts/genimg.py --list-models
```

to print the known model IDs.

## HTTP Call

`POST https://openrouter.ai/api/v1/chat/completions`

```json
{
  "model": "openai/gpt-5.4-image-2",
  "messages": [{"role": "user", "content": "<image prompt>"}],
  "modalities": ["image", "text"]
}
```

`modalities: ["image", "text"]` is required. Without it, the model may return text instead of an `images[]` field.

## Response Shape

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

## Examples

```bash
# Default model, timestamped PNG in current directory
python3 scripts/genimg.py "a cyberpunk skyline at sunset"

# Cheaper model + custom output path
python3 scripts/genimg.py "minimalist red fox logo" \
  --model openai/gpt-5-image \
  --out ~/Desktop/fox.png

# List known models
python3 scripts/genimg.py --list-models

```

Stdout for `genimg.py`: one absolute path per generated image.
Stderr: cost/model info, e.g. `# cost: $0.2291 (openai/gpt-5.4-image-2)`.

## Delivery

- CLI mode: print the absolute path in plain text. Do not emit `MEDIA:` tags.
- Messaging platforms: include `MEDIA:/absolute/path.png` so the platform attaches it natively.
- Always verify the file: size > 1000 bytes and `file <path>` says PNG image data.

## Common Pitfalls

1. Stale OpenRouter docs may mention `openai/gpt-image-1`; that model ID may not exist on OpenRouter. Use the IDs above.
2. Don't use a higher-level image generation server tool when the user simply says "make me an image of X". Direct calls are simpler and avoid fake generated file paths.
3. `modalities` is mandatory. Omitting it usually returns text with no `images[]` field.
4. High-quality generation takes 30-120s. Use a 300s timeout.
5. Cost: `gpt-5.4-image-2` is about $0.22/image. Confirm before batching many images.
6. Aspect ratio/size is not reliably honored through chat completions. Put composition in the prompt, then crop/pad with Pillow/ImageMagick if strict dimensions are required.
7. Transparent background has no separate flag; say "transparent background" in the prompt.
8. Text rendering is still imperfect for long text. Keep text under ~5 words.

## Verification Checklist

- [ ] `OPENROUTER_API_KEY` is available in env or `~/.hermes/.env`
- [ ] Script exits 0 and prints an absolute file path
- [ ] `ls -la <path>` shows size > 1000 bytes
- [ ] `file <path>` says PNG image data
- [ ] Optional: use vision to confirm the image matches the requested prompt
