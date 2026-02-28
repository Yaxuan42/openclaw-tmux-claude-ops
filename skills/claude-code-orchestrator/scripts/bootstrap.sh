#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

echo "=== OpenClaw Claude Code Orchestrator — Bootstrap ==="
echo ""

errors=0
warnings=0

# --- Required tools (missing = fatal) ---
echo "Required tools:"
for tool in tmux claude openclaw rg jq python3 git; do
  if command -v "$tool" >/dev/null 2>&1; then
    version="$("$tool" --version 2>/dev/null | head -1 || echo "ok")"
    echo "  [OK] $tool → $version"
  else
    echo "  [MISSING] $tool — required; please install before using the orchestrator"
    errors=$((errors + 1))
  fi
done

echo ""

# --- Optional tools (missing = warn, non-fatal) ---
echo "Optional tools (needed for specific features):"
for tool in ssh scp npm pnpm yarn; do
  if command -v "$tool" >/dev/null 2>&1; then
    version="$("$tool" --version 2>/dev/null | head -1 || echo "ok")"
    echo "  [OK] $tool → $version"
  else
    case "$tool" in
      ssh|scp) hint="needed for --target ssh (remote execution)" ;;
      npm|pnpm|yarn) hint="needed only if you pass --lint-cmd / --build-cmd" ;;
      *) hint="" ;;
    esac
    echo "  [WARN] $tool not found — $hint"
    warnings=$((warnings + 1))
  fi
done

echo ""

# Check socket directory
SOCKET_DIR="${TMPDIR:-/tmp}/clawdbot-tmux-sockets"
if mkdir -p "$SOCKET_DIR" 2>/dev/null; then
  echo "  [OK] Socket dir writable: $SOCKET_DIR"
else
  echo "  [FAIL] Cannot create socket dir: $SOCKET_DIR"
  errors=$((errors + 1))
fi

# Check scripts exist and are executable
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for script in start-tmux-task.sh monitor-tmux-task.sh complete-tmux-task.sh wake.sh status-tmux-task.sh; do
  if [[ -x "$SCRIPT_DIR/$script" ]]; then
    echo "  [OK] $script executable"
  elif [[ -f "$SCRIPT_DIR/$script" ]]; then
    echo "  [WARN] $script exists but not executable — run: chmod +x $SCRIPT_DIR/$script"
  else
    echo "  [SKIP] $script not found (may not be created yet)"
  fi
done

echo ""

if [[ "$errors" -gt 0 ]]; then
  echo "RESULT: $errors required tool(s) missing. Fix them before running tasks."
  exit 1
fi

if [[ "$warnings" -gt 0 ]]; then
  echo "RESULT: All required checks passed ($warnings optional tool(s) not found — see above)."
else
  echo "RESULT: All checks passed."
fi

# Dry-run: create and destroy a tmux session
if [[ "$DRY_RUN" == true ]]; then
  echo ""
  echo "=== Dry-run: testing tmux session lifecycle ==="
  SOCKET="$SOCKET_DIR/clawdbot.sock"
  TEST_SESSION="cc-bootstrap-test"

  tmux -S "$SOCKET" new -d -s "$TEST_SESSION" -n shell
  echo "  [OK] Created session: $TEST_SESSION"

  if tmux -S "$SOCKET" has-session -t "$TEST_SESSION" 2>/dev/null; then
    echo "  [OK] Session exists"
  else
    echo "  [FAIL] Session not found after creation"
    exit 1
  fi

  tmux -S "$SOCKET" kill-session -t "$TEST_SESSION"
  echo "  [OK] Destroyed session: $TEST_SESSION"
  echo ""
  echo "DRY_RUN: PASSED — tmux session lifecycle works."
fi
