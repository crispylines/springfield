<p align="center">
  <img src="assets/springfield-logo.png" alt="Springfield" width="480" />
</p>

<p align="center">
  <strong>Describe it. Springfield builds it.</strong><br/>
  An autonomous development loop powered by Claude Code — from idea to working app.
</p>

<p align="center">
  <a href="#quick-start">Quick Start</a> &nbsp;·&nbsp;
  <a href="#how-it-works">How It Works</a> &nbsp;·&nbsp;
  <a href="#visual-dashboard">Dashboard</a> &nbsp;·&nbsp;
  <a href="#usage-options">Options</a>
</p>

---

## What is Springfield?

You describe what you want to build. Springfield researches, plans, builds, and reviews it — story by story — with no manual intervention.

Four agents work together in sequence:

```
  YOU                                                          WORKING APP
   |                                                               ^
   |  "A crypto dashboard with real-time prices"                   |
   v                                                               |
┌──────────────┐   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│  DECOMPOSER  │──>│  ARCHITECT   │──>│   BUILDER    │──>│   REVIEWER   │
│              │   │              │   │              │   │              │
│  Researches  │   │  Creates     │   │  Implements  │   │  Validates   │
│  & generates │   │  the plan    │   │  story by    │   │  quality &   │
│  stories     │   │  & design    │   │  story       │   │  correctness │
└──────────────┘   └──────────────┘   └──────────────┘   └──────────────┘
                                            |                   |
                                            └───── retry loop ──┘
```

**Key features:**
- **Resume anytime** — stop and restart, it picks up where you left off
- **Auto-rollback** — 3 failed attempts triggers git rollback + your choice to skip or debug
- **Architecture-first** — builder follows a plan, not guesswork
- **Design-aware** — generates distinctive visual identities, not generic UIs
- **Two-pass validation** — builder self-checks, then reviewer validates

---

## Prerequisites

| Requirement | What it's for |
|------------|---------------|
| [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) | The AI engine powering the agents |
| Git | Version control, checkpoints, rollback |
| Node.js | For the projects Springfield builds |
| Python 3 | JSON parsing in the bash script (Mac/Linux only) |

---

## Quick Start

### 1. Install & authenticate Claude Code

```bash
npm install -g @anthropic-ai/claude-code
claude          # opens browser to log in (one-time)
claude -p "Say hello"   # verify it works
```

### 2. Clone & run

**Windows (PowerShell):**
```powershell
git clone https://github.com/crispylines/springfield.git
cd springfield
.\scripts\springfield\springfield.ps1
```

**Mac / Linux:**
```bash
git clone https://github.com/crispylines/springfield.git
cd springfield
chmod +x scripts/springfield/springfield.sh
./scripts/springfield/springfield.sh
```

### 3. Answer a few questions

```
Describe your project in a few sentences:
> A real-time crypto dashboard that shows new PumpFun token launches
> with filtering by age, market cap, and search

Any reference URLs or docs? (comma-separated, or Enter to skip):
> https://pumpportal.fun/data-api

Springfield has a few follow-up questions:

  Q1: What visual style do you want?
  > dark theme, neon accents, data-dense layout like a trading terminal

  Q2: What are the most important user interactions?
  > click tokens to see details, filter by criteria, search by name

  Q3: Any technical preferences or constraints?
  > use Tailwind, WebSocket for real-time data
```

### 4. Watch it work

Springfield will:
1. Research your idea and generate user stories
2. Create an architecture + design plan
3. Build each story, run tests, commit
4. Review each story for quality
5. Repeat until all stories pass

> **Note:** Springfield runs Claude with `--dangerously-skip-permissions`, which allows it to read/write files, run commands, and commit autonomously. This is required for the loop to run without manual approval at each step.

---

## How It Works

### The four phases

| # | Phase | Agent | Output |
|---|-------|-------|--------|
| 1 | **Research & Decompose** | Decomposer | `prd.json` + `research.md` — user stories with design direction |
| 2 | **Plan** | Architect | `architecture.md` — implementation plan, interfaces, design system |
| 3 | **Build** | Builder | Code, tests, commits — one story at a time |
| 4 | **Review** | Reviewer | Approve or reject — rejected stories go back to the builder |

### Story lifecycle

```
  pending ──> building ──> self-check ──> review
                 ^                          |
                 |        rejected          |
                 └──────────────────────────┘
                                            |
                                        approved ──> next story
```

Each story tracks: `passes`, `reviewed`, `attempts`, `blocked`, `reviewNotes`, `lastError`.

### Failure handling

When a story fails 3 times:
1. Git rolls back to the pre-story checkpoint
2. You choose: **(1) Skip** it and continue, or **(2) Stop** to debug manually
3. Restart the script after debugging — it resumes automatically

---

## Visual Dashboard

Springfield includes a pixel art dashboard that shows your agents working in real-time. It launches automatically with the loop.

**Run it standalone:**
```bash
python -m http.server 3333        # Windows
python3 -m http.server 3333       # Mac/Linux
# open http://localhost:3333/dashboard/
```

**Keyboard shortcuts:**
| Key | Action |
|-----|--------|
| `D` | Toggle demo mode (cycles animations with fake data) |
| `B` | Toggle debug overlay (bounding boxes and anchors) |

---

## Usage Options

```powershell
# Windows (PowerShell)
.\scripts\springfield\springfield.ps1                    # default: 40 iterations
.\scripts\springfield\springfield.ps1 -MaxIterations 50  # custom limit
.\scripts\springfield\springfield.ps1 -NoDashboard       # skip visual dashboard

# Mac / Linux (Bash)
./scripts/springfield/springfield.sh                     # default: 40 iterations
./scripts/springfield/springfield.sh 50                  # custom limit
./scripts/springfield/springfield.sh --no-dashboard      # skip visual dashboard
```

---

## Resuming a Run

Stop the loop anytime (`Ctrl+C`) and restart — it detects existing progress:

| File exists? | What happens |
|-------------|-------------|
| `prd.json` | Skips Decomposer (stories already generated) |
| `architecture.md` | Skips Architect (plan already created) |
| Neither | Starts from scratch |

The build loop picks up at the next unfinished story automatically.

### Starting fresh

```bash
rm scripts/springfield/prd.json scripts/springfield/research.md scripts/springfield/architecture.md
```

---

## Writing Good Descriptions

The quality of your input directly affects the output:

```
Bad:  "Build an app"
Good: "A real-time Solana token dashboard with price charts,
       watchlists, and paper trading"

Bad:  "Make a website"
Good: "A portfolio site with blog, project showcase, and contact
       form using Next.js with a minimal dark theme"
```

> **Tip:** Adding reference URLs helps the Decomposer research effectively:
> `https://api.coingecko.com/api/v3, https://nextjs.org/docs`

---

## File Structure

```
scripts/springfield/
├── springfield.ps1          # Orchestrator (PowerShell)
├── springfield.sh           # Orchestrator (Bash)
├── prompts/
│   ├── decomposer.md        # Story generation instructions
│   ├── architect.md          # Architecture planning instructions
│   ├── builder.md            # Implementation instructions
│   ├── reviewer.md           # Review & validation instructions
│   └── followup.md           # Follow-up question generator
├── prd.json                  # Generated user stories
├── progress.txt              # Shared learning log
├── research.md               # Research findings (generated)
└── architecture.md           # Implementation plan (generated)
```

---

<p align="center">
  <sub>Inspired by the <a href="https://ampcode.com/looping">Ralph Loop</a> concept from AmpCode.</sub><br/>
  <sub>Built by <a href="https://x.com/qrimeCapital">qrime</a></sub>
</p>
