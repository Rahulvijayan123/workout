-- ============================================
-- ML TRAINING SCHEMA V2.1
-- Optimized for clean, causal, non-leaky training data
-- With 3-state labels and proper exploration logging
-- ============================================

-- ============================================
-- 1. RECOMMENDATION EVENTS (Immutable Policy Log)
-- This is the MOST IMPORTANT table for ML training
-- ============================================
CREATE TABLE IF NOT EXISTS recommendation_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id UUID REFERENCES workout_sessions(id) ON DELETE SET NULL,
    session_exercise_id UUID REFERENCES session_exercises(id) ON DELETE SET NULL,
    
    -- What was recommended (the chosen action)
    exercise_id TEXT NOT NULL,
    recommended_weight_kg DECIMAL(10,3) NOT NULL,
    recommended_reps INT NOT NULL,
    recommended_sets INT NOT NULL,
    recommended_rir INT NOT NULL,
    
    -- Policy metadata (CRITICAL for versioning and evaluation)
    policy_version TEXT NOT NULL DEFAULT 'v1.0',
    policy_type TEXT NOT NULL DEFAULT 'deterministic', -- deterministic, ml_v1, exploration
    
    -- Action classification
    action_type TEXT NOT NULL CHECK (action_type IN (
        'increase_load', 'decrease_load', 'hold_load',
        'increase_reps', 'decrease_reps', 'hold_reps',
        'deload', 'reset'
    )),
    
    -- Reasoning (for debugging and counterfactual analysis)
    reason_codes TEXT[] NOT NULL DEFAULT '{}',
    
    -- PREDICTION & CONFIDENCE (Required for policy evaluation)
    predicted_p_success DECIMAL(4,3), -- Predicted probability of success (0.000 to 1.000)
    model_confidence DECIMAL(4,3),    -- Model's confidence in prediction (separate from p_success)
    
    -- EXPLORATION (Required for off-policy learning)
    is_exploration BOOLEAN NOT NULL DEFAULT FALSE,
    action_probability DECIMAL(6,5) NOT NULL DEFAULT 1.0, -- P(action) - REQUIRED if exploring
    exploration_delta_kg DECIMAL(6,3), -- Delta from deterministic
    exploration_eligible BOOLEAN DEFAULT FALSE, -- Did this pass safety checks?
    exploration_blocked_reason TEXT, -- Why exploration was blocked (if blocked)
    
    -- CANDIDATE ACTIONS (For counterfactual analysis)
    candidate_actions_json JSONB, -- Array of {weight_kg, reps, p_success, probability, is_chosen}
    
    -- Counterfactual: what would deterministic policy have done?
    deterministic_weight_kg DECIMAL(10,3),
    deterministic_reps INT,
    deterministic_p_success DECIMAL(4,3),
    
    -- POLICY SELECTION METADATA (Required for bandit/shadow mode evaluation)
    executed_policy_id TEXT,                    -- Which policy was executed (e.g., 'conservative_lp', 'ml_v1')
    executed_action_probability DECIMAL(6,5),   -- P(this action | executed policy)
    exploration_mode TEXT,                      -- 'greedy', 'epsilon_greedy', 'shadow_only', etc.
    shadow_policy_id TEXT,                      -- Shadow policy for counterfactual (if different from executed)
    shadow_action_probability DECIMAL(6,5),     -- P(this action | shadow policy)
    
    -- State snapshot at recommendation time (CRITICAL - prevents leakage)
    state_at_recommendation JSONB NOT NULL,
    -- Contains: rolling_e1rm_kg, raw_e1rm_kg, consecutive_failures, consecutive_successes,
    --           high_rpe_streak, days_since_last_exposure, days_since_last_deload,
    --           last_session_weight_kg, last_session_reps, last_session_rir, last_session_outcome,
    --           exposures_last_14d, volume_last_7d_kg, successful_sessions_count, total_sessions_count,
    --           e1rm_trend, e1rm_slope_per_week, template_version
    
    generated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Constraints
    CONSTRAINT valid_p_success CHECK (predicted_p_success IS NULL OR (predicted_p_success >= 0 AND predicted_p_success <= 1)),
    CONSTRAINT valid_confidence CHECK (model_confidence IS NULL OR (model_confidence >= 0 AND model_confidence <= 1)),
    CONSTRAINT valid_action_prob CHECK (action_probability >= 0 AND action_probability <= 1)
);

-- Add columns that may not exist in older versions of the table
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS executed_policy_id TEXT;
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS executed_action_probability DECIMAL(6,5);
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS exploration_mode TEXT;
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS shadow_policy_id TEXT;
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS shadow_action_probability DECIMAL(6,5);

CREATE INDEX IF NOT EXISTS idx_rec_events_user_exercise ON recommendation_events(user_id, exercise_id);
CREATE INDEX IF NOT EXISTS idx_rec_events_session ON recommendation_events(session_id);
CREATE INDEX IF NOT EXISTS idx_rec_events_policy ON recommendation_events(policy_version, policy_type);
CREATE INDEX IF NOT EXISTS idx_rec_events_exploration ON recommendation_events(is_exploration) WHERE is_exploration = TRUE;
CREATE INDEX IF NOT EXISTS idx_rec_events_time ON recommendation_events(generated_at);

COMMENT ON TABLE recommendation_events IS 'Immutable log of all recommendations. NEVER update, only append. Required for policy evaluation and off-policy learning.';

-- ============================================
-- 2. PLANNED SETS (Immutable prescription at session start)
-- Separate from performed sets to enable counterfactual analysis
-- ============================================
CREATE TABLE IF NOT EXISTS planned_sets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_exercise_id UUID NOT NULL REFERENCES session_exercises(id) ON DELETE CASCADE,
    recommendation_event_id UUID REFERENCES recommendation_events(id) ON DELETE SET NULL,
    
    set_number INT NOT NULL,
    target_weight_kg DECIMAL(10,3) NOT NULL,
    target_reps INT NOT NULL,
    target_rir INT NOT NULL DEFAULT 2,
    target_rest_seconds INT,
    
    -- Tempo (optional, only if prescribed)
    target_tempo_eccentric INT,
    target_tempo_pause_bottom INT,
    target_tempo_concentric INT,
    target_tempo_pause_top INT,
    
    is_warmup BOOLEAN NOT NULL DEFAULT FALSE,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    UNIQUE(session_exercise_id, set_number)
);

CREATE INDEX IF NOT EXISTS idx_planned_sets_exercise ON planned_sets(session_exercise_id);

COMMENT ON TABLE planned_sets IS 'What was prescribed at session start. Immutable once created.';

-- ============================================
-- 2.5 POLICY DECISION LOGS (Policy selection attribution)
-- Captures decision-time policy choice + propensity, and later outcome markers.
-- ============================================
CREATE TABLE IF NOT EXISTS policy_decision_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    stable_user_id TEXT NOT NULL,
    session_id UUID NOT NULL,
    exercise_id TEXT NOT NULL,
    family_reference_key TEXT,
    
    executed_policy_id TEXT NOT NULL,
    executed_action_probability DECIMAL(6,5) NOT NULL,
    exploration_mode TEXT,
    shadow_policy_id TEXT,
    shadow_action_probability DECIMAL(6,5),
    
    decided_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    outcome_was_success BOOLEAN,
    outcome_was_grinder BOOLEAN,
    outcome_execution_context TEXT,
    outcome_recorded_at TIMESTAMPTZ,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_policy_decisions_user_time ON policy_decision_logs(user_id, decided_at DESC);
CREATE INDEX IF NOT EXISTS idx_policy_decisions_session ON policy_decision_logs(session_id);
CREATE INDEX IF NOT EXISTS idx_policy_decisions_exercise ON policy_decision_logs(exercise_id);
CREATE INDEX IF NOT EXISTS idx_policy_decisions_policy ON policy_decision_logs(executed_policy_id);

-- ============================================
-- 3. UPDATE SESSION_SETS for performed data + user edits
-- ============================================
ALTER TABLE session_sets
ADD COLUMN IF NOT EXISTS planned_set_id UUID REFERENCES planned_sets(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS is_user_modified BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS original_prescribed_weight_kg DECIMAL(10,3),
ADD COLUMN IF NOT EXISTS original_prescribed_reps INT,
ADD COLUMN IF NOT EXISTS modification_reason TEXT CHECK (modification_reason IN (
    'felt_strong', 'felt_weak', 'pain', 'equipment_unavailable', 
    'time_constraint', 'warmup_insufficient', 'form_concern', 'other', NULL
)),
-- Columns needed by trigger (add if not exist from base schema)
ADD COLUMN IF NOT EXISTS recommended_reps INT,
ADD COLUMN IF NOT EXISTS recommended_weight_kg DECIMAL(10,3),
ADD COLUMN IF NOT EXISTS target_rir INT,
ADD COLUMN IF NOT EXISTS target_rpe DECIMAL(3,1),
-- Outcome labels (computed, but stored for fast queries)
ADD COLUMN IF NOT EXISTS set_outcome TEXT CHECK (set_outcome IN ('success', 'failure', 'grinder', 'pain_stop', 'skipped')),
ADD COLUMN IF NOT EXISTS met_rep_target BOOLEAN,
ADD COLUMN IF NOT EXISTS met_effort_target BOOLEAN;

-- 3-STATE OUTCOME LABEL (CRITICAL for proper training)
-- unknown_difficulty should NOT be used as clean success
ALTER TABLE session_sets
ADD COLUMN IF NOT EXISTS set_outcome TEXT CHECK (set_outcome IN (
    'success',            -- Hit reps AND effort confirmed acceptable
    'failure',            -- Missed reps OR confirmed too hard
    'grinder',            -- Hit reps but effort confirmed too high
    'unknown_difficulty', -- Hit reps but RIR missing - NOT A CLEAN LABEL
    'pain_stop',          -- Stopped due to pain - exclude from training
    'skipped'             -- Did not attempt
));

-- Index for clean labels only
CREATE INDEX IF NOT EXISTS idx_session_sets_clean_outcome ON session_sets(set_outcome) 
    WHERE set_outcome IN ('success', 'failure', 'grinder');

COMMENT ON COLUMN session_sets.set_outcome IS '3-state label. Only use success/failure/grinder for training. unknown_difficulty is NOT a clean success label.';
COMMENT ON COLUMN session_sets.target_rir IS 'DEPRECATED: Use planned_sets.target_rir instead';
COMMENT ON COLUMN session_sets.target_rpe IS 'DEPRECATED: Use planned_sets equivalent';

-- ============================================
-- 4. UPDATE SESSION_EXERCISES with state snapshot and exposure definition
-- ============================================
ALTER TABLE session_exercises

-- STATE SNAPSHOT at session start (CRITICAL for non-leaky training)
ADD COLUMN IF NOT EXISTS state_snapshot_rolling_e1rm_kg DECIMAL(10,3),
ADD COLUMN IF NOT EXISTS state_snapshot_raw_e1rm_kg DECIMAL(10,3),
ADD COLUMN IF NOT EXISTS state_snapshot_consecutive_failures INT,
ADD COLUMN IF NOT EXISTS state_snapshot_consecutive_successes INT,
ADD COLUMN IF NOT EXISTS state_snapshot_high_rpe_streak INT,
ADD COLUMN IF NOT EXISTS state_snapshot_days_since_last_exposure INT,
ADD COLUMN IF NOT EXISTS state_snapshot_days_since_last_deload INT,
ADD COLUMN IF NOT EXISTS state_snapshot_last_weight_kg DECIMAL(10,3),
ADD COLUMN IF NOT EXISTS state_snapshot_last_reps INT,
ADD COLUMN IF NOT EXISTS state_snapshot_last_rir INT,
ADD COLUMN IF NOT EXISTS state_snapshot_last_outcome TEXT,
ADD COLUMN IF NOT EXISTS state_snapshot_exposures_last_14d INT,
ADD COLUMN IF NOT EXISTS state_snapshot_volume_last_7d_kg DECIMAL(12,3),
ADD COLUMN IF NOT EXISTS state_snapshot_successful_sessions INT,
ADD COLUMN IF NOT EXISTS state_snapshot_total_sessions INT,
ADD COLUMN IF NOT EXISTS state_snapshot_e1rm_trend TEXT,
ADD COLUMN IF NOT EXISTS state_snapshot_template_version INT,

-- EXPOSURE DEFINITION (for consistent modeling)
ADD COLUMN IF NOT EXISTS exposure_role TEXT CHECK (exposure_role IN (
    'top_set_only', 'straight_sets', 'ramp_up', 'backoff_sets', 'pyramid', 'drop_sets'
)),
ADD COLUMN IF NOT EXISTS primary_set_id UUID,
ADD COLUMN IF NOT EXISTS planned_top_set_weight_kg DECIMAL(10,3),
ADD COLUMN IF NOT EXISTS planned_top_set_reps INT,
ADD COLUMN IF NOT EXISTS planned_target_rir INT,
ADD COLUMN IF NOT EXISTS performed_top_set_weight_kg DECIMAL(10,3),
ADD COLUMN IF NOT EXISTS performed_top_set_reps INT,
ADD COLUMN IF NOT EXISTS performed_top_set_rir INT,

-- OUTCOME LABELS (3-state: success/fail/unknown_difficulty)
ADD COLUMN IF NOT EXISTS exposure_outcome TEXT CHECK (exposure_outcome IN (
    'success', 'partial', 'failure', 'unknown_difficulty', 'pain_stop', 'skipped'
)),
ADD COLUMN IF NOT EXISTS sets_successful INT,
ADD COLUMN IF NOT EXISTS sets_failed INT,
ADD COLUMN IF NOT EXISTS sets_unknown_difficulty INT,
ADD COLUMN IF NOT EXISTS session_e1rm_kg DECIMAL(10,3),
ADD COLUMN IF NOT EXISTS raw_top_set_e1rm_kg DECIMAL(10,3),
ADD COLUMN IF NOT EXISTS e1rm_delta_kg DECIMAL(10,3),

-- NEAR-FAILURE SIGNALS (auxiliary label for early training)
ADD COLUMN IF NOT EXISTS near_failure_missed_reps BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS near_failure_last_rep_grind BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS near_failure_long_rest BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS near_failure_session_ended_early BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS near_failure_next_load_reduced BOOLEAN, -- Computed after next session
ADD COLUMN IF NOT EXISTS near_failure_score DECIMAL(3,2), -- 0.00 to 1.00

-- MODIFICATION DETAILS (numeric, for learning from overrides)
ADD COLUMN IF NOT EXISTS modification_delta_weight_kg DECIMAL(8,3),
ADD COLUMN IF NOT EXISTS modification_delta_reps INT,
ADD COLUMN IF NOT EXISTS modification_direction TEXT CHECK (modification_direction IN ('up', 'down', 'same', 'mixed')),
ADD COLUMN IF NOT EXISTS modification_reason_code TEXT,

-- Pain tracking
ADD COLUMN IF NOT EXISTS stopped_due_to_pain BOOLEAN DEFAULT FALSE;

-- Ensure workout_sessions has the columns referenced by the view
ALTER TABLE workout_sessions ADD COLUMN IF NOT EXISTS planned_at TIMESTAMPTZ;
ALTER TABLE workout_sessions ADD COLUMN IF NOT EXISTS pre_workout_readiness INT;
ALTER TABLE workout_sessions ADD COLUMN IF NOT EXISTS session_rpe INT;
ALTER TABLE workout_sessions ADD COLUMN IF NOT EXISTS was_deload BOOLEAN DEFAULT FALSE;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_session_exercises_outcome ON session_exercises(exposure_outcome);
CREATE INDEX IF NOT EXISTS idx_session_exercises_clean_labels ON session_exercises(exposure_outcome) 
    WHERE exposure_outcome IN ('success', 'failure', 'partial');
CREATE INDEX IF NOT EXISTS idx_session_exercises_near_failure ON session_exercises(near_failure_score) 
    WHERE near_failure_score >= 0.4;

-- ============================================
-- 5. PAIN EVENTS (Normalized, not JSONB)
-- ============================================
CREATE TABLE IF NOT EXISTS pain_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id UUID REFERENCES workout_sessions(id) ON DELETE SET NULL,
    session_exercise_id UUID REFERENCES session_exercises(id) ON DELETE SET NULL,
    session_set_id UUID REFERENCES session_sets(id) ON DELETE SET NULL,
    
    body_region TEXT NOT NULL CHECK (body_region IN (
        'neck', 'shoulder', 'upper_back', 'lower_back', 'chest',
        'bicep', 'tricep', 'forearm', 'wrist', 'hand',
        'hip', 'glute', 'quad', 'hamstring', 'knee', 'calf', 'ankle', 'foot',
        'core', 'other'
    )),
    severity INT NOT NULL CHECK (severity >= 0 AND severity <= 10),
    
    pain_type TEXT CHECK (pain_type IN ('sharp', 'dull', 'burning', 'aching', 'other', NULL)),
    caused_stop BOOLEAN NOT NULL DEFAULT FALSE,
    notes TEXT,
    
    reported_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pain_events_user ON pain_events(user_id);
CREATE INDEX IF NOT EXISTS idx_pain_events_session ON pain_events(session_id);
CREATE INDEX IF NOT EXISTS idx_pain_events_exercise ON pain_events(session_exercise_id);
CREATE INDEX IF NOT EXISTS idx_pain_events_severity ON pain_events(severity) WHERE severity >= 5;

COMMENT ON TABLE pain_events IS 'Normalized pain tracking. One row per pain report.';

-- ============================================
-- 6. USER SENSITIVE CONTEXT (Opt-in, separate table)
-- ============================================
CREATE TABLE IF NOT EXISTS user_sensitive_context (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    
    -- Menstrual cycle (opt-in)
    cycle_phase TEXT CHECK (cycle_phase IN (
        'menstrual', 'follicular', 'ovulatory', 'luteal', 'not_tracking', NULL
    )),
    cycle_day_number INT,
    on_hormonal_birth_control BOOLEAN,
    
    -- Nutrition (opt-in)
    nutrition_bucket TEXT CHECK (nutrition_bucket IN ('deficit', 'maintenance', 'surplus', NULL)),
    protein_bucket TEXT CHECK (protein_bucket IN ('low', 'adequate', 'high', NULL)),
    
    -- Mood/stress (opt-in)
    mood_score INT CHECK (mood_score >= 1 AND mood_score <= 5),
    stress_level INT CHECK (stress_level >= 1 AND stress_level <= 5),
    
    -- Consent tracking
    consented_to_ml_training BOOLEAN NOT NULL DEFAULT FALSE,
    consent_timestamp TIMESTAMPTZ,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    UNIQUE(user_id, date)
);

CREATE INDEX IF NOT EXISTS idx_sensitive_context_user_date ON user_sensitive_context(user_id, date);

COMMENT ON TABLE user_sensitive_context IS 'Sensitive user data stored separately with explicit consent. NOT joined to ML training by default.';

-- ============================================
-- 7. EXERCISE VARIANTS (Normalization)
-- ============================================
CREATE TABLE IF NOT EXISTS exercise_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    base_exercise_id TEXT NOT NULL, -- Links to your exercise library
    variant_name TEXT NOT NULL,
    
    -- Variant attributes
    implement TEXT CHECK (implement IN ('barbell', 'dumbbell', 'cable', 'machine', 'bodyweight', 'kettlebell', 'band', 'other')),
    angle TEXT CHECK (angle IN ('flat', 'incline', 'decline', 'standing', 'seated', 'other', NULL)),
    grip TEXT CHECK (grip IN ('wide', 'narrow', 'neutral', 'supinated', 'pronated', 'mixed', 'other', NULL)),
    stance TEXT CHECK (stance IN ('bilateral', 'unilateral', 'staggered', 'sumo', 'conventional', 'other', NULL)),
    rom_modifier TEXT CHECK (rom_modifier IN ('full', 'partial', 'pause', 'deficit', 'block', NULL)),
    
    -- Estimated strength ratio vs base (e.g., incline DB = 0.7 * flat barbell)
    strength_ratio_estimate DECIMAL(3,2) DEFAULT 1.0,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_exercise_variants_base ON exercise_variants(base_exercise_id);

-- ============================================
-- 8. ML TRAINING VIEW (Clean, non-leaky, 3-state labels)
-- ============================================
DROP VIEW IF EXISTS ml_training_exposures_clean;
DROP VIEW IF EXISTS ml_training_exposures;
CREATE VIEW ml_training_exposures AS
SELECT 
    -- Identifiers
    se.id as exposure_id,
    ws.user_id,
    ws.id as session_id,
    se.exercise_id,
    se.exercise_name,
    
    -- Temporal features
    ws.started_at as session_date,
    EXTRACT(DOW FROM ws.started_at) as day_of_week,
    EXTRACT(HOUR FROM ws.started_at) as hour_of_day,
    se.state_snapshot_days_since_last_exposure as days_since_last,
    se.state_snapshot_days_since_last_deload as days_since_deload,
    
    -- State at session start (NO LEAKAGE - snapshot values only)
    se.state_snapshot_rolling_e1rm_kg as e1rm_at_start,
    se.state_snapshot_raw_e1rm_kg as raw_e1rm_at_start,
    se.state_snapshot_consecutive_failures as failures_at_start,
    se.state_snapshot_consecutive_successes as successes_at_start,
    se.state_snapshot_high_rpe_streak as high_rpe_streak_at_start,
    se.state_snapshot_successful_sessions as successful_sessions_at_start,
    se.state_snapshot_total_sessions as total_sessions_at_start,
    se.state_snapshot_last_weight_kg as last_weight_kg,
    se.state_snapshot_last_reps as last_reps,
    se.state_snapshot_last_rir as last_rir,
    se.state_snapshot_last_outcome as last_outcome,
    se.state_snapshot_exposures_last_14d as exposures_last_14d,
    se.state_snapshot_volume_last_7d_kg as volume_last_7d_kg,
    se.state_snapshot_e1rm_trend as e1rm_trend,
    se.state_snapshot_template_version as template_version,
    
    -- Exposure definition
    se.exposure_role,
    se.planned_top_set_weight_kg,
    se.planned_top_set_reps,
    se.planned_target_rir,
    se.performed_top_set_weight_kg,
    se.performed_top_set_reps,
    se.performed_top_set_rir,
    
    -- Prescription (from recommendation event)
    re.recommended_weight_kg,
    re.recommended_reps,
    re.recommended_rir,
    re.action_type,
    re.policy_version,
    re.policy_type,
    re.predicted_p_success,
    re.model_confidence,
    re.is_exploration,
    re.action_probability,
    re.exploration_delta_kg,
    re.deterministic_weight_kg,
    re.deterministic_reps,
    
    -- Policy selection metadata (for bandit/shadow evaluation)
    re.executed_policy_id,
    re.executed_action_probability,
    re.exploration_mode,
    re.shadow_policy_id,
    re.shadow_action_probability,
    
    -- What user actually did (aggregated)
    se.total_sets_completed as sets_performed,
    se.total_reps_completed as reps_performed,
    ROUND(se.total_volume_kg / NULLIF(se.total_reps_completed, 0), 2) as avg_weight_kg,
    
    -- OUTCOMES (3-state labels)
    se.exposure_outcome,
    se.sets_successful,
    se.sets_failed,
    se.sets_unknown_difficulty,
    -- Is this a clean label for binary training?
    CASE WHEN se.exposure_outcome IN ('success', 'failure', 'partial') THEN TRUE ELSE FALSE END as is_clean_label,
    -- Binary success (only valid when is_clean_label = TRUE)
    CASE WHEN se.exposure_outcome = 'success' THEN TRUE ELSE FALSE END as is_success,
    
    -- e1RM outcomes
    se.session_e1rm_kg,
    se.raw_top_set_e1rm_kg,
    se.e1rm_delta_kg,
    
    -- Near-failure signals (auxiliary labels)
    se.near_failure_missed_reps,
    se.near_failure_last_rep_grind,
    se.near_failure_long_rest,
    se.near_failure_session_ended_early,
    se.near_failure_next_load_reduced,
    se.near_failure_score,
    CASE WHEN se.near_failure_score >= 0.4 THEN TRUE ELSE FALSE END as is_too_aggressive,
    
    -- User modifications (important signal)
    se.modification_delta_weight_kg,
    se.modification_delta_reps,
    se.modification_direction,
    se.modification_reason_code,
    (SELECT COUNT(*) FROM session_sets ss WHERE ss.session_exercise_id = se.id AND ss.is_user_modified = TRUE) as sets_modified_count,
    
    -- Context (sparse, don't depend on these for core model)
    ws.pre_workout_readiness,
    ws.session_rpe,
    ws.was_deload,
    
    -- Pain signal
    (SELECT MAX(severity) FROM pain_events pe WHERE pe.session_exercise_id = se.id) as max_pain_severity,
    se.stopped_due_to_pain

FROM session_exercises se
JOIN workout_sessions ws ON se.session_id = ws.id
LEFT JOIN recommendation_events re ON re.session_exercise_id = se.id
WHERE 
    ws.ended_at IS NOT NULL  -- Only completed sessions
    AND se.is_completed = TRUE
    AND se.total_sets_completed > 0
ORDER BY ws.started_at DESC;

COMMENT ON VIEW ml_training_exposures IS 
'Clean training data at exercise-exposure level. 
Uses snapshots to prevent leakage. 
Uses 3-state labels (success/fail/unknown_difficulty). 
ONLY use rows where is_clean_label = TRUE for binary classification.
Use near_failure_score for auxiliary "too aggressive" learning.';

-- ============================================
-- 8b. VIEW FOR CLEAN LABELS ONLY (for convenient training queries)
-- ============================================
CREATE OR REPLACE VIEW ml_training_exposures_clean AS
SELECT * FROM ml_training_exposures
WHERE is_clean_label = TRUE;

COMMENT ON VIEW ml_training_exposures_clean IS 'Training data filtered to clean labels only (excludes unknown_difficulty, pain_stop, skipped).';

-- ============================================
-- 9. OUTCOME COMPUTATION FUNCTION
-- Call this when a session ends to compute labels
-- ============================================
CREATE OR REPLACE FUNCTION compute_exposure_outcomes(p_session_id UUID)
RETURNS VOID AS $$
DECLARE
    v_exercise RECORD;
    v_success_count INT;
    v_failure_count INT;
    v_outcome TEXT;
    v_best_e1rm DECIMAL;
BEGIN
    FOR v_exercise IN 
        SELECT se.* 
        FROM session_exercises se 
        WHERE se.session_id = p_session_id
    LOOP
        -- Count successes and failures
        SELECT 
            COUNT(*) FILTER (WHERE set_outcome = 'success'),
            COUNT(*) FILTER (WHERE set_outcome IN ('failure', 'grinder'))
        INTO v_success_count, v_failure_count
        FROM session_sets
        WHERE session_exercise_id = v_exercise.id
          AND is_warmup = FALSE
          AND is_completed = TRUE;
        
        -- Determine exposure outcome
        IF v_failure_count = 0 AND v_success_count > 0 THEN
            v_outcome := 'success';
        ELSIF v_success_count > v_failure_count THEN
            v_outcome := 'partial';
        ELSIF v_exercise.stopped_due_to_pain THEN
            v_outcome := 'pain_stop';
        ELSE
            v_outcome := 'failure';
        END IF;
        
        -- Compute best e1RM (Brzycki, only for reps <= 12)
        SELECT MAX(weight_kg / (1.0278 - 0.0278 * reps))
        INTO v_best_e1rm
        FROM session_sets
        WHERE session_exercise_id = v_exercise.id
          AND is_warmup = FALSE
          AND is_completed = TRUE
          AND reps BETWEEN 1 AND 12
          AND NOT COALESCE(is_failure, FALSE);
        
        -- Update the exercise
        UPDATE session_exercises
        SET 
            exposure_outcome = v_outcome,
            sets_successful = v_success_count,
            sets_failed = v_failure_count,
            session_e1rm_kg = v_best_e1rm,
            e1rm_delta_kg = v_best_e1rm - state_snapshot_rolling_e1rm_kg
        WHERE id = v_exercise.id;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 10. SET OUTCOME COMPUTATION FUNCTION (3-STATE LABELS)
-- ============================================
-- CRITICAL: Returns 'unknown_difficulty' when reps are hit but RIR is missing.
-- This prevents labeling "probably too hard" sets as success.
-- RIR missingness is correlated with failure risk (users skip logging when rushed/tired).

CREATE OR REPLACE FUNCTION compute_set_outcome(
    p_reps INT,
    p_target_reps INT,
    p_rir_observed INT,
    p_target_rir INT,
    p_is_failure BOOLEAN,
    p_pain_stop BOOLEAN
) RETURNS TEXT AS $$
BEGIN
    -- Pain stop - exclude from training entirely
    IF p_pain_stop THEN
        RETURN 'pain_stop';
    END IF;
    
    -- Explicit failure flag
    IF p_is_failure THEN
        RETURN 'failure';
    END IF;
    
    -- Missed reps = definite failure
    IF p_reps < p_target_reps THEN
        RETURN 'failure';
    END IF;
    
    -- Reps achieved - now check effort
    IF p_rir_observed IS NOT NULL THEN
        -- RIR present - we have clean labels
        IF p_rir_observed < (p_target_rir - 1) THEN
            RETURN 'grinder';  -- Hit reps but too hard (use as failure signal)
        ELSE
            RETURN 'success';  -- Clean success
        END IF;
    ELSE
        -- RIR missing - DO NOT assume success
        -- This is correlated with failure risk
        RETURN 'unknown_difficulty';
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION compute_set_outcome IS 
'3-state outcome label. Returns unknown_difficulty when reps hit but RIR missing. 
Do NOT use unknown_difficulty as clean success for training - RIR missingness is correlated with failure risk.';

-- ============================================
-- 11. TRIGGER to compute set outcomes on insert/update
-- ============================================
CREATE OR REPLACE FUNCTION trigger_compute_set_outcome()
RETURNS TRIGGER AS $$
DECLARE
    v_target_reps INT;
    v_target_rir INT;
BEGIN
    -- Get targets from planned_set if available
    SELECT target_reps, target_rir INTO v_target_reps, v_target_rir
    FROM planned_sets
    WHERE id = NEW.planned_set_id;
    
    -- Fallback to recommendation or defaults
    IF v_target_reps IS NULL THEN
        v_target_reps := COALESCE(NEW.recommended_reps, 8);
    END IF;
    IF v_target_rir IS NULL THEN
        v_target_rir := COALESCE(NEW.target_rir, 2);
    END IF;
    
    -- Compute outcome
    NEW.set_outcome := compute_set_outcome(
        NEW.reps,
        v_target_reps,
        NEW.rir_observed,
        v_target_rir,
        COALESCE(NEW.is_failure, FALSE),
        FALSE  -- pain_stop handled separately
    );
    
    NEW.met_rep_target := NEW.reps >= v_target_reps;
    NEW.met_effort_target := NEW.rir_observed IS NULL OR NEW.rir_observed >= (v_target_rir - 1);
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_outcome_trigger ON session_sets;
CREATE TRIGGER set_outcome_trigger
    BEFORE INSERT OR UPDATE ON session_sets
    FOR EACH ROW
    EXECUTE FUNCTION trigger_compute_set_outcome();
