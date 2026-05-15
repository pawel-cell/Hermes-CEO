#!/usr/bin/env bash
# Hermes CEO -> Codex CTO: one-shot project initializer.
#
# What it does (mechanical only):
#   1. Preflight: node, npm, git, hermes, codex
#   2. Install Codex CLI globally if missing
#   3. Verify codex is logged in (won't log in for you — that's a browser flow)
#   4. Scaffold .agents/ + AGENTS.md + CEO_GOAL.md + .agents/CTO_HANDOFF.md
#      in the current repo
#   5. Print the human-only next steps
#
# What it does NOT do:
#   - Run `codex login` (browser flow — you must do this in a real terminal)
#   - Run `hermes setup` / `hermes model` (interactive — you do this)
#   - Buy a ChatGPT subscription
#   - Fill in your business context in CEO_GOAL.md
#
# Usage:
#   cd /path/to/your/repo
#   bash <(curl -fsSL https://raw.githubusercontent.com/pawel-cell/Hermes-CEO/main/install.sh)
# or:
#   git clone https://github.com/pawel-cell/Hermes-CEO.git ~/Hermes-CEO
#   cd /path/to/your/repo
#   bash ~/Hermes-CEO/install.sh

set -euo pipefail

# ── colors ────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  B=$'\e[1m'; D=$'\e[2m'; R=$'\e[0m'
  G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; X=$'\e[31m'
else
  B=""; D=""; R=""; G=""; Y=""; C=""; X=""
fi

ok()   { printf "  %s✓%s %s\n" "$G" "$R" "$1"; }
warn() { printf "  %s!%s %s\n" "$Y" "$R" "$1"; }
err()  { printf "  %s✗%s %s\n" "$X" "$R" "$1"; }
hdr()  { printf "\n%s%s%s\n" "$B" "$1" "$R"; }
note() { printf "    %s%s%s\n" "$D" "$1" "$R"; }

# ── 0. Sanity: in a git repo? ────────────────────────────────────────
hdr "0. Repo check"
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  err "Not inside a git repo. cd into your project first."
  note "Codex refuses to run in workspace-write sandbox outside a repo."
  exit 1
fi
REPO_ROOT="$(git rev-parse --show-toplevel)"
ok "Repo: $REPO_ROOT"

# ── 1. Preflight ─────────────────────────────────────────────────────
hdr "1. Preflight"
MISSING=()
for cmd in node npm git; do
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$cmd $(${cmd} --version 2>&1 | head -1)"
  else
    err "$cmd missing"
    MISSING+=("$cmd")
  fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
  err "Install missing prerequisites first: ${MISSING[*]}"
  note "Recommended: install Node via nvm (https://github.com/nvm-sh/nvm)"
  exit 1
fi

if command -v hermes >/dev/null 2>&1; then
  ok "hermes $(hermes --version 2>&1 | head -1)"
else
  warn "hermes not on PATH"
  note "Install Hermes Agent first:"
  note "  curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash"
  note "  hermes setup && hermes model"
  note "Continuing — Codex still works without Hermes, but you'll be missing the CEO half."
fi

# ── 2. Codex CLI ─────────────────────────────────────────────────────
hdr "2. Codex CLI"
if command -v codex >/dev/null 2>&1; then
  CODEX_VER="$(codex --version 2>&1 | head -1)"
  ok "codex installed: $CODEX_VER"
else
  warn "codex not found — installing via npm"
  npm i -g @openai/codex
  ok "codex installed: $(codex --version 2>&1 | head -1)"
fi

# Auth check — we don't drive the login, just detect.
if [ -f "$HOME/.codex/auth.json" ]; then
  ok "codex auth file present at ~/.codex/auth.json"
else
  warn "no codex auth detected"
  note "After this script finishes, run:  codex login"
  note "(opens a browser — must be done in a real terminal, not via SSH-only sessions)"
fi

# ── 3. Scaffold project files ────────────────────────────────────────
hdr "3. Scaffolding project files in $REPO_ROOT"
cd "$REPO_ROOT"
mkdir -p .agents

# Don't clobber existing files — write only if absent.
maybe_write() {
  local path="$1"; local content="$2"
  if [ -e "$path" ]; then
    warn "exists, skipping: $path"
  else
    printf "%s" "$content" > "$path"
    ok "wrote: $path"
  fi
}

maybe_write "AGENTS.md" '# Agent Instructions

## Stack
- Language:   <e.g. TypeScript / Python>
- Framework:  <e.g. Next.js / FastAPI>
- Tests:      <e.g. vitest / pytest>
- Lint:       <e.g. eslint / ruff>

## Commands
- Install:    <npm ci  |  uv sync>
- Test:       <npm test  |  pytest -q>
- Lint:       <npm run lint  |  ruff check .>
- Typecheck:  <npm run typecheck  |  mypy .>

## Coding rules
- Minimal diff. No drive-by refactors.
- Preserve public APIs unless the handoff says otherwise.
- Add or update tests for every behavior change.
- Never commit secrets. Use env vars.
- Prefer existing utilities over new dependencies.

## Definition of Done
- Tests pass.
- Lint + typecheck clean (or explicitly waived in the report).
- Report lists: changed files, tests run, risks, next suggested task.
'

maybe_write "CEO_GOAL.md" '# CEO Goal

Business objective:
  <one sentence — what success looks like for the product>

Current milestone:
  <what we are shipping this week/sprint>

Constraints:
  - Budget:     <money / tokens / time>
  - Timeline:   <deadline>
  - Technical:  <stack constraints, perf budgets>
  - Compliance: <security, legal, data residency>

Decision rules:
  - Hermes owns prioritization and scope.
  - Codex owns implementation inside a single scoped handoff.
  - Hermes accepts or rejects every Codex report.
  - Scope changes require an explicit Hermes update to CEO_GOAL.md.
'

maybe_write ".agents/CTO_HANDOFF.md" '# CTO Handoff

CTO_GOAL:
  <one sentence, imperative — "Add rate limiting to /auth/reset">

Repo:           <abs path>
Branch:         <branch name>
Worktree:       <abs path if applicable>

Context:
  - <relevant files / modules>
  - <existing patterns to follow>
  - <gotchas Codex would not discover on its own>

Constraints:
  - Minimal diff.
  - Do not change public APIs.
  - No new dependencies without justification in the report.
  - Network access: forbidden.

Files likely involved:
  - <paths>

Commands to run before reporting:
  - <test command>
  - <lint command>

Done when:
  - Tests pass.
  - Diff is < N files / < N lines, OR Codex explains why it is larger.

Return to Hermes (required sections in your final message):
  1. PLAN
  2. CHANGED FILES (path + 1-line reason each)
  3. TESTS RUN (command + pass/fail counts)
  4. FAILING TESTS (if any, with stack traces)
  5. RISKS
  6. NEXT RECOMMENDED TASK
'

# .gitignore: keep transient last_report out of git.
if [ -f .gitignore ]; then
  if ! grep -q "^\.agents/last_report\.md$" .gitignore 2>/dev/null; then
    {
      echo ""
      echo "# Hermes CEO -> Codex CTO transient files"
      echo ".agents/last_report.md"
      echo ".agents/*.tmp"
    } >> .gitignore
    ok "appended .agents transient patterns to .gitignore"
  else
    ok ".gitignore already covers .agents transients"
  fi
else
  cat > .gitignore <<'EOF'
# Hermes CEO -> Codex CTO transient files
.agents/last_report.md
.agents/*.tmp
EOF
  ok "created .gitignore"
fi

# ── 4. Human-only next steps ─────────────────────────────────────────
hdr "4. Done — human-only next steps"
cat <<EOF
  1. ${C}codex login${R}
     (browser flow; must be a real terminal session)

  2. Open ${C}CEO_GOAL.md${R} and fill in your business objective + milestone.

  3. Open ${C}AGENTS.md${R} and replace every <placeholder> with your stack/commands.

  4. In Hermes, say:
        ${C}"Load the hermes-ceo-codex-cto-fleet skill and run a task in $REPO_ROOT"${R}
     (After installing the skills — see README.md → "Install the Hermes skills")

  5. For your first task, edit ${C}.agents/CTO_HANDOFF.md${R} with a real CTO_GOAL,
     then either ask Hermes to run it, or test manually:
        ${C}codex exec --sandbox workspace-write "\$(cat .agents/CTO_HANDOFF.md)" < /dev/null${R}

Read GUIDEBOOK.md (https://github.com/pawel-cell/Hermes-CEO/blob/main/GUIDEBOOK.md)
for the full protocol.
EOF

# ── 5. Known friction (read this before you launch codex) ────────────
printf "\n%s%s%s\n" "$B" "════ KNOWN FRICTION — read before launching codex ════" "$R"
cat <<EOF
${Y}ONE CODEX AT A TIME, EVER.${R}
  Codex uses ChatGPT OAuth. Refresh tokens are single-use. If two
  codex processes refresh in parallel, both get logged out with
  ${X}refresh_token_reused${R} and you'll need to ${C}codex logout && codex login${R}
  to recover. Before launching ANY codex run (interactive or exec):

      ${C}pkill codex 2>/dev/null; sleep 1${R}
      ${C}ps -ef | grep -v grep | grep codex${R}    # must print nothing

  This includes leftover ${C}codex --yolo${R} TUI sessions in other tabs,
  cron-spawned codex jobs, and parallel-worktree codex processes on
  the same machine. Worktrees let you parallelize ${B}files${R}, not auth.

${Y}RATE LIMITS ARE PLAN-CAPACITY, NOT PROMPT-LENGTH.${R}
  ChatGPT Plus has a finite per-window token budget. Long "read all
  these files first" prompts burn budget fast. Prefer surgical handoffs
  (CTO_GOAL + 2-3 specific files + Done-when) over context dumps.
  Codex Pro gives ~5× more headroom if you hit the limit often.

${Y}SILENT HANGS HAPPEN.${R}
  If codex exec sits at zero output growth for >5 min AND ${C}ss -tnp${R}
  shows no :443 connection from its pid AND ${C}ps${R} shows CPU time
  =00:00:00, it's dead. Kill it (${C}kill -9${R}) and retry. No graceful
  recovery — codex doesn't surface the network error.

${Y}IF YOUR REPO TASK IS <200 LINES / <4 FILES, DON'T DELEGATE.${R}
  Codex orchestration has overhead (auth, rate limits, sandbox boot,
  model latency). For tiny tasks just edit yourself or have your CEO
  agent do it directly. The fleet skill's "When to abandon delegation"
  section is canon.

Full failure-mode reference:
  https://github.com/pawel-cell/Hermes-CEO/blob/main/GUIDEBOOK.md#known-friction
EOF

