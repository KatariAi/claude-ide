# Claude IDE - Cross-Instance Communication Protocol

## Overview

This document describes how multiple Claude instances communicate via the shared Supabase database. The `work_queue` table serves as the message bus.

---

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Claude IDE     │     │    Supabase     │     │   Emergent      │
│  (claude.ai)    │◄───►│   work_queue    │◄───►│   Agent         │
│                 │     │                 │     │                 │
│ session_key:    │     │                 │     │ session_key:    │
│ claude_ide_main │     │                 │     │ emergent_main   │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

---

## Message Flow

### 1. Posting a Message

Source instance creates a work_queue entry:

```sql
INSERT INTO work_queue (
    source_session,
    target_session,
    task_type,
    payload,
    priority,
    status
) VALUES (
    'claude_ide_main',           -- Who is sending
    'emergent_main',             -- Who should receive
    'request',                   -- Type of message
    '{                           -- Message content
        "action": "review_code",
        "context": {
            "file": "src/main.py",
            "changes": "Added error handling"
        },
        "reply_to": "claude_ide_main"
    }'::jsonb,
    5,                           -- Priority (1-10, higher = more urgent)
    'pending'                    -- Ready to be claimed
);
```

### 2. Receiving Messages

Target instance polls for messages:

```sql
SELECT * FROM work_queue 
WHERE target_session = 'emergent_main' 
AND status = 'pending'
ORDER BY priority DESC, created_at ASC;
```

### 3. Processing Messages

Claim the work (atomic operation prevents double-processing):

```sql
SELECT * FROM claim_work('emergent_agent', 'emergent_main');
```

### 4. Responding

Post response back to original sender:

```sql
-- Update original work as completed
UPDATE work_queue 
SET status = 'completed',
    result = '{"status": "approved", "comments": "LGTM"}'::jsonb,
    completed_at = NOW()
WHERE id = 'ORIGINAL_WORK_UUID';

-- Optionally post a new message back
INSERT INTO work_queue (
    source_session,
    target_session,
    task_type,
    payload,
    status
) VALUES (
    'emergent_main',
    'claude_ide_main',
    'response',
    '{
        "in_reply_to": "ORIGINAL_WORK_UUID",
        "action": "review_complete",
        "result": {"approved": true, "comments": "Code looks good"}
    }'::jsonb,
    'pending'
);
```

---

## Message Types

| task_type | Purpose | Expected Payload |
|-----------|---------|-----------------|
| `request` | Ask another instance to do something | `{action, context, reply_to}` |
| `response` | Reply to a request | `{in_reply_to, result}` |
| `notification` | One-way info (no reply expected) | `{event, data}` |
| `handoff` | Transfer work ownership | `{work_description, state_snapshot}` |
| `sync` | Request state synchronization | `{checkpoint_id, state_key}` |

---

## Coordination Patterns

### Pattern 1: Request-Response

```
Claude IDE                    Supabase                     Emergent
    │                            │                            │
    │──── POST request ─────────►│                            │
    │                            │◄─── Poll pending ──────────│
    │                            │──── Return work ──────────►│
    │                            │                            │
    │                            │◄─── POST response ─────────│
    │◄─── Poll pending ──────────│                            │
    │                            │                            │
```

### Pattern 2: Work Handoff

When one instance needs to hand off work to another:

```sql
-- Step 1: Create handoff message with full context
INSERT INTO work_queue (source_session, target_session, task_type, payload, status)
VALUES (
    'claude_ide_main',
    'emergent_main',
    'handoff',
    '{
        "work_description": "Implement feature X",
        "state_snapshot": {
            "current_progress": "50%",
            "completed_steps": ["design", "spec"],
            "remaining_steps": ["implement", "test"],
            "relevant_files": ["src/feature.py", "tests/test_feature.py"]
        },
        "checkpoint_reference": "checkpoint_uuid_here"
    }'::jsonb,
    'pending'
);

-- Step 2: Create checkpoint marking handoff
INSERT INTO context_checkpoints (agent_role, session_key, description, state_snapshot, verification_status)
VALUES (
    'orchestrator',
    'claude_ide_main',
    'Handed off feature X implementation to emergent_main',
    '{"status": "handed_off", "handed_to": "emergent_main", "work_id": "work_uuid"}'::jsonb,
    'verified'
);
```

### Pattern 3: Broadcast

Send to multiple instances:

```sql
-- No specific target = broadcast to all listeners
INSERT INTO work_queue (source_session, target_session, task_type, payload, status)
VALUES 
    ('claude_ide_main', 'emergent_main', 'notification', '{"event": "schema_updated"}'::jsonb, 'pending'),
    ('claude_ide_main', 'vibe_agent_1', 'notification', '{"event": "schema_updated"}'::jsonb, 'pending'),
    ('claude_ide_main', 'audit_main', 'notification', '{"event": "schema_updated"}'::jsonb, 'pending');
```

---

## Polling Strategy

### On Session Start

```sql
-- Check for any pending messages
SELECT COUNT(*) as pending_count 
FROM work_queue 
WHERE target_session = 'MY_SESSION_KEY' 
AND status = 'pending';

-- If any pending, process them
SELECT * FROM work_queue 
WHERE target_session = 'MY_SESSION_KEY' 
AND status = 'pending'
ORDER BY priority DESC, created_at ASC;
```

### Periodic Check (During Long Tasks)

Every N operations or when natural breakpoint occurs:

```sql
-- Quick check for urgent messages
SELECT * FROM work_queue 
WHERE target_session = 'MY_SESSION_KEY' 
AND status = 'pending'
AND priority >= 8
LIMIT 1;
```

---

## Error Handling

### Message Processing Failed

```sql
SELECT fail_work(
    'WORK_UUID',
    'Error: Could not parse payload'
);
-- This increments retry_count and resets to pending (up to max_retries)
```

### Message Expired/Stale

```sql
-- Cancel old unprocessed messages
UPDATE work_queue 
SET status = 'cancelled',
    error_message = 'Expired: not processed within 24 hours'
WHERE status = 'pending'
AND created_at < NOW() - INTERVAL '24 hours';
```

---

## Best Practices

1. **Always include `reply_to`** in requests so responses can be routed correctly

2. **Use meaningful task_types** - don't overload `request` for everything

3. **Keep payloads focused** - include only what's needed, reference checkpoints for large context

4. **Set appropriate priorities**:
   - 1-3: Background, can wait
   - 4-6: Normal operations
   - 7-8: Important, process soon
   - 9-10: Urgent, process immediately

5. **Create checkpoints before handoffs** - preserve state before transferring work

6. **Acknowledge receipt** - update status to 'claimed' immediately to prevent double-processing

---

## Session Registration

For discoverability, register active sessions in `agent_state`:

```sql
SELECT set_state(
    'active_sessions',
    '{
        "claude_ide_main": {
            "type": "orchestrator",
            "capabilities": ["planning", "coordination"],
            "last_seen": "2024-01-01T00:00:00Z"
        },
        "emergent_main": {
            "type": "executor",
            "capabilities": ["coding", "testing"],
            "last_seen": "2024-01-01T00:00:00Z"
        }
    }'::jsonb,
    'Registry of active Claude sessions'
);
```

Query active sessions:

```sql
SELECT get_state('active_sessions');
```
