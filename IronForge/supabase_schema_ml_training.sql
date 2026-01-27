-- IronForge / Atlas Supabase Schema - ML TRAINING DATA COLLECTION
-- Extended schema for comprehensive ML training data with data quality controls
-- Run this AFTER supabase_schema_pilot.sql

-- 1. ML DECISION RECORDS (Enhanced engine_trajectories with full feature vectors)

CREATE TABLE IF NOT EXISTS public.ml_decision_records (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    session_id UUID REFERENCES public.workout_sessions(id) ON DELETE SET NULL,
    exercise_id TEXT NOT NULL,
    
    decision_timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    session_date DATE NOT NULL,
    
    -- DATA QUALITY FLAGS
    collection_status TEXT NOT NULL DEFAULT 'pending' CHECK (collection_status IN (
        'pending',
        'outcome_recorded',
        'validated',
        'invalidated',
        'expired'
    )),
    
    validation_unit_consistent BOOLEAN,
    validation_timing_valid BOOLEAN,
    validation_load_plausible BOOLEAN,
    validation_context_complete BOOLEAN,
    validation_no_known_anomaly BOOLEAN,
    
    invalidation_reason TEXT,
    invalidated_at TIMESTAMPTZ,
    data_completeness_score INTEGER,
    
    -- FEATURES: HISTORY SUMMARY
    hist_session_count INTEGER,
    hist_sessions_last_7d INTEGER,
    hist_sessions_last_14d INTEGER,
    hist_sessions_last_28d INTEGER,
    hist_volume_last_7d NUMERIC(10,2),
    hist_volume_last_14d NUMERIC(10,2),
    hist_avg_session_duration_min NUMERIC(5,1),
    hist_deload_sessions_last_28d INTEGER,
    hist_days_since_last_workout INTEGER,
    hist_training_streak_weeks INTEGER,
    
    -- FEATURES: LAST N EXPOSURES (JSONB array)
    last_exposures JSONB DEFAULT '[]'::jsonb,
    last_exposures_count INTEGER DEFAULT 0,
    
    -- FEATURES: TREND STATISTICS
    trend_direction TEXT CHECK (trend_direction IN ('improving', 'stable', 'declining', 'insufficient')),
    trend_slope_per_session NUMERIC(8,4),
    trend_slope_percentage NUMERIC(6,2),
    trend_r_squared NUMERIC(4,3),
    trend_data_points INTEGER,
    trend_days_spanned INTEGER,
    trend_recent_volatility NUMERIC(8,2),
    trend_has_two_session_decline BOOLEAN,
    
    -- FEATURES: READINESS DISTRIBUTION
    readiness_current INTEGER,
    readiness_mean NUMERIC(5,2),
    readiness_median NUMERIC(5,2),
    readiness_stddev NUMERIC(5,2),
    readiness_min INTEGER,
    readiness_max INTEGER,
    readiness_low_count INTEGER,
    readiness_consecutive_low_days INTEGER,
    readiness_trend TEXT CHECK (readiness_trend IN ('improving', 'stable', 'declining')),
    readiness_sample_count INTEGER,
    
    -- FEATURES: CONSTRAINTS
    constraint_equipment_available BOOLEAN,
    constraint_rounding_increment NUMERIC(4,2),
    constraint_rounding_unit TEXT CHECK (constraint_rounding_unit IN ('pounds', 'kilograms')),
    constraint_microloading_enabled BOOLEAN,
    constraint_min_load_floor NUMERIC(6,2),
    constraint_max_load_ceiling NUMERIC(6,2),
    constraint_is_planned_deload_week BOOLEAN,
    
    -- FEATURES: VARIATION CONTEXT
    variation_is_primary BOOLEAN,
    variation_is_substitution BOOLEAN,
    variation_original_exercise_id TEXT,
    variation_family_reference_key TEXT,
    variation_family_update_key TEXT,
    variation_family_coefficient NUMERIC(4,2),
    variation_movement_pattern TEXT,
    variation_equipment TEXT,
    variation_state_is_exercise_specific BOOLEAN,
    
    -- FEATURES: SESSION INTENT
    session_intent TEXT CHECK (session_intent IN ('heavy', 'volume', 'light', 'general')),
    experience_level TEXT CHECK (experience_level IN ('beginner', 'intermediate', 'advanced', 'elite')),
    
    -- FEATURES: LIFT SIGNALS
    signals_last_working_weight_value NUMERIC(6,2),
    signals_last_working_weight_unit TEXT,
    signals_rolling_e1rm NUMERIC(6,2),
    signals_fail_streak INTEGER,
    signals_high_rpe_streak INTEGER,
    signals_success_streak INTEGER,
    signals_days_since_exposure INTEGER,
    signals_days_since_deload INTEGER,
    signals_successful_sessions_count INTEGER,
    signals_last_session_was_failure BOOLEAN,
    signals_last_session_was_grinder BOOLEAN,
    signals_last_session_avg_rir NUMERIC(4,2),
    signals_last_session_reps INTEGER[],
    signals_target_reps_lower INTEGER,
    signals_target_reps_upper INTEGER,
    signals_target_rir INTEGER,
    signals_load_strategy TEXT,
    signals_session_deload_triggered BOOLEAN,
    signals_session_deload_reason TEXT,
    signals_is_compound BOOLEAN,
    signals_is_upper_body_press BOOLEAN,
    signals_has_training_gap BOOLEAN,
    signals_has_extended_break BOOLEAN,
    signals_relative_strength NUMERIC(4,2),
    
    -- ACTION: ENGINE DECISION
    action_direction TEXT NOT NULL CHECK (action_direction IN (
        'increase', 'hold', 'decrease_slightly', 'deload', 'reset_after_break'
    )),
    action_primary_reason TEXT NOT NULL,
    action_contributing_reasons TEXT[],
    action_delta_load_value NUMERIC(6,2),
    action_delta_load_unit TEXT,
    action_load_multiplier NUMERIC(6,4),
    action_absolute_load_value NUMERIC(6,2) NOT NULL,
    action_absolute_load_unit TEXT NOT NULL,
    action_baseline_load_value NUMERIC(6,2),
    action_target_reps INTEGER NOT NULL,
    action_target_rir INTEGER NOT NULL,
    action_set_count INTEGER NOT NULL,
    action_volume_adjustment INTEGER,
    action_is_session_deload BOOLEAN,
    action_is_exercise_deload BOOLEAN,
    action_adjustment_kind TEXT CHECK (action_adjustment_kind IN ('none', 'deload', 'readiness_cut', 'break_reset')),
    action_explanation TEXT,
    action_confidence NUMERIC(4,3),
    
    -- POLICY TRACE
    policy_checks JSONB DEFAULT '[]'::jsonb,
    
    -- COUNTERFACTUALS
    counterfactuals JSONB DEFAULT '[]'::jsonb,
    
    -- METADATA
    engine_version TEXT NOT NULL,
    schema_version TEXT DEFAULT 'v1',
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ml_decision_user ON public.ml_decision_records(user_id, decision_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_ml_decision_exercise ON public.ml_decision_records(exercise_id, decision_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_ml_decision_session ON public.ml_decision_records(session_id);
CREATE INDEX IF NOT EXISTS idx_ml_decision_status ON public.ml_decision_records(collection_status);
CREATE INDEX IF NOT EXISTS idx_ml_decision_direction ON public.ml_decision_records(action_direction);
CREATE INDEX IF NOT EXISTS idx_ml_decision_validated ON public.ml_decision_records(collection_status) WHERE collection_status = 'validated';

-- 2. ML OUTCOME RECORDS

CREATE TABLE IF NOT EXISTS public.ml_outcome_records (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    decision_id UUID NOT NULL REFERENCES public.ml_decision_records(id) ON DELETE CASCADE,
    
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    outcome_source TEXT NOT NULL CHECK (outcome_source IN (
        'session_completion',
        'manual_entry',
        'inferred',
        'partial'
    )),
    
    hours_since_decision NUMERIC(6,2),
    
    execution_context TEXT CHECK (execution_context IN (
        'normal',
        'equipment_issue',
        'time_constraint',
        'injury_discomfort',
        'intentional_change',
        'environmental'
    )),
    
    outcome_reps_per_set INTEGER[] NOT NULL,
    outcome_avg_reps NUMERIC(4,2) NOT NULL,
    outcome_total_reps INTEGER NOT NULL,
    outcome_rir_per_set INTEGER[],
    outcome_avg_rir NUMERIC(4,2),
    outcome_actual_load_value NUMERIC(6,2) NOT NULL,
    outcome_actual_load_unit TEXT NOT NULL,
    outcome_session_e1rm NUMERIC(6,2),
    
    outcome_was_success BOOLEAN NOT NULL,
    outcome_was_failure BOOLEAN NOT NULL,
    outcome_was_grinder BOOLEAN NOT NULL,
    
    outcome_total_volume NUMERIC(10,2),
    
    in_session_adjustments JSONB DEFAULT '[]'::jsonb,
    
    load_deviation_value NUMERIC(6,2),
    load_deviation_percent NUMERIC(5,2),
    reps_vs_target TEXT CHECK (reps_vs_target IN ('below', 'at', 'above')),
    followed_prescription BOOLEAN,
    
    readiness_at_execution INTEGER,
    sleep_quality TEXT CHECK (sleep_quality IN ('poor', 'fair', 'good', 'excellent')),
    stress_level TEXT CHECK (stress_level IN ('low', 'moderate', 'high', 'extreme')),
    nutrition_quality TEXT CHECK (nutrition_quality IN ('poor', 'fair', 'good', 'excellent')),
    time_of_day TEXT CHECK (time_of_day IN ('morning', 'afternoon', 'evening', 'night')),
    
    pain_reported BOOLEAN DEFAULT false,
    pain_location TEXT,
    pain_severity INTEGER CHECK (pain_severity IS NULL OR (pain_severity >= 1 AND pain_severity <= 5)),
    
    user_overrode_prescription BOOLEAN DEFAULT false,
    override_direction TEXT CHECK (override_direction IN ('lighter', 'heavier', 'fewer_reps', 'more_reps', 'skipped')),
    override_reason TEXT,
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ml_outcome_decision ON public.ml_outcome_records(decision_id);
CREATE INDEX IF NOT EXISTS idx_ml_outcome_recorded ON public.ml_outcome_records(recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_ml_outcome_success ON public.ml_outcome_records(outcome_was_success);

-- 3. ML NEXT-SESSION PERFORMANCE

CREATE TABLE IF NOT EXISTS public.ml_next_session_performance (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    decision_id UUID NOT NULL REFERENCES public.ml_decision_records(id) ON DELETE CASCADE,
    next_decision_id UUID REFERENCES public.ml_decision_records(id) ON DELETE SET NULL,
    
    days_until_next_exposure INTEGER NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    next_load_value NUMERIC(6,2) NOT NULL,
    next_load_unit TEXT NOT NULL,
    load_delta_value NUMERIC(6,2),
    load_delta_percent NUMERIC(5,2),
    
    next_was_success BOOLEAN NOT NULL,
    next_was_failure BOOLEAN NOT NULL,
    
    e1rm_delta NUMERIC(6,2),
    e1rm_delta_percent NUMERIC(5,2),
    
    progression_status TEXT CHECK (progression_status IN (
        'progressed',
        'maintained',
        'regressed',
        'deload_recovery',
        'break_recovery'
    )),
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ml_next_decision ON public.ml_next_session_performance(decision_id);

-- 4. DATA QUALITY AUDIT LOG

CREATE TABLE IF NOT EXISTS public.ml_data_quality_audit (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    decision_id UUID NOT NULL REFERENCES public.ml_decision_records(id) ON DELETE CASCADE,
    
    audited_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    audit_type TEXT NOT NULL CHECK (audit_type IN (
        'automated',
        'manual_review',
        'anomaly_detected',
        'user_reported'
    )),
    
    checks_performed TEXT[] NOT NULL,
    
    passed_all_checks BOOLEAN NOT NULL,
    failed_checks TEXT[],
    warnings TEXT[],
    
    audit_details JSONB DEFAULT '{}'::jsonb,
    
    action_taken TEXT CHECK (action_taken IN (
        'none',
        'flagged_for_review',
        'invalidated',
        'corrected',
        'marked_low_quality'
    )),
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_decision ON public.ml_data_quality_audit(decision_id);
CREATE INDEX IF NOT EXISTS idx_audit_failed ON public.ml_data_quality_audit(passed_all_checks) WHERE NOT passed_all_checks;

-- 5. KNOWN DATA ANOMALIES

CREATE TABLE IF NOT EXISTS public.ml_known_anomalies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    user_id UUID REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    exercise_id TEXT,
    date_range_start DATE,
    date_range_end DATE,
    decision_ids UUID[],
    
    anomaly_type TEXT NOT NULL CHECK (anomaly_type IN (
        'unit_confusion',
        'data_entry_error',
        'equipment_change',
        'injury_period',
        'testing_data',
        'account_shared',
        'program_transition',
        'outlier_performance',
        'sync_issue',
        'other'
    )),
    
    description TEXT,
    
    handling TEXT DEFAULT 'exclude' CHECK (handling IN (
        'exclude',
        'flag_only',
        'correct',
        'review_needed'
    )),
    
    correction_applied JSONB,
    
    identified_by TEXT CHECK (identified_by IN ('system', 'user', 'analyst')),
    identified_at TIMESTAMPTZ DEFAULT NOW(),
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_anomaly_user ON public.ml_known_anomalies(user_id);
CREATE INDEX IF NOT EXISTS idx_anomaly_exercise ON public.ml_known_anomalies(exercise_id);
CREATE INDEX IF NOT EXISTS idx_anomaly_type ON public.ml_known_anomalies(anomaly_type);

-- 6. DATA COLLECTION CONFIGURATION

CREATE TABLE IF NOT EXISTS public.ml_collection_config (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    config_key TEXT NOT NULL UNIQUE,
    config_value JSONB NOT NULL,
    description TEXT,
    
    effective_from TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    effective_until TIMESTAMPTZ,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert default configuration
INSERT INTO public.ml_collection_config (config_key, config_value, description) VALUES
(
    'validation_thresholds',
    '{"max_hours_between_decision_and_outcome": 72, "max_load_change_percent_single_session": 25, "min_load_kg": 0.5, "max_load_kg": 500, "min_reps": 1, "max_reps": 100, "min_rir": 0, "max_rir": 10, "min_sets": 1, "max_sets": 20}'::jsonb,
    'Thresholds for automated validation checks'
),
(
    'anomaly_detection',
    '{"load_change_zscore_threshold": 3.0, "e1rm_change_zscore_threshold": 2.5, "consecutive_failures_alert": 4, "unit_confusion_ratio_threshold": 2.0}'::jsonb,
    'Parameters for anomaly detection algorithms'
),
(
    'data_quality_requirements',
    '{"min_completeness_for_training": 80, "required_fields_for_validation": ["action_direction", "action_absolute_load_value", "action_target_reps", "signals_last_working_weight_value"]}'::jsonb,
    'Minimum requirements for data to be used in training'
)
ON CONFLICT (config_key) DO NOTHING;

-- 7. RLS POLICIES

ALTER TABLE public.ml_decision_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ml_outcome_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ml_next_session_performance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ml_data_quality_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ml_known_anomalies ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'ml_decision_policy') THEN
        CREATE POLICY ml_decision_policy ON public.ml_decision_records FOR ALL USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'ml_outcome_policy') THEN
        CREATE POLICY ml_outcome_policy ON public.ml_outcome_records FOR ALL 
            USING (EXISTS (SELECT 1 FROM public.ml_decision_records d WHERE d.id = decision_id AND auth.uid() = d.user_id));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'ml_next_session_policy') THEN
        CREATE POLICY ml_next_session_policy ON public.ml_next_session_performance FOR ALL 
            USING (EXISTS (SELECT 1 FROM public.ml_decision_records d WHERE d.id = decision_id AND auth.uid() = d.user_id));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'ml_audit_policy') THEN
        CREATE POLICY ml_audit_policy ON public.ml_data_quality_audit FOR ALL 
            USING (EXISTS (SELECT 1 FROM public.ml_decision_records d WHERE d.id = decision_id AND auth.uid() = d.user_id));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'ml_anomaly_policy') THEN
        CREATE POLICY ml_anomaly_policy ON public.ml_known_anomalies FOR ALL USING (auth.uid() = user_id OR user_id IS NULL);
    END IF;
END $$;

-- 8. VALIDATION FUNCTION

CREATE OR REPLACE FUNCTION validate_ml_decision(decision_uuid UUID)
RETURNS BOOLEAN AS $$
DECLARE
    record public.ml_decision_records%ROWTYPE;
    config JSONB;
    all_valid BOOLEAN := true;
    reasons TEXT[] := ARRAY[]::TEXT[];
BEGIN
    SELECT * INTO record FROM public.ml_decision_records WHERE id = decision_uuid;
    IF NOT FOUND THEN
        RETURN false;
    END IF;
    
    SELECT config_value INTO config 
    FROM public.ml_collection_config 
    WHERE config_key = 'validation_thresholds';
    
    IF record.signals_last_working_weight_unit IS NOT NULL 
       AND record.action_absolute_load_unit IS NOT NULL
       AND record.signals_last_working_weight_unit != record.action_absolute_load_unit THEN
        UPDATE public.ml_decision_records 
        SET validation_unit_consistent = false 
        WHERE id = decision_uuid;
        all_valid := false;
        reasons := array_append(reasons, 'unit_mismatch');
    ELSE
        UPDATE public.ml_decision_records 
        SET validation_unit_consistent = true 
        WHERE id = decision_uuid;
    END IF;
    
    IF record.action_absolute_load_value < (config->>'min_load_kg')::numeric 
       OR record.action_absolute_load_value > (config->>'max_load_kg')::numeric THEN
        UPDATE public.ml_decision_records 
        SET validation_load_plausible = false 
        WHERE id = decision_uuid;
        all_valid := false;
        reasons := array_append(reasons, 'load_out_of_bounds');
    ELSE
        UPDATE public.ml_decision_records 
        SET validation_load_plausible = true 
        WHERE id = decision_uuid;
    END IF;
    
    IF record.action_direction IS NULL 
       OR record.action_absolute_load_value IS NULL
       OR record.action_target_reps IS NULL THEN
        UPDATE public.ml_decision_records 
        SET validation_context_complete = false 
        WHERE id = decision_uuid;
        all_valid := false;
        reasons := array_append(reasons, 'incomplete_context');
    ELSE
        UPDATE public.ml_decision_records 
        SET validation_context_complete = true 
        WHERE id = decision_uuid;
    END IF;
    
    IF all_valid THEN
        UPDATE public.ml_decision_records 
        SET collection_status = 'validated',
            validation_no_known_anomaly = true,
            updated_at = NOW()
        WHERE id = decision_uuid;
    ELSE
        UPDATE public.ml_decision_records 
        SET invalidation_reason = array_to_string(reasons, ', '),
            invalidated_at = NOW(),
            updated_at = NOW()
        WHERE id = decision_uuid;
    END IF;
    
    RETURN all_valid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 9. COMPLETENESS SCORE FUNCTION

CREATE OR REPLACE FUNCTION compute_completeness_score(decision_uuid UUID)
RETURNS INTEGER AS $$
DECLARE
    record public.ml_decision_records%ROWTYPE;
    score INTEGER := 0;
    total_fields INTEGER := 20;
    filled_fields INTEGER := 0;
BEGIN
    SELECT * INTO record FROM public.ml_decision_records WHERE id = decision_uuid;
    IF NOT FOUND THEN
        RETURN 0;
    END IF;
    
    IF record.hist_session_count IS NOT NULL THEN filled_fields := filled_fields + 1; END IF;
    IF record.last_exposures_count > 0 THEN filled_fields := filled_fields + 1; END IF;
    IF record.trend_direction IS NOT NULL THEN filled_fields := filled_fields + 1; END IF;
    IF record.readiness_current IS NOT NULL THEN filled_fields := filled_fields + 1; END IF;
    IF record.signals_last_working_weight_value IS NOT NULL THEN filled_fields := filled_fields + 1; END IF;
    IF record.signals_rolling_e1rm IS NOT NULL THEN filled_fields := filled_fields + 1; END IF;
    IF record.signals_fail_streak IS NOT NULL THEN filled_fields := filled_fields + 1; END IF;
    IF record.signals_success_streak IS NOT NULL THEN filled_fields := filled_fields + 1; END IF;
    IF record.action_direction IS NOT NULL THEN filled_fields := filled_fields + 1; END IF;
    IF record.action_primary_reason IS NOT NULL THEN filled_fields := filled_fields + 1; END IF;
    IF record.action_absolute_load_value IS NOT NULL THEN filled_fields := filled_fields + 1; END IF;
    IF record.action_target_reps IS NOT NULL THEN filled_fields := filled_fields + 1; END IF;
    IF record.action_confidence IS NOT NULL THEN filled_fields := filled_fields + 1; END IF;
    IF record.experience_level IS NOT NULL THEN filled_fields := filled_fields + 1; END IF;
    IF record.session_intent IS NOT NULL THEN filled_fields := filled_fields + 1; END IF;
    IF jsonb_array_length(record.policy_checks) > 0 THEN filled_fields := filled_fields + 1; END IF;
    IF jsonb_array_length(record.counterfactuals) > 0 THEN filled_fields := filled_fields + 1; END IF;
    IF record.variation_movement_pattern IS NOT NULL THEN filled_fields := filled_fields + 1; END IF;
    IF record.constraint_rounding_increment IS NOT NULL THEN filled_fields := filled_fields + 1; END IF;
    IF record.engine_version IS NOT NULL THEN filled_fields := filled_fields + 1; END IF;
    
    score := (filled_fields * 100) / total_fields;
    
    UPDATE public.ml_decision_records 
    SET data_completeness_score = score,
        updated_at = NOW()
    WHERE id = decision_uuid;
    
    RETURN score;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 10. VALIDATION TRIGGERS

CREATE OR REPLACE FUNCTION trigger_validate_decision()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM compute_completeness_score(NEW.id);
    PERFORM validate_ml_decision(NEW.id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS after_ml_decision_insert ON public.ml_decision_records;
CREATE TRIGGER after_ml_decision_insert
    AFTER INSERT ON public.ml_decision_records
    FOR EACH ROW
    EXECUTE FUNCTION trigger_validate_decision();

CREATE OR REPLACE FUNCTION trigger_update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS before_ml_decision_update ON public.ml_decision_records;
CREATE TRIGGER before_ml_decision_update
    BEFORE UPDATE ON public.ml_decision_records
    FOR EACH ROW
    EXECUTE FUNCTION trigger_update_timestamp();

-- 11. VIEWS FOR ML TRAINING DATA EXPORT

CREATE OR REPLACE VIEW public.ml_training_data_validated AS
SELECT 
    d.id as decision_id,
    d.user_id,
    d.session_id,
    d.exercise_id,
    d.decision_timestamp,
    d.session_date,
    
    d.hist_sessions_last_14d,
    d.hist_volume_last_14d,
    d.hist_days_since_last_workout,
    d.hist_training_streak_weeks,
    
    d.trend_direction,
    d.trend_slope_percentage,
    d.trend_has_two_session_decline,
    
    d.readiness_current,
    d.readiness_mean,
    d.readiness_low_count,
    
    d.signals_last_working_weight_value,
    d.signals_rolling_e1rm,
    d.signals_fail_streak,
    d.signals_high_rpe_streak,
    d.signals_success_streak,
    d.signals_days_since_exposure,
    d.signals_last_session_was_failure,
    d.signals_last_session_was_grinder,
    d.signals_target_reps_lower,
    d.signals_target_reps_upper,
    d.signals_target_rir,
    d.signals_is_compound,
    d.signals_is_upper_body_press,
    
    d.session_intent,
    d.experience_level,
    d.variation_movement_pattern,
    d.constraint_is_planned_deload_week,
    
    d.action_direction,
    d.action_primary_reason,
    d.action_absolute_load_value,
    d.action_target_reps,
    d.action_load_multiplier,
    d.action_volume_adjustment,
    d.action_confidence,
    
    d.counterfactuals,
    
    o.outcome_was_success,
    o.outcome_was_failure,
    o.outcome_was_grinder,
    o.outcome_avg_reps,
    o.outcome_avg_rir,
    o.load_deviation_percent,
    o.followed_prescription,
    o.execution_context,
    
    n.days_until_next_exposure,
    n.load_delta_percent,
    n.e1rm_delta_percent,
    n.next_was_success,
    n.progression_status,
    
    d.data_completeness_score,
    d.collection_status
    
FROM public.ml_decision_records d
LEFT JOIN public.ml_outcome_records o ON o.decision_id = d.id
LEFT JOIN public.ml_next_session_performance n ON n.decision_id = d.id
WHERE d.collection_status = 'validated'
  AND d.data_completeness_score >= 80;

CREATE OR REPLACE VIEW public.ml_data_quality_dashboard AS
SELECT 
    DATE_TRUNC('day', d.decision_timestamp) as date,
    COUNT(*) as total_records,
    SUM(CASE WHEN d.collection_status = 'validated' THEN 1 ELSE 0 END) as validated_count,
    SUM(CASE WHEN d.collection_status = 'invalidated' THEN 1 ELSE 0 END) as invalidated_count,
    SUM(CASE WHEN d.collection_status = 'pending' THEN 1 ELSE 0 END) as pending_count,
    ROUND(AVG(d.data_completeness_score), 1) as avg_completeness,
    SUM(CASE WHEN d.validation_unit_consistent = false THEN 1 ELSE 0 END) as unit_issues,
    SUM(CASE WHEN d.validation_load_plausible = false THEN 1 ELSE 0 END) as load_issues,
    SUM(CASE WHEN o.id IS NOT NULL THEN 1 ELSE 0 END) as with_outcomes,
    SUM(CASE WHEN n.id IS NOT NULL THEN 1 ELSE 0 END) as with_next_session
FROM public.ml_decision_records d
LEFT JOIN public.ml_outcome_records o ON o.decision_id = d.id
LEFT JOIN public.ml_next_session_performance n ON n.decision_id = d.id
GROUP BY DATE_TRUNC('day', d.decision_timestamp)
ORDER BY date DESC;

-- 12. SESSION ABANDONMENT TRACKING

CREATE TABLE IF NOT EXISTS public.ml_session_abandonments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    session_id UUID REFERENCES public.workout_sessions(id) ON DELETE SET NULL,
    
    abandoned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    session_date DATE NOT NULL,
    
    abandonment_reason TEXT NOT NULL CHECK (abandonment_reason IN (
        'user_cancelled',
        'app_crash',
        'timeout',
        'equipment_issue',
        'injury',
        'emergency',
        'unknown'
    )),
    
    exercises_planned INTEGER,
    exercises_completed INTEGER,
    completion_percentage NUMERIC(5,2),
    
    pending_decision_ids UUID[],
    
    notes TEXT,
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_abandonment_user ON public.ml_session_abandonments(user_id, abandoned_at DESC);
CREATE INDEX IF NOT EXISTS idx_abandonment_reason ON public.ml_session_abandonments(abandonment_reason);

ALTER TABLE public.ml_session_abandonments ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'ml_abandonment_policy') THEN
        CREATE POLICY ml_abandonment_policy ON public.ml_session_abandonments FOR ALL USING (auth.uid() = user_id);
    END IF;
END $$;

-- 13. USER CONSENT TRACKING

CREATE TABLE IF NOT EXISTS public.ml_user_consent (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    
    consent_given BOOLEAN NOT NULL,
    consent_timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    consent_version TEXT NOT NULL DEFAULT 'v1',
    
    consent_scope TEXT[] DEFAULT ARRAY['decision_logging', 'outcome_tracking', 'anonymized_training']::TEXT[],
    
    ip_address INET,
    device_info TEXT,
    
    revoked_at TIMESTAMPTZ,
    revocation_reason TEXT,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(user_id)
);

CREATE INDEX IF NOT EXISTS idx_consent_user ON public.ml_user_consent(user_id);
CREATE INDEX IF NOT EXISTS idx_consent_given ON public.ml_user_consent(consent_given) WHERE consent_given = true;

ALTER TABLE public.ml_user_consent ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'ml_consent_policy') THEN
        CREATE POLICY ml_consent_policy ON public.ml_user_consent FOR ALL USING (auth.uid() = user_id);
    END IF;
END $$;

-- 14. DATA VALIDATION SUMMARY VIEW

CREATE OR REPLACE VIEW public.ml_validation_summary AS
SELECT 
    d.user_id,
    COUNT(*) as total_decisions,
    SUM(CASE WHEN d.collection_status = 'validated' THEN 1 ELSE 0 END) as validated,
    SUM(CASE WHEN d.collection_status = 'invalidated' THEN 1 ELSE 0 END) as invalidated,
    SUM(CASE WHEN d.validation_unit_consistent = false THEN 1 ELSE 0 END) as unit_issues,
    SUM(CASE WHEN d.validation_load_plausible = false THEN 1 ELSE 0 END) as load_issues,
    SUM(CASE WHEN d.validation_timing_valid = false THEN 1 ELSE 0 END) as timing_issues,
    SUM(CASE WHEN d.validation_context_complete = false THEN 1 ELSE 0 END) as incomplete_context,
    ROUND(AVG(d.data_completeness_score), 1) as avg_completeness,
    MIN(d.decision_timestamp) as first_decision,
    MAX(d.decision_timestamp) as last_decision,
    COUNT(DISTINCT d.exercise_id) as unique_exercises
FROM public.ml_decision_records d
GROUP BY d.user_id;

-- 15. FUNCTION TO CHECK CONSENT BEFORE INSERT

CREATE OR REPLACE FUNCTION check_ml_consent()
RETURNS TRIGGER AS $$
DECLARE
    has_consent BOOLEAN;
BEGIN
    SELECT consent_given INTO has_consent
    FROM public.ml_user_consent
    WHERE user_id = NEW.user_id
      AND consent_given = true
      AND revoked_at IS NULL;
    
    IF has_consent IS NULL OR has_consent = false THEN
        RAISE EXCEPTION 'User has not consented to ML data collection';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Note: Uncomment below to enforce consent checking (disabled by default for flexibility)
-- DROP TRIGGER IF EXISTS check_consent_before_insert ON public.ml_decision_records;
-- CREATE TRIGGER check_consent_before_insert
--     BEFORE INSERT ON public.ml_decision_records
--     FOR EACH ROW
--     EXECUTE FUNCTION check_ml_consent();
