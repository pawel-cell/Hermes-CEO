# Hermes CEO → Codex CTO: Implementation Guide

A copy-pasteable playbook. Every step is a real command or a real file.
By the end you have: Hermes orchestrating, Codex coding, a shared protocol,
and a repo skeleton you can fork for any project.

──────────────────────────────────────────────────────────────────────
TL;DR
──────────────────────────────────────────────────────────────────────
- Hermes  = CEO (plans, remembers, delegates, reviews, schedules)
- Codex   = CTO (reads/edits/runs code inside one repo, returns a report)
- Budget  = 1× ChatGPT Plus to start; upgrade to Pro when limits bite
- Glue    = Hermes calls `codex exec` in a sandboxed shell, parses the result

──────────────────────────────────────────────────────────────────────
1. ONE-TIME INSTALL  (run these in order)
──────────────────────────────────────────────────────────────────────

# 1.1 Codex CLI
npm i -g @openai/codex
codex login                       # opens browser → log in to ChatGPT
codex --version                   # confirm >= 0.130

# 1.2 Hermes Agent
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
hermes setup
hermes model                      # pick a provider (OpenAI/Anthropic/etc.)

# 1.3 Sanity check
hermes --version
codex exec --sandbox read-only "echo hello from codex"

If either command fails, fix it before continuing. Don't paper over auth
errors — Codex auth lives in ~/.codex/auth.json, Hermes config in
~/.hermes/config.yaml.

──────────────────────────────────────────────────────────────────────
2. PROJECT SKELETON  (do this once per repo)
──────────────────────────────────────────────────────────────────────

From the root of any repo Hermes+Codex will touch:

    mkdir -p .agents
    touch AGENTS.md CEO_GOAL.md .agents/CTO_HANDOFF.md .agents/last_report.md

Then fill the three files using the templates in section 6. The `.agents/`
folder is the message bus between Hermes and Codex — handoffs go in,
reports come out.

Add to .gitignore:

    .agents/last_report.md        # transient; don't commit
    .agents/*.tmp

Commit AGENTS.md, CEO_GOAL.md, and CTO_HANDOFF.md (the template).

──────────────────────────────────────────────────────────────────────
3. THE DELEGATION LOOP  (the actual mechanism)
──────────────────────────────────────────────────────────────────────

Hermes does this on every cycle:

  Step A. Read CEO_GOAL.md + memory + recent reports.
  Step B. Pick ONE next engineering task.
  Step C. Write a fully scoped handoff to .agents/CTO_HANDOFF.md.
  Step D. Shell out:

      cd /path/to/repo
      codex exec \
        --sandbox workspace-write \
        --skip-git-repo-check=false \
        "$(cat .agents/CTO_HANDOFF.md)" \
        > .agents/last_report.md 2>&1

  Step E. Read .agents/last_report.md.
  Step F. Decide: accept / reject / request revision.
  Step G. Update memory + Kanban + next CTO task.

That's the entire loop. Everything else is templates and guardrails.

Sandbox cheat-sheet:
  read-only          → Codex can look but not touch (use for code review)
  workspace-write    → Codex can edit files in cwd, no network (DEFAULT)
  danger-full-access → Codex can do anything (only in containers/VMs)

──────────────────────────────────────────────────────────────────────
4. PARALLEL CTO EXECUTION  (when one task isn't enough)
──────────────────────────────────────────────────────────────────────

Use git worktrees so two Codex processes never fight over the same files:

    git worktree add ../app-auth   -b codex/auth-rate-limit
    git worktree add ../app-bill   -b codex/billing-cleanup

Then run two background Codex jobs from Hermes — one per worktree.
Hermes background terminal pattern:

    terminal(background=true, notify_on_complete=true,
             workdir="/abs/path/app-auth",
             command="codex exec --sandbox workspace-write \"$(cat .agents/CTO_HANDOFF.md)\" > .agents/last_report.md")

When both finish, Hermes reads each last_report.md, opens a PR per branch,
and updates Kanban.

Rules:
  - Never run two Codex processes in the same working directory.
  - Always give each worktree its own .agents/CTO_HANDOFF.md.
  - Merge order is decided by Hermes, not Codex.

──────────────────────────────────────────────────────────────────────
5. RECURRING / DURABLE WORK  (cron + Kanban)
──────────────────────────────────────────────────────────────────────

For tasks that should run on a schedule (nightly tests, weekly dep
updates, daily security scan), use Hermes cron with workdir set to the
repo. Example cron prompt:

    name:     nightly-test-and-fix
    schedule: 0 3 * * *
    workdir:  /root/app
    prompt:   |
      Read AGENTS.md + CEO_GOAL.md.
      Run the test suite. If anything fails:
        1. Write a CTO_HANDOFF to .agents/CTO_HANDOFF.md describing the
           failures.
        2. Run `codex exec --sandbox workspace-write` against it.
        3. Open a PR with the fix.
        4. Report the result back to the chat.

For long-running multi-step pipelines that should outlive a single turn,
use Hermes Kanban instead of delegate_task — Kanban is durable, cron-safe,
and supports specialist roster workers.

──────────────────────────────────────────────────────────────────────
6. TEMPLATES  (copy these verbatim into your repo)
──────────────────────────────────────────────────────────────────────

────── AGENTS.md ──────
# Agent Instructions

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

────── CEO_GOAL.md ──────
# CEO Goal

Business objective:
  <one sentence — what success looks like for the product>

Current milestone:
  <what we're shipping this week/sprint>

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

────── .agents/CTO_HANDOFF.md ──────
# CTO Handoff

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
  - Diff is < N files / < N lines, OR Codex explains why it's larger.

Return to Hermes (required sections in your final message):
  1. PLAN
  2. CHANGED FILES (path + 1-line reason each)
  3. TESTS RUN (command + pass/fail counts)
  4. FAILING TESTS (if any, with stack traces)
  5. RISKS
  6. NEXT RECOMMENDED TASK

──────────────────────────────────────────────────────────────────────
7. ACCEPTANCE CHECKLIST  (Hermes runs this on every report)
──────────────────────────────────────────────────────────────────────

  [ ] CTO_GOAL was actually satisfied (not partially, not adjacent).
  [ ] Tests were run AND passed (or failures are documented + intentional).
  [ ] No unrelated files changed.
  [ ] No new dependencies without justification.
  [ ] No secrets in the diff.
  [ ] Diff size is proportional to the goal.
  [ ] Risks section is non-empty and honest.
  [ ] Next-task suggestion is concrete.

Reject = write a revised CTO_HANDOFF and re-run Codex. Don't argue with
Codex in dialogue; iterate via the handoff file.

──────────────────────────────────────────────────────────────────────
8. SUBSCRIPTION SIZING
──────────────────────────────────────────────────────────────────────

  Plus  ($20/mo)  → Start here. Good for 1 repo, focused sessions, MVP.
  Pro   ($200/mo) → Upgrade when you hit rate limits or want parallel
                    worktrees running all day.
  API key         → Only for CI, shared automation, or billing that
                    must be independent of a ChatGPT account.

Same ChatGPT account in both Codex (`codex login`) and Hermes
(`hermes model`). Don't split accounts — auth stores are separate but
quota is per-account.

──────────────────────────────────────────────────────────────────────
9. SAFETY DEFAULTS
──────────────────────────────────────────────────────────────────────

  - Default sandbox = workspace-write. Never `--dangerously-bypass-
    approvals-and-sandbox` outside a container or throwaway VM.
  - Always run Codex inside a git repo with a clean working tree —
    that way `git diff` IS the audit log.
  - Keep secrets in environment variables or a vault. Codex must never
    see plaintext keys in CTO_HANDOFF.md.
  - Use branches/worktrees. Never let Codex commit to main directly.
  - Review the diff before merging, even when Codex says tests pass.

──────────────────────────────────────────────────────────────────────
10. THE CORE RULE
──────────────────────────────────────────────────────────────────────

  Hermes decides WHAT should be done.
  Codex decides HOW to implement the scoped engineering task.
  Hermes decides WHETHER the result is accepted.

If any of those three roles blur, stop and re-read CEO_GOAL.md.
