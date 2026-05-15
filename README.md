# Hermes CEO → Codex CTO

A copy-pasteable playbook + bootstrapper for using **Hermes Agent as
the CEO/orchestrator** and **OpenAI's Codex CLI as the CTO/executor**
in any git repo.

- **Hermes** owns the goal, memory, scheduling, review.
- **Codex** owns code edits inside one scoped handoff at a time.
- They talk through two files: `.agents/CTO_HANDOFF.md` in,
  `.agents/last_report.md` out.

Full protocol → [`GUIDEBOOK.md`](./GUIDEBOOK.md)

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
  > .agents/last_report.md 2>&1
```

That's the manual loop. The Hermes skill below automates it.

## Install the Hermes skills

Two skills, separated by role:

| Skill                            | Use when                                              |
|----------------------------------|-------------------------------------------------------|
| `hermes-ceo-codex-cto-install`   | First-time bootstrap of the pattern in a repo         |
| `hermes-ceo-codex-cto-fleet`     | Day-to-day: delegate, parallel worktrees, cron, review |

Install both:

```bash
# Clone this repo somewhere
git clone https://github.com/pawel-cell/Hermes-CEO.git ~/Hermes-CEO

# Drop both skills into your Hermes skill tree
mkdir -p ~/.hermes/skills/orchestration
cp -r ~/Hermes-CEO/skill/hermes-ceo-codex-cto-install \
      ~/Hermes-CEO/skill/hermes-ceo-codex-cto-fleet \
      ~/.hermes/skills/orchestration/
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

## Repo contents

| File                                   | Purpose                                                  |
|----------------------------------------|----------------------------------------------------------|
| `GUIDEBOOK.md`                         | Full protocol: templates, delegation loop, parallelism   |
| `install.sh`                           | Bootstrapper — preflight + Codex install + scaffolding   |
| `skill/hermes-ceo-codex-cto-install/`  | Hermes skill: first-time bootstrap                       |
| `skill/hermes-ceo-codex-cto-fleet/`    | Hermes skill: day-to-day fleet operations                |

## License

MIT
