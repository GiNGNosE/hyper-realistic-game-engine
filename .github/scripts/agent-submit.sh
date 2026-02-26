#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  .github/scripts/agent-submit.sh --agent <agent1|agent2|agent3> --task-id <TaskID> --message "<summary>" [--task-board-version <value>] [--base <branch>] [--title "<pr title>"] [--body-file <path>] [--draft]

Behavior:
  1) Stages and commits local changes if present.
  2) Pushes current branch to origin.
  3) Creates a PR if one does not already exist for this branch.
EOF
}

AGENT=""
TASK_ID=""
MESSAGE=""
TASK_BOARD_VERSION=""
BASE_BRANCH="main"
PR_TITLE=""
PR_BODY_FILE=""
DRAFT_FLAG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)
      AGENT="${2:-}"
      shift 2
      ;;
    --message)
      MESSAGE="${2:-}"
      shift 2
      ;;
    --task-id)
      TASK_ID="${2:-}"
      shift 2
      ;;
    --task-board-version)
      TASK_BOARD_VERSION="${2:-}"
      shift 2
      ;;
    --base)
      BASE_BRANCH="${2:-}"
      shift 2
      ;;
    --title)
      PR_TITLE="${2:-}"
      shift 2
      ;;
    --body-file)
      PR_BODY_FILE="${2:-}"
      shift 2
      ;;
    --draft)
      DRAFT_FLAG="--draft"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "${AGENT}" || -z "${TASK_ID}" || -z "${MESSAGE}" ]]; then
  echo "--agent, --task-id, and --message are required." >&2
  usage
  exit 2
fi

if [[ "${AGENT}" != "agent1" && "${AGENT}" != "agent2" && "${AGENT}" != "agent3" ]]; then
  echo "Invalid --agent: ${AGENT}. Expected one of: agent1, agent2, agent3." >&2
  exit 2
fi

if [[ -z "${TASK_BOARD_VERSION}" ]]; then
  if [[ ! -f "docs/governance/agent-task-board.md" ]]; then
    echo "Missing docs/governance/agent-task-board.md and no --task-board-version provided." >&2
    exit 2
  fi
  TASK_BOARD_VERSION="$(python3 - <<'PY'
import pathlib
import re
text = pathlib.Path("docs/governance/agent-task-board.md").read_text(encoding="utf-8")
m = re.search(r"(?m)^BoardVersion:\s*(\S+)\s*$", text)
print(m.group(1) if m else "")
PY
)"
  if [[ -z "${TASK_BOARD_VERSION}" ]]; then
    echo "Could not resolve BoardVersion from docs/governance/agent-task-board.md" >&2
    exit 2
  fi
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not inside a git repository." >&2
  exit 2
fi

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "${CURRENT_BRANCH}" == "HEAD" || "${CURRENT_BRANCH}" == "main" ]]; then
  echo "Refusing to submit from detached HEAD or main. Current branch: ${CURRENT_BRANCH}" >&2
  exit 2
fi

if [[ -z "${PR_TITLE}" ]]; then
  PR_TITLE="[${AGENT}] ${MESSAGE}"
fi

if [[ -n "$(git status --porcelain)" ]]; then
  git add -A
  git commit -m "[${AGENT}] ${MESSAGE}"
fi

git push -u origin HEAD

if gh pr view --json url >/dev/null 2>&1; then
  EXISTING_URL="$(gh pr view --json url --jq '.url')"
  echo "PR already exists: ${EXISTING_URL}"
  exit 0
fi

if [[ -n "${PR_BODY_FILE}" ]]; then
  gh pr create \
    --base "${BASE_BRANCH}" \
    --title "${PR_TITLE}" \
    --body-file "${PR_BODY_FILE}" \
    ${DRAFT_FLAG}
else
  gh pr create \
    --base "${BASE_BRANCH}" \
    --title "${PR_TITLE}" \
    --body "$(cat <<EOF
OwnerAgent: ${AGENT}
TaskBoardVersion: ${TASK_BOARD_VERSION}
TaskID: ${TASK_ID}
ImplementationComplete: true

## Summary
- ${MESSAGE}

## Validation
- [ ] Relevant CI checks pass
- [ ] Reviewer-agent findings are assigned and resolved
EOF
)" \
    ${DRAFT_FLAG}
fi

