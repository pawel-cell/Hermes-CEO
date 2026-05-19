# AUDIT.md

## Executive Summary

`Hermes-CEO` is a documentation-and-templates repository whose only executable surface is `install.sh` (a bootstrapper) and `scripts/genimg.py` (an OpenRouter image-generation helper). Documentation quality is high and the install script is well-structured, but there are several code-quality issues worth addressing before merging: a `curl | bash` install pattern with no integrity check, weak input/secret handling in `genimg.py`, a few portability/robustness bugs in `install.sh`, and missing CI / linting infrastructure (no `shellcheck`, no Python linter, no tests, no `LICENSE` file despite README declaring MIT).

The repo is small enough that all findings below are tractable in a single follow-up PR.

---

## Findings (ordered by severity)

### 1. `curl | bash` install pattern with no checksum or pinned ref — High
**File:** `README.md` (Quick start section)

The advertised install command is:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/pawel-cell/Hermes-CEO/main/install.sh)
```

This pulls `main` at runtime, so any future compromise or accidental bad commit auto-propagates to every new user. There is no checksum, signature, or pinned tag.

**Recommendation:**
- Publish tagged releases and document `…/raw/v1.0.0/install.sh` instead of `main`.
- Optionally publish a SHA256 alongside the release and instruct users to `sha256sum -c` before piping to `bash`.
- Provide the safer two-step alternative (`curl -O … && less install.sh && bash install.sh`) as the *primary* path, with the one-liner as the convenience option.

### 2. `OPENROUTER_API_KEY` read from `~/.hermes/.env` without permission check — High
**File:** `skill/openrouter-image-generation/scripts/genimg.py` (`load_env_key`)

The script silently reads an API key from `~/.hermes/.env` regardless of file permissions, and emits the raw upstream error body on HTTP failure (`raise SystemExit(f"OpenRouter HTTP {e.code}: {detail}")`). On a shared host the env file may be world-readable, and verbose upstream errors can occasionally leak request metadata.

**Recommendation:**
- Warn (or refuse) if `~/.hermes/.env` mode is group/world readable: `if path.stat().st_mode & 0o077: print("warning: insecure perms", file=sys.stderr)`.
- Redact `Authorization` / key fragments from any error string before raising.
- Document the precedence (`OPENROUTER_API_KEY` env > `~/.hermes/.env`) in `SKILL.md`.

### 3. `install.sh` writes a `.gitignore` that may conflict; uses non-portable bash features — Medium
**File:** `install.sh`

Issues:
- Shebang is `#!/usr/bin/env bash` with `set -euo pipefail` — fine — but the README invokes via `bash <(curl …)`, which on systems where `/bin/sh` is dash and the user runs `sh install.sh` would silently break. Add an explicit bash check: `[ -n "${BASH_VERSION:-}" ] || { echo "Run with bash"; exit 1; }`.
- The `.gitignore` append uses `grep -q "^\.agents/last_report\.md$"` but the file is created later with a leading blank line + comment. Re-running the script idempotently is fine, but if the user already has `.agents/` patterns under a different form, duplicates accumulate. Consider checking by pattern, not exact line.
- `maybe_write` uses `printf "%s" "$content"` for heredoc-like multiline strings — works, but heredocs (`cat > "$path" <<'EOF' … EOF`) are clearer and avoid quoting hazards if the templates ever embed `%`.
- Color escapes are emitted unconditionally to stderr-bound `note`/`warn` — fine, but `[ -t 1 ]` only checks stdout; the helpers all write to stdout, so this is consistent. Document or unify.

**Recommendation:** Add a `shellcheck` pass to CI; address the issues above; add a `--dry-run` flag.

### 4. No `LICENSE` file despite README claiming MIT — Medium
**File:** `README.md` ("## License" → "MIT")

The repo asserts MIT but ships no `LICENSE` file in the listed contents. This is a real legal-clarity issue for a public template repo.

**Recommendation:** Add a top-level `LICENSE` file containing the MIT text with the correct copyright holder and year.

### 5. `genimg.py`: unbounded image count, no size cap, costs not gated — Medium
**File:** `skill/openrouter-image-generation/scripts/genimg.py`

The script will save every image returned (`for i, item in enumerate(images)`), print `# cost: $…` only *after* the spend has happened, and has no `--max-cost` or `--confirm` flag. The default model is `openai/gpt-5.4-image-2` at ~$0.22/call (per `SKILL.md`). A typo in a loop / accidental re-run can rack up real money.

**Recommendation:**
- Add `--max-images N` (default 1) that truncates `images[]`.
- Add `--confirm-cost` for any model in a “premium” list, or read an env-configurable ceiling.
- Validate `--model` against the `MODELS` list and exit with a helpful error otherwise (currently any string is sent through and the API rejects it).

### 6. `genimg.py`: silent skipping of malformed images — Low
**File:** `skill/openrouter-image-generation/scripts/genimg.py`

```python
for i, item in enumerate(images):
    url = ((item or {}).get("image_url") or {}).get("url")
    if not url:
        continue
```

If every entry lacks a URL the script exits 0 with no output, which `goal-prompt-slide-deck.md` callers will misread as success. Print to stderr and exit non-zero when `paths` ends up empty.

### 7. Inconsistent model IDs across docs — Low
**Files:** `skill/n-slide-deck-goal-template/goal-prompt-slide-deck.md`, `skill/openrouter-image-generation/SKILL.md`, `scripts/genimg.py`

The slide-deck template hard-codes `openai/gpt-5.4-image-2` and `google/gemini-3.1-flash-image-preview` as the *only* permitted models, but `genimg.py` lists six and `SKILL.md` lists yet another superset. Names like `gpt-5.4-image-2` and `gpt-5-image` will quickly drift from reality.

**Recommendation:** Make `scripts/genimg.py --list-models` the single source of truth and reference it from both markdown files; or extract `MODELS` to a JSON/YAML file imported by both the script and a docs-generation step.

### 8. README "Subscription sizing" and "Known friction" duplicate the fleet skill — Low
**File:** `README.md`

Large blocks of friction documentation are duplicated between `README.md` and the (referenced but not shown) `hermes-ceo-codex-cto-fleet/SKILL.md`. This will drift. Keep the canonical copy in the skill and link from README.

### 9. Missing repo hygiene — Low
No `CONTRIBUTING.md`, no `CODE_OF_CONDUCT.md`, no CI workflow (`shellcheck`, `ruff`, `markdownlint`), no issue templates, no `requirements.txt`/`pyproject.toml` (the Python script depends only on stdlib, which is good — note this explicitly).

---

## Concrete Recommendations Summary

| # | File | Change |
|---|---|---|
| 1 | `README.md` | Pin install URL to a tag; document checksum verification |
| 2 | `scripts/genimg.py` | Permission check on `~/.hermes/.env`; redact errors |
| 3 | `install.sh` | Add `shellcheck`; bash-version guard; cleaner heredocs |
| 4 | `LICENSE` (new) | Add MIT license text |
| 5 | `scripts/genimg.py` | `--max-images`, model whitelist validation, cost gate |
| 6 | `scripts/genimg.py` | Exit non-zero when no images saved |
| 7 | All `*.md` referencing models | Single source of truth for model IDs |
| 8 | `README.md` | De-duplicate friction docs with fleet skill |
| 9 | `.github/workflows/ci.yml` (new) | `shellcheck install.sh`; `ruff check scripts/`; `markdownlint **/*.md` |

---

## Next Steps Checklist

- [ ] Add `LICENSE` (MIT) at repo root.
- [ ] Add `.github/workflows/ci.yml` running `shellcheck`, `ruff`, and `markdownlint`.
- [ ] Pin the README install one-liner to a tagged release; cut `v0.1.0`.
- [ ] Harden `genimg.py`: model whitelist, `--max-images`, env-file permission warning, redacted errors, non-zero exit on empty output.
- [ ] Add a bash-version guard and `--dry-run` flag to `install.sh`.
- [ ] Extract the model list to a single JSON/YAML file consumed by `genimg.py` and referenced from both `SKILL.md` files.
- [ ] Replace duplicated "Known friction" content in `README.md` with a link to the canonical skill doc.
- [ ] Add a minimal `tests/` smoke test for `genimg.py` (mock `urllib.request.urlopen`) so future refactors stay safe.
- [ ] Add `CONTRIBUTING.md` documenting how to test `install.sh` against a throwaway repo.