# Claude Code Integration for Claude IDE

## Overview

Claude Code is Anthropic's command-line tool for agentic coding. This document explains how to integrate Claude Code as a coordinated node in your Claude IDE system, enabling it to receive tasks from Claude.ai, execute them locally, and report results back.

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│    Claude.ai    │     │    Supabase     │     │   Claude Code   │
│    (Planning)   │◄───►│ (Shared Brain)  │◄───►│   (Execution)   │
│                 │     │                 │     │                 │
│ - High-level    │     │ - Checkpoints   │     │ - Local files   │
│ - Architecture  │     │ - Work queue    │     │ - Git commits   │
│ - Coordination  │     │ - State store   │     │ - Shell commands│
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

---

## Why Claude Code?

| Capability | Benefit |
|------------|---------|
| **Local file system access** | Reads/writes your actual codebase, not artifacts |
| **Shell execution** | Runs tests, builds, linters, git directly |
| **No browser** | Works in terminal, can run in background |
| **Git-native** | Commits, branches, pushes without copy-paste |
| **Long sessions** | Maintains context through complex multi-file changes |

---

## Setup

### Prerequisites

1. Claude Code installed ([docs.anthropic.com](https://docs.anthropic.com))
2. Claude IDE Supabase database set up (see main README)
3. Environment variables configured

### Environment Variables

Create a `.env` file in your project root (add to `.gitignore`!):

```bash
# Supabase
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIs...

# Session identity
CLAUDE_CODE_SESSION=claude_code_main
```

---

## System Prompt for Claude Code

Add this to your Claude Code configuration or paste at session start:

```markdown
# Claude Code - Claude IDE Integration

You are Claude Code operating as part of a Claude IDE coordination system. Your state is stored in Supabase and you coordinate with other Claude instances (Claude.ai, other vibe coding agents) through a shared database.

## Credentials

```
SUPABASE_URL: ${SUPABASE_URL}
SUPABASE_KEY: ${SUPABASE_SERVICE_ROLE_KEY}
SESSION_KEY: claude_code_main
```

## On Session Start

1. Check for pending work assigned to you:
```bash
curl -s "${SUPABASE_URL}/rest/v1/work_queue?target_session=eq.claude_code_main&status=eq.pending&order=priority.desc,created_at.asc" \
  -H "apikey: ${SUPABASE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_KEY}"
```

2. Check last checkpoint:
```bash
curl -s "${SUPABASE_URL}/rest/v1/context_checkpoints?session_key=eq.claude_code_main&order=created_at.desc&limit=1" \
  -H "apikey: ${SUPABASE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_KEY}"
```

3. Report status and begin work. Do not ask "should I continue?"

## Claiming Work

When you find pending work, claim it atomically:
```bash
curl -s -X POST "${SUPABASE_URL}/rest/v1/rpc/claim_work" \
  -H "apikey: ${SUPABASE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"p_agent_role": "claude_code", "p_target_session": "claude_code_main"}'
```

## Completing Work

After finishing a task:
```bash
curl -s -X PATCH "${SUPABASE_URL}/rest/v1/work_queue?id=eq.WORK_UUID" \
  -H "apikey: ${SUPABASE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "status": "completed",
    "completed_at": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "result": {"commit": "abc123", "files_changed": ["src/main.py"]}
  }'
```

## Creating Checkpoints

After completing meaningful work:
```bash
curl -s -X POST "${SUPABASE_URL}/rest/v1/context_checkpoints" \
  -H "apikey: ${SUPABASE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_KEY}" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d '{
    "agent_role": "claude_code",
    "session_key": "claude_code_main",
    "description": "Implemented feature X, committed as abc123",
    "state_snapshot": {"last_commit": "abc123", "branch": "main"},
    "verification_status": "unverified"
  }'
```

## Posting Messages to Other Instances

To send work or messages to Claude.ai:
```bash
curl -s -X POST "${SUPABASE_URL}/rest/v1/work_queue" \
  -H "apikey: ${SUPABASE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "source_session": "claude_code_main",
    "target_session": "claude_ide_main",
    "task_type": "notification",
    "payload": {"event": "implementation_complete", "details": {"feature": "auth", "commit": "abc123"}},
    "status": "pending"
  }'
```

## Anti-Drift Rules

**FORBIDDEN:**
- "Should I..." / "Would you like me to..."
- Vague quantifiers ("several", "various")
- Asking permission for executable tasks

**REQUIRED:**
- Execute first, report after
- Create checkpoints after completing work
- Commit to git with descriptive messages
- Use past tense for completed actions

## Workflow

1. Check for pending work in `work_queue`
2. Claim work atomically
3. Execute locally (edit files, run commands, git commit)
4. Mark work as completed with results
5. Create checkpoint
6. Check for more work or await instructions

## Commands

- **"sync"** → Check work_queue for pending tasks
- **"status"** → Report current checkpoint and pending work
- **"checkpoint"** → Save current state to database
```

---

## Workflow Examples

### Example 1: Receiving and Executing a Task

**Claude.ai posts a task:**
```json
{
  "source_session": "claude_ide_main",
  "target_session": "claude_code_main",
  "task_type": "request",
  "payload": {
    "action": "implement",
    "spec": "Add input validation to the login form in src/components/Login.tsx",
    "acceptance_criteria": [
      "Email format validation",
      "Password minimum 8 characters",
      "Show inline error messages"
    ]
  },
  "priority": 7,
  "status": "pending"
}
```

**Claude Code:**
1. Polls work_queue, finds the task
2. Claims it (status → 'claimed')
3. Reads `src/components/Login.tsx`
4. Implements validation
5. Runs tests
6. Commits: `git commit -m "Add login form validation"`
7. Marks complete with result: `{"commit": "def456", "tests_passed": true}`
8. Creates checkpoint

### Example 2: Reporting Back to Claude.ai

After completing work, Claude Code can notify Claude.ai:

```bash
curl -s -X POST "${SUPABASE_URL}/rest/v1/work_queue" \
  -H "apikey: ${SUPABASE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "source_session": "claude_code_main",
    "target_session": "claude_ide_main",
    "task_type": "response",
    "payload": {
      "in_reply_to": "original_work_uuid",
      "status": "completed",
      "summary": "Implemented login validation with email regex and password length check",
      "commit": "def456",
      "files_changed": ["src/components/Login.tsx", "src/utils/validation.ts"],
      "tests_added": ["tests/Login.test.tsx"]
    },
    "status": "pending"
  }'
```

### Example 3: Requesting Clarification

If Claude Code needs more information:

```bash
curl -s -X POST "${SUPABASE_URL}/rest/v1/work_queue" \
  -H "apikey: ${SUPABASE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "source_session": "claude_code_main",
    "target_session": "claude_ide_main",
    "task_type": "request",
    "payload": {
      "action": "clarification_needed",
      "original_work_id": "work_uuid",
      "question": "Should password validation allow special characters? Current regex only allows alphanumeric.",
      "options": ["Allow all special chars", "Allow limited set (!@#$%)", "Keep alphanumeric only"]
    },
    "priority": 8,
    "status": "pending"
  }'
```

---

## Helper Scripts

### sync.sh - Check for pending work

```bash
#!/bin/bash
source .env

curl -s "${SUPABASE_URL}/rest/v1/work_queue?target_session=eq.claude_code_main&status=eq.pending&order=priority.desc,created_at.asc" \
  -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" | jq .
```

### checkpoint.sh - Save current state

```bash
#!/bin/bash
source .env

DESCRIPTION="$1"
COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "no-git")
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")

curl -s -X POST "${SUPABASE_URL}/rest/v1/context_checkpoints" \
  -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d "{
    \"agent_role\": \"claude_code\",
    \"session_key\": \"claude_code_main\",
    \"description\": \"${DESCRIPTION}\",
    \"state_snapshot\": {\"commit\": \"${COMMIT}\", \"branch\": \"${BRANCH}\"},
    \"verification_status\": \"unverified\"
  }" | jq .
```

### complete.sh - Mark work as done

```bash
#!/bin/bash
source .env

WORK_ID="$1"
COMMIT=$(git rev-parse HEAD)

curl -s -X PATCH "${SUPABASE_URL}/rest/v1/work_queue?id=eq.${WORK_ID}" \
  -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Content-Type: application/json" \
  -d "{
    \"status\": \"completed\",
    \"completed_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
    \"result\": {\"commit\": \"${COMMIT}\"}
  }" | jq .
```

---

## Session Key Conventions

| Session Key | Purpose |
|-------------|---------|
| `claude_ide_main` | Claude.ai orchestrator |
| `claude_code_main` | Primary Claude Code instance |
| `claude_code_{project}` | Project-specific Claude Code |
| `vibe_agent_main` | Other vibe coding agents |

---

## Best Practices

### 1. Always Commit with Context

Include work_id in commit messages for traceability:

```bash
git commit -m "Add login validation [work:abc123]"
```

### 2. Checkpoint After Git Operations

```bash
git commit -m "Feature X complete"
./checkpoint.sh "Completed feature X, commit $(git rev-parse --short HEAD)"
```

### 3. Use Structured Payloads

Always include enough context in task payloads:

```json
{
  "action": "implement",
  "spec": "Clear description of what to build",
  "files_to_modify": ["src/specific/file.ts"],
  "acceptance_criteria": ["Testable", "Criteria", "List"],
  "context": {
    "related_files": ["src/types.ts"],
    "dependencies": ["zod for validation"]
  }
}
```

### 4. Report Results with Details

```json
{
  "status": "completed",
  "commit": "abc123",
  "files_changed": ["list", "of", "files"],
  "tests_passed": true,
  "notes": "Any important observations"
}
```

---

## Troubleshooting

### "No pending work found"

- Check `target_session` matches your session key
- Verify work status is 'pending' not 'claimed'
- Check priority ordering

### "Permission denied" on Supabase

- Verify you're using `service_role` key, not `anon` key
- Check key hasn't been rotated

### Work stuck in 'claimed' status

Task was claimed but not completed. Reset it:

```bash
curl -s -X PATCH "${SUPABASE_URL}/rest/v1/work_queue?id=eq.WORK_ID" \
  -H "apikey: ${SUPABASE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"status": "pending", "claimed_by": null, "claimed_at": null}'
```

---

## Integration Diagram

```
User Request
     │
     ▼
┌─────────────┐
│  Claude.ai  │  "Implement login validation"
└──────┬──────┘
       │
       │ POST to work_queue
       ▼
┌─────────────┐
│  Supabase   │  work_queue: pending task
└──────┬──────┘
       │
       │ Poll & claim
       ▼
┌─────────────┐
│ Claude Code │  
│             │  1. Read files
│             │  2. Implement changes
│             │  3. Run tests
│             │  4. Git commit
│             │  5. Mark complete
└──────┬──────┘
       │
       │ POST completion notification
       ▼
┌─────────────┐
│  Supabase   │  work_queue: completed + result
└──────┬──────┘
       │
       │ Sync
       ▼
┌─────────────┐
│  Claude.ai  │  "Login validation complete, commit def456"
└─────────────┘
```

---

## Summary

Claude Code becomes a powerful execution node in your Claude IDE system by:

1. **Polling** `work_queue` for assigned tasks
2. **Claiming** work atomically to prevent conflicts
3. **Executing** locally with full file system and git access
4. **Reporting** results back through the shared database
5. **Checkpointing** state for session continuity

This enables a workflow where Claude.ai handles planning and coordination while Claude Code handles local execution—all synchronized through Supabase.
