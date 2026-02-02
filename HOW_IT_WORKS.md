# Claude IDE - How It Works

## The Problem This Solves

When you use Claude in conversations, each session starts fresh. Claude has no memory of what happened in previous chats, what decisions were made, or what work was completed. This creates several problems:

1. **Lost Context**: You have to re-explain your project every time
2. **Repeated Work**: Claude might redo work it already completed
3. **No Coordination**: Multiple Claude instances (e.g., claude.ai and Emergent) can't talk to each other
4. **Drift**: Without a single source of truth, different sessions develop inconsistent understanding

## The Solution: Supabase as External Memory

This system gives Claude a persistent brain that lives outside the conversation. Instead of relying on chat history, Claude reads and writes to a Supabase database that maintains:

- **Checkpoints**: Snapshots of what was accomplished and what's next
- **Work Queue**: Tasks to be done and messages between Claude instances
- **State**: Configuration, prompts, schemas, and any key-value data
- **Artifacts**: Outputs like code, documents, and analysis results

```
┌─────────────────────────────────────────────────────────────────┐
│                         SUPABASE                                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ checkpoints  │  │  work_queue  │  │    state     │          │
│  │              │  │              │  │              │          │
│  │ "Phase 2     │  │ "Implement   │  │ "config": {} │          │
│  │  completed"  │  │  feature X"  │  │ "schema": {} │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
└─────────────────────────────────────────────────────────────────┘
         ▲                   ▲                   ▲
         │                   │                   │
         ▼                   ▼                   ▼
┌─────────────┐       ┌─────────────┐      ┌─────────────┐
│  Claude.ai  │       │  Emergent   │      │  Future     │
│  Session 1  │       │   Agent     │      │  Instance   │
└─────────────┘       └─────────────┘      └─────────────┘
```

## How a Session Works

### 1. Session Start

When you begin a conversation, Claude immediately:

```sql
SELECT * FROM context_checkpoints 
WHERE session_key = 'claude_ide_main' 
ORDER BY created_at DESC LIMIT 1;
```

This retrieves the last checkpoint, which tells Claude:
- What phase/stage the project is in
- What was just completed
- What work is pending
- Any relevant context

**Example checkpoint:**
```json
{
  "checkpoint_number": 47,
  "description": "Completed API integration for user auth",
  "state_snapshot": {
    "phase": "backend_development",
    "completed": ["database_schema", "auth_endpoints"],
    "pending": ["frontend_integration", "testing"],
    "blockers": []
  }
}
```

### 2. During Work

As Claude works, it:

1. **Checks the work queue** for assigned tasks
2. **Executes tasks** autonomously (doesn't ask permission)
3. **Stores artifacts** (code, documents) in the database or commits to GitHub
4. **Updates state** as needed

### 3. Session End (or Mid-Session)

After completing meaningful work, Claude creates a checkpoint:

```sql
INSERT INTO context_checkpoints (agent_role, session_key, description, state_snapshot)
VALUES (
  'orchestrator',
  'claude_ide_main', 
  'Implemented user authentication flow',
  '{"phase": "backend_development", "completed": ["auth_flow"], "next": "frontend"}'
);
```

This checkpoint persists even after the conversation ends. The next session picks up exactly where this one left off.

---

## Cross-Instance Communication

The real power emerges when multiple Claude instances coordinate through the shared database.

### Scenario: Claude.ai delegates to Emergent

**Step 1: Claude.ai posts a task**
```sql
INSERT INTO work_queue (source_session, target_session, task_type, payload, status)
VALUES (
  'claude_ide_main',
  'emergent_main',
  'request',
  '{"action": "implement_feature", "spec": "Build login form with validation"}',
  'pending'
);
```

**Step 2: Emergent polls for work**
```sql
SELECT * FROM work_queue 
WHERE target_session = 'emergent_main' 
AND status = 'pending';
```

**Step 3: Emergent claims and executes**
```sql
SELECT * FROM claim_work('emergent_agent', 'emergent_main');
-- Returns the task, marks it as 'claimed'
```

**Step 4: Emergent completes and responds**
```sql
UPDATE work_queue 
SET status = 'completed', 
    result = '{"files_created": ["login.tsx"], "commit": "abc123"}'
WHERE id = 'task_uuid';
```

**Step 5: Claude.ai sees the result**
Next time Claude.ai checks, it sees the completed work and continues from there.

---

## The Tables Explained

### `context_checkpoints`
**Purpose**: Save/restore session state across conversations

| Column | Purpose |
|--------|---------|
| `session_key` | Identifies which Claude instance (e.g., 'claude_ide_main') |
| `checkpoint_number` | Auto-incrementing for ordering |
| `description` | Human-readable summary of what happened |
| `state_snapshot` | JSON blob with detailed state |
| `verification_status` | Whether human verified this checkpoint |

### `work_queue`
**Purpose**: Task management and inter-instance messaging

| Column | Purpose |
|--------|---------|
| `source_session` | Who created the task |
| `target_session` | Who should execute it |
| `task_type` | 'request', 'response', 'notification', 'handoff' |
| `payload` | JSON with task details |
| `status` | 'pending' → 'claimed' → 'completed' or 'failed' |
| `priority` | 1-10 (higher = more urgent) |

### `agent_state`
**Purpose**: Versioned key-value storage

| Column | Purpose |
|--------|---------|
| `state_key` | Unique identifier (e.g., 'project_config') |
| `state_value` | JSON blob with the data |
| `version` | Increments on each update (history preserved) |
| `is_active` | Only latest version is active |

### `agent_config`
**Purpose**: System prompts and capabilities per agent role

### `artifacts`
**Purpose**: Store outputs (code, docs, analysis)

### `adrs`
**Purpose**: Architecture Decision Records for design decisions

---

## Anti-Drift Rules

"Drift" is when Claude gradually loses alignment with your intent over time. This system prevents drift through:

### 1. Single Source of Truth
All state lives in Supabase, not in Claude's "memory" of the conversation. Every session reads the same database.

### 2. Explicit State
Instead of vague context, state is stored as structured JSON:
```json
{
  "phase": "implementation",
  "completed_tasks": ["task_1", "task_2"],
  "pending_tasks": ["task_3"],
  "decisions": {
    "database": "PostgreSQL",
    "framework": "Next.js"
  }
}
```

### 3. Autonomous Execution
Claude is instructed to **execute first, report after**. This prevents drift caused by endless clarification loops:

**Bad (causes drift):**
> "Should I implement the login feature? Would you like me to use OAuth or email/password?"

**Good (prevents drift):**
> "Implemented login feature using OAuth (per ADR-0003). Created `auth.ts` and `login.tsx`. Checkpoint #48 saved."

### 4. Checkpoints as Contracts
Each checkpoint is a commitment. If something goes wrong, you can roll back to a known-good state.

---

## Practical Usage Patterns

### Pattern 1: Daily Development

**Morning (new session):**
```
You: "continue"
Claude: [Reads checkpoint #47]
        "Resuming from checkpoint #47. Last session completed auth endpoints.
         Pending: frontend integration. Executing now..."
```

**Evening (end session):**
```
You: "checkpoint"
Claude: [Creates checkpoint #48 with day's work summary]
```

### Pattern 2: Delegate to Emergent

```
You: "Have Emergent implement the dashboard component based on this spec: [spec]"
Claude: [Posts to work_queue with target_session='emergent_main']
        "Task posted to Emergent. Will check for completion on next sync."
```

Later, in Emergent:
```
Emergent: [Polls work_queue, claims task, implements, marks complete]
```

Back in Claude.ai:
```
You: "sync"
Claude: [Checks work_queue for completed tasks]
        "Emergent completed dashboard implementation. Commit: abc123. 
         Integrating into main branch..."
```

### Pattern 3: Architecture Decisions

```
You: "We're going to use PostgreSQL instead of MongoDB"
Claude: [Creates ADR entry]
        "Created ADR-0005: Use PostgreSQL for primary database.
         Updated project state. All future work will use PostgreSQL."
```

This decision persists across all sessions and instances.

---

## Security Considerations

### Service Role Key
The `service_role` key bypasses Row Level Security and has full database access. 

**DO:**
- Keep it in Claude Project instructions (Anthropic-secured)
- Rotate if accidentally exposed

**DON'T:**
- Share in public repos
- Include in frontend code
- Send via unsecured channels

### Data in Supabase
Everything in the database is readable by anyone with the service role key. Don't store:
- Passwords or secrets
- Personal identifying information
- Sensitive business data

For sensitive projects, consider:
- Enabling Row Level Security with proper policies
- Using Supabase's built-in encryption
- Self-hosting Supabase

---

## Troubleshooting

### "Claude doesn't remember anything"

1. Check that credentials in Project Instructions are correct
2. Verify `session_key` is consistent ('claude_ide_main')
3. Look at `context_checkpoints` table directly in Supabase dashboard

### "Work queue tasks not being picked up"

1. Verify `target_session` matches the receiving instance's session_key
2. Check `status` is 'pending' (not already claimed/completed)
3. Ensure receiving instance is polling the queue

### "State seems inconsistent"

1. Check if multiple sessions are using the same `session_key` (conflict)
2. Review `agent_state` version history for unexpected changes
3. Look for failed checkpoints with `verification_status = 'failed'`

---

## Quick Reference Commands

| Command | What Claude Does |
|---------|------------------|
| `continue` | Read last checkpoint, execute next pending work |
| `status` | Report current state without executing |
| `checkpoint` | Save current state to database |
| `sync` | Check work_queue for messages from other instances |

---

## Summary

This system transforms Claude from a stateless chatbot into a coordinated development agent with persistent memory. Key benefits:

1. **Continuity**: Pick up exactly where you left off
2. **Coordination**: Multiple Claude instances work together
3. **Accountability**: Every action creates a checkpoint trail
4. **Anti-drift**: Single source of truth prevents context degradation

The database is the brain. Claude is the hands. You are the director.
