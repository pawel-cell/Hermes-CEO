---
name: hermes-ceo-codex-cto
description: Use when the user wants to set up or operate the Hermes CEO / Codex CTO pattern — installing the toolchain in a repo, drafting CEO_GOAL.md, writing CTO handoffs, running the codex-exec delegation loop, reviewing reports, or scheduling recurring engineering work. The skill walks the user through human-only steps (codex login, ChatGPT subscription, business context) and executes everything mechanical itself.
version: 1.0.0
author: pawel-cell
license: MIT
metadata:
  hermes:
    tags: [orchestration, codex, delegation, devops, agents]
    related_skills: [codex, github-pr-workflow, demo-mvp-webapp]
---

# Hermes CEO → Codex CTO

## Overview

This skill turns Hermes into the CEO/orchestrator and OpenAI's Codex CLI
into the CTO/executor for any git repo. Hermes owns the goal, memory,
scheduling, and review. Codex owns the actual code-editing inside one
scoped handoff at a time. They talk through two files: `.agents/CTO_HANDOFF.md`
goes in, `.agents/last_report.md` comes out.

Reference repo: https://github.com/pawel-cell/Hermes-CEO

## When to Use

Load this skill when the user says any of:

- "set up Hermes CEO Codex CTO" / "install Hermes-CEO in this repo"
- "delegate this engineering task to Codex" (and Codex is the intended executor)
- "review what Codex just did"
- "schedule a nightly Codex job in this repo"
- "set up parallel Codex worktrees"
- The user pastes the GUIDEBOOK.md from pawel-cell/Hermes-CEO and asks Hermes to follow it

Don't use for:

- Generic "run Codex once" tasks → use the `codex` skill directly
- Non-Codex coding delegation (Claude Code, OpenCode) → use those skills
- Hermes Agent install/config itself → use the `hermes-agent` skill

## The Two-File Message Bus

```
.agents/CTO_HANDOFF.md     ← Hermes writes a scoped task for Codex
.agents/last_report.md     ← Codex writes its structured result back
                             (gitignored — transient)
```

Every delegation is one round-trip through these files. Don't try to
maintain conversation state with Codex across runs; if you need to
iterate, rewrite CTO_HANDOFF.md.

## Setup Flow (first time in a repo)

1. **Confirm git + cwd.** Make sure you're inside a clean-ish git
   working tree. Codex needs this for the workspace-write sandbox.

2. **Run the bootstrap script.** From the repo root:

       bash <(curl -fsSL https://raw.githubusercontent.com/pawel-cell/Hermes-CEO/main/install.sh)

   This script:
   - Verifies node / npm / git / hermes presence
   - Installs `@openai/codex` globally if missing
   - Creates `.agents/`, `AGENTS.md`, `CEO_GOAL.md`, `.agents/CTO_HANDOFF.md`
   - Appends `.agents/last_report.md` to `.gitignore`
   - Does NOT clobber existing files

3. **Hand off the human-only steps.** Tell the user, in plain text:

   - Run `codex login` themselves in a real terminal (browser flow).
     Cannot be automated by Hermes.
   - Fill in `CEO_GOAL.md` with the actual business objective.
   - Fill in `AGENTS.md` placeholders (stack, test/lint/typecheck commands).
   - Confirm they have an active ChatGPT Plus or Pro subscription.

4. **Verify Codex auth.** After they say "done", run:

       codex exec --sandbox read-only "echo ok"

   If it errors with auth, point them back to `codex login`.

## The Delegation Loop (every task)

1. **Read state.** Open `CEO_GOAL.md`, `AGENTS.md`, last
   `.agents/last_report.md` (if any), plus any session memory.

2. **Pick ONE task.** Granularity rule: small enough that the report
   should fit in ~200 lines. If the task feels bigger, split it.

3. **Write the handoff** to `.agents/CTO_HANDOFF.md`. Use the 6-section
   template (CTO_GOAL / Repo+Branch / Context / Constraints / Files /
   Commands / Done-when / Return-format). Be explicit about constraints
   — Codex will follow them literally.

4. **Pre-commit safety.** If repo has uncommitted changes that aren't
   related to the upcoming task, ask the user to commit or stash first.
   This makes `git diff` the audit log.

5. **Execute Codex.** Default invocation:

       cd <REPO_ROOT>
       codex exec \
         --sandbox workspace-write \
         "$(cat .agents/CTO_HANDOFF.md)" \
         > .agents/last_report.md 2>&1

   For longer jobs, use Hermes background terminal with
   `notify_on_complete=true` and `workdir=<REPO_ROOT>` instead of
   blocking the current turn.

6. **Read the report.** Parse the 6 required sections out of
   `.agents/last_report.md`. If any are missing, that's a reject.

7. **Run the acceptance checklist** (see next section).

8. **Record outcome.** Update Hermes memory or Kanban with: task ID,
   files changed, test result, next suggested task. Don't write
   per-task progress to long-term memory — keep it in Kanban or as a
   git note.

## Acceptance Checklist

Run this against every Codex report before accepting. Each unchecked
item is grounds for revision (rewrite CTO_HANDOFF.md, re-run; do not
argue with Codex in dialogue).

- [ ] CTO_GOAL was actually satisfied (not partially, not adjacent)
- [ ] Tests were run AND passed, OR failures are documented + intentional
- [ ] No unrelated files in the diff (`git diff --name-only`)
- [ ] No new dependencies without justification in the report
- [ ] No secrets, tokens, or PII in the diff (`git diff | grep -Ei 'token|secret|password|api[_-]?key'`)
- [ ] Diff size is proportional to the goal
- [ ] Risks section is non-empty and honest
- [ ] Next-task suggestion is concrete

## Parallel Worktrees

When the user asks for parallel work:

```bash
git worktree add ../<repo>-<short-slug> -b codex/<slug>
cp .agents/CTO_HANDOFF.md ../<repo>-<short-slug>/.agents/CTO_HANDOFF.md
# edit the new copy with its own CTO_GOAL
```

Then spawn one Hermes background terminal per worktree. Three hard rules:

1. Never run two `codex exec` processes in the same cwd.
2. Each worktree gets its own `.agents/CTO_HANDOFF.md`.
3. Hermes owns merge order — pick the PR sequence after both finish.

## Recurring Work (cron)

Schedule via Hermes cron with `workdir=<REPO_ROOT>`. The cron prompt
should be self-contained (cron has no chat memory). Example:

```
schedule: 0 3 * * *
workdir:  /root/myapp
prompt: |
  Load the hermes-ceo-codex-cto skill.
  Read AGENTS.md and CEO_GOAL.md.
  Run the test suite. If anything fails:
    1. Write a CTO_HANDOFF describing the failures.
    2. Execute codex exec --sandbox workspace-write against it.
    3. Open a PR with the fix using gh.
    4. Deliver a one-paragraph summary back to chat.
  If tests pass, deliver "all green".
```

For multi-step durable pipelines (e.g. test → fix → review → PR), use
Hermes Kanban with the kanban-orchestrator skill instead of cron.

## Common Pitfalls

1. **Running `codex exec` outside a git repo.** workspace-write sandbox
   refuses. Always `cd` to a git worktree first.

2. **PTY hangs on `codex login`.** Don't try to run `codex login`
   inside Hermes's PTY — the browser flow won't complete. Tell the
   user to run it in their own terminal.

3. **Conversational drift with Codex.** Codex's `exec` mode is
   one-shot. Don't try to follow up with "now also do X" — write a
   new CTO_HANDOFF.md.

4. **Codex changing unrelated files.** Caused by vague CTO_GOAL or
   missing "Constraints: minimal diff, do not refactor unrelated code"
   in the handoff. Reject and tighten the handoff.

5. **Secrets in the handoff.** Don't paste API keys into CTO_HANDOFF.md
   — Codex will see them. Reference env vars by name only.

6. **Two Codex processes in one cwd.** They will race on file writes.
   Always use separate `git worktree` paths for parallel work.

7. **Trusting "tests pass" without checking.** Codex sometimes
   summarizes optimistically. Read the actual test output section of
   the report; if it doesn't show the test runner's pass/fail line,
   reject.

8. **Using `--dangerously-bypass-approvals-and-sandbox` casually.**
   Only inside a container/VM you don't mind nuking. On a real host
   running as root, this is one prompt-injection away from data loss.

9. **Leaving `.agents/last_report.md` committed.** The install.sh
   gitignores it, but if you bootstrap a repo manually, remember.

10. **Forgetting Hermes runtime caveats.** Some Hermes tools
    (`delegate_task`, `memory`, `session_search`, `todo`) are not
    available on the Codex app-server runtime. Stay on the default
    runtime when using this skill — Codex is invoked as a subprocess,
    not the host runtime.

## Verification Checklist (after setup)

- [ ] `.agents/`, `AGENTS.md`, `CEO_GOAL.md` exist in the repo
- [ ] `.gitignore` contains `.agents/last_report.md`
- [ ] `codex --version` works
- [ ] `codex exec --sandbox read-only "echo ok"` succeeds
- [ ] CEO_GOAL.md has actual business content, not placeholders
- [ ] AGENTS.md has actual stack/commands, not placeholders
- [ ] User has confirmed an active ChatGPT subscription

## One-Shot Recipes

### "Set up Hermes-CEO in /root/myapp"
1. `cd /root/myapp`
2. `bash <(curl -fsSL https://raw.githubusercontent.com/pawel-cell/Hermes-CEO/main/install.sh)`
3. Walk user through `codex login` + filling AGENTS.md + CEO_GOAL.md.
4. Run `codex exec --sandbox read-only "echo ok"` to verify auth.

### "Delegate this bug fix to Codex"
1. Confirm cwd is the right repo + working tree is clean.
2. Write CTO_HANDOFF.md with goal + constraints + done-when.
3. `codex exec --sandbox workspace-write "$(cat .agents/CTO_HANDOFF.md)" > .agents/last_report.md 2>&1`
4. Read report → run acceptance checklist → accept or revise.

### "Run two Codex tasks in parallel"
1. `git worktree add ../myapp-a -b codex/task-a`
2. `git worktree add ../myapp-b -b codex/task-b`
3. Write each task's `.agents/CTO_HANDOFF.md` in its own worktree.
4. Spawn two Hermes background terminals (workdir per worktree,
   notify_on_complete=true).
5. After both notify, read each report, accept/reject, decide PR order.

### "Daily nightly fix-or-pass cron"
1. Verify the repo's test command in AGENTS.md.
2. Create a cron job with workdir=<repo>, schedule=`0 3 * * *`, and
   the prompt from the "Recurring Work" section above.
3. Confirm the cron job's enabled_toolsets includes `terminal` and `file`.
