-- ============================================
-- Claude IDE - Supabase Schema
-- Run this in the Supabase SQL Editor
-- ============================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- CONTEXT CHECKPOINTS
-- Stores session state across Claude instances
-- ============================================
CREATE TABLE IF NOT EXISTS context_checkpoints (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    checkpoint_number SERIAL,
    agent_role TEXT NOT NULL,
    session_key TEXT NOT NULL,
    description TEXT,
    state_snapshot JSONB DEFAULT '{}'::jsonb,
    verification_status TEXT DEFAULT 'unverified' CHECK (verification_status IN ('unverified', 'verified', 'failed')),
    verified_at TIMESTAMPTZ,
    verified_by TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_checkpoints_session ON context_checkpoints(session_key, created_at DESC);
CREATE INDEX idx_checkpoints_status ON context_checkpoints(verification_status);

-- ============================================
-- WORK QUEUE
-- Cross-instance task/message passing
-- ============================================
CREATE TABLE IF NOT EXISTS work_queue (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    source_session TEXT,
    target_session TEXT,
    task_type TEXT NOT NULL,
    payload JSONB DEFAULT '{}'::jsonb,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'claimed', 'in_progress', 'completed', 'failed', 'cancelled')),
    priority INTEGER DEFAULT 5,
    claimed_by TEXT,
    claimed_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    result JSONB,
    error_message TEXT,
    retry_count INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 3,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_work_queue_status ON work_queue(status, priority DESC, created_at);
CREATE INDEX idx_work_queue_target ON work_queue(target_session, status);
CREATE INDEX idx_work_queue_source ON work_queue(source_session);

-- ============================================
-- AGENT STATE
-- Versioned key-value storage for prompts, schemas, etc.
-- ============================================
CREATE TABLE IF NOT EXISTS agent_state (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    state_key TEXT NOT NULL,
    state_value JSONB NOT NULL,
    version INTEGER DEFAULT 1,
    description TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(state_key, version)
);

CREATE INDEX idx_agent_state_key ON agent_state(state_key, is_active, version DESC);

-- ============================================
-- AGENT CONFIG
-- System prompts and configuration per agent role
-- ============================================
CREATE TABLE IF NOT EXISTS agent_config (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    agent_role TEXT NOT NULL UNIQUE,
    system_prompt TEXT NOT NULL,
    capabilities JSONB DEFAULT '[]'::jsonb,
    constraints JSONB DEFAULT '[]'::jsonb,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_agent_config_role ON agent_config(agent_role, is_active);

-- ============================================
-- ARTIFACTS
-- Output storage with metadata
-- ============================================
CREATE TABLE IF NOT EXISTS artifacts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    artifact_type TEXT NOT NULL,
    name TEXT NOT NULL,
    content TEXT,
    content_hash TEXT,
    metadata JSONB DEFAULT '{}'::jsonb,
    source_session TEXT,
    source_work_id UUID REFERENCES work_queue(id),
    git_commit_sha TEXT,
    git_path TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_artifacts_type ON artifacts(artifact_type, created_at DESC);
CREATE INDEX idx_artifacts_source ON artifacts(source_session);

-- ============================================
-- ADRS (Architecture Decision Records)
-- ============================================
CREATE TABLE IF NOT EXISTS adrs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    adr_number TEXT NOT NULL UNIQUE,
    title TEXT NOT NULL,
    status TEXT DEFAULT 'proposed' CHECK (status IN ('proposed', 'accepted', 'deprecated', 'superseded')),
    context TEXT,
    decision TEXT,
    consequences TEXT,
    superseded_by TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_adrs_status ON adrs(status);

-- ============================================
-- WORKFLOW LEARNINGS
-- Patterns and improvements discovered by Claude
-- ============================================
CREATE TABLE IF NOT EXISTS workflow_learnings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    learning_type TEXT NOT NULL CHECK (learning_type IN ('pattern', 'anti_pattern', 'optimization', 'tool_usage', 'communication', 'error_recovery')),
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    trigger_condition TEXT,  -- When to apply this learning
    recommended_action TEXT, -- What to do when triggered
    examples JSONB DEFAULT '[]'::jsonb,
    effectiveness_score INTEGER DEFAULT 0, -- Track if this learning helps
    discovered_by TEXT,      -- Which session discovered this
    discovered_in_context TEXT, -- What task led to this discovery
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_workflow_learnings_type ON workflow_learnings(learning_type, is_active);
CREATE INDEX idx_workflow_learnings_active ON workflow_learnings(is_active, effectiveness_score DESC);

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

-- Get last verified checkpoint for a session
CREATE OR REPLACE FUNCTION get_last_verified_checkpoint(p_session_key TEXT)
RETURNS TABLE (
    id UUID,
    checkpoint_number INTEGER,
    agent_role TEXT,
    session_key TEXT,
    description TEXT,
    state_snapshot JSONB,
    verification_status TEXT,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        cc.id,
        cc.checkpoint_number,
        cc.agent_role,
        cc.session_key,
        cc.description,
        cc.state_snapshot,
        cc.verification_status,
        cc.created_at
    FROM context_checkpoints cc
    WHERE cc.session_key = p_session_key
    AND cc.verification_status = 'verified'
    ORDER BY cc.created_at DESC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;

-- Create a new checkpoint
CREATE OR REPLACE FUNCTION create_checkpoint(
    p_agent_role TEXT,
    p_session_key TEXT,
    p_description TEXT,
    p_state_snapshot JSONB
)
RETURNS UUID AS $$
DECLARE
    new_id UUID;
BEGIN
    INSERT INTO context_checkpoints (agent_role, session_key, description, state_snapshot)
    VALUES (p_agent_role, p_session_key, p_description, p_state_snapshot)
    RETURNING id INTO new_id;
    
    RETURN new_id;
END;
$$ LANGUAGE plpgsql;

-- Claim work from queue (atomic operation)
CREATE OR REPLACE FUNCTION claim_work(p_agent_role TEXT, p_target_session TEXT DEFAULT NULL)
RETURNS TABLE (
    id UUID,
    task_type TEXT,
    payload JSONB,
    source_session TEXT
) AS $$
DECLARE
    work_id UUID;
BEGIN
    -- Atomically claim the highest priority pending work
    UPDATE work_queue wq
    SET 
        status = 'claimed',
        claimed_by = p_agent_role,
        claimed_at = NOW(),
        updated_at = NOW()
    WHERE wq.id = (
        SELECT wq2.id
        FROM work_queue wq2
        WHERE wq2.status = 'pending'
        AND (p_target_session IS NULL OR wq2.target_session = p_target_session)
        ORDER BY wq2.priority DESC, wq2.created_at
        LIMIT 1
        FOR UPDATE SKIP LOCKED
    )
    RETURNING wq.id INTO work_id;
    
    IF work_id IS NULL THEN
        RETURN;
    END IF;
    
    RETURN QUERY
    SELECT wq.id, wq.task_type, wq.payload, wq.source_session
    FROM work_queue wq
    WHERE wq.id = work_id;
END;
$$ LANGUAGE plpgsql;

-- Complete work
CREATE OR REPLACE FUNCTION complete_work(
    p_work_id UUID,
    p_result JSONB DEFAULT NULL,
    p_artifact_id UUID DEFAULT NULL
)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE work_queue
    SET 
        status = 'completed',
        completed_at = NOW(),
        result = COALESCE(p_result, result),
        updated_at = NOW()
    WHERE id = p_work_id;
    
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Fail work with error
CREATE OR REPLACE FUNCTION fail_work(
    p_work_id UUID,
    p_error_message TEXT
)
RETURNS BOOLEAN AS $$
DECLARE
    current_retries INTEGER;
    max_retry INTEGER;
BEGIN
    SELECT retry_count, max_retries INTO current_retries, max_retry
    FROM work_queue WHERE id = p_work_id;
    
    IF current_retries < max_retry THEN
        -- Retry: reset to pending with incremented retry count
        UPDATE work_queue
        SET 
            status = 'pending',
            retry_count = retry_count + 1,
            error_message = p_error_message,
            claimed_by = NULL,
            claimed_at = NULL,
            updated_at = NOW()
        WHERE id = p_work_id;
    ELSE
        -- Max retries reached: mark as failed
        UPDATE work_queue
        SET 
            status = 'failed',
            error_message = p_error_message,
            updated_at = NOW()
        WHERE id = p_work_id;
    END IF;
    
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Get active state by key
CREATE OR REPLACE FUNCTION get_state(p_state_key TEXT)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    SELECT state_value INTO result
    FROM agent_state
    WHERE state_key = p_state_key
    AND is_active = true
    ORDER BY version DESC
    LIMIT 1;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Record a new workflow learning
CREATE OR REPLACE FUNCTION record_learning(
    p_learning_type TEXT,
    p_title TEXT,
    p_description TEXT,
    p_trigger_condition TEXT DEFAULT NULL,
    p_recommended_action TEXT DEFAULT NULL,
    p_examples JSONB DEFAULT '[]'::jsonb,
    p_discovered_by TEXT DEFAULT NULL,
    p_discovered_in_context TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    new_id UUID;
BEGIN
    INSERT INTO workflow_learnings (
        learning_type, title, description, trigger_condition,
        recommended_action, examples, discovered_by, discovered_in_context
    ) VALUES (
        p_learning_type, p_title, p_description, p_trigger_condition,
        p_recommended_action, p_examples, p_discovered_by, p_discovered_in_context
    )
    RETURNING id INTO new_id;
    
    RETURN new_id;
END;
$$ LANGUAGE plpgsql;

-- Get active learnings (call on session start)
CREATE OR REPLACE FUNCTION get_active_learnings(p_learning_type TEXT DEFAULT NULL)
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
BEGIN
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
    WHERE wl.is_active = true
    AND (p_learning_type IS NULL OR wl.learning_type = p_learning_type)
    ORDER BY wl.effectiveness_score DESC, wl.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- Update learning effectiveness (call when a learning helped or didn't)
CREATE OR REPLACE FUNCTION update_learning_effectiveness(
    p_learning_id UUID,
    p_delta INTEGER  -- +1 if helped, -1 if didn't help
)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE workflow_learnings
    SET effectiveness_score = effectiveness_score + p_delta,
        updated_at = NOW()
    WHERE id = p_learning_id;
    
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Set state (creates new version)
CREATE OR REPLACE FUNCTION set_state(
    p_state_key TEXT,
    p_state_value JSONB,
    p_description TEXT DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    new_version INTEGER;
BEGIN
    -- Get next version number
    SELECT COALESCE(MAX(version), 0) + 1 INTO new_version
    FROM agent_state
    WHERE state_key = p_state_key;
    
    -- Deactivate previous versions
    UPDATE agent_state
    SET is_active = false, updated_at = NOW()
    WHERE state_key = p_state_key;
    
    -- Insert new version
    INSERT INTO agent_state (state_key, state_value, version, description, is_active)
    VALUES (p_state_key, p_state_value, new_version, p_description, true);
    
    RETURN new_version;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- ROW LEVEL SECURITY (Optional)
-- Uncomment if you need RLS
-- ============================================

-- ALTER TABLE context_checkpoints ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE work_queue ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE agent_state ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE agent_config ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE artifacts ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE adrs ENABLE ROW LEVEL SECURITY;

-- ============================================
-- TRIGGERS FOR updated_at
-- ============================================

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_context_checkpoints_updated_at
    BEFORE UPDATE ON context_checkpoints
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_work_queue_updated_at
    BEFORE UPDATE ON work_queue
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_agent_state_updated_at
    BEFORE UPDATE ON agent_state
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_agent_config_updated_at
    BEFORE UPDATE ON agent_config
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_artifacts_updated_at
    BEFORE UPDATE ON artifacts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_adrs_updated_at
    BEFORE UPDATE ON adrs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_workflow_learnings_updated_at
    BEFORE UPDATE ON workflow_learnings
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================
-- LEARNING PROPAGATION (For Organizations)
-- ============================================

-- Learning submissions for review
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

-- Canon versions (versioned snapshots of approved learnings)
CREATE TABLE IF NOT EXISTS canon_versions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    version_number INTEGER NOT NULL UNIQUE,
    description TEXT,
    learnings_snapshot JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    created_by TEXT
);

CREATE INDEX idx_canon_versions ON canon_versions(version_number DESC);

-- Developer sync status
CREATE TABLE IF NOT EXISTS developer_sync_status (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    developer_id TEXT NOT NULL UNIQUE,
    developer_name TEXT,
    current_version INTEGER NOT NULL DEFAULT 0,
    last_sync_at TIMESTAMPTZ DEFAULT NOW(),
    auto_sync_enabled BOOLEAN DEFAULT true
);

CREATE INDEX idx_developer_sync ON developer_sync_status(developer_id);

-- Submit a learning for organization review
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

-- Approve a learning submission
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
    
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Create a new canon version with all approved learnings
CREATE OR REPLACE FUNCTION create_canon_version(
    p_description TEXT,
    p_created_by TEXT
)
RETURNS INTEGER AS $$
DECLARE
    new_version INTEGER;
    learnings_json JSONB;
BEGIN
    SELECT COALESCE(MAX(version_number), 0) + 1 INTO new_version
    FROM canon_versions;
    
    SELECT jsonb_agg(row_to_json(wl))
    INTO learnings_json
    FROM workflow_learnings wl
    JOIN learning_submissions ls ON ls.learning_id = wl.id
    WHERE ls.status = 'approved'
    AND wl.is_active = true;
    
    INSERT INTO canon_versions (version_number, description, learnings_snapshot, created_by)
    VALUES (new_version, p_description, COALESCE(learnings_json, '[]'::jsonb), p_created_by);
    
    RETURN new_version;
END;
$$ LANGUAGE plpgsql;

-- Get learnings added since a specific version
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
    SELECT learnings_snapshot INTO old_snapshot
    FROM canon_versions
    WHERE version_number = p_version;
    
    IF old_snapshot IS NULL OR old_snapshot = '[]'::jsonb THEN
        old_ids := ARRAY[]::UUID[];
    ELSE
        SELECT array_agg((elem->>'id')::UUID)
        INTO old_ids
        FROM jsonb_array_elements(old_snapshot) AS elem;
    END IF;
    
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
    AND (old_ids IS NULL OR array_length(old_ids, 1) IS NULL OR wl.id != ALL(old_ids));
END;
$$ LANGUAGE plpgsql;

-- Quality control: Auto-reject low-quality submissions
CREATE OR REPLACE FUNCTION validate_learning_submission()
RETURNS TRIGGER AS $$
DECLARE
    learning_title TEXT;
    learning_desc TEXT;
    learning_trigger TEXT;
BEGIN
    SELECT title, description, trigger_condition
    INTO learning_title, learning_desc, learning_trigger
    FROM workflow_learnings WHERE id = NEW.learning_id;
    
    IF LENGTH(learning_title) < 10 THEN
        NEW.status := 'rejected';
        NEW.review_notes := 'Auto-rejected: Title too short (min 10 chars)';
        NEW.reviewed_at := NOW();
        NEW.reviewer := 'system';
        RETURN NEW;
    END IF;
    
    IF LENGTH(learning_desc) < 50 THEN
        NEW.status := 'rejected';
        NEW.review_notes := 'Auto-rejected: Description too short (min 50 chars)';
        NEW.reviewed_at := NOW();
        NEW.reviewer := 'system';
        RETURN NEW;
    END IF;
    
    IF learning_trigger IS NULL OR LENGTH(learning_trigger) < 10 THEN
        NEW.status := 'rejected';
        NEW.review_notes := 'Auto-rejected: Missing or too short trigger condition';
        NEW.reviewed_at := NOW();
        NEW.reviewer := 'system';
        RETURN NEW;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_learning_quality
    BEFORE INSERT ON learning_submissions
    FOR EACH ROW EXECUTE FUNCTION validate_learning_submission();

-- Auto-deactivate learnings with negative effectiveness
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

CREATE TRIGGER update_learning_submissions_updated_at
    BEFORE UPDATE ON learning_submissions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================
-- CAPABILITY NOTIFICATIONS
-- Auto-notify developers of new learnings
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
CREATE INDEX idx_notifications_pending ON capability_notifications(developer_id) WHERE is_read = false AND is_dismissed = false;

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
    ORDER BY wl.effectiveness_score DESC, cn.created_at DESC
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

-- Dismiss notification
CREATE OR REPLACE FUNCTION dismiss_notification(p_notification_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE capability_notifications
    SET is_dismissed = true, is_read = true, read_at = NOW()
    WHERE id = p_notification_id;
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Apply notification (user activated the capability)
CREATE OR REPLACE FUNCTION apply_notification(p_notification_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE capability_notifications
    SET is_applied = true, is_read = true, applied_at = NOW(), read_at = NOW()
    WHERE id = p_notification_id;
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Trigger: Create notifications for all developers when learning is approved
CREATE OR REPLACE FUNCTION notify_all_developers_of_learning()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'approved' AND (OLD IS NULL OR OLD.status IS DISTINCT FROM 'approved') THEN
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

CREATE TRIGGER on_learning_approved
    AFTER INSERT OR UPDATE ON learning_submissions
    FOR EACH ROW EXECUTE FUNCTION notify_all_developers_of_learning();

-- ============================================
-- SEED DATA (Optional)
-- ============================================

-- Example: Insert default orchestrator config
INSERT INTO agent_config (agent_role, system_prompt, capabilities, constraints)
VALUES (
    'orchestrator',
    'You are the primary orchestrator. Coordinate work, maintain state, execute autonomously.',
    '["checkpoint_management", "work_assignment", "state_tracking"]'::jsonb,
    '["no_permission_asking", "no_vague_quantifiers", "execute_then_report"]'::jsonb
) ON CONFLICT (agent_role) DO NOTHING;

-- Example: Insert initial checkpoint
INSERT INTO context_checkpoints (agent_role, session_key, description, state_snapshot, verification_status)
VALUES (
    'orchestrator',
    'claude_ide_main',
    'Initial checkpoint - system initialized',
    '{"phase": "initialized", "pending_work": []}'::jsonb,
    'verified'
);

COMMENT ON TABLE context_checkpoints IS 'Stores session state checkpoints for cross-session continuity';
COMMENT ON TABLE work_queue IS 'Task queue for cross-instance communication and work distribution';
COMMENT ON TABLE agent_state IS 'Versioned key-value store for prompts, schemas, and configuration';
COMMENT ON TABLE agent_config IS 'System prompts and capabilities per agent role';
COMMENT ON TABLE artifacts IS 'Output artifacts with metadata and optional git references';
COMMENT ON TABLE adrs IS 'Architecture Decision Records for design decisions';
COMMENT ON TABLE workflow_learnings IS 'Patterns and improvements discovered by Claude for continuous self-improvement';
