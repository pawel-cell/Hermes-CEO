---
name: hermes-ceo-codex-cto-install
description: Use when the user wants to install or bootstrap the Hermes CEO / Codex CTO toolchain into a repo for the first time — running install.sh, getting codex logged in, filling in AGENTS.md and CEO_GOAL.md placeholders, and verifying the codex exec sandbox actually works. After install completes successfully, hand off to the hermes-ceo-codex-cto-fleet skill for ongoing operations.
version: 1.0.0
author: pawel-cell
license: MIT
metadata:
  hermes:
    tags: [install, setup, codex, bootstrap, orchestration]
    related_skills: [hermes-ceo-codex-cto-fleet, codex, hermes-agent]
---

# Hermes CEO → Codex CTO: Install

## Overview

One-time-per-repo installer for the Hermes CEO / Codex CTO pattern.
Scope is intentionally narrow: get the toolchain working and the
scaffolding files in place. Everything operational (delegation,
parallel worktrees, cron, reviews) lives in the sibling skill
`hermes-ceo-codex-cto-fleet`.

Reference repo: https://github.com/pawel-cell/Hermes-CEO

## When to Use

Load this skill when the user says any of:

- "install Hermes CEO Codex CTO in this repo"
- "set up Hermes-CEO on this project"
- "bootstrap the CEO/CTO pattern here"
- "I cloned pawel-cell/Hermes-CEO, what now?"

Don't use for:

- Running Codex on a task → `hermes-ceo-codex-cto-fleet`
- Re-running install in a repo that's already set up → check first,
  then likely jump straight to the fleet skill
- Installing Hermes Agent itself → `hermes-agent` skill
- Installing Codex CLI standalone (no CEO pattern) → `codex` skill

## Preconditions to Check First

Before touching anything, verify all of these. Tell the user clearly
which one is missing — don't try to silently fix the missing ones.

1. **Inside a git repo.** `git rev-parse --show-toplevel` succeeds.
2. **Node + npm.** `node --version` (≥18) and `npm --version` succeed.
3. **Real terminal.** Codex login uses a browser flow. If the user is
   on a chat platform (Telegram/Discord/Slack/SMS), they must run
   `codex login` themselves on their actual machine — Hermes can't
   drive the browser for them.
4. **ChatGPT subscription.** Codex needs Plus or Pro (or an API key).
   Ask explicitly; don't assume.
5. **Hermes Agent installed.** Optional for `install.sh` itself, but
   required to use the fleet skill. If missing, point to the
   `hermes-agent` skill.

If any of (1)-(4) fail, stop and explain. Don't proceed.

## The Install Flow

### Step 1: Run the bootstrapper

From the user's project root:

```bash
cd /path/to/their/repo
bash <(curl -fsSL https://raw.githubusercontent.com/pawel-cell/Hermes-CEO/main/install.sh)
```

What it does:

- Verifies node / npm / git / hermes on PATH
- `npm i -g @openai/codex` if codex is missing
- Detects `~/.codex/auth.json` (does NOT log in for the user)
- Creates `.agents/`, `AGENTS.md`, `CEO_GOAL.md`,
  `.agents/CTO_HANDOFF.md` — only if they don't already exist
- Appends `.agents/last_report.md` to `.gitignore`

It's safe to re-run — non-clobbering by design.

### Step 2: Codex login (human-only)

Tell the user, in plain text:

> Run `codex login` in your terminal. It opens a browser. Cannot be
> automated by Hermes. When the browser flow completes, come back here.

If they're on a chat client and not at their machine, this is a hard
stop. Don't try to use Hermes's PTY for `codex login` — the OAuth
redirect won't complete.

### Step 3: Fill placeholders

Two files need real content before the pattern works:

- `AGENTS.md` — replace every `<placeholder>` with the project's
  actual stack, test command, lint command, typecheck command.
- `CEO_GOAL.md` — replace placeholders with the actual business
  objective + current milestone.

Hermes CAN help draft these. Ask the user:

> What's the stack (language, framework, test runner)?
> What's the business objective for this product in one sentence?
> What's the current milestone or sprint goal?

Then write the answers into the files via `patch` or `write_file`,
preserving the section structure the bootstrapper created.

### Step 4: Verify Codex auth works

After the user confirms `codex login` finished, run:

```bash
cd <REPO_ROOT>
codex exec --sandbox read-only "echo ok"
```

Expected output ends with something like `ok` and the process exits 0.

Failure modes:

- `not signed in` / `unauthorized` → repeat Step 2
- `not in a git repo` → cd is wrong; fix and retry
- `command not found: codex` → install.sh didn't finish, or npm
  global bin isn't on PATH (`npm config get prefix`)

### Step 5: Install the Hermes fleet skill

The user already has THIS skill (or they wouldn't be here), but the
operational sibling needs to be installed separately:

```bash
git clone https://github.com/pawel-cell/Hermes-CEO.git ~/Hermes-CEO 2>/dev/null \
  || (cd ~/Hermes-CEO && git pull)
mkdir -p ~/.hermes/skills/orchestration
cp -r ~/Hermes-CEO/skill/hermes-ceo-codex-cto-fleet \
      ~/.hermes/skills/orchestration/
```

Then tell the user:

> Start a fresh Hermes session — skills load at session start. Then
> say "use the hermes-ceo-codex-cto-fleet skill" to run your first task.

### Step 6: Verification checklist

Run this before declaring success:

- [ ] `git rev-parse --show-toplevel` in the repo
- [ ] `.agents/CTO_HANDOFF.md`, `AGENTS.md`, `CEO_GOAL.md` exist
- [ ] `.gitignore` contains `.agents/last_report.md`
- [ ] `codex --version` works
- [ ] `codex exec --sandbox read-only "echo ok"` succeeds
- [ ] AGENTS.md has actual stack/commands, not `<placeholder>` text
- [ ] CEO_GOAL.md has actual business content, not `<placeholder>` text
- [ ] Fleet skill is at `~/.hermes/skills/orchestration/hermes-ceo-codex-cto-fleet/SKILL.md`

If all eight pass, install is done. Hand off:

> Setup complete. Next time you want to run a coding task, load the
> `hermes-ceo-codex-cto-fleet` skill. Initial commit recommended:
>     git add AGENTS.md CEO_GOAL.md .agents/CTO_HANDOFF.md .gitignore
>     git commit -m "Set up Hermes CEO / Codex CTO scaffolding"

## Common Pitfalls

1. **PTY hang on codex login.** Trying to run `codex login` inside
   Hermes's terminal tool — browser redirect can't complete. Always
   user-run on their own machine.

2. **`codex` not on PATH after npm install.** Happens with non-default
   nvm setups. Fix: `npm config get prefix` → ensure `$PREFIX/bin` is
   on PATH; or use `npx @openai/codex` as a workaround.

3. **Running install.sh outside a repo.** Script exits early — that's
   correct behavior. cd into the repo first.

4. **Overwriting existing AGENTS.md.** The script doesn't, but if you
   manually scaffold, check first. The user may already have one.

5. **Skipping the verification step.** "codex installed, we're done"
   is wrong. The auth + sandbox check (Step 4) is the only proof the
   chain actually works.

6. **Forgetting the fleet skill.** Users will say "Hermes set this
   up, now nothing happens." Step 5 is mandatory, not optional.

7. **Filling placeholders for the user without asking.** AGENTS.md
   and CEO_GOAL.md need REAL project context. Inventing it leads
   to Codex doing wrong things later. Always ask.

8. **Running on a chat platform with no real terminal.** The install
   itself can work via Hermes terminal, but Step 2 (codex login)
   absolutely cannot. Be upfront about this before starting.

## Verification Checklist

(Same as Step 6 above — duplicated here for the skill validator.)

- [ ] Preconditions all green before install
- [ ] install.sh ran without errors
- [ ] codex login succeeded (user confirmed)
- [ ] AGENTS.md and CEO_GOAL.md filled with real content
- [ ] `codex exec --sandbox read-only "echo ok"` returns 0
- [ ] Fleet skill installed at ~/.hermes/skills/orchestration/
- [ ] Initial commit suggested to the user
- [ ] User pointed to the fleet skill for next steps

## One-Shot Recipes

### "Install Hermes-CEO in /root/myapp"
1. `cd /root/myapp && git rev-parse --show-toplevel` → verify
2. Ask: stack, test cmd, business goal, milestone, ChatGPT sub?
3. `bash <(curl -fsSL https://raw.githubusercontent.com/pawel-cell/Hermes-CEO/main/install.sh)`
4. Tell user to run `codex login` themselves; wait for confirmation
5. Patch AGENTS.md + CEO_GOAL.md with answers from step 2
6. `codex exec --sandbox read-only "echo ok"` → verify
7. Install fleet skill (Step 5 above)
8. Suggest the initial commit
