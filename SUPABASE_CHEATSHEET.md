# Claude IDE - Supabase Quick Reference

## Connection (curl)

```bash
# Base URL and headers
SUPABASE_URL="https://YOUR_PROJECT.supabase.co"
SERVICE_ROLE_KEY="your_service_role_key"

# Headers for all requests
-H "apikey: $SERVICE_ROLE_KEY" \
-H "Authorization: Bearer $SERVICE_ROLE_KEY" \
-H "Content-Type: application/json"
```

---

## Checkpoint Operations

### Read Last Checkpoint
```bash
curl -X GET "$SUPABASE_URL/rest/v1/context_checkpoints?session_key=eq.claude_ide_main&order=created_at.desc&limit=1" \
  -H "apikey: $SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY"
```

### Create Checkpoint
```bash
curl -X POST "$SUPABASE_URL/rest/v1/context_checkpoints" \
  -H "apikey: $SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d '{
    "agent_role": "orchestrator",
    "session_key": "claude_ide_main",
    "description": "Checkpoint description here",
    "state_snapshot": {"phase": "working", "current_task": "task_name"},
    "verification_status": "verified"
  }'
```

### Verify Checkpoint
```bash
curl -X PATCH "$SUPABASE_URL/rest/v1/context_checkpoints?id=eq.CHECKPOINT_UUID" \
  -H "apikey: $SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "verification_status": "verified",
    "verified_at": "2024-01-01T00:00:00Z",
    "verified_by": "human"
  }'
```

---

## Work Queue Operations

### Check Pending Work
```bash
curl -X GET "$SUPABASE_URL/rest/v1/work_queue?status=eq.pending&order=priority.desc,created_at.asc" \
  -H "apikey: $SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY"
```

### Check Messages for Session
```bash
curl -X GET "$SUPABASE_URL/rest/v1/work_queue?target_session=eq.claude_ide_main&status=eq.pending&order=created_at.asc" \
  -H "apikey: $SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY"
```

### Post Work/Message
```bash
curl -X POST "$SUPABASE_URL/rest/v1/work_queue" \
  -H "apikey: $SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d '{
    "source_session": "claude_ide_main",
    "target_session": "other_session",
    "task_type": "message",
    "payload": {"content": "Your message here", "context": {}},
    "priority": 5,
    "status": "pending"
  }'
```

### Complete Work
```bash
curl -X PATCH "$SUPABASE_URL/rest/v1/work_queue?id=eq.WORK_UUID" \
  -H "apikey: $SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "status": "completed",
    "completed_at": "2024-01-01T00:00:00Z",
    "result": {"outcome": "success", "details": {}}
  }'
```

### Claim Work (using RPC)
```bash
curl -X POST "$SUPABASE_URL/rest/v1/rpc/claim_work" \
  -H "apikey: $SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "p_agent_role": "orchestrator",
    "p_target_session": "claude_ide_main"
  }'
```

---

## State Operations

### Get State
```bash
curl -X GET "$SUPABASE_URL/rest/v1/agent_state?state_key=eq.my_key&is_active=eq.true&order=version.desc&limit=1" \
  -H "apikey: $SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY"
```

### Set State (via RPC)
```bash
curl -X POST "$SUPABASE_URL/rest/v1/rpc/set_state" \
  -H "apikey: $SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "p_state_key": "my_key",
    "p_state_value": {"data": "value"},
    "p_description": "Description of this state"
  }'
```

---

## Artifacts

### Store Artifact
```bash
curl -X POST "$SUPABASE_URL/rest/v1/artifacts" \
  -H "apikey: $SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d '{
    "artifact_type": "code",
    "name": "my_script.py",
    "content": "print(\"hello world\")",
    "metadata": {"language": "python"},
    "source_session": "claude_ide_main"
  }'
```

### Get Artifacts
```bash
curl -X GET "$SUPABASE_URL/rest/v1/artifacts?source_session=eq.claude_ide_main&order=created_at.desc" \
  -H "apikey: $SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY"
```

---

## Agent Config

### Get Agent Config
```bash
curl -X GET "$SUPABASE_URL/rest/v1/agent_config?agent_role=eq.orchestrator&is_active=eq.true" \
  -H "apikey: $SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY"
```

### Update Agent Config
```bash
curl -X PATCH "$SUPABASE_URL/rest/v1/agent_config?agent_role=eq.orchestrator" \
  -H "apikey: $SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "system_prompt": "Updated system prompt here"
  }'
```

---

## ADRs

### List ADRs
```bash
curl -X GET "$SUPABASE_URL/rest/v1/adrs?status=eq.accepted&order=adr_number.asc" \
  -H "apikey: $SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY"
```

### Create ADR
```bash
curl -X POST "$SUPABASE_URL/rest/v1/adrs" \
  -H "apikey: $SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d '{
    "adr_number": "ADR-0001",
    "title": "Use Supabase for State Management",
    "status": "accepted",
    "context": "We need persistent state across Claude sessions",
    "decision": "Use Supabase as the single source of truth",
    "consequences": "All state must be externalized to database"
  }'
```

---

## Useful Query Patterns

### Filter by JSON field
```bash
# Get checkpoints where state_snapshot contains specific phase
?state_snapshot->>phase=eq.working
```

### Multiple conditions
```bash
?status=eq.pending&priority=gte.5&order=created_at.asc
```

### Select specific columns
```bash
?select=id,task_type,payload,status
```

### Pagination
```bash
?limit=10&offset=20
```

---

## Session Keys Convention

| Session Key | Purpose |
|-------------|---------|
| `claude_ide_main` | Primary orchestrator |
| `claude_code_{id}` | Claude Code sessions |
| `vibe_{purpose}_{id}` | Vibe coding sessions |
| `audit_{id}` | Audit/review sessions |

---

## Error Handling

Check response status codes:
- `200/201` - Success
- `400` - Bad request (check JSON syntax)
- `401` - Unauthorized (check API key)
- `404` - Not found
- `409` - Conflict (duplicate key)

Always use `-w "\n%{http_code}\n"` to see status code.
