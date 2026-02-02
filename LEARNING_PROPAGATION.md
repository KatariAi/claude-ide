# Claude IDE - Learning Propagation System

## Overview

When multiple developers in your organization use Claude IDE, each discovers improvements independently. Without propagation, these learnings stay siloed. This document explains how to share learnings across all developers so everyone benefits from discoveries made by anyone.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        ORGANIZATION CANON                                │
│                    (Central Supabase Instance)                          │
│                                                                         │
│   ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐   │
│   │   workflow_     │    │    approved_    │    │     canon_      │   │
│   │   learnings     │───►│    learnings    │───►│    updates      │   │
│   │   (pending)     │    │   (vetted)      │    │  (versioned)    │   │
│   └─────────────────┘    └─────────────────┘    └─────────────────┘   │
│           ▲                                              │              │
│           │                                              ▼              │
└───────────┼──────────────────────────────────────────────┼──────────────┘
            │                                              │
   ┌────────┴────────┐                          ┌─────────┴─────────┐
   │   SUBMIT        │                          │    PULL           │
   │   Learning      │                          │    Updates        │
   └────────┬────────┘                          └─────────┬─────────┘
            │                                              │
┌───────────┴──────────────────────────────────────────────┴───────────────┐
│                                                                          │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐                │
│  │  Developer   │   │  Developer   │   │  Developer   │                │
│  │  Alice       │   │  Bob         │   │  Carol       │                │
│  │              │   │              │   │              │                │
│  │  Local       │   │  Local       │   │  Local       │                │
│  │  Supabase    │   │  Supabase    │   │  Supabase    │                │
│  └──────────────┘   └──────────────┘   └──────────────┘                │
│                                                                          │
│                         DEVELOPER INSTANCES                              │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Two Deployment Models

### Model A: Shared Supabase (Recommended for Teams)

All developers connect to the same Supabase instance. Learnings are automatically shared.

**Pros:**
- Zero propagation effort
- Real-time sharing
- Single source of truth

**Cons:**
- Requires network access to central database
- Noisy if learnings aren't curated
- Risk of low-quality learnings polluting the system

**Setup:**
1. Create one Supabase project for the organization
2. All developers use the same credentials
3. Add approval workflow (see below)

---

### Model B: Federated Supabase (For Larger Orgs or Privacy)

Each developer has their own Supabase instance. A central "canon" instance aggregates approved learnings.

**Pros:**
- Developers can experiment locally
- Only vetted learnings propagate
- Works offline

**Cons:**
- Requires sync mechanism
- More infrastructure to manage
- Learnings lag behind discoveries

**Setup:**
1. Each developer creates their own Supabase project
2. Organization maintains a central "canon" Supabase
3. Developers push learnings to canon for review
4. Approved learnings are pulled by all instances

---

## Schema Additions for Propagation

Add these tables to support learning propagation:

```sql
-- ============================================
-- LEARNING SUBMISSIONS
-- Learnings submitted for organization review
-- ============================================
CREATE TABLE IF NOT EXISTS learning_submissions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    learning_id UUID REFERENCES workflow_learnings(id),
    submitted_by TEXT NOT NULL,
    submitted_at TIMESTAMPTZ DEFAULT NOW(),
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'needs_revision')),
    reviewer TEXT,
    reviewed_at TIMESTAMPTZ,
    review_notes TEXT,
    revision_count INTEGER DEFAULT 0
);

CREATE INDEX idx_submissions_status ON learning_submissions(status, submitted_at);

-- ============================================
-- CANON VERSIONS
-- Versioned snapshots of approved learnings
-- ============================================
CREATE TABLE IF NOT EXISTS canon_versions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    version_number INTEGER NOT NULL UNIQUE,
    description TEXT,
    learnings_snapshot JSONB NOT NULL,  -- Array of approved learnings
    created_at TIMESTAMPTZ DEFAULT NOW(),
    created_by TEXT
);

CREATE INDEX idx_canon_versions ON canon_versions(version_number DESC);

-- ============================================
-- DEVELOPER SYNC STATUS
-- Tracks which version each developer has
-- ============================================
CREATE TABLE IF NOT EXISTS developer_sync_status (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    developer_id TEXT NOT NULL UNIQUE,
    current_version INTEGER NOT NULL DEFAULT 0,
    last_sync_at TIMESTAMPTZ DEFAULT NOW(),
    auto_sync_enabled BOOLEAN DEFAULT true
);

-- ============================================
-- FUNCTIONS
-- ============================================

-- Submit a learning for review
CREATE OR REPLACE FUNCTION submit_learning_for_review(
    p_learning_id UUID,
    p_submitted_by TEXT
)
RETURNS UUID AS $$
DECLARE
    submission_id UUID;
BEGIN
    INSERT INTO learning_submissions (learning_id, submitted_by)
    VALUES (p_learning_id, p_submitted_by)
    RETURNING id INTO submission_id;
    
    RETURN submission_id;
END;
$$ LANGUAGE plpgsql;

-- Approve a learning
CREATE OR REPLACE FUNCTION approve_learning(
    p_submission_id UUID,
    p_reviewer TEXT,
    p_notes TEXT DEFAULT NULL
)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE learning_submissions
    SET status = 'approved',
        reviewer = p_reviewer,
        reviewed_at = NOW(),
        review_notes = p_notes
    WHERE id = p_submission_id;
    
    -- Mark the learning as organization-approved
    UPDATE workflow_learnings wl
    SET is_active = true
    FROM learning_submissions ls
    WHERE ls.id = p_submission_id
    AND wl.id = ls.learning_id;
    
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Create a new canon version
CREATE OR REPLACE FUNCTION create_canon_version(
    p_description TEXT,
    p_created_by TEXT
)
RETURNS INTEGER AS $$
DECLARE
    new_version INTEGER;
    learnings_json JSONB;
BEGIN
    -- Get next version number
    SELECT COALESCE(MAX(version_number), 0) + 1 INTO new_version
    FROM canon_versions;
    
    -- Snapshot all approved learnings
    SELECT jsonb_agg(row_to_json(wl))
    INTO learnings_json
    FROM workflow_learnings wl
    JOIN learning_submissions ls ON ls.learning_id = wl.id
    WHERE ls.status = 'approved'
    AND wl.is_active = true;
    
    -- Create version
    INSERT INTO canon_versions (version_number, description, learnings_snapshot, created_by)
    VALUES (new_version, p_description, COALESCE(learnings_json, '[]'::jsonb), p_created_by);
    
    RETURN new_version;
END;
$$ LANGUAGE plpgsql;

-- Get learnings added since a version
CREATE OR REPLACE FUNCTION get_learnings_since_version(p_version INTEGER)
RETURNS TABLE (
    id UUID,
    learning_type TEXT,
    title TEXT,
    description TEXT,
    trigger_condition TEXT,
    recommended_action TEXT,
    examples JSONB,
    effectiveness_score INTEGER
) AS $$
DECLARE
    old_snapshot JSONB;
    old_ids UUID[];
BEGIN
    -- Get IDs from old version
    SELECT learnings_snapshot INTO old_snapshot
    FROM canon_versions
    WHERE version_number = p_version;
    
    IF old_snapshot IS NULL THEN
        old_ids := ARRAY[]::UUID[];
    ELSE
        SELECT array_agg((elem->>'id')::UUID)
        INTO old_ids
        FROM jsonb_array_elements(old_snapshot) AS elem;
    END IF;
    
    -- Return learnings not in old version
    RETURN QUERY
    SELECT 
        wl.id,
        wl.learning_type,
        wl.title,
        wl.description,
        wl.trigger_condition,
        wl.recommended_action,
        wl.examples,
        wl.effectiveness_score
    FROM workflow_learnings wl
    JOIN learning_submissions ls ON ls.learning_id = wl.id
    WHERE ls.status = 'approved'
    AND wl.is_active = true
    AND (old_ids IS NULL OR wl.id != ALL(old_ids));
END;
$$ LANGUAGE plpgsql;
```

---

## Workflow: Submitting a Learning

When Claude discovers something useful:

### 1. Record the learning locally
```bash
# Claude records the learning
curl -s -X POST "$SUPABASE_URL/rest/v1/workflow_learnings" \
  -H "apikey: $SUPABASE_KEY" \
  -H "Authorization: Bearer $SUPABASE_KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d '{
    "learning_type": "optimization",
    "title": "Batch Supabase inserts for better performance",
    "description": "When inserting multiple rows, use a single POST with an array instead of multiple calls",
    "trigger_condition": "Inserting 3+ rows to any table",
    "recommended_action": "Combine into single request with JSON array body",
    "examples": [{"context": "Creating 5 checkpoints", "outcome": "5x faster with batch insert"}],
    "discovered_by": "alice_dev",
    "discovered_in_context": "Bulk checkpoint migration task"
  }' | jq -r '.id'
```

### 2. Submit for organization review
```bash
# Submit the learning for review
LEARNING_ID="uuid-from-step-1"
curl -s -X POST "$CANON_SUPABASE_URL/rest/v1/rpc/submit_learning_for_review" \
  -H "apikey: $CANON_KEY" \
  -H "Authorization: Bearer $CANON_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"p_learning_id\": \"$LEARNING_ID\", \"p_submitted_by\": \"alice_dev\"}"
```

### 3. Reviewer approves (or requests revision)
```bash
# Admin approves the submission
SUBMISSION_ID="uuid-from-step-2"
curl -s -X POST "$CANON_SUPABASE_URL/rest/v1/rpc/approve_learning" \
  -H "apikey: $CANON_KEY" \
  -H "Authorization: Bearer $CANON_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"p_submission_id\": \"$SUBMISSION_ID\", \"p_reviewer\": \"admin\", \"p_notes\": \"Verified - significant performance improvement\"}"
```

### 4. Create new canon version (periodic)
```bash
# Create a new canon version with all approved learnings
curl -s -X POST "$CANON_SUPABASE_URL/rest/v1/rpc/create_canon_version" \
  -H "apikey: $CANON_KEY" \
  -H "Authorization: Bearer $CANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"p_description": "Weekly update - 3 new learnings", "p_created_by": "admin"}'
```

---

## Workflow: Pulling Updates

### On Session Start (add to CLAUDE_PROJECT_INSTRUCTIONS.md)

```bash
# Check current version
CURRENT_VERSION=$(curl -s "$SUPABASE_URL/rest/v1/developer_sync_status?developer_id=eq.$DEVELOPER_ID&select=current_version" \
  -H "apikey: $SUPABASE_KEY" \
  -H "Authorization: Bearer $SUPABASE_KEY" | jq -r '.[0].current_version // 0')

# Get latest canon version
LATEST_VERSION=$(curl -s "$CANON_SUPABASE_URL/rest/v1/canon_versions?order=version_number.desc&limit=1&select=version_number" \
  -H "apikey: $CANON_KEY" \
  -H "Authorization: Bearer $CANON_KEY" | jq -r '.[0].version_number // 0')

# If behind, pull new learnings
if [ "$CURRENT_VERSION" -lt "$LATEST_VERSION" ]; then
  echo "Pulling learnings from canon (v$CURRENT_VERSION → v$LATEST_VERSION)..."
  
  # Get new learnings
  curl -s -X POST "$CANON_SUPABASE_URL/rest/v1/rpc/get_learnings_since_version" \
    -H "apikey: $CANON_KEY" \
    -H "Authorization: Bearer $CANON_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"p_version\": $CURRENT_VERSION}" | jq -c '.[]' | while read learning; do
    
    # Insert into local workflow_learnings
    curl -s -X POST "$SUPABASE_URL/rest/v1/workflow_learnings" \
      -H "apikey: $SUPABASE_KEY" \
      -H "Authorization: Bearer $SUPABASE_KEY" \
      -H "Content-Type: application/json" \
      -d "$learning"
  done
  
  # Update sync status
  curl -s -X PATCH "$SUPABASE_URL/rest/v1/developer_sync_status?developer_id=eq.$DEVELOPER_ID" \
    -H "apikey: $SUPABASE_KEY" \
    -H "Authorization: Bearer $SUPABASE_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"current_version\": $LATEST_VERSION, \"last_sync_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
fi
```

---

## GitHub Integration

For organizations using GitHub, learnings can also propagate through the repo:

### 1. Export learnings to JSON
```bash
# Export approved learnings to JSON file
curl -s "$CANON_SUPABASE_URL/rest/v1/workflow_learnings?is_active=eq.true&order=effectiveness_score.desc" \
  -H "apikey: $CANON_KEY" \
  -H "Authorization: Bearer $CANON_KEY" > learnings/approved_learnings.json

git add learnings/approved_learnings.json
git commit -m "Update approved learnings - $(date +%Y-%m-%d)"
git push
```

### 2. Developers pull on session start
```bash
git pull origin main
# Claude reads learnings/approved_learnings.json
```

### 3. Submit learnings via PR
- Developer creates `learnings/submissions/learning_YYYY-MM-DD_title.json`
- Opens PR for review
- Admin merges after approval
- CI/CD imports to canon Supabase

---

## Quality Control

### Auto-Rejection Rules

Add to schema to auto-reject low-quality submissions:

```sql
-- Trigger to validate learning quality
CREATE OR REPLACE FUNCTION validate_learning_submission()
RETURNS TRIGGER AS $$
BEGIN
    -- Reject if title is too short
    IF LENGTH((SELECT title FROM workflow_learnings WHERE id = NEW.learning_id)) < 10 THEN
        NEW.status := 'rejected';
        NEW.review_notes := 'Auto-rejected: Title too short (min 10 chars)';
        NEW.reviewed_at := NOW();
        NEW.reviewer := 'system';
    END IF;
    
    -- Reject if description is too short
    IF LENGTH((SELECT description FROM workflow_learnings WHERE id = NEW.learning_id)) < 50 THEN
        NEW.status := 'rejected';
        NEW.review_notes := 'Auto-rejected: Description too short (min 50 chars)';
        NEW.reviewed_at := NOW();
        NEW.reviewer := 'system';
    END IF;
    
    -- Reject if no trigger condition
    IF (SELECT trigger_condition FROM workflow_learnings WHERE id = NEW.learning_id) IS NULL THEN
        NEW.status := 'rejected';
        NEW.review_notes := 'Auto-rejected: Missing trigger condition';
        NEW.reviewed_at := NOW();
        NEW.reviewer := 'system';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_learning_quality
    BEFORE INSERT ON learning_submissions
    FOR EACH ROW EXECUTE FUNCTION validate_learning_submission();
```

### Effectiveness Threshold

Learnings with negative effectiveness scores are auto-deactivated:

```sql
-- Auto-deactivate ineffective learnings
CREATE OR REPLACE FUNCTION check_learning_effectiveness()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.effectiveness_score < -3 THEN
        NEW.is_active := false;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER deactivate_ineffective_learnings
    BEFORE UPDATE ON workflow_learnings
    FOR EACH ROW
    WHEN (NEW.effectiveness_score < OLD.effectiveness_score)
    EXECUTE FUNCTION check_learning_effectiveness();
```

---

## Notification System (Optional)

Alert developers when new learnings are available:

```sql
-- Track unread learnings per developer
CREATE TABLE IF NOT EXISTS learning_notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    developer_id TEXT NOT NULL,
    learning_id UUID REFERENCES workflow_learnings(id),
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Trigger: Create notification for all developers when learning is approved
CREATE OR REPLACE FUNCTION notify_developers_of_learning()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'approved' AND OLD.status != 'approved' THEN
        INSERT INTO learning_notifications (developer_id, learning_id)
        SELECT developer_id, (SELECT learning_id FROM learning_submissions WHERE id = NEW.id)
        FROM developer_sync_status
        WHERE auto_sync_enabled = true;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_learning_approved
    AFTER UPDATE ON learning_submissions
    FOR EACH ROW EXECUTE FUNCTION notify_developers_of_learning();
```

---

## Summary

| Approach | Best For | Effort | Real-time |
|----------|----------|--------|-----------|
| Shared Supabase | Small teams (<10) | Low | Yes |
| Federated + Canon | Large orgs, privacy needs | Medium | No (periodic sync) |
| GitHub JSON | Git-centric teams | Medium | No (PR-based) |
| Hybrid | Enterprise | High | Partial |

**Recommended for most teams:** Start with Shared Supabase + quality control triggers. Add federation later if needed.

---

## Quick Start for Shared Model

1. All developers use the same Supabase credentials
2. Add the propagation schema (learning_submissions, etc.)
3. Add quality control triggers
4. Designate 1-2 admins as reviewers
5. Weekly: Admin creates new canon version
6. Claude auto-loads learnings on session start

That's it. Every developer's Claude now benefits from everyone's discoveries.
