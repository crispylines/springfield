# Springfield
by qrime (https://x.com/qrimeCapital)
An enhanced autonomous development loop powered by Claude Code. Describe what you want to build in one sentence, and Springfield researches, plans, builds, and reviews it — story by story.

## What is Springfield?

Springfield breaks your idea into stories and runs four agent roles to build it end-to-end:

| Phase | Agent | What it does |
|-------|-------|-------------|
| 1 | **Decomposer** | Takes your idea, researches it, generates properly-sized user stories |
| 2 | **Architect** | Reads the stories, creates a full implementation plan with interfaces & patterns |
| 3 | **Builder** | Implements stories one by one, recursively running tests and committing as it goes |
| 3 | **Reviewer** | Validates each story against acceptance criteria and architecture |

Plus:
- **Resume support** — stop and restart anytime, picks up where you left off
- **Rollback on failure** — 3 failed attempts triggers git rollback + user prompt
- **Architecture-first** — builder follows a plan instead of going blind
- **Two-pass validation** — builder self-checks, then reviewer validates

## Prerequisites

- **Claude Code CLI** — the AI engine that powers the loop
- **Git** — for version control, checkpoints, and rollback
- **Node.js** — for the projects Springfield builds
- **Python 3** — used by the bash script for JSON parsing (Mac/Linux only)

## Setting Up Claude Code

Springfield uses the Claude Code CLI under the hood. **No API key is stored in this repo** — each user authenticates with their own account.

### 1. Install Claude Code CLI

```bash
npm install -g @anthropic-ai/claude-code
```

### 2. Authenticate (one-time setup)

Run `claude` in your terminal:

```bash
claude
```

This will open your browser to log in with your Anthropic account (or prompt for an API key). Once authenticated, your credentials are stored locally on your machine — you won't need to log in again.

### 3. Verify it works

```bash
claude -p "Say hello"
```

If you get a response, you're good to go. Springfield will use this same `claude` command behind the scenes.

> **Note:** Springfield runs Claude with the `--dangerously-skip-permissions` flag, which allows Claude to read/write files, run commands, and make git commits autonomously. This is required for the loop to work without manual approval at each step.

## Quick Start

### 1. Clone the repo

```bash
git clone https://github.com/your-username/springfield.git
cd springfield
```

### 2. Run it

**Windows (PowerShell):**
```powershell
.\scripts\springfield\springfield.ps1
```

**Mac/Linux (Bash):**
```bash
chmod +x scripts/springfield/springfield.sh
./scripts/springfield/springfield.sh
```

### 3. Answer two questions

```
What do you want to build? (1 sentence): A real-time crypto dashboard with price alerts
Any reference URLs or docs? (comma-separated, or Enter to skip): https://docs.coingecko.com/v3
```

### 4. Watch it work

Springfield will:
1. Research your idea and generate user stories (`prd.json`)
2. Create an architecture plan (`architecture.md`)
3. Build each story, run tests, commit
4. Review each story for quality
5. Continue until all stories pass

## Visual Dashboard

Springfield includes a pixel art dashboard that shows your agents working in real-time. It launches automatically when you start the loop, but you can also run it standalone:

```bash
# From the project root, start a local server
python -m http.server 3333       # Windows
python3 -m http.server 3333      # Mac/Linux

# Then open in your browser
# http://localhost:3333/dashboard/
```

**Keyboard shortcuts (in the browser):**
- **D** — toggle demo mode (cycles through all animations with fake data)
- **B** — toggle debug overlay (shows bounding boxes and anchor points)

To stop the server, press `Ctrl+C` in the terminal.

> **Tip:** To skip the dashboard when running the loop:
> ```powershell
> # Windows (PowerShell)
> .\scripts\springfield\springfield.ps1 -NoDashboard
>
> # Mac/Linux (Bash)
> ./scripts/springfield/springfield.sh --no-dashboard
> ```

## Usage Options

```powershell
# Default: 40 max iterations
.\scripts\springfield\springfield.ps1

# Custom iteration limit
.\scripts\springfield\springfield.ps1 -MaxIterations 50

# Run without the visual dashboard
.\scripts\springfield\springfield.ps1 -NoDashboard

# Bash equivalent
./scripts/springfield/springfield.sh 50

# Bash without dashboard
./scripts/springfield/springfield.sh --no-dashboard
```

## Resuming

If you stop the loop (Ctrl+C) or it hits max iterations, just run the script again. It detects existing progress:

- If `prd.json` exists with stories — skips Decomposer phase
- If `architecture.md` exists — skips Architect phase
- Picks up at the next unfinished story in the build loop

## File Structure

```
scripts/springfield/
├── springfield.ps1        # Main orchestrator (PowerShell)
├── springfield.sh         # Main orchestrator (Bash)
├── prompts/
│   ├── decomposer.md      # Decomposer agent instructions
│   ├── architect.md        # Architect agent instructions
│   ├── builder.md          # Builder agent instructions
│   └── reviewer.md         # Reviewer agent instructions
├── prd.json               # User stories (generated by Decomposer)
├── progress.txt           # Learnings log (all agents write here)
├── research.md            # Research findings (generated by Decomposer)
└── architecture.md        # Implementation plan (generated by Architect)
```

## How Stories Work

Each story in `prd.json` has these fields:

| Field | Purpose |
|-------|---------|
| `passes` | Builder sets `true` when tests pass |
| `reviewed` | Reviewer sets `true` when quality is validated |
| `attempts` | How many times the builder has tried |
| `blocked` | Set `true` if story fails 3 times and user chooses to skip |
| `reviewNotes` | Reviewer feedback (read by builder on retry) |
| `lastError` | Last error message for debugging |

## Failure Handling

When a story fails 3 times:

1. Git rolls back to the checkpoint before that story
2. The script asks you:
   - **(1) Continue** — marks the story as blocked, moves to the next one
   - **(2) Stop** — exits so you can debug manually
3. Restart the script after debugging to resume

## Writing Good Descriptions

The quality of your one-sentence description matters:

```
Bad:  "Build an app"
Good: "A real-time Solana token dashboard with price charts, watchlists, and paper trading"

Bad:  "Make a website"
Good: "A portfolio website with blog, project showcase, and contact form using Next.js"
```

Adding reference URLs helps the Decomposer research effectively:
```
References: https://api.coingecko.com/api/v3, https://nextjs.org/docs
```

## Starting Fresh

To start a completely new project, delete the generated files:

```bash
# Remove generated files (keeps prompts and scripts)
rm scripts/springfield/prd.json scripts/springfield/research.md scripts/springfield/architecture.md
# Reset progress.txt to template (or delete it)
```

Then run the script again.

## Credits

Inspired by the [Ralph Loop](https://ampcode.com/looping) concept from AmpCode.
