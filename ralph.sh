#!/bin/bash
# Ralph Wiggum - Long-running AI agent loop
# Usage: ./ralph.sh [--tool claude|codex|pi] [--prompt file] [max_iterations]

set -e

# Parse arguments
TOOL="claude"  # Default tool
PROMPT_FILE=""  # Optional override; defaults per tool below
MAX_ITERATIONS=10

while [[ $# -gt 0 ]]; do
  case $1 in
    --tool)
      TOOL="$2"
      shift 2
      ;;
    --tool=*)
      TOOL="${1#*=}"
      shift
      ;;
    --prompt)
      PROMPT_FILE="$2"
      shift 2
      ;;
    --prompt=*)
      PROMPT_FILE="${1#*=}"
      shift
      ;;
    *)
      # Assume it's max_iterations if it's a number
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
      fi
      shift
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Validate tool choice and pick the default prompt file for it.
# Claude Code reads CLAUDE.md natively; Codex and pi both read AGENTS.md
# natively, so they share the tool-neutral prompt-generic.md.
case "$TOOL" in
  claude) DEFAULT_PROMPT="$SCRIPT_DIR/CLAUDE.md" ;;
  codex)  DEFAULT_PROMPT="$SCRIPT_DIR/prompt-generic.md" ;;
  pi)     DEFAULT_PROMPT="$SCRIPT_DIR/prompt-generic.md" ;;
  *)
    echo "Error: Invalid tool '$TOOL'. Must be one of: claude, codex, pi."
    exit 1
    ;;
esac
PROMPT_FILE="${PROMPT_FILE:-$DEFAULT_PROMPT}"

if [ ! -f "$PROMPT_FILE" ]; then
  echo "Error: Prompt file not found: $PROMPT_FILE"
  exit 1
fi

if ! command -v "$TOOL" >/dev/null 2>&1; then
  echo "Error: '$TOOL' is not installed or not on PATH."
  exit 1
fi
PRD_FILE="$SCRIPT_DIR/prd.json"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"

# Archive previous run if branch changed
if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")
  
  if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
    # Archive the previous run
    DATE=$(date +%Y-%m-%d)
    # Strip "ralph/" prefix from branch name for folder
    FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^ralph/||')
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"
    
    echo "Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    echo "   Archived to: $ARCHIVE_FOLDER"
    
    # Reset progress file for new run
    echo "# Ralph Progress Log" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
  fi
fi

# Track current branch
if [ -f "$PRD_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  if [ -n "$CURRENT_BRANCH" ]; then
    echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
  fi
fi

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

echo "Starting Ralph - Tool: $TOOL - Prompt: $PROMPT_FILE - Max iterations: $MAX_ITERATIONS"

for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo "==============================================================="
  echo "  Ralph Iteration $i of $MAX_ITERATIONS ($TOOL)"
  echo "==============================================================="

  # Run the selected tool with the ralph prompt.
  # Every backend must: run unattended (no permission prompts), accept the
  # prompt non-interactively, and print the agent's final message to stdout
  # so the completion signal below can be detected.
  case "$TOOL" in
    claude)
      # Claude Code: --dangerously-skip-permissions for autonomous operation, --print for output
      OUTPUT=$(claude --dangerously-skip-permissions --print < "$PROMPT_FILE" 2>&1 | tee /dev/stderr) || true
      ;;
    codex)
      # Codex CLI: `exec` is the non-interactive mode. Its progress stream echoes the
      # prompt, which contains the completion string, so grepping the transcript would
      # give a false "complete". Instead ask codex to write only the agent's final
      # message to a file (-o) and check that. The transcript still goes to the terminal.
      # The bypass flag disables both approvals and the sandbox, which Ralph needs
      # for git commits and test runs. stdin is closed so codex does not wait on it.
      LAST_MSG_FILE="$(mktemp)"
      codex exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check \
        -o "$LAST_MSG_FILE" "$(cat "$PROMPT_FILE")" < /dev/null || true
      OUTPUT=$(cat "$LAST_MSG_FILE")
      rm -f "$LAST_MSG_FILE"
      ;;
    pi)
      # pi coding agent: -p is print mode (run one prompt, print the response, exit).
      # pi has no per-tool permission prompts by design. --approve trusts the
      # project for this run so project-local settings/extensions load without
      # an interactive trust prompt. Capture stdout only, as with codex above.
      OUTPUT=$(pi -p --approve "$(cat "$PROMPT_FILE")" < /dev/null | tee /dev/stderr) || true
      ;;
  esac

  # Check for completion signal
  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    echo ""
    echo "Ralph completed all tasks!"
    echo "Completed at iteration $i of $MAX_ITERATIONS"
    exit 0
  fi
  
  echo "Iteration $i complete. Continuing..."
  sleep 2
done

echo ""
echo "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
echo "Check $PROGRESS_FILE for status."
exit 1
