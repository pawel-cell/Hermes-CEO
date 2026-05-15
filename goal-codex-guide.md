# The /goal + Codex CLI Playbook

How to turn one sentence into a fleet of autonomous agents.

## 1. What `/goal` actually is

`/goal` is Hermes' "Ralph loop" — a standing objective that survives across turns. You type it once, and Hermes works toward it turn after turn until done. No babysitting.

How it works under the hood:

- You type: `/goal <one paragraph describing the mission>`
- Turn 1 fires: Hermes treats the goal text as a normal prompt and starts working immediately.
- After each turn: an auxiliary judge checks whether the goal is done. Same session, same prompt cache, same tools. You see:

  ```text
  ↻ Continuing toward goal (3/20): <judge reason>
  ```

- If done:

  ```text
  ✓ Goal achieved
  ```

- If the turn budget is hit:

  ```text
  ⏸ Goal paused — 20/20 turns used.
  ```

  `/goal resume` keeps going. The budget is configurable via `goals.max_turns`.

Important properties:

- Any real message you send preempts the loop.
- State persists across `/resume` — close laptop, come back, and the standing goal still exists.
- Judge fails open — a broken judge never wedges progress; the turn budget is the real backstop.
- Subcommands: `/goal status`, `/goal pause`, `/goal resume`, `/goal clear`.

This is the magic: `/goal` is the substrate that lets one prompt orchestrate a multi-hour, multi-agent build without you re-typing "continue" 40 times.

## 2. Why `/goal` + Codex = multi-agent workflows

Hermes is strong at orchestration, file operations, web, tools, memory, scheduling, and reasoning. Codex CLI is strong at heads-down coding in a sandbox.

Combine them:

```text
Hermes (the CEO)
  │
  ├──► spawns Codex agent A  (CTO — builds the app)
  │      via: terminal(command="codex --yolo exec '<prompt>'",
  │                    workdir="...", background=true, pty=true)
  │
  ├──► spawns Codex agent B  (CMO — builds marketing)
  │      same pattern, different workdir
  │
  └──► /goal keeps Hermes alive across turns until BOTH children
       commit their deliverables AND any integration step
       (for example: "CTO pulls CMO's blog posts into the app") is done.
```

The `/goal` judge is what makes this end without you watching: it keeps checking "are both repos committed? is the integration in place?" and only marks done when the answer is yes.

## 3. The core prompt template

This is the shape the CEO/CTO/CMO example follows. Copy, adapt, fire.

```text
/goal You are the CEO. Spawn N Codex subagents via the
autonomous-ai-agents Codex skill:
https://hermes-agent.nousresearch.com/docs/user-guide/skills/bundled/autonomous-ai-agents/autonomous-ai-agents-codex

<ROLE 1>:
  <one-paragraph mission>
  Deliverables:
    - <concrete artifact 1>
    - <concrete artifact 2>

<ROLE 2>:
  <one-paragraph mission>
  Deliverables:
    - <concrete artifact 1>
    - <concrete artifact 2>

Goal criteria:
  All repos/workdirs are committed with required deliverables.
  Then <integration step that ties the children's outputs together>.
```

Five non-negotiable parts:

1. Role hat for Hermes itself: "You are the CEO."
2. Explicit instruction to spawn Codex via the skill — this brings in the PTY rules, parallelism gotchas, and known pitfalls.
3. Per-subagent role, scope, and deliverables list. Be concrete. "3 blog posts" beats "some marketing content."
4. A measurable goal criteria sentence. This is what the judge evaluates. If you can't grep it, the judge can't either.
5. An integration step. This is where multi-agent stops being a parlor trick and starts producing something coherent.

## 4. The reference example, annotated

```text
/goal You are the CEO. Spawn two Codex subagents via the
autonomous-ai-agents Codex skill: <link>

CTO:
  Build a modern Next.js team weekly reporting app.
  App goal: team members submit weekly reports including:
    - wins
    - blockers
    - plans
    - 2 cold emails

CMO:
  Build the launch campaign.
  Deliverables:
    - 3 blog posts
    - 2 cold emails
    - launch positioning

Goal criteria: Both repos are committed with all required
deliverables for each. Then the CTO integrates the marketing
blogs into the app.
```

What this triggers, step by step:

- Turn 1: Hermes loads the Codex skill, picks two workdirs such as `/tmp/weekly-reports` and `/tmp/launch-campaign`, initializes git repos, writes prompt files, and spawns Codex #1 (CTO) with `background=true`, `pty=true`.
- Turn 2+: The Codex skill says to prefer sequential execution on one OAuth account. Hermes waits on CTO's `notify_on_complete`, verifies the commit, then spawns CMO. If you have separate auth or machines, they can truly run in parallel.
- Turn N: Both children commit. Hermes opens CMO's `blog/` folder, copies the markdown into the CTO app's content directory, wires routing, and commits the integration.
- Judge: Reads Hermes' summary — for example, "I've copied 3 blog posts into `/tmp/weekly-reports/content/` and committed. Both repos done." — then marks done.

## 5. Design patterns that work

### A. Role fan-out

One CEO Hermes → N Codex children, each with a role.

Best for: cross-functional product builds, engineering + design + marketing + ops, batch issue fixing, and multi-service systems.

### B. Build then integrate

Children build in isolation, parent stitches them together.

The integration step is the whole reason to use `/goal` here — without it you could just run two separate `codex exec` calls.

### C. Build then review

Codex #1 builds. Codex #2 reviews with `codex review --base main`. Hermes reads the review and either approves or kicks work back.

### D. Iterate until green

Example: "Make `pytest -n 4` exit 0 in this repo." Codex commits, Hermes runs tests, fails, sends Codex the failure log, Codex commits again. Judge stops when tests pass.

### E. Research → build handoff

Hermes does the research with web/tools, no Codex. Then it spawns Codex with the findings as the prompt. The goal stays alive across the handoff because it's all one Hermes session.

## 6. Hard-won rules

These are baked into the Codex skill that Hermes loads, but you should know them so your `/goal` text doesn't fight them.

- Sequential by default, parallel only with separate auth. Two `codex --yolo exec` instances on one OpenAI account on one machine can stall at the planning step. Treat this as a bug, not a workflow.
- Use separate workdirs. Hermes can do this with `mktemp -d && git init`, but only if your goal tells it to put each child in its own workdir.
- Codex can look frozen for 60-180 seconds while it plans. Do not `/stop` too early.
- Files on disk plus `git log --oneline` are ground truth. The judge model reads Hermes' text summary, but you should also verify by listing the workdirs after a run.
- `notify_on_complete` is the right monitor pattern. Polling loops are the wrong one.
- Codex TUI slash commands such as `/goal` or `/plan` inside Codex itself cannot be puppeted from Hermes background PTY. Use `codex exec "<prompt>"` — it is the headless equivalent.

## 7. Writing a goal that the judge can grade

Good criteria, because the judge can verify from a summary:

- "Both `/tmp/A` and `/tmp/B` contain a git commit on main with message starting `feat:`. `/tmp/A` has `src/app/page.tsx`."
- "`ruff check .` exits 0. All 47 tests pass."
- "PR #128 is merged and `gh pr view 128` shows state `MERGED`."

Bad criteria, because the judge has to hallucinate:

- "Make it good."
- "The marketing copy should resonate with B2B buyers."
- "App should be production-ready."

Rule of thumb: if you couldn't write a 5-line shell script that returns 0/1 based on filesystem state, the judge can't grade it either. Add concrete artifacts to every role.

## 8. Three ready-to-fire templates

### Template 1 — Product + Marketing

```text
/goal You are the CEO. Spawn two Codex subagents via the autonomous-ai-agents Codex skill.

CTO: Build the app at /tmp/<slug>-app. Required files:
  - src/app/page.tsx
  - src/app/api/<route>/route.ts
  - README.md
Commit on main with "feat: initial build".

CMO: Build the launch campaign at /tmp/<slug>-marketing. Required files:
  - STRATEGY.md
  - blog/post-1.md
  - blog/post-2.md
  - blog/post-3.md
  - emails/cold-1.md
  - emails/cold-2.md
Commit on main with "marketing: initial campaign".

Goal criteria: Both repos have the listed files AND a commit matching the message above. Then copy all blog/*.md into the app at src/content/blog/, wire a /blog route, and commit "feat: integrate marketing blogs".
```

### Template 2 — Build + Review

```text
/goal You are the lead. Spawn Codex BUILDER at /tmp/<slug> to implement <feature>. After BUILDER commits, spawn Codex REVIEWER in the same workdir to run `codex review --base main` and write its findings to REVIEW.md. If REVIEW.md contains "BLOCKER", relaunch BUILDER with the blocker text. Goal criteria: REVIEW.md exists, contains no BLOCKER lines, and a commit "review: pass" is on main.
```

### Template 3 — Iterate Until Green

```text
/goal You are the maintainer of <repo>. Spawn one Codex agent in /path/to/repo. Its job: make pytest -xvs exit 0. After each Codex commit, run the tests yourself, and if they fail, feed the failure log back to a fresh Codex exec with the instruction to fix. Goal criteria: pytest -xvs exits 0 AND the latest commit message is "test: green".
```

## 9. When not to use `/goal`

- Single one-shot task that finishes in one turn — just ask.
- Tasks where you want to inspect each step before continuing. `/goal` will charge ahead. Use plain chat and steer manually instead.
- Open-ended creative exploration where "done" is subjective.
- Anything you are not willing to let run unattended.

## 10. Lifecycle commands

Keep these handy:

```text
/goal <text>       Set + fire turn 1
/goal status       Where are we? turn N/20, current judge verdict
/goal pause        Stop the loop, keep the state
/goal resume       Resume, resets counter to 0
/goal clear        Drop it entirely
/stop              Kill background processes; use before setting a new goal mid-run
```

## The pattern in one sentence

`/goal` lets you spawn a fleet, declare done, and walk away — Codex does the typing, Hermes keeps the mission alive, verifies the outputs, and stitches the pieces together.

## Practical next steps

- Ask Hermes: "set up a CEO/CTO/CMO build."
- Save this guide as a Markdown file, for example `~/Documents/goal-codex-guide.md`.
- Adapt one of the three templates to the specific demo you are filming next.
