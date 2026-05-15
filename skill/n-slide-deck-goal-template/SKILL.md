---
name: n-slide-deck-goal-template
description: Universal copy-paste /goal prompt template for producing an N-slide 16:9 deck with OpenRouter image generation, using slide 1 as the visual anchor and generating slides 2..N in parallel.
version: 1.0.0
author: pawel-cell
license: MIT
metadata:
  hermes:
    tags: [presentations, slide-deck, goal, openrouter, image-generation]
    related_skills: [openrouter-image-generation]
---

# /goal Prompt — N-Slide Deck Universal Template

Fill in the bracketed fields, then copy-paste the `/goal` block into a Hermes CLI session.

──────────────────────────────────────────────────────────────────────
Fill these in first
──────────────────────────────────────────────────────────────────────

[TOPIC]        → what the deck is about, e.g. "Hermes Agents"
[N]            → number of slides, e.g. 5
[N-1]          → [N] minus one; count of slides 2..N
[OUTPUT_DIR]   → absolute output path, e.g.
                 ~/Downloads/Deliverables/2026-05-15-video/deck/
[IMAGE_MODEL]  → image model string. Use ONE of the following only:
                 - google/gemini-3.1-flash-image-preview
                 - openai/gpt-5.4-image-2
DECK CONTENT   → fill the block near the bottom with one concept per slide:
                 headline + supporting visual

──────────────────────────────────────────────────────────────────────
Required setup before pasting the /goal line
──────────────────────────────────────────────────────────────────────

1. Install the OpenRouter image generation skill first.
   This `/goal` will fail without it.

   hermes skills install openrouter-image-generation

   Or, if you have the SKILL.md file locally:

   hermes skills install file:///absolute/path/to/SKILL.md

   If you have it via URL:

   hermes skills install https://path/to/SKILL.md

   Verify it loaded:

   hermes skills list | grep openrouter-image-generation

2. Export your OpenRouter API key in the same shell:

   export OPENROUTER_API_KEY=sk-or-v1-...

3. Attach the reference design image to the chat BEFORE pasting the `/goal` line.

   In the CLI:

   /image /path/to/reference.png

   In a messaging gateway: drop the image as an attachment, then send the `/goal` text in the next message.

If you skip step 1, the agent may try to generate images with the wrong tool, hallucinate `/mnt/data/` paths, or burn turns figuring it out. Do not skip step 1.

──────────────────────────────────────────────────────────────────────
Copy everything below this line into Hermes
──────────────────────────────────────────────────────────────────────

```text
/goal You are a senior presentation designer. Produce a complete
[N]-slide deck about [TOPIC] at 16:9 aspect ratio. The user has
attached a reference image in this conversation that defines the
visual system: palette, typography vibe, layout grid, mood, texture.
Treat that reference as the single source of truth for style — every
slide must look like it belongs in the same deck as the reference.

MANDATORY: use the openrouter-image-generation skill for every image.
Load it now if it isn't loaded. Do NOT use any other image tool, do
NOT use the openrouter:image_generation server tool, and do NOT
hallucinate /mnt/data/ paths. The [IMAGE_MODEL] value MUST be exactly
one of:
    - google/gemini-3.1-flash-image-preview
    - openai/gpt-5.4-image-2
No other models are permitted for this deck. Use the helper:

    python3 scripts/genimg.py "<prompt>" --model [IMAGE_MODEL] --out <path>

Output directory: [OUTPUT_DIR]
Create it if missing. Name files slide-1.png through slide-[N].png.

EXECUTION ORDER — this is the whole point of using /goal:

STEP 1 — Establish the visual system.
  Generate SLIDE 1 FIRST, alone. Slide 1 is the title / cover slide
  for "[TOPIC]". Bake the reference image's style into the prompt:
  name its palette, typography feel, composition, texture, lighting,
  and any signature motif you see. Mention "ultra-wide 16:9
  composition" in the prompt body because chat-completions ignores
  size params and prompt-side hints work better. After it is saved,
  verify the file with `file` and `ls -la`. This slide is the visual
  contract for the rest of the deck.

STEP 2 — Fan out slides 2-[N] concurrently using slide 1 as the
visual anchor.
  Generate slides 2 through [N] in PARALLEL via [N-1] concurrent
  terminal(background=true) calls to scripts/genimg.py. Each prompt
  must reference the same style descriptors used in slide 1 verbatim:
  palette names, type style, layout grid, texture, lighting, and
  signature motif. This makes the deck read as one coherent system,
  not [N] unrelated lookalikes.

DECK CONTENT — one concept per slide. Use a short headline and a
supporting visual. Keep body text minimal because image models corrupt
long copy. Fill one line block per slide; keep the last slide as the CTA.

  Slide 1 — Title:           "[DECK TITLE]"
                             Subtitle: "[ONE-LINE SUBTITLE]"
  Slide 2 — [SLIDE LABEL]:   "[HEADLINE, <= 5 WORDS]"
                             Visual: [SUPPORTING VISUAL IDEA]
  Slide 3 — [SLIDE LABEL]:   "[HEADLINE, <= 5 WORDS]"
                             Visual: [SUPPORTING VISUAL IDEA]
  ...   repeat for each slide up to [N]-1
  Slide [N] — Call to action: "[HEADLINE, <= 5 WORDS]"
                             Visual: [SUPPORTING VISUAL IDEA]

CONSTRAINTS:
  - Every image is 16:9. State that in every prompt.
  - Headline text on slides is fine when it is <= 5 words.
  - Avoid paragraphs inside the image. Text renders unreliably past that.
  - Re-use exact style language across all [N] prompts.
  - Inconsistent descriptors = inconsistent deck.
  - If a slide comes back off-style, regenerate it with the style
    language strengthened, not the headline reworded.
  - The --model flag passed to genimg.py MUST be either
    google/gemini-3.1-flash-image-preview or openai/gpt-5.4-image-2.

GOAL CRITERIA — the judge will check this exactly:
  All [N] files exist at [OUTPUT_DIR] named slide-1.png through
  slide-[N].png, each > 50 KB, each confirmed as "PNG image data"
  via the `file` command, and the final assistant message lists the
  [N] absolute paths plus a one-line note confirming slides 2-[N]
  referenced slide 1's style.

WHEN DONE, print the [N] absolute paths in plain text. Do not use
MEDIA: tags — this is the CLI. Do not declare success until every file
passes the `file` check.
```

──────────────────────────────────────────────────────────────────────
Why this works
──────────────────────────────────────────────────────────────────────

- `/goal` keeps Hermes running across turns until all [N] PNGs land. No babysitting, no "continue" loops.
- Slide 1 first establishes the look. The next [N-1] prompts copy slide 1's style language, which creates a design system from a single anchor.
- Slides 2-[N] fan out in parallel because image generation is I/O-bound and the OpenRouter API is safe for this concurrency pattern.
- Hard, file-grep-able goal criteria let the judge model decide "done" without hallucinating.
- Mandatory skill load blocks the most common failure mode: wrong tool path, fake file paths, and missing output files.
