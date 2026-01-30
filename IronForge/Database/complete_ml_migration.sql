-- ============================================================================
-- IRONFORGE ML TRAINING SCHEMA - COMPLETE MIGRATION
-- Version: 2.1
-- Run this ONCE in Supabase SQL Editor
-- ============================================================================
-- 
-- This migration adds:
-- 1. Recommendation events table (immutable policy log)
-- 2. Planned sets table (prescription at session start)
-- 3. Pain events table (normalized)
-- 4. User sensitive context table (opt-in)
-- 5. Exercise variants table
-- 6. All ML fields on session_sets, session_exercises, workout_sessions, daily_biometrics
-- 7. ML training views
-- 8. Outcome computation functions
--
-- ============================================================================

-- ============================================================================
-- SECTION 0: DROP VIEWS FIRST (they depend on tables)
-- ============================================================================
DROP VIEW IF EXISTS ml_training_exposures_clean CASCADE;
DROP VIEW IF EXISTS ml_training_exposures CASCADE;

-- ============================================================================
-- SECTION 1: NEW TABLES
-- ============================================================================

-- 1.1 RECOMMENDATION EVENTS (Immutable Policy Log)
-- CRITICAL: Never update, only append. Required for policy evaluation.
CREATE TABLE IF NOT EXISTS recommendation_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id UUID,
    session_exercise_id UUID,
    
    -- What was recommended
    exercise_id TEXT NOT NULL,
    recommended_weight_kg DECIMAL(10,3) NOT NULL,
    recommended_reps INT NOT NULL,
    recommended_sets INT NOT NULL,
    recommended_rir INT NOT NULL,
    
    -- Policy metadata
    policy_version TEXT NOT NULL DEFAULT 'v1.0',
    policy_type TEXT NOT NULL DEFAULT 'deterministic',
    action_type TEXT NOT NULL,
    reason_codes TEXT[] NOT NULL DEFAULT '{}',
    
    -- ML CRITICAL: Policy selection metadata (bandit/shadow mode)
    executed_policy_id TEXT,
    executed_action_probability DECIMAL(6,5),
    exploration_mode TEXT,
    shadow_policy_id TEXT,
    shadow_action_probability DECIMAL(6,5),
    
    -- Prediction & confidence
    predicted_p_success DECIMAL(4,3),
    model_confidence DECIMAL(4,3),
    
    -- Exploration
    is_exploration BOOLEAN NOT NULL DEFAULT FALSE,
    action_probability DECIMAL(6,5) NOT NULL DEFAULT 1.0,
    exploration_delta_kg DECIMAL(6,3),
    exploration_eligible BOOLEAN DEFAULT FALSE,
    exploration_blocked_reason TEXT,
    
    -- Candidate actions
    candidate_actions_json JSONB,
    
    -- Counterfactual
    deterministic_weight_kg DECIMAL(10,3),
    deterministic_reps INT,
    deterministic_p_success DECIMAL(4,3),
    
    -- State snapshot (prevents leakage)
    state_at_recommendation JSONB NOT NULL DEFAULT '{}',
    
    generated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Add ALL columns if table already exists (idempotent)
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS exercise_id TEXT;
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS recommended_weight_kg DECIMAL(10,3);
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS recommended_reps INT;
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS recommended_sets INT;
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS recommended_rir INT;
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS policy_version TEXT DEFAULT 'v1.0';
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS policy_type TEXT DEFAULT 'deterministic';
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS action_type TEXT;
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS reason_codes TEXT[] DEFAULT '{}';
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS predicted_p_success DECIMAL(4,3);
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS model_confidence DECIMAL(4,3);
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS is_exploration BOOLEAN DEFAULT FALSE;
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS action_probability DECIMAL(6,5) DEFAULT 1.0;
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS exploration_delta_kg DECIMAL(6,3);
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS exploration_eligible BOOLEAN DEFAULT FALSE;
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS exploration_blocked_reason TEXT;
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS candidate_actions_json JSONB;
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS deterministic_weight_kg DECIMAL(10,3);
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS deterministic_reps INT;
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS deterministic_p_success DECIMAL(4,3);
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS state_at_recommendation JSONB DEFAULT '{}';
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS executed_policy_id TEXT;
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS executed_action_probability DECIMAL(6,5);
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS exploration_mode TEXT;
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS shadow_policy_id TEXT;
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS shadow_action_probability DECIMAL(6,5);
ALTER TABLE recommendation_events ADD COLUMN IF NOT EXISTS generated_at TIMESTAMPTZ DEFAULT NOW();

CREATE INDEX IF NOT EXISTS idx_rec_events_user_exercise ON recommendation_events(user_id, exercise_id);
CREATE INDEX IF NOT EXISTS idx_rec_events_session ON recommendation_events(session_id);
CREATE INDEX IF NOT EXISTS idx_rec_events_session_exercise ON recommendation_events(session_exercise_id);
CREATE INDEX IF NOT EXISTS idx_rec_events_policy ON recommendation_events(policy_version, policy_type);
CREATE INDEX IF NOT EXISTS idx_rec_events_exploration ON recommendation_events(is_exploration) WHERE is_exploration = TRUE;
CREATE INDEX IF NOT EXISTS idx_rec_events_time ON recommendation_events(generated_at);

-- 1.2 PLANNED SETS (Immutable prescription)
CREATE TABLE IF NOT EXISTS planned_sets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_exercise_id UUID NOT NULL,
    recommendation_event_id UUID,
    
    set_number INT NOT NULL,
    target_weight_kg DECIMAL(10,3) NOT NULL,
    target_reps INT NOT NULL,
    target_rir INT NOT NULL DEFAULT 2,
    target_rest_seconds INT,
    
    target_tempo_eccentric INT,
    target_tempo_pause_bottom INT,
    target_tempo_concentric INT,
    target_tempo_pause_top INT,
    
    is_warmup BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    UNIQUE(session_exercise_id, set_number)
);

CREATE INDEX IF NOT EXISTS idx_planned_sets_exercise ON planned_sets(session_exercise_id);
CREATE INDEX IF NOT EXISTS idx_planned_sets_recommendation ON planned_sets(recommendation_event_id);

-- 1.3 POLICY DECISION LOGS (Policy selection attribution)
-- Captures decision-time policy choice + propensity, and later outcome markers.
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

-- RLS (match the rest of the user-owned tables)
ALTER TABLE policy_decision_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS policy_decision_logs_select ON policy_decision_logs;
DROP POLICY IF EXISTS policy_decision_logs_insert ON policy_decision_logs;
DROP POLICY IF EXISTS policy_decision_logs_update ON policy_decision_logs;
DROP POLICY IF EXISTS policy_decision_logs_delete ON policy_decision_logs;
CREATE POLICY policy_decision_logs_select ON policy_decision_logs FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY policy_decision_logs_insert ON policy_decision_logs FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY policy_decision_logs_update ON policy_decision_logs FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY policy_decision_logs_delete ON policy_decision_logs FOR DELETE USING (auth.uid() = user_id);

-- 1.3 PAIN EVENTS (Normalized)
CREATE TABLE IF NOT EXISTS pain_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id UUID,
    session_exercise_id UUID,
    session_set_id UUID,
    
    body_region TEXT NOT NULL,
    severity INT NOT NULL CHECK (severity >= 0 AND severity <= 10),
    pain_type TEXT,
    caused_stop BOOLEAN NOT NULL DEFAULT FALSE,
    notes TEXT,
    
    reported_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pain_events_user ON pain_events(user_id);
CREATE INDEX IF NOT EXISTS idx_pain_events_session ON pain_events(session_id);
CREATE INDEX IF NOT EXISTS idx_pain_events_exercise ON pain_events(session_exercise_id);
CREATE INDEX IF NOT EXISTS idx_pain_events_high_severity ON pain_events(severity) WHERE severity >= 5;

-- 1.4 USER SENSITIVE CONTEXT (Opt-in)
CREATE TABLE IF NOT EXISTS user_sensitive_context (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    
    cycle_phase TEXT,
    cycle_day_number INT,
    on_hormonal_birth_control BOOLEAN,
    
    nutrition_bucket TEXT,
    protein_bucket TEXT,
    
    mood_score INT CHECK (mood_score IS NULL OR (mood_score >= 1 AND mood_score <= 5)),
    stress_level INT CHECK (stress_level IS NULL OR (stress_level >= 1 AND stress_level <= 5)),
    
    consented_to_ml_training BOOLEAN NOT NULL DEFAULT FALSE,
    consent_timestamp TIMESTAMPTZ,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    UNIQUE(user_id, date)
);

CREATE INDEX IF NOT EXISTS idx_sensitive_context_user_date ON user_sensitive_context(user_id, date);

-- 1.5 EXERCISE VARIANTS
CREATE TABLE IF NOT EXISTS exercise_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    base_exercise_id TEXT NOT NULL,
    variant_name TEXT NOT NULL,
    
    implement TEXT,
    angle TEXT,
    grip TEXT,
    stance TEXT,
    rom_modifier TEXT,
    
    strength_ratio_estimate DECIMAL(3,2) DEFAULT 1.0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_exercise_variants_base ON exercise_variants(base_exercise_id);

-- ============================================================================
-- SECTION 2: ALTER EXISTING TABLES
-- ============================================================================

-- 2.1 SESSION_SETS - Add ML fields
ALTER TABLE session_sets
ADD COLUMN IF NOT EXISTS planned_set_id UUID,
ADD COLUMN IF NOT EXISTS target_rir INT,
ADD COLUMN IF NOT EXISTS target_rpe DECIMAL(3,1),
ADD COLUMN IF NOT EXISTS actual_rest_seconds INT,
ADD COLUMN IF NOT EXISTS is_dropset BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS is_user_modified BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS original_prescribed_weight_kg DECIMAL(10,3),
ADD COLUMN IF NOT EXISTS original_prescribed_reps INT,
ADD COLUMN IF NOT EXISTS modification_reason TEXT,
ADD COLUMN IF NOT EXISTS compliance TEXT,
ADD COLUMN IF NOT EXISTS compliance_reason TEXT,
ADD COLUMN IF NOT EXISTS recommended_weight_kg DECIMAL(10,3),
ADD COLUMN IF NOT EXISTS recommended_reps INT,
ADD COLUMN IF NOT EXISTS tempo_eccentric INT,
ADD COLUMN IF NOT EXISTS tempo_pause_bottom INT,
ADD COLUMN IF NOT EXISTS tempo_concentric INT,
ADD COLUMN IF NOT EXISTS tempo_pause_top INT,
ADD COLUMN IF NOT EXISTS has_limited_rom BOOLEAN,
ADD COLUMN IF NOT EXISTS has_grip_issue BOOLEAN,
ADD COLUMN IF NOT EXISTS has_stability_issue BOOLEAN,
ADD COLUMN IF NOT EXISTS has_breathing_issue BOOLEAN,
ADD COLUMN IF NOT EXISTS has_technique_other BOOLEAN,
ADD COLUMN IF NOT EXISTS technique_limitation_notes TEXT,
ADD COLUMN IF NOT EXISTS set_outcome TEXT,
ADD COLUMN IF NOT EXISTS met_rep_target BOOLEAN,
ADD COLUMN IF NOT EXISTS met_effort_target BOOLEAN;

CREATE INDEX IF NOT EXISTS idx_session_sets_outcome ON session_sets(set_outcome);
CREATE INDEX IF NOT EXISTS idx_session_sets_clean_outcome ON session_sets(set_outcome) 
    WHERE set_outcome IN ('success', 'failure', 'grinder');

-- 2.2 SESSION_EXERCISES - Add ML fields
ALTER TABLE session_exercises
-- State snapshot (CRITICAL - prevents leakage)
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
-- Exposure definition
ADD COLUMN IF NOT EXISTS exposure_role TEXT,
ADD COLUMN IF NOT EXISTS primary_set_id UUID,
ADD COLUMN IF NOT EXISTS planned_top_set_weight_kg DECIMAL(10,3),
ADD COLUMN IF NOT EXISTS planned_top_set_reps INT,
ADD COLUMN IF NOT EXISTS planned_target_rir INT,
ADD COLUMN IF NOT EXISTS performed_top_set_weight_kg DECIMAL(10,3),
ADD COLUMN IF NOT EXISTS performed_top_set_reps INT,
ADD COLUMN IF NOT EXISTS performed_top_set_rir INT,
-- Outcome labels
ADD COLUMN IF NOT EXISTS exposure_outcome TEXT,
ADD COLUMN IF NOT EXISTS sets_successful INT,
ADD COLUMN IF NOT EXISTS sets_failed INT,
ADD COLUMN IF NOT EXISTS sets_unknown_difficulty INT,
ADD COLUMN IF NOT EXISTS session_e1rm_kg DECIMAL(10,3),
ADD COLUMN IF NOT EXISTS raw_top_set_e1rm_kg DECIMAL(10,3),
ADD COLUMN IF NOT EXISTS e1rm_delta_kg DECIMAL(10,3),
-- Near-failure signals
ADD COLUMN IF NOT EXISTS near_failure_missed_reps BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS near_failure_last_rep_grind BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS near_failure_long_rest BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS near_failure_session_ended_early BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS near_failure_next_load_reduced BOOLEAN,
ADD COLUMN IF NOT EXISTS near_failure_score DECIMAL(3,2),
-- Modification details
ADD COLUMN IF NOT EXISTS modification_delta_weight_kg DECIMAL(8,3),
ADD COLUMN IF NOT EXISTS modification_delta_reps INT,
ADD COLUMN IF NOT EXISTS modification_direction TEXT,
ADD COLUMN IF NOT EXISTS modification_reason_code TEXT,
-- Pain tracking
ADD COLUMN IF NOT EXISTS pain_entries_json JSONB,
ADD COLUMN IF NOT EXISTS overall_pain_level INT,
ADD COLUMN IF NOT EXISTS stopped_due_to_pain BOOLEAN DEFAULT FALSE,
-- Substitution tracking
ADD COLUMN IF NOT EXISTS original_exercise_id TEXT,
ADD COLUMN IF NOT EXISTS original_exercise_name TEXT,
ADD COLUMN IF NOT EXISTS substitution_reason TEXT,
ADD COLUMN IF NOT EXISTS is_substitution BOOLEAN DEFAULT FALSE,
-- Equipment/compliance
ADD COLUMN IF NOT EXISTS equipment_variation TEXT,
ADD COLUMN IF NOT EXISTS exercise_compliance TEXT,
ADD COLUMN IF NOT EXISTS exercise_compliance_reason TEXT,
-- Technique
ADD COLUMN IF NOT EXISTS has_limited_rom BOOLEAN,
ADD COLUMN IF NOT EXISTS has_grip_issue BOOLEAN,
ADD COLUMN IF NOT EXISTS has_stability_issue BOOLEAN,
ADD COLUMN IF NOT EXISTS has_breathing_issue BOOLEAN,
ADD COLUMN IF NOT EXISTS has_technique_other BOOLEAN,
ADD COLUMN IF NOT EXISTS technique_limitation_notes TEXT,
-- Recommendation link
ADD COLUMN IF NOT EXISTS recommendation_event_id UUID;

CREATE INDEX IF NOT EXISTS idx_session_exercises_outcome ON session_exercises(exposure_outcome);
CREATE INDEX IF NOT EXISTS idx_session_exercises_clean_labels ON session_exercises(exposure_outcome) 
    WHERE exposure_outcome IN ('success', 'failure', 'partial');
CREATE INDEX IF NOT EXISTS idx_session_exercises_near_failure ON session_exercises(near_failure_score) 
    WHERE near_failure_score IS NOT NULL AND near_failure_score >= 0.4;
CREATE INDEX IF NOT EXISTS idx_session_exercises_recommendation ON session_exercises(recommendation_event_id);

-- 2.3 WORKOUT_SESSIONS - Add ML fields
ALTER TABLE workout_sessions
-- Plan timing
ADD COLUMN IF NOT EXISTS planned_at TIMESTAMPTZ,
-- Pre-session signals
ADD COLUMN IF NOT EXISTS pre_workout_readiness INT,
ADD COLUMN IF NOT EXISTS pre_workout_soreness INT,
ADD COLUMN IF NOT EXISTS pre_workout_energy INT,
ADD COLUMN IF NOT EXISTS pre_workout_motivation INT,
-- Post-session signals
ADD COLUMN IF NOT EXISTS session_rpe INT,
ADD COLUMN IF NOT EXISTS post_workout_feeling INT,
ADD COLUMN IF NOT EXISTS harder_than_expected BOOLEAN,
-- Pain tracking
ADD COLUMN IF NOT EXISTS session_pain_entries_json JSONB,
ADD COLUMN IF NOT EXISTS max_pain_level INT,
ADD COLUMN IF NOT EXISTS any_stopped_due_to_pain BOOLEAN DEFAULT FALSE,
-- Life stress flags
ADD COLUMN IF NOT EXISTS has_illness BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS has_travel BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS has_work_stress BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS has_poor_sleep BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS has_other_stress BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS stress_notes TEXT,
-- Context signals
ADD COLUMN IF NOT EXISTS time_of_day TEXT,
ADD COLUMN IF NOT EXISTS was_fasted BOOLEAN,
ADD COLUMN IF NOT EXISTS hours_since_last_meal DECIMAL(4,2),
ADD COLUMN IF NOT EXISTS sleep_quality_last_night INT,
ADD COLUMN IF NOT EXISTS sleep_hours_last_night DECIMAL(4,2);

CREATE INDEX IF NOT EXISTS idx_workout_sessions_rpe ON workout_sessions(session_rpe);
CREATE INDEX IF NOT EXISTS idx_workout_sessions_readiness ON workout_sessions(pre_workout_readiness);

-- 2.4 DAILY_BIOMETRICS - Add ML fields
ALTER TABLE daily_biometrics
ADD COLUMN IF NOT EXISTS sleep_disruptions INT,
ADD COLUMN IF NOT EXISTS lean_body_mass_kg DECIMAL(6,2),
ADD COLUMN IF NOT EXISTS body_weight_from_healthkit BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS nutrition_bucket TEXT,
ADD COLUMN IF NOT EXISTS protein_bucket TEXT,
ADD COLUMN IF NOT EXISTS protein_grams INT,
ADD COLUMN IF NOT EXISTS calories_consumed INT,
ADD COLUMN IF NOT EXISTS hydration_level INT,
ADD COLUMN IF NOT EXISTS alcohol_level INT,
ADD COLUMN IF NOT EXISTS cycle_phase TEXT,
ADD COLUMN IF NOT EXISTS cycle_day_number INT,
ADD COLUMN IF NOT EXISTS on_hormonal_birth_control BOOLEAN,
ADD COLUMN IF NOT EXISTS mood_score INT,
ADD COLUMN IF NOT EXISTS has_illness BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS has_travel BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS has_work_stress BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS had_poor_sleep BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS has_other_stress BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS stress_notes TEXT;

-- ============================================================================
-- SECTION 2.5: FOREIGN KEYS (JOINABILITY GUARANTEES)
-- ============================================================================
-- These constraints enforce the join keys used for ML training:
-- - session_exercises.recommendation_event_id -> recommendation_events.id
-- - session_sets.planned_set_id -> planned_sets.id
-- - planned_sets.session_exercise_id -> session_exercises.id
-- - planned_sets.recommendation_event_id -> recommendation_events.id
--
-- NOTE: Postgres doesn't support `ADD CONSTRAINT IF NOT EXISTS`, so we guard via pg_constraint.

DO $$
BEGIN
    -- Enforce joinability: do NOT silently null out attribution if a referenced row is deleted.
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'session_exercises_recommendation_event_id_fkey')
       AND (SELECT confdeltype FROM pg_constraint WHERE conname = 'session_exercises_recommendation_event_id_fkey' LIMIT 1) <> 'r' THEN
        ALTER TABLE session_exercises
        DROP CONSTRAINT session_exercises_recommendation_event_id_fkey;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'session_exercises_recommendation_event_id_fkey') THEN
        ALTER TABLE session_exercises
        ADD CONSTRAINT session_exercises_recommendation_event_id_fkey
        FOREIGN KEY (recommendation_event_id) REFERENCES recommendation_events(id) ON DELETE RESTRICT;
    END IF;
END $$;

DO $$
BEGIN
    -- If a planned_set is deleted (e.g., exercise removed), delete dependent performed rows too.
    -- This avoids "orphaned but valid" session_sets that break attribution.
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'session_sets_planned_set_id_fkey')
       AND (SELECT confdeltype FROM pg_constraint WHERE conname = 'session_sets_planned_set_id_fkey' LIMIT 1) <> 'c' THEN
        ALTER TABLE session_sets
        DROP CONSTRAINT session_sets_planned_set_id_fkey;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'session_sets_planned_set_id_fkey') THEN
        ALTER TABLE session_sets
        ADD CONSTRAINT session_sets_planned_set_id_fkey
        FOREIGN KEY (planned_set_id) REFERENCES planned_sets(id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'planned_sets_session_exercise_id_fkey') THEN
        ALTER TABLE planned_sets
        ADD CONSTRAINT planned_sets_session_exercise_id_fkey
        FOREIGN KEY (session_exercise_id) REFERENCES session_exercises(id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    -- Enforce joinability for immutable attribution rows.
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'planned_sets_recommendation_event_id_fkey')
       AND (SELECT confdeltype FROM pg_constraint WHERE conname = 'planned_sets_recommendation_event_id_fkey' LIMIT 1) <> 'r' THEN
        ALTER TABLE planned_sets
        DROP CONSTRAINT planned_sets_recommendation_event_id_fkey;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'planned_sets_recommendation_event_id_fkey') THEN
        ALTER TABLE planned_sets
        ADD CONSTRAINT planned_sets_recommendation_event_id_fkey
        FOREIGN KEY (recommendation_event_id) REFERENCES recommendation_events(id) ON DELETE RESTRICT;
    END IF;
END $$;

-- Post-migration validation: fail fast if we didn't reach the expected final schema.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'session_exercises_recommendation_event_id_fkey') THEN
        RAISE EXCEPTION 'Missing constraint: session_exercises_recommendation_event_id_fkey';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'session_sets_planned_set_id_fkey') THEN
        RAISE EXCEPTION 'Missing constraint: session_sets_planned_set_id_fkey';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'planned_sets_session_exercise_id_fkey') THEN
        RAISE EXCEPTION 'Missing constraint: planned_sets_session_exercise_id_fkey';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'planned_sets_recommendation_event_id_fkey') THEN
        RAISE EXCEPTION 'Missing constraint: planned_sets_recommendation_event_id_fkey';
    END IF;

    IF (SELECT confdeltype FROM pg_constraint WHERE conname = 'session_exercises_recommendation_event_id_fkey' LIMIT 1) <> 'r' THEN
        RAISE EXCEPTION 'Constraint session_exercises_recommendation_event_id_fkey must be ON DELETE RESTRICT';
    END IF;
    IF (SELECT confdeltype FROM pg_constraint WHERE conname = 'session_sets_planned_set_id_fkey' LIMIT 1) <> 'c' THEN
        RAISE EXCEPTION 'Constraint session_sets_planned_set_id_fkey must be ON DELETE CASCADE';
    END IF;
    IF (SELECT confdeltype FROM pg_constraint WHERE conname = 'planned_sets_session_exercise_id_fkey' LIMIT 1) <> 'c' THEN
        RAISE EXCEPTION 'Constraint planned_sets_session_exercise_id_fkey must be ON DELETE CASCADE';
    END IF;
    IF (SELECT confdeltype FROM pg_constraint WHERE conname = 'planned_sets_recommendation_event_id_fkey' LIMIT 1) <> 'r' THEN
        RAISE EXCEPTION 'Constraint planned_sets_recommendation_event_id_fkey must be ON DELETE RESTRICT';
    END IF;
END $$;

-- ============================================================================
-- SECTION 3: FUNCTIONS
-- ============================================================================

-- 3.1 SET OUTCOME COMPUTATION (3-STATE LABELS)
CREATE OR REPLACE FUNCTION compute_set_outcome(
    p_reps INT,
    p_target_reps INT,
    p_rir_observed INT,
    p_target_rir INT,
    p_is_failure BOOLEAN,
    p_pain_stop BOOLEAN
) RETURNS TEXT AS $$
BEGIN
    IF p_pain_stop THEN
        RETURN 'pain_stop';
    END IF;
    
    IF p_is_failure THEN
        RETURN 'failure';
    END IF;
    
    IF p_reps < p_target_reps THEN
        RETURN 'failure';
    END IF;
    
    IF p_rir_observed IS NOT NULL THEN
        IF p_rir_observed < (p_target_rir - 1) THEN
            RETURN 'grinder';
        ELSE
            RETURN 'success';
        END IF;
    ELSE
        RETURN 'unknown_difficulty';
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- 3.2 EXPOSURE OUTCOME COMPUTATION
CREATE OR REPLACE FUNCTION compute_exposure_outcomes(p_session_id UUID)
RETURNS VOID AS $$
DECLARE
    v_exercise RECORD;
    v_success_count INT;
    v_failure_count INT;
    v_unknown_count INT;
    v_outcome TEXT;
    v_best_e1rm DECIMAL;
BEGIN
    FOR v_exercise IN 
        SELECT se.* 
        FROM session_exercises se 
        WHERE se.session_id = p_session_id
    LOOP
        SELECT 
            COUNT(*) FILTER (WHERE set_outcome = 'success'),
            COUNT(*) FILTER (WHERE set_outcome IN ('failure', 'grinder')),
            COUNT(*) FILTER (WHERE set_outcome = 'unknown_difficulty')
        INTO v_success_count, v_failure_count, v_unknown_count
        FROM session_sets
        WHERE session_exercise_id = v_exercise.id
          AND is_warmup = FALSE
          AND is_completed = TRUE;
        
        IF v_exercise.stopped_due_to_pain THEN
            v_outcome := 'pain_stop';
        ELSIF v_failure_count = 0 AND v_success_count > 0 AND v_unknown_count = 0 THEN
            v_outcome := 'success';
        ELSIF v_failure_count = 0 AND v_success_count > 0 AND v_unknown_count > 0 THEN
            v_outcome := 'unknown_difficulty';
        ELSIF v_success_count > v_failure_count THEN
            v_outcome := 'partial';
        ELSIF v_success_count = 0 AND v_failure_count = 0 THEN
            v_outcome := 'skipped';
        ELSE
            v_outcome := 'failure';
        END IF;
        
        SELECT MAX(weight_kg / (1.0278 - 0.0278 * reps))
        INTO v_best_e1rm
        FROM session_sets
        WHERE session_exercise_id = v_exercise.id
          AND is_warmup = FALSE
          AND is_completed = TRUE
          AND reps BETWEEN 1 AND 12
          AND NOT COALESCE(is_failure, FALSE);
        
        UPDATE session_exercises
        SET 
            exposure_outcome = v_outcome,
            sets_successful = v_success_count,
            sets_failed = v_failure_count,
            sets_unknown_difficulty = v_unknown_count,
            session_e1rm_kg = v_best_e1rm,
            e1rm_delta_kg = v_best_e1rm - state_snapshot_rolling_e1rm_kg
        WHERE id = v_exercise.id;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- 3.3 SET OUTCOME TRIGGER
CREATE OR REPLACE FUNCTION trigger_compute_set_outcome()
RETURNS TRIGGER AS $$
DECLARE
    v_target_reps INT;
    v_target_rir INT;
BEGIN
    SELECT target_reps, target_rir INTO v_target_reps, v_target_rir
    FROM planned_sets
    WHERE id = NEW.planned_set_id;
    
    IF v_target_reps IS NULL THEN
        v_target_reps := COALESCE(NEW.recommended_reps, 8);
    END IF;
    IF v_target_rir IS NULL THEN
        v_target_rir := COALESCE(NEW.target_rir, 2);
    END IF;
    
    NEW.set_outcome := compute_set_outcome(
        NEW.reps,
        v_target_reps,
        NEW.rir_observed,
        v_target_rir,
        COALESCE(NEW.is_failure, FALSE),
        FALSE
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

-- ============================================================================
-- SECTION 4: ML TRAINING VIEWS
-- ============================================================================

-- 4.1 MAIN TRAINING VIEW
CREATE OR REPLACE VIEW ml_training_exposures AS
SELECT 
    se.id as exposure_id,
    ws.user_id,
    ws.id as session_id,
    se.exercise_id,
    se.exercise_name,
    
    ws.started_at as session_date,
    EXTRACT(DOW FROM ws.started_at) as day_of_week,
    EXTRACT(HOUR FROM ws.started_at) as hour_of_day,
    
    -- State snapshot (NO LEAKAGE)
    se.state_snapshot_rolling_e1rm_kg as e1rm_at_start,
    se.state_snapshot_raw_e1rm_kg as raw_e1rm_at_start,
    se.state_snapshot_consecutive_failures as failures_at_start,
    se.state_snapshot_consecutive_successes as successes_at_start,
    se.state_snapshot_high_rpe_streak as high_rpe_streak_at_start,
    se.state_snapshot_days_since_last_exposure as days_since_last,
    se.state_snapshot_days_since_last_deload as days_since_deload,
    se.state_snapshot_last_weight_kg as last_weight_kg,
    se.state_snapshot_last_reps as last_reps,
    se.state_snapshot_last_rir as last_rir,
    se.state_snapshot_last_outcome as last_outcome,
    se.state_snapshot_exposures_last_14d as exposures_last_14d,
    se.state_snapshot_volume_last_7d_kg as volume_last_7d_kg,
    se.state_snapshot_successful_sessions as successful_sessions_at_start,
    se.state_snapshot_total_sessions as total_sessions_at_start,
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
    
    -- Prescription
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
    
    -- Performance
    se.total_sets_completed as sets_performed,
    se.total_reps_completed as reps_performed,
    ROUND(se.total_volume_kg / NULLIF(se.total_reps_completed, 0), 2) as avg_weight_kg,
    
    -- Outcomes (3-state)
    se.exposure_outcome,
    se.sets_successful,
    se.sets_failed,
    se.sets_unknown_difficulty,
    CASE WHEN se.exposure_outcome IN ('success', 'failure', 'partial') THEN TRUE ELSE FALSE END as is_clean_label,
    CASE WHEN se.exposure_outcome = 'success' THEN TRUE ELSE FALSE END as is_success,
    
    -- e1RM outcomes
    se.session_e1rm_kg,
    se.raw_top_set_e1rm_kg,
    se.e1rm_delta_kg,
    
    -- Near-failure signals
    se.near_failure_missed_reps,
    se.near_failure_last_rep_grind,
    se.near_failure_long_rest,
    se.near_failure_session_ended_early,
    se.near_failure_next_load_reduced,
    se.near_failure_score,
    CASE WHEN se.near_failure_score >= 0.4 THEN TRUE ELSE FALSE END as is_too_aggressive,
    
    -- Modifications
    se.modification_delta_weight_kg,
    se.modification_delta_reps,
    se.modification_direction,
    se.modification_reason_code,
    
    -- Context
    ws.pre_workout_readiness,
    ws.session_rpe,
    ws.was_deload,
    se.stopped_due_to_pain,
    (SELECT MAX(severity) FROM pain_events pe WHERE pe.session_exercise_id = se.id) as max_pain_severity

FROM session_exercises se
JOIN workout_sessions ws ON se.session_id = ws.id
LEFT JOIN recommendation_events re ON re.session_exercise_id = se.id
WHERE 
    ws.ended_at IS NOT NULL
    AND se.is_completed = TRUE
    AND se.total_sets_completed > 0;

-- 4.2 CLEAN LABELS VIEW
CREATE OR REPLACE VIEW ml_training_exposures_clean AS
SELECT * FROM ml_training_exposures
WHERE is_clean_label = TRUE;

-- ============================================================================
-- SECTION 5: COMMENTS
-- ============================================================================

COMMENT ON TABLE recommendation_events IS 'Immutable log of all recommendations. NEVER update, only append.';
COMMENT ON TABLE planned_sets IS 'Prescription at session start. Immutable once created.';
COMMENT ON TABLE pain_events IS 'Normalized pain tracking. One row per pain report.';
COMMENT ON TABLE user_sensitive_context IS 'Sensitive user data. Opt-in with explicit consent.';
COMMENT ON VIEW ml_training_exposures IS 'ML training data. Uses snapshots to prevent leakage. Use is_clean_label=TRUE for binary classification.';
COMMENT ON VIEW ml_training_exposures_clean IS 'ML training data filtered to clean labels only.';
COMMENT ON FUNCTION compute_set_outcome IS '3-state outcome. unknown_difficulty = RIR missing, NOT a clean success.';

-- ============================================================================
-- DONE
-- ============================================================================
SELECT 'Migration complete. Tables created: recommendation_events, planned_sets, pain_events, user_sensitive_context, exercise_variants. Views created: ml_training_exposures, ml_training_exposures_clean.' as status;
