---
name: hermes-ceo-codex-cto-fleet
description: Use when the user wants to operate the Hermes CEO / Codex CTO pattern day-to-day — delegating one or many engineering tasks to Codex, running parallel coding agents across git worktrees, opening or managing a persistent /goal + /subgoal CEO mission, scheduling recurring Codex jobs via cron, reviewing reports against the acceptance checklist, or coordinating a fleet of background coding agents. Assumes the install skill (hermes-ceo-codex-cto-install) has already run successfully in the target repo.
version: 1.0.0
author: pawel-cell
license: MIT
metadata:
  hermes:
    tags: [orchestration, codex, delegation, parallelism, cron, fleet]
    related_skills: [hermes-ceo-codex-cto-install, codex, github-pr-workflow, kanban-orchestrator]
---

# Hermes CEO → Codex CTO: Fleet Operations

## Overview

Day-to-day operations skill for the Hermes CEO / Codex CTO pattern.
Use this for every task AFTER the install skill has finished. Covers:
single delegation, parallel worktrees, scheduled cron, the acceptance
checklist, and fleet coordination patterns.

The pattern in one line: **Hermes writes `.agents/CTO_HANDOFF.md`,
shells out to `codex exec`, reads `.agents/last_report.md`, decides.**

Reference repo: https://github.com/pawel-cell/Hermes-CEO

## When to Use

Load this skill when the user says any of:

- "delegate this fix/feature/refactor to Codex"
- "run Codex on /path/to/repo"
- "review what Codex just did"
- "set up parallel Codex jobs across worktrees"
- "schedule a nightly Codex test-and-fix"
- "what's the status of the coding agents I started?"
- "kill the running Codex job in repo X"
- "open a persistent CEO mission with /goal + /subgoal"
- "add an acceptance criterion to the active goal"
- "show me the current /goal and subgoals"

Don't use for:

- First-time bootstrap → `hermes-ceo-codex-cto-install`
- One-off `codex exec` calls outside the CEO pattern → `codex` skill
- Non-Codex coding agents (Claude Code, OpenCode) → those skills
- Hermes Agent install/config → `hermes-agent` skill

## Preconditions

Before running any task, verify ALL of these. If any fails, route to
the install skill.

- [ ] cwd is inside a git repo: `git rev-parse --show-toplevel`
- [ ] `AGENTS.md` and `CEO_GOAL.md` exist and are NOT placeholder
- [ ] `.agents/CTO_HANDOFF.md` exists
- [ ] `codex --version` works
- [ ] User has confirmed an active ChatGPT subscription

Fast check, all in one shot:

```bash
for f in AGENTS.md CEO_GOAL.md .agents/CTO_HANDOFF.md; do
  [ -f "$f" ] || { echo "MISSING: $f"; exit 1; }
done
grep -q "<placeholder>\|<one sentence\|<e.g\." AGENTS.md CEO_GOAL.md \
  && echo "WARN: placeholders still in AGENTS.md or CEO_GOAL.md"
codex --version
```

## The Two-File Message Bus

```
.agents/CTO_HANDOFF.md     ← Hermes writes a scoped task for Codex
.agents/last_report.md     ← Codex writes its structured result back
                             (gitignored — transient)
```

One round-trip per task. Don't try to maintain conversation state
across runs — if Codex's first attempt is wrong, rewrite the handoff
and re-run.

## Single Task: The Delegation Loop

Seven steps. Do them in order; don't skip 1 or 7.

### 1. Read state

- `CEO_GOAL.md` — what we're shipping
- `AGENTS.md` — how we ship (commands, rules)
- `.agents/last_report.md` — last outcome (if any)
- Hermes memory for project-specific conventions

### 2. Pick ONE task

Granularity rule: small enough that the report fits in ~200 lines. If
it feels bigger, split it. Multi-step work goes to parallel worktrees
or Kanban, not a single bloated handoff.

### 3. Write the handoff

`patch` or `write_file` to `.agents/CTO_HANDOFF.md`. Required structure:

```
CTO_GOAL:    <one imperative sentence>
Repo:        <abs path>
Branch:      <branch name>
Context:     <existing files/patterns/gotchas Codex won't discover>
Constraints: <minimal diff, no public API change, no new deps, etc.>
Files likely involved: <paths>
Commands to run before reporting: <test cmd, lint cmd>
Done when:   <explicit acceptance criteria>
Return to Hermes:
  1. PLAN
  2. CHANGED FILES (path + 1-line reason each)
  3. TESTS RUN (command + pass/fail counts)
  4. FAILING TESTS (if any, with stack traces)
  5. RISKS
  6. NEXT RECOMMENDED TASK
```

Be aggressive about Constraints. "Minimal diff. Do not refactor
adjacent code." is worth a paragraph of explanation later.

### 4. Pre-flight git state

If the working tree has unrelated uncommitted changes, ask the user
to commit or stash first. After Codex runs, `git diff` should be
**only Codex's work**. Otherwise the audit log is poisoned.

```bash
git status --short
```

If output is non-empty AND not from a prior in-progress Codex run,
pause.

### 5. Execute Codex

Default invocation, blocking:

```bash
cd <REPO_ROOT>
codex exec \
  --sandbox workspace-write \
  "$(cat .agents/CTO_HANDOFF.md)" \
  > .agents/last_report.md 2>&1
```

For tasks expected to take >2 minutes, use a Hermes background
terminal so the chat doesn't block:

```
terminal(
  background=true,
  notify_on_complete=true,
  workdir="<REPO_ROOT>",
  command='codex exec --sandbox workspace-write "$(cat .agents/CTO_HANDOFF.md)" > .agents/last_report.md 2>&1'
)
```

Sandbox table:

| Sandbox              | Use when                                   |
|----------------------|--------------------------------------------|
| `read-only`          | Code review, planning, no edits intended    |
| `workspace-write`    | Normal coding (DEFAULT)                     |
| `danger-full-access` | Only inside a container/VM you'd nuke       |

### 6. Read the report

Open `.agents/last_report.md`. Verify all 6 sections are present.
Missing sections = automatic reject (the constraint was clear).

**BEFORE you reject, diagnose.** `codex exec` exiting non-zero with a
malformed report is often infra, not Codex doing a bad job. Check the
LAST 20 lines of `.agents/last_report.md`:

```bash
tail -20 .agents/last_report.md
```

Look for these signatures and route accordingly:

| Signature in last_report.md                          | Cause                              | Fix                                                  |
|------------------------------------------------------|------------------------------------|------------------------------------------------------|
| `You've hit your usage limit. ... try again at HH:MM` | ChatGPT Codex quota exhausted      | Wait, upgrade Plus→Pro, or set `OPENAI_API_KEY`     |
| `refresh token was revoked` / `401 Unauthorized`     | OAuth session dead                 | User runs `codex login` again in a real terminal     |
| `Codex could not find bubblewrap on PATH` (warn only) | Optional sandbox tool missing      | `apt install bubblewrap` (cosmetic — runs continue)  |
| `not in a git repo`                                  | cwd outside a worktree             | cd into the repo, retry                              |
| Empty report / killed mid-run                        | Network drop, timeout, OOM         | Check Hermes terminal logs, retry                    |
| `command not found: codex`                           | npm bin not on PATH                | `npm config get prefix` → add `$PREFIX/bin` to PATH  |

If the report has all 6 sections AND has a real PLAN / CHANGED FILES,
proceed to Step 7. Only the CODE was bad → tighten handoff + re-run.

### 7. Run the acceptance checklist

Each unchecked item is grounds for revision. Reject = rewrite the
handoff and re-run. **Do not argue with Codex in chat-style dialogue
— iterate via the handoff file.**

- [ ] CTO_GOAL was actually satisfied (not partially, not adjacent)
- [ ] Tests were run AND passed, OR failures are documented + intentional
- [ ] No unrelated files in the diff (`git diff --name-only`)
- [ ] No new dependencies without justification in the report
- [ ] No secrets in the diff: `git diff | grep -Ei 'token|secret|password|api[_-]?key'`
- [ ] Diff size is proportional to the goal
- [ ] Risks section is non-empty and honest
- [ ] Next-task suggestion is concrete

On accept: commit (Hermes can draft the message), suggest a PR via the
`github-pr-workflow` skill, and update memory/Kanban with the next
task. On reject: tighten the handoff and re-run.

## Fleet Mode: Parallel Worktrees

When the user wants 2+ Codex tasks running at once. The hard rule:
**one Codex process per cwd, ever.** Use git worktrees.

### Setup

```bash
git worktree add ../<repo>-auth   -b codex/auth-rate-limit
git worktree add ../<repo>-bill   -b codex/billing-cleanup
```

Each worktree gets its own scaffolding:

```bash
for wt in ../<repo>-auth ../<repo>-bill; do
  mkdir -p "$wt/.agents"
  cp .agents/CTO_HANDOFF.md "$wt/.agents/CTO_HANDOFF.md"  # then edit
done
```

### Launch

Spawn one Hermes background terminal per worktree:

```
terminal(
  background=true,
  notify_on_complete=true,
  workdir="<abs path to worktree>",
  command='codex exec --sandbox workspace-write "$(cat .agents/CTO_HANDOFF.md)" > .agents/last_report.md 2>&1'
)
```

Record the returned session IDs. Hermes will get notified as each one
finishes.

### Status & control

| Action                | Tool call                                    |
|-----------------------|----------------------------------------------|
| List running          | `process(action='list')`                     |
| Check progress        | `process(action='poll', session_id=...)`     |
| Wait for one          | `process(action='wait', session_id=...)`     |
| Kill a stuck Codex    | `process(action='kill', session_id=...)`     |

### Merge order

After all worktrees report, Hermes decides PR order. Common heuristic:

1. Smallest diff first (lowest merge risk)
2. Files that don't overlap with other PRs
3. Things blocking the milestone in CEO_GOAL.md

Never let Codex decide merge order. That's a CEO decision.

### Cleanup

```bash
git worktree remove ../<repo>-auth   # after PR merged
git branch -d codex/auth-rate-limit
```

## Persistent Missions: `/goal` + `/subgoal`

For CEO-level missions that span multiple Codex delegations, use
Hermes's persistent goal system instead of one-shot prompts.

`/goal` = the CEO mission. Hermes keeps working across turns and uses a
judge model to decide when the goal is satisfied.

`/subgoal` = acceptance criteria layered onto the active goal. Adds
requirements without resetting. Signature: `/subgoal [text | remove N | clear]`.

### Template: CEO mission with strict CTO contract

Open the mission:

```
/goal Act as CEO. Deliver the next engineering milestone in <repo> by
delegating implementation to Codex CTO, reviewing each result against
the acceptance checklist, and deciding accept/reject.
```

Then layer the contract:

```
/subgoal CTO_HANDOFF must include CTO_GOAL, repo path, constraints, and Done-when.
/subgoal Codex must produce a minimal diff and avoid unrelated refactors.
/subgoal Codex must run the test/lint/typecheck commands from AGENTS.md and report exact pass/fail counts.
/subgoal Each Codex report must contain all 6 required sections (PLAN, CHANGED FILES, TESTS RUN, FAILING TESTS, RISKS, NEXT).
/subgoal Hermes must run the 8-item acceptance checklist before accepting any report.
/subgoal Final mission summary must list: accepted PRs, rejected attempts with reasons, remaining risks, next CTO task.
```

The judge will refuse vague "all done" claims — it requires concrete
evidence (file paths, command output, test counts). That's exactly
what the 6-section report contract produces, so the pieces fit.

### When to add subgoals mid-flight

- A Codex report came back with "tests pass" but no test counts →
  `/subgoal Test reports must include the exact runner output with pass/fail counts.`
- Codex changed unrelated files → `/subgoal Diffs touching files outside the handoff's "Files likely involved" list must be reverted before reporting.`
- A new business constraint came up → `/subgoal No changes to public API surface in src/api/v1/ until milestone X ships.`

### Inspect / clean up

```
/subgoal                # show current goal + numbered subgoals
/subgoal remove 3       # drop the 3rd criterion
/subgoal clear          # keep main /goal, drop all criteria
```

### Pitfalls specific to /subgoal

- **Subgoals are not delegation.** `/subgoal` does NOT spawn Codex.
  It only modifies the acceptance contract for the active `/goal`.
  Still call `codex exec` (or the parallel-worktree pattern) to do work.
- **Don't pack implementation into subgoals.** Subgoals are criteria,
  not tasks. "Codex must implement X" belongs in CTO_HANDOFF.md.
- **One mission per `/goal`.** New product mission? New `/goal`.
  Don't pile unrelated subgoals onto an old goal.
- **Subgoals are persistent across turns.** Use `/subgoal clear`
  before starting a different mission, or the judge will keep checking
  stale criteria.

## Recurring Work: Cron Jobs

For nightly/weekly automation. Use Hermes `cronjob(action='create')`
with `workdir` set to the repo. Cron sessions have NO chat memory —
the prompt must be self-contained and load this skill explicitly.

### Template: nightly test-and-fix

```
cronjob(
  action='create',
  name='nightly-codex-fix',
  schedule='0 3 * * *',
  workdir='/root/myapp',
  enabled_toolsets=['terminal', 'file', 'github'],
  skills=['hermes-ceo-codex-cto-fleet'],
  prompt='''
    Read AGENTS.md and CEO_GOAL.md.
    Run the test command from AGENTS.md.
    If anything fails:
      1. Write .agents/CTO_HANDOFF.md describing the failures.
      2. Run: codex exec --sandbox workspace-write "$(cat .agents/CTO_HANDOFF.md)" > .agents/last_report.md 2>&1
      3. Run the acceptance checklist from this skill.
      4. If accepted, open a PR via gh.
      5. Deliver a one-paragraph summary back to chat.
    If tests pass, deliver "all green - <date>".
  '''
)
```

### Template: weekly dependency audit

Same shape, schedule=`0 9 * * 1`, with a handoff that says "list
outdated direct dependencies, propose upgrades for any with security
advisories, do not touch lock files for non-security upgrades."

For durable multi-stage pipelines (test → fix → review → PR with
human approval gates), use Hermes Kanban via the `kanban-orchestrator`
skill instead of cron.

## Common Pitfalls

1. **Two Codex processes in one cwd.** They race on file writes and
   produce garbage diffs. Always use separate worktrees.

2. **Trusting "tests pass" without checking.** Codex sometimes
   summarizes optimistically. Verify the actual test runner output
   appears in the TESTS RUN section with a pass/fail line.

3. **Vague CTO_GOAL.** "Improve auth" → Codex changes 20 files.
   "Add per-IP rate limit of 5/min to POST /auth/reset, return 429
   with Retry-After header" → minimal diff. Be surgical.

4. **Skipping the pre-flight git check.** Codex's diff will mix with
   yours and the audit log is destroyed.

5. **Conversational drift.** Codex `exec` is one-shot. Don't try
   follow-ups — write a new handoff.

6. **Secrets in CTO_HANDOFF.md.** Codex will see them. Reference env
   var NAMES only, never values.

7. **`--dangerously-bypass-approvals-and-sandbox` outside a container.**
   One prompt injection from data loss. Just don't.

8. **Forgetting to gitignore last_report.md.** install.sh handles
   it, but verify in repos bootstrapped manually.

9. **Running cron without `workdir`.** Cron defaults to the
   scheduler's cwd. Always set `workdir=<repo>` explicitly.

10. **Loading this skill for a first-time install.** Wrong skill.
    Route to `hermes-ceo-codex-cto-install`.

11. **Stuck Codex processes.** Codex with full-access sandbox can hit
    a network prompt and wait forever. Use `process(action='poll')`
    after 5 min idle; kill if needed.

12. **Worktree cleanup forgotten.** Stale worktrees + branches
    accumulate. After merging each PR, remove the worktree and branch.

13. **Treating infra failures as code failures.** `codex exec` exit
    code 1 with an empty/short last_report.md is almost always infra
    (quota, revoked OAuth token, network). Use the diagnosis table
    in Step 6 BEFORE rewriting the handoff. Don't waste handoff
    iterations on infra problems.

## Verification Checklist (per task, before "accepted")

- [ ] Preconditions all green
- [ ] `.agents/CTO_HANDOFF.md` has all required sections
- [ ] Working tree was clean before `codex exec` ran
- [ ] `.agents/last_report.md` has all 6 required sections
- [ ] Acceptance checklist (8 items) passed
- [ ] If multi-worktree: every worktree's report reviewed independently
- [ ] Commit / PR drafted via `github-pr-workflow`
- [ ] Memory or Kanban updated with the next task

## One-Shot Recipes

### "Delegate this bug fix to Codex in /root/myapp"
1. cd, run preconditions check
2. `git status --short` → must be clean
3. Patch `.agents/CTO_HANDOFF.md` with the goal + constraints
4. `codex exec --sandbox workspace-write "$(cat .agents/CTO_HANDOFF.md)" > .agents/last_report.md 2>&1`
5. Read report → run acceptance checklist
6. Accept: draft commit + suggest PR. Reject: tighten handoff, re-run.

### "Run two fixes in parallel"
1. `git worktree add ../myapp-a -b codex/task-a`
2. `git worktree add ../myapp-b -b codex/task-b`
3. Write each worktree's `.agents/CTO_HANDOFF.md`
4. Two `terminal(background=true, notify_on_complete=true, workdir=...)` calls
5. On each completion notification, review that worktree's report
6. Decide PR merge order (smallest/safest first)
7. `git worktree remove` + branch delete after each merge

### "Set up nightly Codex auto-fix for /root/myapp"
1. Verify AGENTS.md test command actually works
2. `cronjob(action='create', ...)` with the nightly template above
3. `cronjob(action='run', job_id=...)` once to smoke-test
4. Check the delivered message in chat

### "What's the status of my coding agents?"
1. `process(action='list')` → all backgrounds
2. For each Codex process, `process(action='poll', session_id=...)`
3. Report: running / done / failed, with last 10 lines of output
4. Offer: wait for one, kill a stuck one, or review a completed report

### "Codex went rogue and changed 50 files"
1. `git diff --stat` to see scope
2. `git checkout -- <unrelated files>` to revert non-task changes
3. Tighten Constraints in `.agents/CTO_HANDOFF.md`:
   "Minimal diff. Touch ONLY <specific files>. Reject any change to
   <other paths>."
4. `git reset --hard HEAD` and re-run from clean state

### "codex exec just failed — is it code or infra?"
1. `tail -20 .agents/last_report.md`
2. Cross-reference the Step-6 diagnosis table.
3. If infra → fix that and retry the SAME handoff (no edits).
4. If code → run the 8-item acceptance checklist; if it fails,
   tighten the handoff and re-run.
5. Common: "usage limit" = ChatGPT quota → wait or set
   `OPENAI_API_KEY` to switch to API billing for this session.
6. Common: "refresh token revoked" = OAuth dead → tell the user to
   run `codex login` themselves (browser flow; Hermes can't do it).
