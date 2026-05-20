# Repository Audit: Hermes-CEO

## Executive Summary

`Hermes-CEO` is a documentation- and shell-script-heavy "playbook + bootstrapper" repo that wires Hermes Agent (CEO) to OpenAI's Codex CLI (CTO). The codebase is small (one Bash installer, one Python helper, several Markdown skill files), so the audit surface is correspondingly narrow but high-leverage: the project's primary execution path is `bash <(curl ...) install.sh`, which is itself a security-sensitive distribution pattern.

The headline concerns are: (1) a `curl | bash` install flow with no verification, (2) a Python helper that writes user-controlled prompt text into filesystem paths with weak sanitization, (3) operational guidance that normalizes `--dangerously-bypass-approvals-and-sandbox` and `--yolo` flags, and (4) a missing CI/lint baseline for the Shell + Python code that the project ships. None are catastrophic, but several should be fixed before this gets meaningful adoption.

Overall code quality is good for what it is — `install.sh` uses `set -euo pipefail`, is idempotent, and avoids clobbering. The Python helper is small and reasonable. Most weaknesses are around supply-chain hygiene, input validation, and the absence of automated checks.

---

## Findings (Highest Impact First)

### 1. `curl | bash` install flow with no integrity verification — **HIGH (supply chain)**

`README.md` instructs users to run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/pawel-cell/Hermes-CEO/main/install.sh)
```

This pattern executes arbitrary code from `main` with no pinning, no checksum, no signature, and no tag. Any compromise of the GitHub account, a force-push to `main`, or a momentary MITM on a misconfigured network gives an attacker arbitrary code execution as the user — and `install.sh` then runs `npm i -g @openai/codex`, which can require elevated privileges depending on the npm prefix.

Compounding factors:
- `install.sh` also runs `npm i -g @openai/codex` without pinning a version (`install.sh` §2 "Codex CLI").
- No `SECURITY.md`, no signing key advertised, no release tags observed.

**Recommendation:**
- Publish tagged releases and reference a pinned tag in README (e.g. `…/raw/v0.3.0/install.sh`).
- Provide a SHA-256 checksum in the README and a `curl … | sha256sum -c -` two-step example as the preferred path; keep `curl|bash` as the convenience path with a clear warning.
- Consider signing releases (cosign / minisign / gpg) and documenting verification.
- Pin `@openai/codex` to a known-good version range in `install.sh`.

### 2. Operational guidance normalizes dangerous flags — **HIGH (security culture)**

`goal-codex-guide.md` repeatedly recommends spawning Codex with `codex --yolo exec '<prompt>'` and the README's "Safety defaults" only weakly warns against `--dangerously-bypass-approvals-and-sandbox`. Because this repo's whole point is autonomous fleets driven by `/goal`, "walk away and let it run" is presented as the happy path:

> `/goal` lets you spawn a fleet, declare done, and walk away

This is a fine philosophy for sandboxed throwaway VMs but is dangerous guidance for users who will run it in their main dev environment with credentialed `.env.local` files (which README §6 explicitly tells them to populate).

**Recommendation:**
- In `goal-codex-guide.md`, replace bare `codex --yolo exec` examples with `codex exec --sandbox workspace-write` as the default; reserve `--yolo` for an explicit "VM/container only" section with a visual warning block.
- Add a top-of-`README.md` callout about credential blast radius when running autonomously with `.env.local` populated.
- Document a recommended container/VM recipe (e.g. devcontainer, `podman run --rm -v`) as the preferred isolation primitive.

### 3. Python helper has weak input/path hygiene — **MEDIUM**

`skill/openrouter-image-generation/scripts/genimg.py`:

- `default_out_path()` slugifies the prompt and writes into `Path.cwd()`. The slug regex prevents most filesystem issues, but the `--out` path is taken verbatim and `out.parent.mkdir(parents=True, exist_ok=True)` will silently create directory trees anywhere the user has write access — including overwriting an existing file at that exact path with `out.write_bytes(raw)` (no `exist_ok`/overwrite confirmation).
- `load_env_key()` parses `~/.hermes/.env` by hand. The split on `=` and strip of quotes is fine for happy paths but will misread values containing `=` or trailing whitespace, and silently returns `None` on parse problems. A malformed env can also leak partial keys into error messages depending on caller behavior.
- `urllib.request.urlopen` is used with `timeout=300` but no TLS verification customization — fine by default, but worth an explicit comment that the system CA store is being trusted.
- `HTTPError` body is interpolated into a `SystemExit` message; if OpenRouter ever echoes the API key back in an error (unlikely but possible), it lands in shell output and shell history.

**Recommendation:**
- Refuse to overwrite existing files unless `--force` is passed.
- Use `python-dotenv` or a stricter parser; only accept `^[A-Z_][A-Z0-9_]*=…$` lines.
- Redact any header values from `HTTPError` output explicitly.
- Add a short docstring and `--help` examples; consider `argparse`'s `type=Path` for `--out`.

### 4. No automated checks (lint / shellcheck / CI) — **MEDIUM (code quality)**

There is no `.github/workflows/`, no `shellcheck` config, no Python linter config, and no tests visible. For a project whose primary artifact is a Bash installer that thousands of users may pipe into their shell, this is a notable gap.

**Recommendation:**
- Add a GitHub Actions workflow running:
  - `shellcheck install.sh` (and any other `.sh`)
  - `ruff check` + `ruff format --check` on `scripts/`
  - `python -m py_compile` smoke test
  - `markdownlint` on `*.md` (optional)
- Add a `bats` test that runs `install.sh` against a fresh temp git repo and asserts the expected files exist.

### 5. `install.sh` minor robustness issues — **LOW/MEDIUM**

In `install.sh`:

- `${cmd} --version 2>&1 | head -1` runs the command for version display; if `node`/`npm`/`git` is present but broken (e.g. `node` shimmed to a failing version manager), the `set -e` is short-circuited by the pipe and the script proceeds. Consider `command -v "$cmd" >/dev/null && "$cmd" --version >/dev/null 2>&1` as a real health check.
- `npm i -g @openai/codex` may need `sudo` depending on npm prefix; the script does not detect EACCES or guide users to fix prefix. A failed install will exit via `set -e` with no actionable message.
- The script writes templated files containing literal `<placeholder>` strings; a `grep -nE '<[a-z][^>]+>' AGENTS.md CEO_GOAL.md` check at the end (warning only) would help users discover unfilled fields.
- `.gitignore` append uses `grep -q "^\.agents/last_report\.md$"` — fine, but the matching block also appends `.agents/*.tmp` which won't be detected on re-run; a second invocation will duplicate that line. Track each pattern separately.

**Recommendation:** small edits in `install.sh` per above; idempotency tests covered by the CI in finding #4.

### 6. Secrets handling guidance is incomplete — **LOW/MEDIUM**

README §6 instructs users to populate `.env.local` with `OPENROUTER_API_KEY`, `GITHUB_TOKEN`, etc., and the bootstrapper does not:

- Add `.env*` patterns to `.gitignore` (it only adds `.agents/last_report.md` and `.agents/*.tmp`).
- Warn that `CTO_HANDOFF.md` is `git add`-able and might inadvertently capture pasted secrets.

**Recommendation:**
- Append `.env`, `.env.local`, `.env.*.local` to the generated `.gitignore` block in `install.sh`.
- Add a pre-commit hook recipe (e.g. `gitleaks`) to the README's "Safety defaults" section.

### 7. Model allowlist drift between docs — **LOW**

`skill/n-slide-deck-goal-template/goal-prompt-slide-deck.md` mandates that `[IMAGE_MODEL]` MUST be `google/gemini-3.1-flash-image-preview` or `openai/gpt-5.4-image-2`, but `skill/openrouter-image-generation/SKILL.md` lists six models and defaults to `openai/gpt-5.4-image-2`. The two files will drift; one source of truth (e.g. a JSON list referenced by both, or the `MODELS` constant in `genimg.py`) would prevent rot.

**Recommendation:** Have `genimg.py --list-models` be the canonical source and reference it from both Markdown files. Add a CI check that greps both Markdowns against `MODELS`.

### 8. Missing repo-hygiene files — **LOW**

No `LICENSE` file in the file list (README claims MIT but a `LICENSE` file is the artifact that matters legally), no `SECURITY.md`, no `CONTRIBUTING.md`, no `CODE_OF_CONDUCT.md`. For a public template repo, the LICENSE file is the important one.

**Recommendation:** Add `LICENSE` (MIT, since README says so), `SECURITY.md` (how to report), and a brief `CONTRIBUTING.md`.

---

## Concrete Recommendations Summary

| # | File | Change |
|---|---|---|
| 1 | `README.md` | Replace unpinned `curl|bash` example with a tag-pinned + checksum-verified example |
| 1 | `install.sh` | Pin `@openai/codex` version |
| 2 | `goal-codex-guide.md` | Demote `codex --yolo`; promote `--sandbox workspace-write` |
| 3 | `scripts/genimg.py` | `--force` flag for overwrite, stricter env parsing, redact HTTPError bodies |
| 4 | `.github/workflows/ci.yml` | New: shellcheck + ruff + bats smoke test |
| 5 | `install.sh` | Health-check existing tools; detect npm EACCES; verify template placeholders are filled (warn) |
| 6 | `install.sh` | Add `.env*` to generated `.gitignore`; mention gitleaks in README |
| 7 | both skill `*.md` | Reference `genimg.py --list-models` as the model source of truth |
| 8 | repo root | Add `LICENSE`, `SECURITY.md` |

---

## Next Steps Checklist

- [ ] Add `LICENSE` (MIT) and `SECURITY.md` to repo root
- [ ] Cut a `v0.1.0` git tag; update README to install via `…/raw/v0.1.0/install.sh` with a published SHA-256
- [ ] Pin `@openai/codex` in `install.sh` (`npm i -g @openai/codex@<version>`)
- [ ] Add `.github/workflows/ci.yml` running `shellcheck`, `ruff`, `python -m py_compile`, and a `bats` install smoke test
- [ ] Patch `install.sh` to (a) extend `.gitignore` with `.env*` patterns, (b) detect duplicated lines on re-run, (c) warn on unfilled `<placeholder>` markers
- [ ] Patch `scripts/genimg.py` to require `--force` for overwrite and redact API errors
- [ ] Rewrite `goal-codex-guide.md` examples to default to `--sandbox workspace-write`; add a clearly-marked "isolated VM/container only" section for `--yolo`
- [ ] Add a "credential blast radius" callout near the top of `README.md`
- [ ] Centralize the image-model allowlist; reference it from both skill Markdowns
- [ ] (Stretch) Provide a devcontainer / Dockerfile recipe so users can run the fleet pattern in an isolated environment