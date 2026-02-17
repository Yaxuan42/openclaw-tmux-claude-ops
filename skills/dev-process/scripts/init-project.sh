#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=""
PROJECT_NAME=""
PROJECT_TYPE="general"
FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    --project-name) PROJECT_NAME="$2"; shift 2 ;;
    --project-type) PROJECT_TYPE="$2"; shift 2 ;;
    --force) FORCE=true; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

[[ -n "$PROJECT_DIR" && -n "$PROJECT_NAME" ]] || {
  echo "Usage: $0 --project-dir <dir> --project-name <name> [--project-type web|general] [--force]"
  exit 1
}

# Sanitize project name: only allow alphanumeric, dash, underscore
SAFE_NAME="$(echo "$PROJECT_NAME" | sed 's/[^a-zA-Z0-9_-]/_/g')"
if [[ "$SAFE_NAME" != "$PROJECT_NAME" ]]; then
  echo "WARN: project name sanitized: '$PROJECT_NAME' → '$SAFE_NAME'"
  PROJECT_NAME="$SAFE_NAME"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/../templates"
CREATED_DATE="$(date +%Y-%m-%d)"

# Check if docs/ already exists
if [[ -d "$PROJECT_DIR/docs" && "$FORCE" != true ]]; then
  echo "ERROR: $PROJECT_DIR/docs/ already exists. Use --force to overwrite."
  exit 1
fi

# Create project directories
# Note: tests/ is NOT created here — let the Phase 3 agent create it
# based on the test strategy defined in DESIGN.md. Creating it unconditionally
# causes Phase 3 gate to fail for projects without a test runner.
mkdir -p "$PROJECT_DIR/docs"
mkdir -p "$PROJECT_DIR/src"

echo "Creating project docs for: $PROJECT_NAME ($PROJECT_TYPE)"

# sed replacement helper (macOS/GNU compatible)
do_sed() {
  local file="$1"
  if sed --version >/dev/null 2>&1; then
    # GNU sed
    sed -i "s/{{PROJECT_NAME}}/$PROJECT_NAME/g; s/{{CREATED_DATE}}/$CREATED_DATE/g; s/{{PROJECT_TYPE}}/$PROJECT_TYPE/g" "$file"
  else
    # macOS sed
    sed -i '' "s/{{PROJECT_NAME}}/$PROJECT_NAME/g; s/{{CREATED_DATE}}/$CREATED_DATE/g; s/{{PROJECT_TYPE}}/$PROJECT_TYPE/g" "$file"
  fi
}

# Copy and fill templates
copy_template() {
  local template="$1"
  local dest="$2"
  if [[ ! -f "$TEMPLATE_DIR/$template" ]]; then
    echo "WARN: template not found: $template"
    return
  fi
  cp "$TEMPLATE_DIR/$template" "$dest"
  do_sed "$dest"
  echo "  ✓ $(basename "$dest")"
}

copy_template "STATUS_TEMPLATE.md"           "$PROJECT_DIR/docs/STATUS.md"
copy_template "MRD_TEMPLATE.md"              "$PROJECT_DIR/docs/MRD.md"
copy_template "PRD_TEMPLATE.md"              "$PROJECT_DIR/docs/PRD.md"
copy_template "DESIGN_TEMPLATE.md"           "$PROJECT_DIR/docs/DESIGN.md"
copy_template "TEST_PLAN_TEMPLATE.md"        "$PROJECT_DIR/docs/TEST_PLAN.md"
copy_template "CHANGELOG_TEMPLATE.md"        "$PROJECT_DIR/docs/CHANGELOG.md"
copy_template "LESSONS_LEARNED_TEMPLATE.md"  "$PROJECT_DIR/docs/LESSONS_LEARNED.md"

# Web project: add API_CONTRACT.md
if [[ "$PROJECT_TYPE" == "web" ]]; then
  copy_template "API_CONTRACT_TEMPLATE.md"   "$PROJECT_DIR/docs/API_CONTRACT.md"
fi

# Inject CLAUDE.md rules
INJECT_CONTENT="$TEMPLATE_DIR/CLAUDE_MD_INJECT.md"
CLAUDE_MD="$PROJECT_DIR/CLAUDE.md"

if [[ -f "$CLAUDE_MD" ]]; then
  # Check if already injected
  if rg -q "Dev Process Rules" "$CLAUDE_MD" 2>/dev/null; then
    echo "  ⓘ CLAUDE.md already contains Dev Process Rules — skipping injection"
  else
    echo "" >> "$CLAUDE_MD"
    cat "$INJECT_CONTENT" >> "$CLAUDE_MD"
    echo "  ✓ CLAUDE.md (appended dev-process rules)"
  fi
else
  echo "# $PROJECT_NAME" > "$CLAUDE_MD"
  echo "" >> "$CLAUDE_MD"
  cat "$INJECT_CONTENT" >> "$CLAUDE_MD"
  echo "  ✓ CLAUDE.md (created with dev-process rules)"
fi

echo ""
echo "Project initialized:"
echo ""
echo "  $PROJECT_DIR/"
echo "  ├── docs/"
echo "  │   ├── STATUS.md"
echo "  │   ├── MRD.md"
echo "  │   ├── PRD.md"
echo "  │   ├── DESIGN.md"
echo "  │   ├── TEST_PLAN.md"
if [[ "$PROJECT_TYPE" == "web" ]]; then
echo "  │   ├── API_CONTRACT.md"
fi
echo "  │   ├── CHANGELOG.md"
echo "  │   └── LESSONS_LEARNED.md"
echo "  ├── src/"
echo "  └── CLAUDE.md"
echo ""
echo "Next step: Start Phase 1 (需求分析)"
echo "  1. Edit docs/MRD.md — define the market problem"
echo "  2. Edit docs/PRD.md — define user stories and scope"
echo "  3. Run gate check: bash $SCRIPT_DIR/phase1-gate-check.sh --project-dir $PROJECT_DIR"
