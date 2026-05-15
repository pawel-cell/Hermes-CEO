#!/usr/bin/env python3
import argparse
import base64
import json
import mimetypes
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

MODELS = [
    "openai/gpt-5.4-image-2",
    "openai/gpt-5-image",
    "openai/gpt-5-image-mini",
    "google/gemini-3-pro-image-preview",
    "google/gemini-3.1-flash-image-preview",
    "google/gemini-2.5-flash-image",
]
DEFAULT_MODEL = "openai/gpt-5.4-image-2"


def load_env_key():
    key = os.environ.get("OPENROUTER_API_KEY")
    if key:
        return key.strip()
    env_path = Path.home() / ".hermes" / ".env"
    if env_path.exists():
        for line in env_path.read_text(errors="ignore").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            if k.strip() == "OPENROUTER_API_KEY":
                return v.strip().strip('"').strip("'")
    return None


def decode_data_url(data_url):
    m = re.match(r"^data:([^;,]+)?(;base64)?,(.*)$", data_url, re.S)
    if not m:
        raise ValueError("image URL was not a data URL")
    mime = m.group(1) or "image/png"
    is_b64 = bool(m.group(2))
    payload = m.group(3)
    if not is_b64:
        raise ValueError("image data URL was not base64")
    return mime, base64.b64decode(payload)


def default_out_path(prompt, idx=0, ext="png"):
    slug = re.sub(r"[^a-z0-9]+", "-", prompt.lower()).strip("-")[:48] or "image"
    ts = time.strftime("%Y%m%d-%H%M%S")
    suffix = f"-{idx+1}" if idx else ""
    return str((Path.cwd() / f"genimg-{slug}-{ts}{suffix}.{ext}").resolve())


def call_openrouter(prompt, model, timeout):
    key = load_env_key()
    if not key:
        raise SystemExit("OPENROUTER_API_KEY not set in environment or ~/.hermes/.env")

    body = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "modalities": ["image", "text"],
    }
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/chat/completions",
        data=data,
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "HTTP-Referer": "https://hermes-agent.nousresearch.com",
            "X-Title": "Hermes Agent OpenRouter Image Generation",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")
        raise SystemExit(f"OpenRouter HTTP {e.code}: {detail}")


def main():
    ap = argparse.ArgumentParser(description="Generate images through OpenRouter chat completions")
    ap.add_argument("prompt", nargs="?", help="Image prompt")
    ap.add_argument("--model", default=DEFAULT_MODEL, help="OpenRouter model ID")
    ap.add_argument("--out", help="Output PNG path. If multiple images, suffixes are added.")
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("--list-models", action="store_true")
    args = ap.parse_args()

    if args.list_models:
        print("\n".join(MODELS))
        return 0
    if not args.prompt:
        ap.error("prompt is required unless --list-models is used")

    response = call_openrouter(args.prompt, args.model, args.timeout)
    choice = (response.get("choices") or [{}])[0]
    message = choice.get("message") or {}
    images = message.get("images") or []
    if not images:
        content = message.get("content")
        raise SystemExit(f"No images[] returned. Text content: {content!r}")

    paths = []
    for i, item in enumerate(images):
        url = ((item or {}).get("image_url") or {}).get("url")
        if not url:
            continue
        mime, raw = decode_data_url(url)
        ext = mimetypes.guess_extension(mime) or ".png"
        ext = ext.lstrip(".").replace("jpeg", "jpg")
        if args.out:
            out = Path(args.out).expanduser()
            if len(images) > 1:
                out = out.with_name(f"{out.stem}-{i+1}{out.suffix or '.' + ext}")
            out = out.resolve()
        else:
            out = Path(default_out_path(args.prompt, i, ext))
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(raw)
        paths.append(str(out))

    usage = response.get("usage") or {}
    cost = (usage.get("cost_details") or {}).get("upstream_inference_cost")
    if cost is not None:
        print(f"# cost: ${cost} ({args.model})", file=sys.stderr)
    for p in paths:
        print(p)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
