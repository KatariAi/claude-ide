# Claude IDE - Capability Notification System

## Overview

When new learnings are approved and propagated, developers need to know about them **without having to check manually**. This system injects capability notifications at the end of Claude's responses when new learnings are available.

---

## How It Works

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           CLAUDE RESPONSE                               │
│                                                                         │
│   [Normal response to user's question]                                  │
│                                                                         │
│   ...                                                                   │
│                                                                         │
│   ═══════════════════════════════════════════════════════════════════   │
│   🆕 NEW CAPABILITY AVAILABLE                                           │
│   ───────────────────────────────────────────────────────────────────   │
│   Title: Batch Supabase inserts for better performance                  │
│   Type: optimization                                                    │
│   Source: Discovered by alice_dev on 2024-01-15                        │
│                                                                         │
│   When: Inserting 3+ rows to any table                                  │
│   Do: Combine into single request with JSON array body                  │
│                                                                         │
│   To activate: Say "apply learning [id]" or "show me more"              │
│   To dismiss: Say "dismiss" or ignore                                   │
│   ═══════════════════════════════════════════════════════════════════   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Database Schema Additions

Add this to your Supabase schema:

```sql
-- ============================================
-- CAPABILITY NOTIFICATIONS
-- Pending notifications for developers
-- ============================================
CREATE TABLE IF NOT EXISTS capability_notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    developer_id TEXT NOT NULL,
    learning_id UUID REFERENCES workflow_learnings(id),
    notification_type TEXT DEFAULT 'new_capability' CHECK (notification_type IN ('new_capability', 'update', 'deprecation')),
    is_read BOOLEAN DEFAULT false,
    is_dismissed BOOLEAN DEFAULT false,
    is_applied BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    read_at TIMESTAMPTZ,
    applied_at TIMESTAMPTZ
);

CREATE INDEX idx_notifications_developer ON capability_notifications(developer_id, is_read, is_dismissed);
CREATE INDEX idx_notifications_pending ON capability_notifications(developer_id, is_read, is_dismissed) WHERE is_read = false AND is_dismissed = false;

-- Get pending notifications for a developer
CREATE OR REPLACE FUNCTION get_pending_notifications(p_developer_id TEXT, p_limit INTEGER DEFAULT 3)
RETURNS TABLE (
    notification_id UUID,
    learning_id UUID,
    learning_type TEXT,
    title TEXT,
    description TEXT,
    trigger_condition TEXT,
    recommended_action TEXT,
    discovered_by TEXT,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        cn.id AS notification_id,
        wl.id AS learning_id,
        wl.learning_type,
        wl.title,
        wl.description,
        wl.trigger_condition,
        wl.recommended_action,
        wl.discovered_by,
        cn.created_at
    FROM capability_notifications cn
    JOIN workflow_learnings wl ON wl.id = cn.learning_id
    WHERE cn.developer_id = p_developer_id
    AND cn.is_read = false
    AND cn.is_dismissed = false
    AND wl.is_active = true
    ORDER BY cn.created_at DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- Mark notification as read
CREATE OR REPLACE FUNCTION mark_notification_read(p_notification_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE capability_notifications
    SET is_read = true, read_at = NOW()
    WHERE id = p_notification_id;
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Mark notification as dismissed
CREATE OR REPLACE FUNCTION dismiss_notification(p_notification_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE capability_notifications
    SET is_dismissed = true, is_read = true, read_at = NOW()
    WHERE id = p_notification_id;
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Mark notification as applied (user activated the capability)
CREATE OR REPLACE FUNCTION apply_notification(p_notification_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE capability_notifications
    SET is_applied = true, is_read = true, applied_at = NOW(), read_at = NOW()
    WHERE id = p_notification_id;
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Trigger: Create notifications for all developers when a learning is approved
CREATE OR REPLACE FUNCTION notify_all_developers_of_learning()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'approved' AND (OLD.status IS NULL OR OLD.status != 'approved') THEN
        INSERT INTO capability_notifications (developer_id, learning_id, notification_type)
        SELECT 
            dss.developer_id,
            NEW.learning_id,
            'new_capability'
        FROM developer_sync_status dss
        WHERE dss.auto_sync_enabled = true;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS on_learning_approved ON learning_submissions;
CREATE TRIGGER on_learning_approved
    AFTER INSERT OR UPDATE ON learning_submissions
    FOR EACH ROW EXECUTE FUNCTION notify_all_developers_of_learning();
```

---

## Instructions for Claude (Add to CLAUDE_PROJECT_INSTRUCTIONS.md)

Add this section to the Claude Project instructions:

```markdown
## Capability Notification Protocol

**At the END of EVERY response**, check for pending capability notifications:

```bash
curl -s -X POST "$SUPABASE_URL/rest/v1/rpc/get_pending_notifications" \
  -H "apikey: $SUPABASE_KEY" \
  -H "Authorization: Bearer $SUPABASE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"p_developer_id": "DEVELOPER_ID", "p_limit": 1}'
```

**If notifications exist**, append this block to your response:

```
═══════════════════════════════════════════════════════════════════════════
🆕 NEW CAPABILITY AVAILABLE
───────────────────────────────────────────────────────────────────────────
Title: [title from notification]
Type: [learning_type]
Source: Discovered by [discovered_by]

When: [trigger_condition]
Do: [recommended_action]

→ Say "activate [learning_id]" to start using this
→ Say "tell me more about [learning_id]" for details  
→ Say "dismiss" to hide this notification
═══════════════════════════════════════════════════════════════════════════
```

**When user says "activate [id]":**
1. Mark notification as applied
2. Confirm: "✓ Capability activated. I'll now apply this when [trigger_condition]."
3. Store in your active learnings for this session

**When user says "dismiss":**
1. Mark notification as dismissed
2. Don't show it again

**When user says "tell me more":**
1. Show full learning details including examples
2. Keep notification pending until they activate or dismiss
```

---

## Complete Flow

### 1. Admin approves a learning
```
Learning approved → Trigger fires → Creates notification for all developers
```

### 2. Developer starts Claude session
```
Claude checks pending notifications → Finds 1 new capability → Appends to first response
```

### 3. Developer sees notification
```
═══════════════════════════════════════════════════════════════════════════
🆕 NEW CAPABILITY AVAILABLE
───────────────────────────────────────────────────────────────────────────
Title: Batch Supabase inserts for better performance
Type: optimization
Source: Discovered by alice_dev

When: Inserting 3+ rows to any table
Do: Combine into single request with JSON array body

→ Say "activate abc123" to start using this
→ Say "tell me more about abc123" for details  
→ Say "dismiss" to hide this notification
═══════════════════════════════════════════════════════════════════════════
```

### 4. Developer responds
```
User: "activate abc123"
Claude: "✓ Capability activated. I'll now apply this when inserting 3+ rows to any table."
```

### 5. Later in session
```
User: "Insert these 5 records into the checkpoints table"
Claude: [Uses batch insert per the activated learning]
        "Inserted 5 checkpoints in a single batch request (using activated optimization)."
```

---

## Notification Frequency

To avoid overwhelming users:

1. **Max 1 notification per response** - Even if multiple are pending
2. **Don't repeat in same session** - Once shown, mark as read
3. **Priority order** - Show highest effectiveness_score first
4. **Cooldown** - Don't show notifications more than once per 5 responses

Add to Claude's instructions:
```markdown
**Notification rules:**
- Show max 1 notification per response
- Only check for notifications every 5th response OR at session start
- Once shown, mark as read immediately (even if not activated)
- Prioritize by effectiveness_score DESC
```

---

## Curl Commands for Claude

### Check for notifications (at session start or every 5th response)
```bash
NOTIFICATIONS=$(curl -s -X POST "$SUPABASE_URL/rest/v1/rpc/get_pending_notifications" \
  -H "apikey: $SUPABASE_KEY" \
  -H "Authorization: Bearer $SUPABASE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"p_developer_id": "'$DEVELOPER_ID'", "p_limit": 1}')

# If not empty, format and append to response
```

### Mark as read (after showing)
```bash
curl -s -X POST "$SUPABASE_URL/rest/v1/rpc/mark_notification_read" \
  -H "apikey: $SUPABASE_KEY" \
  -H "Authorization: Bearer $SUPABASE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"p_notification_id": "UUID_HERE"}'
```

### Activate capability (when user says "activate")
```bash
curl -s -X POST "$SUPABASE_URL/rest/v1/rpc/apply_notification" \
  -H "apikey: $SUPABASE_KEY" \
  -H "Authorization: Bearer $SUPABASE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"p_notification_id": "UUID_HERE"}'
```

### Dismiss (when user says "dismiss")
```bash
curl -s -X POST "$SUPABASE_URL/rest/v1/rpc/dismiss_notification" \
  -H "apikey: $SUPABASE_KEY" \
  -H "Authorization: Bearer $SUPABASE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"p_notification_id": "UUID_HERE"}'
```

---

## Registration

For notifications to work, each developer must be registered:

```bash
# Register developer (run once per developer)
curl -s -X POST "$SUPABASE_URL/rest/v1/developer_sync_status" \
  -H "apikey: $SUPABASE_KEY" \
  -H "Authorization: Bearer $SUPABASE_KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d '{
    "developer_id": "alice_dev",
    "developer_name": "Alice Smith",
    "auto_sync_enabled": true
  }'
```

Or add to CLAUDE_PROJECT_INSTRUCTIONS.md credentials section:
```
DEVELOPER_ID: alice_dev
```

---

## Summary

| Event | Action |
|-------|--------|
| Learning approved | Notifications created for all registered developers |
| Session start | Claude checks for pending notifications |
| Every 5th response | Claude checks again |
| Notification found | Appended to response with clear formatting |
| User says "activate" | Learning applied, notification marked applied |
| User says "dismiss" | Notification hidden permanently |
| User ignores | Notification marked read, won't show again this session |

**No manual checking required.** Developers are automatically informed of new capabilities as they use Claude.
