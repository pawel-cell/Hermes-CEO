# Hermes CEO → Codex CTO

A copy-pasteable playbook + bootstrapper for using **Hermes Agent as
the CEO/orchestrator** and **OpenAI's Codex CLI as the CTO/executor**
in any git repo.

- **Hermes** owns the goal, memory, scheduling, review.
- **Codex** owns code edits inside one scoped handoff at a time.
- They talk through two files: `.agents/CTO_HANDOFF.md` in,
  `.agents/last_report.md` out.

Full protocol → [`GUIDEBOOK.md`](./GUIDEBOOK.md)

/goal + Codex fleet playbook → [`goal-codex-guide.md`](./goal-codex-guide.md)

## Quick start

Prerequisites: a real terminal, Node.js 18+, git, an active ChatGPT
Plus or Pro subscription.

```bash
# 1. Bootstrap the project (run from inside YOUR repo, not this one)
cd /path/to/your/repo
bash <(curl -fsSL https://raw.githubusercontent.com/pawel-cell/Hermes-CEO/main/install.sh)

# 2. Log in to Codex (browser flow — must be a real terminal)
codex login

# 3. Fill in the templates the bootstrapper created
$EDITOR AGENTS.md       # stack, test/lint/typecheck commands
$EDITOR CEO_GOAL.md     # business objective + current milestone

# 4. Write your first task and run it
$EDITOR .agents/CTO_HANDOFF.md
codex exec --sandbox workspace-write "$(cat .agents/CTO_HANDOFF.md)" \
  < /dev/null \
  > .agents/last_report.md 2>&1
```

That's the manual loop. The Hermes skill below automates it.

## Install the Hermes skills

Two skills, separated by role:

| Skill                            | Use when                                              |
|----------------------------------|-------------------------------------------------------|
| `hermes-ceo-codex-cto-install`   | First-time bootstrap of the pattern in a repo         |
| `hermes-ceo-codex-cto-fleet`     | Day-to-day: delegate, parallel worktrees, cron, review |
| `openrouter-image-generation`    | Generate images through OpenRouter and save PNGs locally |
| `n-slide-deck-goal-template`     | Copy-paste /goal template for generating N-slide decks with OpenRouter images |

Install the CEO/CTO skills:

```bash
# Clone this repo somewhere
git clone https://github.com/pawel-cell/Hermes-CEO.git ~/Hermes-CEO

# Drop both skills into your Hermes skill tree
mkdir -p ~/.hermes/skills/orchestration
cp -r ~/Hermes-CEO/skill/hermes-ceo-codex-cto-install \
      ~/Hermes-CEO/skill/hermes-ceo-codex-cto-fleet \
      ~/.hermes/skills/orchestration/
```

Optional image-generation + deck-generation prompt skills:

```bash
mkdir -p ~/.hermes/skills/creative
cp -r ~/Hermes-CEO/skill/openrouter-image-generation \
      ~/Hermes-CEO/skill/n-slide-deck-goal-template \
      ~/.hermes/skills/creative/
```

Then start a fresh Hermes session (skills load at session start).

**First time in a repo:**

> Load `hermes-ceo-codex-cto-install` and set it up in `/path/to/my/repo`

**Every time after that:**

> Load `hermes-ceo-codex-cto-fleet` and delegate this task to Codex: ...

## What you get

After running `install.sh` inside a repo:

```
your-repo/
├── AGENTS.md                  ← stack + commands + coding rules (commit)
├── CEO_GOAL.md                ← business objective + milestone (commit)
├── .agents/
│   ├── CTO_HANDOFF.md         ← Hermes writes a scoped task here (commit template)
│   └── last_report.md         ← Codex writes its result here (gitignored)
└── .gitignore                 ← .agents/last_report.md added
```

The bootstrapper never overwrites an existing file, so it's safe to
re-run if you add the pattern to more repos.

## When NOT to use this

- One-off "run Codex once" tasks → just call `codex exec` directly.
- Coding agents other than Codex (Claude Code, OpenCode) → those have
  their own Hermes skills.
- Hermes Agent installation itself → see `hermes-agent` skill.

## Subscription sizing

| Tier              | Use when                                          |
|-------------------|---------------------------------------------------|
| ChatGPT Plus      | One repo, focused sessions, MVP / proof-of-concept |
| ChatGPT Pro       | Parallel worktrees, all-day usage, hitting limits  |
| API key           | CI, shared automation, billing separate from chat  |

Same ChatGPT account for `codex login` and any Hermes provider you
configure — auth stores are separate, quota is per-account.

## Safety defaults

- Default sandbox is `workspace-write`. Never
  `--dangerously-bypass-approvals-and-sandbox` outside a container or
  throwaway VM.
- Always run inside a git repo with a clean working tree — `git diff`
  becomes your audit log.
- Keep secrets in env vars. Never paste tokens into `CTO_HANDOFF.md`.
- Review the diff before merging, even when Codex says tests pass.

## Known friction (read before your first run)

Real failures we've hit while dogfooding this template, with copy-pasteable recovery commands. The fleet skill carries the full playbook; this section is the user-facing summary.

### 1. One Codex at a time — ALWAYS

Codex uses ChatGPT OAuth with single-use refresh tokens. Two `codex` processes refreshing in parallel both get the `refresh_token_reused` 401 and lock you out.

**Pre-flight before EVERY codex run (interactive or `exec`):**

```bash
pkill codex 2>/dev/null; sleep 1
ps -ef | grep -v grep | grep codex     # must print nothing
codex --version                         # confirm it still works
```

This applies even when you're using the fleet pattern's parallel worktrees — worktrees parallelize *files*, not *auth*. One codex auth consumer per machine.

**Recovery when it's already happened** (last_report.md shows `refresh_token_reused`):

```bash
pkill -9 codex
codex logout
codex login            # browser flow, must be a real terminal
```

### 2. Rate limits are about plan capacity, not prompt length

ChatGPT Plus gives `codex exec` a finite token budget per rolling window. Long "read all of PRD.md, AGENTS.md, every doc" prompts burn the budget 5-10× faster than focused ones.

**Lean handoff template (≤2KB):**

```
CTO_GOAL: <one imperative sentence>
Files likely involved: <2-3 paths>
Constraints: <hard rules — minimal diff, no new deps>
Commands to run before reporting: <test cmd>
Done when: <explicit criteria>
Return: <6-section report>
```

**Bloated anti-pattern (≥5KB, will rate-limit you):**

```
CTO_GOAL: ...
Read first, in order: PRD.md, README.md, AGENTS.md,
  docs/foo.md, docs/bar.md, docs/baz.md, legacy/index.html, ...
```

If you keep hitting limits, upgrade to ChatGPT Pro (~5× more headroom) or switch to an API-key-based agent (Claude Code).

### 3. Silent hangs — detect and kill

Sometimes `codex exec` opens a websocket, makes one request, then the connection dies and Codex doesn't notice. Symptom: process alive but TIME=0, %CPU=0, no `:443` socket open, file frozen at 39 bytes ("Reading additional input from stdin...") for >5 minutes.

**Detection one-liner** (replace PID with your codex pid):

```bash
PID=12345
ps -p $PID -o pid,etime,time,pcpu   # TIME=0 + %CPU=0 after >5min = bad
ss -tnp | grep -E "pid=$PID"        # no row = disconnected, dead
```

**Recovery:** `kill -9 $PID` and re-run. Codex's `exec` mode currently has no automatic reconnection — this will improve upstream but until it does, manually kill and retry.

### 4. Don't delegate trivial work

Codex orchestration has fixed overhead (auth, rate limits, sandbox boot, model latency). For tasks of ≤4 files / ≤200 lines, the overhead exceeds the task. Either edit directly, or have your CEO agent (Hermes) do it inline.

Rule of thumb: **if Codex has failed twice on the same handoff in one session, OR the task is tiny, stop delegating and DIY.** Still write a real commit message that follows the 6-section report contract — the contract is what makes the work reviewable, not who did it.

### 5. Timezones when scheduling codex retries

ChatGPT/Codex error messages quote reset times in the **user's local clock**, not UTC. The VPS clock is UTC. If you schedule a cron retry using the literal time Codex showed you ("try again at 2:20 PM") without converting, you'll wait an extra timezone-offset's worth of hours for nothing.

Always convert to UTC before passing to `cronjob(schedule=...)` or `crontab`:

```
UTC = local_time - tz_offset
  Poland (CEST, summer):  UTC = local - 2h
  Poland (CET,  winter):  UTC = local - 1h
  US East (EDT, summer):  UTC = local + 4h
```

### 6. Pre-flight `.env.local` BEFORE writing the handoff

Codex will dutifully run `npm test` and fail at the first API call because `KV_REST_API_URL` / `OPENROUTER_API_KEY` / `GITHUB_TOKEN` are empty. Catch it in 2 seconds:

```bash
[ -f .env.local ] && awk -F= '/^[A-Z_]+=.+/{print $1": "(length($2))" chars"}' .env.local
```

Any required key showing 0 chars → fix the env first, then write the handoff.

---

The fleet skill (`hermes-ceo-codex-cto-fleet/SKILL.md`) has step-by-step recovery recipes for each of these, plus the full diagnostic command bank in `references/failure-modes.md`.

## Repo contents

| File                                   | Purpose                                                  |
|----------------------------------------|----------------------------------------------------------|
| `GUIDEBOOK.md`                         | Full protocol: templates, delegation loop, parallelism   |
| `install.sh`                           | Bootstrapper — preflight + Codex install + scaffolding   |
| `skill/hermes-ceo-codex-cto-install/`  | Hermes skill: first-time bootstrap                       |
| `skill/hermes-ceo-codex-cto-fleet/`    | Hermes skill: day-to-day fleet operations                |

## License

MIT
