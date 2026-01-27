-- =============================================================================
-- IronForge / Atlas Supabase Schema - PILOT ADDITIONS
-- Trajectory logging + sparse reasonableness labels for friend pilot (10-30 users)
-- Run this AFTER supabase_schema.sql and supabase_schema_v2_additions.sql
-- =============================================================================

-- =============================================================================
-- 1. PILOT PARTICIPANTS
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.pilot_participants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    
    -- Enrollment
    enrolled_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    enrolled_by TEXT, -- Who recruited them (for tracking)
    
    -- Pilot status
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'paused', 'completed', 'withdrawn')),
    status_changed_at TIMESTAMPTZ,
    
    -- Guardrail settings
    conservative_mode BOOLEAN DEFAULT true,
    max_weekly_increase_percent NUMERIC(4,2) DEFAULT 5.0, -- Cap at 5% weekly per lift
    allow_increase_after_grinder BOOLEAN DEFAULT false,
    allow_increase_low_readiness BOOLEAN DEFAULT false,
    
    -- Consent
    consent_given_at TIMESTAMPTZ,
    consent_version TEXT DEFAULT 'v1',
    
    -- Feedback preferences
    label_prompt_frequency TEXT DEFAULT 'triggers_only' CHECK (
        label_prompt_frequency IN ('triggers_only', 'every_session', 'never')
    ),
    
    -- Notes
    notes TEXT,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(user_id)
);

CREATE INDEX IF NOT EXISTS idx_pilot_participants_status ON public.pilot_participants(status);

-- =============================================================================
-- 2. ENGINE DECISION TRAJECTORIES
-- Records EVERY engine recommendation with full context for ML training
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.engine_trajectories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    session_id UUID REFERENCES public.workout_sessions(id) ON DELETE SET NULL,
    
    -- When this decision was made
    decided_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Exercise context
    exercise_id TEXT NOT NULL,
    exercise_name TEXT NOT NULL,
    
    -- === INPUT STATE (what the engine saw) ===
    
    -- Prior lift state
    prior_working_weight_kg NUMERIC(6,2),
    prior_e1rm_kg NUMERIC(6,2),
    prior_failure_count INTEGER,
    prior_trend TEXT, -- 'improving', 'stable', 'declining', 'insufficient'
    prior_successful_sessions INTEGER,
    days_since_last_session INTEGER,
    
    -- Session context
    readiness_score INTEGER,
    was_break_return BOOLEAN DEFAULT false,
    break_duration_days INTEGER,
    
    -- Prescription context
    sets_target INTEGER,
    rep_range_min INTEGER,
    rep_range_max INTEGER,
    target_rir INTEGER,
    increment_kg NUMERIC(4,2),
    
    -- === ENGINE ACTION (what was decided) ===
    
    decision_type TEXT NOT NULL CHECK (decision_type IN (
        'increase_weight',
        'increase_reps', 
        'hold',
        'deload',
        'break_reset'
    )),
    
    -- Prescription output
    prescribed_weight_kg NUMERIC(6,2) NOT NULL,
    prescribed_reps INTEGER NOT NULL,
    weight_delta_kg NUMERIC(6,2), -- Change from prior
    weight_delta_percent NUMERIC(5,2),
    
    -- Deload specifics
    is_deload BOOLEAN DEFAULT false,
    deload_reason TEXT,
    deload_intensity_reduction_percent NUMERIC(4,2),
    deload_volume_reduction_sets INTEGER,
    
    -- Decision reasoning (structured)
    decision_reasons JSONB DEFAULT '[]'::jsonb,
    -- e.g., ["hit_top_of_rep_range", "e1rm_improving", "readiness_adequate"]
    
    -- Guardrail interventions
    guardrail_triggered BOOLEAN DEFAULT false,
    guardrail_type TEXT, -- 'max_weekly_cap', 'grinder_block', 'low_readiness_block', 'pain_flag'
    original_decision_type TEXT, -- What engine wanted before guardrail
    original_prescribed_weight_kg NUMERIC(6,2),
    
    -- === VARIATION/SUBSTITUTION CONTEXT ===
    
    is_variation BOOLEAN DEFAULT false,
    variation_of_exercise_id TEXT,
    is_substitution BOOLEAN DEFAULT false,
    substituted_for_exercise_id TEXT,
    
    -- === METADATA ===
    
    engine_version TEXT, -- For tracking algorithm changes
    pilot_version TEXT DEFAULT 'v1',
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_trajectories_user ON public.engine_trajectories(user_id, decided_at DESC);
CREATE INDEX IF NOT EXISTS idx_trajectories_exercise ON public.engine_trajectories(exercise_id, decided_at DESC);
CREATE INDEX IF NOT EXISTS idx_trajectories_session ON public.engine_trajectories(session_id);
CREATE INDEX IF NOT EXISTS idx_trajectories_decision ON public.engine_trajectories(decision_type);

-- =============================================================================
-- 3. SESSION OUTCOMES (links prescription → what actually happened next)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.trajectory_outcomes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    trajectory_id UUID NOT NULL REFERENCES public.engine_trajectories(id) ON DELETE CASCADE,
    
    -- The session where this prescription was executed
    outcome_session_id UUID REFERENCES public.workout_sessions(id) ON DELETE SET NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- === WHAT ACTUALLY HAPPENED ===
    
    -- Did they follow the prescription?
    followed_prescription BOOLEAN,
    actual_weight_kg NUMERIC(6,2),
    actual_reps_achieved INTEGER[], -- Array of reps per set
    actual_sets_completed INTEGER,
    
    -- Effort
    observed_rir INTEGER,
    observed_rpe NUMERIC(3,1),
    was_grinder BOOLEAN DEFAULT false, -- RPE >= 9.5 or RIR 0
    was_failure BOOLEAN DEFAULT false, -- Couldn't hit min reps
    
    -- Completion
    exercise_completed BOOLEAN,
    exercise_skipped BOOLEAN DEFAULT false,
    skip_reason TEXT,
    
    -- Substitution made?
    was_substituted BOOLEAN DEFAULT false,
    substituted_with_exercise_id TEXT,
    substitution_reason TEXT,
    
    -- Pain/discomfort
    pain_reported BOOLEAN DEFAULT false,
    pain_location TEXT,
    pain_severity INTEGER CHECK (pain_severity IS NULL OR (pain_severity >= 1 AND pain_severity <= 5)),
    
    -- Manual override
    user_overrode_prescription BOOLEAN DEFAULT false,
    override_type TEXT, -- 'weight_up', 'weight_down', 'reps_changed', 'skipped'
    override_reason TEXT,
    
    -- === COMPUTED OUTCOME METRICS ===
    
    -- How far off from prescription?
    weight_deviation_kg NUMERIC(6,2),
    weight_deviation_percent NUMERIC(5,2),
    reps_vs_target TEXT, -- 'below', 'at', 'above'
    
    -- e1RM change from this session
    session_e1rm_kg NUMERIC(6,2),
    e1rm_delta_kg NUMERIC(6,2),
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_outcomes_trajectory ON public.trajectory_outcomes(trajectory_id);
CREATE INDEX IF NOT EXISTS idx_outcomes_session ON public.trajectory_outcomes(outcome_session_id);

-- =============================================================================
-- 4. REASONABLENESS LABELS (sparse, only at high-leverage moments)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.reasonableness_labels (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    trajectory_id UUID NOT NULL REFERENCES public.engine_trajectories(id) ON DELETE CASCADE,
    
    -- When was this label collected?
    labeled_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- === TRIGGER CONTEXT ===
    
    trigger_type TEXT NOT NULL CHECK (trigger_type IN (
        'increase_recommended',
        'deload_recommended',
        'after_missed_session',
        'after_break',
        'after_failed_set',
        'after_grinder',
        'substitution_change',
        'acute_low_readiness',
        'manual_request'
    )),
    
    -- Additional trigger context
    trigger_context JSONB DEFAULT '{}'::jsonb,
    -- e.g., {"break_days": 10, "grinder_rpe": 9.5, "readiness_score": 35}
    
    -- === THE LABEL ===
    
    -- Primary question: "Was this recommendation reasonable?"
    was_reasonable BOOLEAN NOT NULL,
    
    -- Follow-up if not reasonable
    unreasonable_reason TEXT CHECK (unreasonable_reason IS NULL OR unreasonable_reason IN (
        'too_heavy',
        'too_light',
        'wrong_direction',  -- Should have increased but held, or vice versa
        'wrong_timing',     -- Right direction but too soon/late
        'other'
    )),
    
    -- Optional free-text
    user_comment TEXT,
    
    -- How confident are they in this label?
    confidence TEXT DEFAULT 'medium' CHECK (confidence IN ('low', 'medium', 'high')),
    
    -- === METADATA ===
    
    -- Time to respond (for label quality estimation)
    prompt_shown_at TIMESTAMPTZ,
    response_time_seconds INTEGER,
    
    -- Was this label solicited or volunteered?
    label_source TEXT DEFAULT 'prompted' CHECK (label_source IN ('prompted', 'volunteered')),
    
    -- Did they skip the prompt?
    was_skipped BOOLEAN DEFAULT false,
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_labels_user ON public.reasonableness_labels(user_id, labeled_at DESC);
CREATE INDEX IF NOT EXISTS idx_labels_trajectory ON public.reasonableness_labels(trajectory_id);
CREATE INDEX IF NOT EXISTS idx_labels_trigger ON public.reasonableness_labels(trigger_type);
CREATE INDEX IF NOT EXISTS idx_labels_reasonable ON public.reasonableness_labels(was_reasonable);

-- =============================================================================
-- 5. MANUAL OVERRIDES LOG
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.manual_overrides (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    session_id UUID REFERENCES public.workout_sessions(id) ON DELETE SET NULL,
    trajectory_id UUID REFERENCES public.engine_trajectories(id) ON DELETE SET NULL,
    
    overridden_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    exercise_id TEXT NOT NULL,
    exercise_name TEXT NOT NULL,
    
    -- What the engine recommended
    engine_prescribed_weight_kg NUMERIC(6,2),
    engine_prescribed_reps INTEGER,
    engine_decision_type TEXT,
    
    -- What the user chose instead
    user_chosen_weight_kg NUMERIC(6,2),
    user_chosen_reps INTEGER,
    
    -- Override magnitude
    weight_override_kg NUMERIC(6,2),
    weight_override_percent NUMERIC(5,2),
    
    -- Why did they override?
    override_reason TEXT CHECK (override_reason IN (
        'too_heavy',
        'too_light',
        'equipment_unavailable',
        'time_constraint',
        'feeling_good',
        'feeling_bad',
        'testing_max',
        'other'
    )),
    override_notes TEXT,
    
    -- Did this override work out?
    outcome_success BOOLEAN, -- Did they complete it successfully?
    outcome_notes TEXT,
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_overrides_user ON public.manual_overrides(user_id, overridden_at DESC);
CREATE INDEX IF NOT EXISTS idx_overrides_session ON public.manual_overrides(session_id);

-- =============================================================================
-- 6. PILOT SAFETY EVENTS
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.pilot_safety_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    session_id UUID REFERENCES public.workout_sessions(id) ON DELETE SET NULL,
    
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    event_type TEXT NOT NULL CHECK (event_type IN (
        'pain_reported',
        'injury_reported',
        'excessive_fatigue',
        'near_miss',          -- Almost dropped weight, form breakdown
        'user_concern',       -- User flagged something
        'guardrail_override', -- User bypassed safety guardrail
        'system_alert'        -- Automated detection (e.g., sudden performance drop)
    )),
    
    severity TEXT DEFAULT 'low' CHECK (severity IN ('low', 'medium', 'high', 'critical')),
    
    description TEXT,
    exercise_id TEXT,
    exercise_name TEXT,
    
    -- Action taken
    action_taken TEXT,
    requires_followup BOOLEAN DEFAULT false,
    followed_up_at TIMESTAMPTZ,
    followup_notes TEXT,
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_safety_user ON public.pilot_safety_events(user_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_safety_severity ON public.pilot_safety_events(severity);

-- =============================================================================
-- 7. LABEL PROMPT QUEUE (tracks what labels to request)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.pending_label_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    trajectory_id UUID NOT NULL REFERENCES public.engine_trajectories(id) ON DELETE CASCADE,
    
    -- Why is this label being requested?
    trigger_type TEXT NOT NULL,
    trigger_context JSONB DEFAULT '{}'::jsonb,
    
    -- When should we ask?
    prompt_after TIMESTAMPTZ NOT NULL DEFAULT NOW(), -- Can delay prompts
    expires_at TIMESTAMPTZ, -- Don't ask if too much time has passed
    
    -- Status
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'shown', 'completed', 'skipped', 'expired')),
    shown_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    
    -- Priority (for ordering multiple pending requests)
    priority INTEGER DEFAULT 5, -- 1 = highest, 10 = lowest
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pending_labels_user ON public.pending_label_requests(user_id, status, priority);
CREATE INDEX IF NOT EXISTS idx_pending_labels_status ON public.pending_label_requests(status, prompt_after);

-- =============================================================================
-- RLS POLICIES
-- =============================================================================

ALTER TABLE public.pilot_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.engine_trajectories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trajectory_outcomes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reasonableness_labels ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.manual_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pilot_safety_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pending_label_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY pilot_participants_policy ON public.pilot_participants FOR ALL USING (auth.uid() = user_id);
CREATE POLICY trajectories_policy ON public.engine_trajectories FOR ALL USING (auth.uid() = user_id);
CREATE POLICY outcomes_policy ON public.trajectory_outcomes FOR ALL 
    USING (EXISTS (SELECT 1 FROM public.engine_trajectories t WHERE t.id = trajectory_id AND auth.uid() = t.user_id));
CREATE POLICY labels_policy ON public.reasonableness_labels FOR ALL USING (auth.uid() = user_id);
CREATE POLICY overrides_policy ON public.manual_overrides FOR ALL USING (auth.uid() = user_id);
CREATE POLICY safety_policy ON public.pilot_safety_events FOR ALL USING (auth.uid() = user_id);
CREATE POLICY pending_labels_policy ON public.pending_label_requests FOR ALL USING (auth.uid() = user_id);

-- =============================================================================
-- HELPER VIEWS FOR ANALYSIS
-- =============================================================================

-- View: Trajectory with outcome and label (for ML training data export)
CREATE OR REPLACE VIEW public.pilot_training_data AS
SELECT 
    t.id as trajectory_id,
    t.user_id,
    t.exercise_id,
    t.exercise_name,
    t.decided_at,
    
    -- Inputs
    t.prior_working_weight_kg,
    t.prior_e1rm_kg,
    t.prior_failure_count,
    t.prior_trend,
    t.days_since_last_session,
    t.readiness_score,
    t.was_break_return,
    t.break_duration_days,
    
    -- Engine action
    t.decision_type,
    t.prescribed_weight_kg,
    t.prescribed_reps,
    t.weight_delta_percent,
    t.is_deload,
    t.deload_reason,
    t.guardrail_triggered,
    t.guardrail_type,
    
    -- Outcome
    o.followed_prescription,
    o.actual_weight_kg,
    o.actual_reps_achieved,
    o.observed_rir,
    o.was_grinder,
    o.was_failure,
    o.pain_reported,
    o.user_overrode_prescription,
    
    -- Label (if exists)
    l.was_reasonable,
    l.unreasonable_reason,
    l.trigger_type as label_trigger,
    l.confidence as label_confidence
    
FROM public.engine_trajectories t
LEFT JOIN public.trajectory_outcomes o ON o.trajectory_id = t.id
LEFT JOIN public.reasonableness_labels l ON l.trajectory_id = t.id;

-- View: Label rate by trigger type
CREATE OR REPLACE VIEW public.pilot_label_stats AS
SELECT 
    trigger_type,
    COUNT(*) as total_labels,
    SUM(CASE WHEN was_reasonable THEN 1 ELSE 0 END) as reasonable_count,
    SUM(CASE WHEN NOT was_reasonable THEN 1 ELSE 0 END) as unreasonable_count,
    ROUND(AVG(CASE WHEN was_reasonable THEN 1.0 ELSE 0.0 END) * 100, 1) as reasonable_percent,
    COUNT(DISTINCT user_id) as unique_users
FROM public.reasonableness_labels
WHERE NOT was_skipped
GROUP BY trigger_type;

-- =============================================================================
-- Done! Run this after the main schema and v2 additions
-- =============================================================================
