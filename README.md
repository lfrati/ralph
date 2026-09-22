# Ralph

![Ralph](ralph.webp)

Ralph is an autonomous AI agent loop that runs AI coding tools ([Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex CLI](https://developers.openai.com/codex/cli) or [pi](https://pi.dev)) repeatedly until all PRD items are complete. Each iteration is a fresh instance with clean context. Memory persists via git history, `progress.txt`, and `prd.json`.

Based on [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/).

This is a fork of [snarktank/ralph](https://github.com/snarktank/ralph) by Ryan Carson. [Read his in-depth article on how he uses Ralph](https://x.com/ryancarson/status/2008548371712135632).

## Prerequisites

- One of the following AI coding tools installed and authenticated:
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`npm install -g @anthropic-ai/claude-code`) (default)
  - [Codex CLI](https://developers.openai.com/codex/cli) (`npm install -g @openai/codex`)
  - [pi coding agent](https://pi.dev) (`npm install -g --ignore-scripts @earendil-works/pi-coding-agent`)
- `jq` installed (`brew install jq` on macOS)
- A git repository for your project

## Setup

### Option 1: Copy to your project

Copy the ralph files into your project:

```bash
# From your project root
mkdir -p scripts/ralph
cp /path/to/ralph/ralph.sh scripts/ralph/

# Copy the prompt template for your AI tool of choice:
cp /path/to/ralph/CLAUDE.md scripts/ralph/CLAUDE.md                  # For Claude Code
# OR
cp /path/to/ralph/prompt-generic.md scripts/ralph/prompt-generic.md  # For Codex or pi

chmod +x scripts/ralph/ralph.sh
```

### Option 2: Install skills globally (Claude Code)

Copy the skills to your Claude Code config for use across all projects:

```bash
cp -r skills/prd ~/.claude/skills/
cp -r skills/ralph ~/.claude/skills/
```

### Option 3: Use as Claude Code Marketplace

Add the Ralph marketplace to Claude Code:

```bash
/plugin marketplace add snarktank/ralph
```

Then install the skills:

```bash
/plugin install ralph-skills@ralph-marketplace
```

Available skills after installation:
- `/prd` - Generate Product Requirements Documents
- `/ralph` - Convert PRDs to prd.json format

Skills are automatically invoked when you ask Claude to:
- "create a prd", "write prd for", "plan this feature"
- "convert this prd", "turn into ralph format", "create prd.json"

## Workflow

### 1. Create a PRD

Use the PRD skill to generate a detailed requirements document:

```
Load the prd skill and create a PRD for [your feature description]
```

Answer the clarifying questions. The skill saves output to `tasks/prd-[feature-name].md`.

### 2. Convert PRD to Ralph format

Use the Ralph skill to convert the markdown PRD to JSON:

```
Load the ralph skill and convert tasks/prd-[feature-name].md to prd.json
```

This creates `prd.json` with user stories structured for autonomous execution.

### 3. Run Ralph

```bash
# Using Claude Code (default)
./scripts/ralph/ralph.sh [max_iterations]

# Using Codex CLI
./scripts/ralph/ralph.sh --tool codex [max_iterations]

# Using pi
./scripts/ralph/ralph.sh --tool pi [max_iterations]
```

Default is 10 iterations. Use `--tool claude|codex|pi` to select your AI coding tool. Each tool has a default prompt file (see Key Files); pass `--prompt path/to/file.md` to use a different one.

Every backend is driven the same way: run the CLI unattended with permission prompts disabled, feed it the prompt, and read the agent's final message (from stdout, or from a file the tool writes it to). Adding another tool is one more `case` branch in `ralph.sh`.

Ralph will:
1. Create a feature branch (from PRD `branchName`)
2. Pick the highest priority story where `passes: false`
3. Implement that single story
4. Run quality checks (typecheck, tests)
5. Commit if checks pass
6. Update `prd.json` to mark story as `passes: true`
7. Append learnings to `progress.txt`
8. Repeat until all stories pass or max iterations reached

## Key Files

| File | Purpose |
|------|---------|
| `ralph.sh` | The bash loop that spawns fresh AI instances (supports `--tool claude`, `codex` or `pi`) |
| `CLAUDE.md` | Prompt template for Claude Code |
| `prompt-generic.md` | Tool-neutral prompt template, used by Codex and pi (both read `AGENTS.md` natively) |
| `prd.json` | User stories with `passes` status (the task list) |
| `prd.json.example` | Example PRD format for reference |
| `progress.txt` | Append-only learnings for future iterations |
| `skills/prd/` | Skill for generating PRDs (Claude Code skill format) |
| `skills/ralph/` | Skill for converting PRDs to JSON (Claude Code skill format) |
| `.claude-plugin/` | Plugin manifest for Claude Code marketplace discovery |
| `flowchart/` | Interactive visualization of how Ralph works |

## Flowchart

[![Ralph Flowchart](ralph-flowchart.png)](https://snarktank.github.io/ralph/)

**[View Interactive Flowchart](https://snarktank.github.io/ralph/)** - Click through to see each step with animations.

The `flowchart/` directory contains the source code. To run locally:

```bash
cd flowchart
npm install
npm run dev
```

## Critical Concepts

### Each Iteration = Fresh Context

Each iteration spawns a **new AI instance** (Claude Code, Codex or pi) with clean context. The only memory between iterations is:
- Git history (commits from previous iterations)
- `progress.txt` (learnings and context)
- `prd.json` (which stories are done)

### Small Tasks

Each PRD item should be small enough to complete in one context window. If a task is too big, the LLM runs out of context before finishing and produces poor code.

Right-sized stories:
- Add a database column and migration
- Add a UI component to an existing page
- Update a server action with new logic
- Add a filter dropdown to a list

Too big (split these):
- "Build the entire dashboard"
- "Add authentication"
- "Refactor the API"

### AGENTS.md / CLAUDE.md Updates Are Critical

After each iteration, Ralph updates the relevant instructions files with learnings: `AGENTS.md` for Codex and pi, `CLAUDE.md` for Claude Code. This is key because AI coding tools automatically read these files, so future iterations (and future human developers) benefit from discovered patterns, gotchas, and conventions.

Examples of what to add:
- Patterns discovered ("this codebase uses X for Y")
- Gotchas ("do not forget to update Z when changing W")
- Useful context ("the settings panel is in component X")

### Feedback Loops

Ralph only works if there are feedback loops:
- Typecheck catches type errors
- Tests verify behavior
- CI must stay green (broken code compounds across iterations)

### Browser Verification for UI Stories

Frontend stories should include "Verify in browser" in their acceptance criteria. If the agent has a browser tool available (for example a browser MCP server or a dev-browser skill), it will navigate to the page, interact with the UI, and confirm changes work. If not, the prompt tells it to note in `progress.txt` that manual browser verification is needed.

### Stop Condition

When all stories have `passes: true`, Ralph outputs `<promise>COMPLETE</promise>` and the loop exits.

## Debugging

Check current state:

```bash
# See which stories are done
cat prd.json | jq '.userStories[] | {id, title, passes}'

# See learnings from previous iterations
cat progress.txt

# Check git history
git log --oneline -10
```

## Customizing the Prompt

After copying `CLAUDE.md` (for Claude Code) or `prompt-generic.md` (for Codex or pi) to your project, customize it for your project:
- Add project-specific quality check commands
- Include codebase conventions
- Add common gotchas for your stack

## Archiving

Ralph automatically archives previous runs when you start a new feature (different `branchName`). Archives are saved to `archive/YYYY-MM-DD-feature-name/`.

## References

- [Geoffrey Huntley's Ralph article](https://ghuntley.com/ralph/)
- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code)
- [Codex CLI documentation](https://developers.openai.com/codex/cli)
- [pi documentation](https://pi.dev)
