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

> **CRITICAL: always close stdin with `< /dev/null` when spawning `codex exec` from a non-interactive parent (Hermes background terminal, cron, systemd, CI).**
>
> When stdin is a pipe and a prompt is also passed via argv, Codex prints
> `Reading additional input from stdin...` and waits forever for either
> data or EOF on the pipe. The bash wrapper Hermes uses leaves stdin open
> as a pipe — Codex sits in `pipe_read` with CPU=0, no live network
> connection, and never exits. This looks identical to a silent network
> hang in `ps` and was responsible for ALL early "Codex hung" reports.
>
> Closing stdin (`< /dev/null`) tells Codex "no more input coming, just
> use the argv prompt." This is required, not optional. It is the
> single-most-important detail in this entire skill.

Default invocation, blocking:

```bash
cd <REPO_ROOT>
codex exec \
  --sandbox workspace-write \
  "$(cat .agents/CTO_HANDOFF.md)" \
  < /dev/null \
  > .agents/last_report.md 2>&1
```

For tasks expected to take >2 minutes, use a Hermes background
terminal so the chat doesn't block:

```
terminal(
  background=true,
  notify_on_complete=true,
  workdir="<REPO_ROOT>",
  command='codex exec --sandbox workspace-write "$(cat .agents/CTO_HANDOFF.md)" < /dev/null > .agents/last_report.md 2>&1'
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
  command='codex exec --sandbox workspace-write "$(cat .agents/CTO_HANDOFF.md)" < /dev/null > .agents/last_report.md 2>&1'
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
      2. Run: codex exec --sandbox workspace-write "$(cat .agents/CTO_HANDOFF.md)" < /dev/null > .agents/last_report.md 2>&1
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

> Diagnostic command bank for when something goes wrong:
> `references/failure-modes.md` (process triage, auth signals, timezone
> sanity for cron retries, nuclear-option cleanup).
>
> Re-runnable scripts (prefer over hand-typing each time):
> - `scripts/codex-preflight.sh` — pre-flight ritual before EVERY
>   `codex exec` (kill stale codex, env check, git clean, handoff
>   sanity). Pass `--port 3000` if your handoff has curl probes.
> - `scripts/detect-codex-hang.sh` — three-signal voter (report growth,
>   CPU ticks, TCP-established) for the silent-hang failure mode.
>   Exit 0=healthy, 1=hung, 2=no codex.
>
> Handoff template: `templates/CTO_HANDOFF-lean.md` — copy into
> `.agents/CTO_HANDOFF.md` and fill in. Stays under 3 KB; doesn't
> trigger the rate-limit-from-context-bloat anti-pattern.
>
> Live monitoring while `codex exec` runs in the background — five
> probes + a decision table for "alive / thinking / hung / dead":
> `references/live-monitoring.md`. Use this every time the user asks
> "how's it going?" so the answer is grounded in probe output, not
> "still running ☕".

1. **Two Codex processes in one cwd.** They race on file writes and
   produce garbage diffs. Always use separate worktrees.

1b. **Two Codex processes sharing one ChatGPT login (any cwd).** The
   OAuth refresh token is single-use — parallel refreshes invalidate
   it and lock the user out with `refresh_token_reused`. Rule: **one
   codex auth consumer per machine** even when the fleet pattern
   allows one `codex exec` per cwd. Before scheduling a cron or
   spawning a worktree, `ps -ef | grep codex` and kill leftover
   interactive sessions. See the recovery recipe for the 401 case.

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

13. **Dangling interactive `codex --yolo` from a prior chat session.**
    Symptom: a `codex` (and child `codex-cli`/native binary) process
    is owned by a `pts/*` and has been idle for tens of minutes. The
    user is usually staring at it waiting. You can't drive an
    interactive TUI from Hermes — convert to the background-handoff
    pattern via the \"I already have an interactive codex running\"
    recipe. Don't be shy about killing it; the user asked you to
    orchestrate, which implies they're done watching.

14. **Launching `codex exec` before checking `.env.local`.** Codex
    will dutifully run lint/build/tests, all of which fail at the
    first call to the API route because KV / OpenRouter / GitHub
    creds are missing. You'll spend a Codex round-trip discovering
    something a `wc -c .env.local` would have shown you. Always
    pre-flight the env (existence + non-empty + length check) before
    writing the handoff.

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
4. `codex exec --sandbox workspace-write "$(cat .agents/CTO_HANDOFF.md)" < /dev/null > .agents/last_report.md 2>&1`
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

### "I already have an interactive `codex --yolo` running, take it over and orchestrate"

User has been working with Codex in a TTY and wants to switch to the background-orchestrated pattern (typically because they are staring at a 20-min wait and want to delegate). Do not try to attach to the running session — it is a TUI, not resumable. Convert cleanly:

1. Identify the dangling process: `ps aux | grep -E 'codex( |$)' | grep -v grep`. Note the PID(s).
2. `cd <repo>` then `git status --short` — Codex's in-flight work is usually uncommitted. Do not reset it; preserve it.
3. Kill the interactive Codex (parent + worker PID): `kill <pid1> <pid2>; sleep 1; ps -p <pid1> <pid2>`.
4. Commit the WIP so the next handoff starts from a clean tree:
   `git add -A && git -c user.email=hermes@local -c user.name=hermes commit -m "wip: codex partial work (pre-orchestration checkpoint)"`
5. If `.agents/` does not exist, scaffold it now (the user was driving Codex without the handoff bus). `mkdir -p .agents` and ensure `.agents/last_report.md` is in `.gitignore`.
6. Verify the env: a real `.env.local` (or equivalent) exists with all the secrets the route/script needs. If creds are missing, ask BEFORE writing the handoff — a Codex run that fails on missing-env is wasted.
7. Write `.agents/CTO_HANDOFF.md` and launch as a Hermes background terminal with `notify_on_complete=true`. Now the user is free.

### "User pasted secrets in chat and I need to drop them into .env.local without echoing"

Common with users who default to copy-paste from password managers. Workflow:

1. `write_file` straight to `<repo>/.env.local` (NEVER use heredoc-in-terminal; that puts the secret in shell history).
2. `chmod 600 .env.local` and confirm `.env.local` is in `.gitignore`.
3. Verify lengths without ever printing values:
   `awk -F= '/^[A-Z_]+=.+/{print $1": "(length($2))" chars"}' .env.local`
4. Known good lengths to sanity-check against:
   - OpenRouter key (`sk-or-v1-...`): 73 chars
   - GitHub fine-grained PAT (`github_pat_...`): 93 chars (sometimes 92 or 94 depending on suffix)
   - Vercel token: 24 chars
5. Remind the user to regenerate any token that went through chat verbatim once the task is done. Do not bury this — call it out at the top of the reply.

### "Codex died with `token_invalidated` / `refresh_token_reused` / 401"

Symptom: `.agents/last_report.md` contains lines like:
```
ERROR codex_login::auth::manager: Failed to refresh token: 401 Unauthorized
"code": "refresh_token_reused"
"code": "token_invalidated"
ERROR: Your access token could not be refreshed because your refresh
token was already used. Please log out and sign in again.
```
Codex exits cleanly (no PID anymore) but never wrote a real report.
This is NOT a rate limit — different recovery.

Root cause: ChatGPT OAuth refresh tokens are single-use. Two `codex`
processes refreshing in parallel (e.g. a leftover interactive
`codex --yolo` plus a `codex exec` from cron), or any second consumer
of the same token, will invalidate both.

Fix — requires the human, you can't recover this for them:
1. Tell the user: `codex logout && codex login` on the VPS (opens a
   browser URL, they sign back into ChatGPT, ~3 min).
2. While they're logging in: kill any other `ps -ef | grep codex`
   leftovers so there's exactly ONE codex auth consumer after relogin.
3. After they confirm relogin, re-run the handoff directly — no need
   to reschedule cron unless the rate-limit reset is also pending.
4. Audit your own behaviour: if you spawned a `codex exec` while
   another codex process (interactive TUI, parallel cron, fleet
   worktree) was still running on the same machine, that's the cause.
   The rule is **one codex auth consumer per machine** even though the
   fleet pattern allows one codex exec per cwd. Don't conflate the two.

### "`Reading additional input from stdin...` is the only thing in last_report.md"

Harmless. That's the bash launcher's noise, not Codex. `codex exec`
reads its prompt from argv, not stdin — the "Reading additional input
from stdin" line is emitted by the wrapper shell. Codex itself is
either still in the read-and-think phase OR has already failed for
another reason (check for auth errors or `usage limit` lower in the
file). Don't kill on this alone; check uptime and file size growth
first.

### "Codex hit the ChatGPT usage limit mid-handoff"

Symptom: `codex exec` exits or stalls with `Error running remote compact
task: You've hit your usage limit. To get more access now, ... try
again at <HH:MM>.` `.agents/last_report.md` is empty or contains only
`Reading additional input from stdin...`.

1. `process(action='kill', session_id=...)` to free the pty if it's stuck.
2. Keep `.agents/CTO_HANDOFF.md` AS-IS. Do NOT rewrite it — the retry
   will re-read it from disk.
3. Commit any preflight scaffolding (.gitignore tweaks, .agents/
   directory creation) so the working tree is clean. Codex's actual
   work commit comes later, after the retry.
4. Schedule a one-shot cron at the reset time (add ~2 min buffer):
   `cronjob(action='create', schedule='YYYY-MM-DDTHH:MMZ', repeat=1,
   workdir=<REPO_ROOT>, skills=['hermes-ceo-codex-cto-fleet'],
   enabled_toolsets=['terminal','file'], deliver='origin', ...)`.
   The cron prompt must: pre-flight, `codex exec` against the existing
   handoff, run the 8-item acceptance checklist, commit-or-stash, and
   deliver a structured summary back to chat. **Important:** the
   cronjob tool defaults `deliver` to `local` in CLI mode — update it
   to `origin` explicitly if you want the result to land in chat.
   **Timezone trap (high-cost):** ChatGPT/Codex error messages quote
   the reset time in the END USER'S LOCAL CLOCK, not UTC. The VPS is
   UTC. Cron schedules MUST be in UTC. If the user is in Poland (CEST,
   UTC+2) and Codex says "try again at 2:20 PM", you schedule
   `12:22 UTC`, not `14:22 UTC`. Confirm the user's timezone before
   computing the UTC value — `date -u` on the VPS will always say UTC,
   which is exactly what makes this trap easy to fall into. When the
   user's location is in memory/profile, do the conversion silently;
   when it isn't, ask before scheduling.
5. Tell the user the reset time and that they don't need to be online.
6. After the cron delivers, run the standard accept/revise loop from
   chat — the cron just unblocks the gated step, it doesn't replace
   the CEO decision.

### "Codex auth token invalidated mid-run"

Symptom: `.agents/last_report.md` contains `ERROR codex_login::auth::manager:
Failed to refresh token: 401 Unauthorized` with `code: refresh_token_reused`
or `code: token_invalidated`. Process exits or hangs after this error.

Cause: OAuth refresh tokens are single-use. Two `codex` processes running
concurrently (e.g. an interactive `codex --yolo` left open in a tmux pane
plus a scheduled `codex exec` from cron) will both try to refresh the
same token; second one wins, first one is locked out. Can also happen
after a manual `codex logout` partway through a session.

Recovery (USER-HANDS REQUIRED — Hermes can't do this remotely):
1. `process(action='kill', ...)` the stuck process.
2. Ask the user to: `codex logout && codex login` (browser-based OAuth).
3. Wait for user's confirmation ("logged in").
4. Re-run `codex exec` against the existing handoff (no rewrite needed).

Prevention: before any `codex exec` invocation, verify there's no
existing `codex` process running in the same user account:
`ps -ef | grep -E 'codex exec|codex --yolo' | grep -v grep`. If one
exists and it's stale (>15min idle, 0% CPU), kill it before launching.

### "Codex silently hangs — process alive but doing nothing"

Symptom: `codex exec` started ≥15 min ago, output file frozen at 39
bytes (just "Reading additional input from stdin..."), process still
shows `Ss` in ps but `TIME=00:00:00 %CPU=0.0`, AND `ss -tnp` shows NO
ESTABLISHED connection from the codex pid to a `:443` upstream.

This is the worst failure mode because Codex doesn't crash, doesn't
log an error, doesn't exit — it just stops trying. Often follows a
transient network blip during the model's first response.

**Fastest detection: run `scripts/detect-codex-hang.sh`.** It samples
three independent signals (report growth over 5s, CPU ticks over 5s,
real TCP-ESTABLISHED count from `/proc`) and votes. Exit 1 = hung.

Manual detection if you don't have the script handy:
```bash
PID=$(pgrep -f 'codex exec' | tail -1)
ps -p $PID -o pid,etime,time,pcpu          # TIME=0 + %CPU=0 = bad sign
# /proc-based socket check (more reliable than ss):
for fd in $(ls /proc/$PID/fd 2>/dev/null); do
  link=$(readlink /proc/$PID/fd/$fd 2>/dev/null)
  echo "$link" | grep -q socket || continue
  inode=$(echo "$link" | sed 's/socket:\[//;s/\]//')
  state=$(awk -v i="$inode" '$10==i {print $4; exit}' /proc/net/tcp /proc/net/tcp6)
  echo "fd=$fd state=${state:-NONE}"
done
```
All sockets `state=NONE` (or all sharing one inode = parent↔child UDS)
and zero CPU consumption over 5s = hung. Kill `-9` and retry — there
is no graceful recovery.

**If it hangs three times in a row** (observed: codex-cli 0.130.0 on
Linux x86_64, May 2026): stop trying. The DIY threshold has been
crossed. Codex's `exec` mode has an unsurfaced reconnection bug that
fires more often on some machines than others. Patch this skill with
new findings if a future codex release fixes it.

### When to abandon delegation and do the work yourself

`codex exec` has a non-trivial baseline overhead (auth, rate limits,
sandbox bootstrap, model latency, hang risk). For very small tasks
(one new file + a few import swaps + running tests) that overhead can
exceed the task itself, especially after a Codex failure or two.

Heuristic threshold: **if Codex has failed twice on the same handoff
within one session, OR the handoff's "Files likely involved" list has
≤4 entries and ≤200 lines of expected churn, just do it yourself.**

Pattern of misuse to avoid: spending 3+ hours of wall-clock on auth
recovery, rate-limit waits, hang diagnostics, and cron rescheduling
for a task you could complete in 15 minutes of direct work. When the
user asks "are we making progress?" and the honest answer is "no, we
have scaffolding but zero shipped code", that's the signal you've
crossed the threshold. Drop delegation, do the task, report the same
6-section format yourself, and resume delegation only for larger
follow-up work where the overhead amortizes.

When you DIY the handoff: still write a real commit message that
mirrors the 6-section report contract (PLAN / CHANGED FILES / TESTS
RUN / FAILING TESTS / RISKS / NEXT). The contract is what guarantees
the work is reviewable — keep it whether or not Codex did it.

### "Codex went rogue and changed 50 files"
1. `git diff --stat` to see scope
2. `git checkout -- <unrelated files>` to revert non-task changes
3. Tighten Constraints in `.agents/CTO_HANDOFF.md`:
   "Minimal diff. Touch ONLY <specific files>. Reject any change to
   <other paths>."
4. `git reset --hard HEAD` and re-run from clean state
