-- =============================================================================
-- IronForge / Atlas Supabase Schema - V2 ADDITIONS
-- Additional tables for comprehensive ML training data
-- Run this AFTER the main schema (supabase_schema.sql)
-- =============================================================================

-- =============================================================================
-- 1. ENHANCED SET-LEVEL PERFORMANCE DATA
-- =============================================================================

-- Add columns to session_sets for detailed performance tracking
-- Tempo tracking (seconds: eccentric-pause-concentric-pause, e.g., "3-1-1-0")
ALTER TABLE public.session_sets ADD COLUMN IF NOT EXISTS tempo_eccentric NUMERIC(3,1);
ALTER TABLE public.session_sets ADD COLUMN IF NOT EXISTS tempo_pause_bottom NUMERIC(3,1);
ALTER TABLE public.session_sets ADD COLUMN IF NOT EXISTS tempo_concentric NUMERIC(3,1);
ALTER TABLE public.session_sets ADD COLUMN IF NOT EXISTS tempo_pause_top NUMERIC(3,1);

-- Velocity-based training metrics (if using a device)
ALTER TABLE public.session_sets ADD COLUMN IF NOT EXISTS mean_velocity_ms NUMERIC(5,3);  -- meters per second
ALTER TABLE public.session_sets ADD COLUMN IF NOT EXISTS peak_velocity_ms NUMERIC(5,3);
ALTER TABLE public.session_sets ADD COLUMN IF NOT EXISTS power_watts NUMERIC(7,2);

-- Detailed effort perception
ALTER TABLE public.session_sets ADD COLUMN IF NOT EXISTS rpe_predicted NUMERIC(3,1);     -- What the app predicted
ALTER TABLE public.session_sets ADD COLUMN IF NOT EXISTS effort_match TEXT;

-- Form quality (self-reported or future: CV-based)
ALTER TABLE public.session_sets ADD COLUMN IF NOT EXISTS form_quality INTEGER;
ALTER TABLE public.session_sets ADD COLUMN IF NOT EXISTS form_breakdown_notes TEXT;       -- e.g., "lower back rounded on last 2 reps"

-- Add constraints separately (CHECK constraints can't be added with ADD COLUMN IF NOT EXISTS easily)
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'session_sets_effort_match_check') THEN
        ALTER TABLE public.session_sets ADD CONSTRAINT session_sets_effort_match_check 
            CHECK (effort_match IS NULL OR effort_match IN ('easier', 'as_expected', 'harder'));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'session_sets_form_quality_check') THEN
        ALTER TABLE public.session_sets ADD CONSTRAINT session_sets_form_quality_check 
            CHECK (form_quality IS NULL OR (form_quality >= 1 AND form_quality <= 5));
    END IF;
END $$;

-- =============================================================================
-- 2. MUSCLE-SPECIFIC RECOVERY TRACKING
-- =============================================================================

-- Track soreness/recovery by muscle group (crucial for intelligent volume management)
CREATE TABLE IF NOT EXISTS public.muscle_recovery (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    
    -- When was this recorded
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Which muscle group
    muscle_group TEXT NOT NULL, -- e.g., "chest", "quadriceps", "lats"
    
    -- Soreness level (1 = none, 5 = extremely sore, can barely move)
    soreness_level INTEGER NOT NULL CHECK (soreness_level >= 1 AND soreness_level <= 5),
    
    -- Perceived recovery (1 = completely fatigued, 5 = fully recovered)
    recovery_level INTEGER CHECK (recovery_level >= 1 AND recovery_level <= 5),
    
    -- Context
    days_since_trained INTEGER,  -- How many days since this muscle was last trained
    notes TEXT,
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_muscle_recovery_user_date 
    ON public.muscle_recovery(user_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_muscle_recovery_muscle 
    ON public.muscle_recovery(user_id, muscle_group, recorded_at DESC);

-- =============================================================================
-- 3. PRE-WORKOUT CONTEXT (Session Planning Data)
-- =============================================================================

-- Capture state BEFORE workout for better recommendations
CREATE TABLE IF NOT EXISTS public.pre_workout_check_ins (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    session_id UUID REFERENCES public.workout_sessions(id) ON DELETE SET NULL,
    
    checked_in_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Energy & Readiness
    energy_level INTEGER NOT NULL CHECK (energy_level >= 1 AND energy_level <= 5),
    motivation_level INTEGER CHECK (motivation_level >= 1 AND motivation_level <= 5),
    stress_level INTEGER CHECK (stress_level >= 1 AND stress_level <= 5),
    
    -- Sleep context (if not already captured in daily biometrics)
    sleep_quality_last_night INTEGER CHECK (sleep_quality_last_night >= 1 AND sleep_quality_last_night <= 5),
    hours_slept_last_night NUMERIC(3,1),
    
    -- Nutrition context
    meals_eaten_today INTEGER CHECK (meals_eaten_today >= 0 AND meals_eaten_today <= 10),
    hours_since_last_meal NUMERIC(4,1),
    caffeine_consumed BOOLEAN DEFAULT false,
    pre_workout_supplement BOOLEAN DEFAULT false,
    hydration_level INTEGER CHECK (hydration_level >= 1 AND hydration_level <= 5),
    
    -- Physical state
    overall_soreness INTEGER CHECK (overall_soreness >= 1 AND overall_soreness <= 5),
    any_pain_or_injury BOOLEAN DEFAULT false,
    pain_notes TEXT,
    
    -- Time context
    time_available_minutes INTEGER,  -- How much time do they have?
    preferred_intensity TEXT CHECK (preferred_intensity IN ('light', 'moderate', 'hard', 'max_effort')),
    
    -- Environment
    gym_crowdedness INTEGER CHECK (gym_crowdedness >= 1 AND gym_crowdedness <= 5),
    equipment_available JSONB DEFAULT '[]'::jsonb,  -- What's actually available today
    
    -- Workout goal for today
    session_goal TEXT, -- e.g., "hit PRs", "active recovery", "maintain", "push hard"
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pre_workout_user ON public.pre_workout_check_ins(user_id, checked_in_at DESC);

-- =============================================================================
-- 4. POST-WORKOUT FEEDBACK (Outcome Data)
-- =============================================================================

-- Detailed post-workout feedback for learning
CREATE TABLE IF NOT EXISTS public.post_workout_feedback (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    session_id UUID NOT NULL REFERENCES public.workout_sessions(id) ON DELETE CASCADE,
    
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Overall session rating
    overall_satisfaction INTEGER NOT NULL CHECK (overall_satisfaction >= 1 AND overall_satisfaction <= 5),
    workout_difficulty INTEGER CHECK (workout_difficulty >= 1 AND workout_difficulty <= 10),
    
    -- Volume/intensity feedback
    volume_feeling TEXT CHECK (volume_feeling IN ('too_little', 'just_right', 'too_much')),
    intensity_feeling TEXT CHECK (intensity_feeling IN ('too_easy', 'just_right', 'too_hard')),
    
    -- Exercise-specific feedback (stored as JSON for flexibility)
    -- e.g., [{"exercise_id": "...", "feedback": "too_hard", "would_substitute": true}]
    exercise_feedback JSONB DEFAULT '[]'::jsonb,
    
    -- What worked well
    highlights TEXT,  -- Free text: what felt good
    
    -- What didn't work
    lowlights TEXT,   -- Free text: what didn't feel good
    
    -- Would they repeat this workout?
    would_repeat BOOLEAN,
    
    -- Pump/mind-muscle connection (for hypertrophy training)
    pump_quality INTEGER CHECK (pump_quality >= 1 AND pump_quality <= 5),
    mind_muscle_connection INTEGER CHECK (mind_muscle_connection >= 1 AND mind_muscle_connection <= 5),
    
    -- Energy after workout
    post_workout_energy INTEGER CHECK (post_workout_energy >= 1 AND post_workout_energy <= 5),
    
    -- Any exercises they want to swap out?
    requested_substitutions JSONB DEFAULT '[]'::jsonb,
    -- e.g., [{"remove": "barbell_row", "prefer": "cable_row", "reason": "lower_back_discomfort"}]
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(session_id)
);

CREATE INDEX IF NOT EXISTS idx_post_workout_user ON public.post_workout_feedback(user_id, submitted_at DESC);

-- =============================================================================
-- 5. SKIPPED/MISSED WORKOUTS (Crucial for understanding adherence)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.missed_workouts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    
    -- When was the workout supposed to happen?
    scheduled_date DATE NOT NULL,
    template_id UUID REFERENCES public.workout_templates(id) ON DELETE SET NULL,
    
    -- Why was it missed?
    reason TEXT CHECK (reason IN (
        'too_tired',
        'too_busy',
        'sick',
        'injured',
        'travel',
        'gym_closed',
        'no_motivation',
        'sore',
        'forgot',
        'social_commitment',
        'work',
        'family',
        'weather',
        'equipment_unavailable',
        'other'
    )),
    reason_details TEXT,
    
    -- Did they do anything instead?
    alternative_activity TEXT,  -- e.g., "went for a walk", "did home workout"
    
    -- When did they log this?
    logged_at TIMESTAMPTZ DEFAULT NOW(),
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_missed_workouts_user ON public.missed_workouts(user_id, scheduled_date DESC);

-- =============================================================================
-- 6. EXERCISE PREFERENCES & FEEDBACK
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.exercise_preferences (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    exercise_id TEXT NOT NULL,
    
    -- Overall preference
    preference_score INTEGER CHECK (preference_score >= 1 AND preference_score <= 5),
    -- 1 = hate it, 3 = neutral, 5 = love it
    
    -- Why they like/dislike it
    enjoyment_level INTEGER CHECK (enjoyment_level >= 1 AND enjoyment_level <= 5),
    effectiveness_perception INTEGER CHECK (effectiveness_perception >= 1 AND effectiveness_perception <= 5),
    
    -- Physical compatibility
    causes_discomfort BOOLEAN DEFAULT false,
    discomfort_location TEXT,  -- e.g., "lower back", "shoulder"
    
    -- Proficiency
    technique_confidence INTEGER CHECK (technique_confidence >= 1 AND technique_confidence <= 5),
    
    -- Context preferences
    preferred_rep_range TEXT,  -- e.g., "6-8", "12-15"
    preferred_equipment_variant TEXT,  -- e.g., "dumbbell" vs "barbell" for rows
    
    -- Blacklist
    is_blacklisted BOOLEAN DEFAULT false,
    blacklist_reason TEXT,
    
    -- Notes
    notes TEXT,
    
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(user_id, exercise_id)
);

CREATE INDEX IF NOT EXISTS idx_exercise_prefs_user ON public.exercise_preferences(user_id);

-- =============================================================================
-- 7. BODY COMPOSITION TRACKING
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.body_measurements (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    
    measured_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Weight
    body_weight_kg NUMERIC(5,2),
    
    -- Body composition
    body_fat_percentage NUMERIC(4,1),
    lean_mass_kg NUMERIC(5,2),
    fat_mass_kg NUMERIC(5,2),
    
    -- Circumference measurements (in cm)
    chest_cm NUMERIC(5,1),
    waist_cm NUMERIC(5,1),
    hips_cm NUMERIC(5,1),
    left_arm_cm NUMERIC(5,1),
    right_arm_cm NUMERIC(5,1),
    left_thigh_cm NUMERIC(5,1),
    right_thigh_cm NUMERIC(5,1),
    left_calf_cm NUMERIC(5,1),
    right_calf_cm NUMERIC(5,1),
    neck_cm NUMERIC(5,1),
    shoulders_cm NUMERIC(5,1),
    
    -- Source of measurement
    measurement_method TEXT CHECK (measurement_method IN (
        'scale',
        'dexa',
        'bod_pod',
        'calipers',
        'bioimpedance',
        'tape_measure',
        'visual_estimate'
    )),
    
    -- Progress photos (store URLs)
    photo_front_url TEXT,
    photo_side_url TEXT,
    photo_back_url TEXT,
    
    notes TEXT,
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_body_measurements_user ON public.body_measurements(user_id, measured_at DESC);

-- =============================================================================
-- 8. NUTRITION LOGGING (Basic)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.daily_nutrition (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    
    date DATE NOT NULL,
    
    -- Macros (grams)
    protein_g NUMERIC(6,1),
    carbs_g NUMERIC(6,1),
    fat_g NUMERIC(6,1),
    fiber_g NUMERIC(5,1),
    
    -- Calories
    total_calories INTEGER,
    
    -- Hydration
    water_liters NUMERIC(4,2),
    
    -- Meal timing
    meals_count INTEGER,
    first_meal_time TIME,
    last_meal_time TIME,
    
    -- Supplements
    creatine_taken BOOLEAN DEFAULT false,
    protein_shake_count INTEGER DEFAULT 0,
    pre_workout_taken BOOLEAN DEFAULT false,
    other_supplements TEXT,
    
    -- Compliance
    hit_protein_target BOOLEAN,
    hit_calorie_target BOOLEAN,
    
    -- Quality
    diet_quality_self_rating INTEGER CHECK (diet_quality_self_rating >= 1 AND diet_quality_self_rating <= 5),
    
    notes TEXT,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(user_id, date)
);

CREATE INDEX IF NOT EXISTS idx_daily_nutrition_user ON public.daily_nutrition(user_id, date DESC);

-- =============================================================================
-- 9. TRAINING BLOCKS / PERIODIZATION
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.training_blocks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    
    name TEXT NOT NULL,  -- e.g., "Hypertrophy Block 1", "Strength Peak"
    
    -- Block type
    block_type TEXT CHECK (block_type IN (
        'accumulation',
        'intensification', 
        'realization',
        'deload',
        'hypertrophy',
        'strength',
        'power',
        'peaking',
        'maintenance',
        'general_fitness'
    )),
    
    -- Timing
    started_at DATE NOT NULL,
    planned_end_at DATE,
    actual_end_at DATE,
    planned_weeks INTEGER,
    
    -- Goals for this block
    primary_goal TEXT,
    target_lifts JSONB DEFAULT '[]'::jsonb,  -- e.g., [{"exercise": "squat", "target_1rm": 150}]
    
    -- Volume/intensity targets
    target_weekly_sets_per_muscle JSONB DEFAULT '{}'::jsonb,
    target_intensity_range TEXT,  -- e.g., "70-80% 1RM"
    
    -- Outcome tracking
    goals_achieved BOOLEAN,
    outcome_notes TEXT,
    
    -- What comes next
    next_block_type TEXT,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_training_blocks_user ON public.training_blocks(user_id, started_at DESC);

-- =============================================================================
-- 10. WEEKLY SUMMARIES (Aggregated for ML features)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.weekly_summaries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    
    -- Week identifier (Monday of the week)
    week_start DATE NOT NULL,
    
    -- Session counts
    planned_sessions INTEGER,
    completed_sessions INTEGER,
    missed_sessions INTEGER,
    adherence_percentage NUMERIC(5,2),
    
    -- Volume metrics
    total_sets INTEGER,
    total_reps INTEGER,
    total_volume_kg NUMERIC(12,2),
    
    -- Per-muscle volume (sets)
    volume_by_muscle JSONB DEFAULT '{}'::jsonb,
    -- e.g., {"chest": 12, "back": 15, "legs": 18, ...}
    
    -- Intensity metrics
    average_rpe NUMERIC(3,1),
    average_rir NUMERIC(3,1),
    
    -- Time investment
    total_workout_minutes INTEGER,
    average_session_minutes NUMERIC(5,1),
    
    -- Recovery metrics
    average_sleep_hours NUMERIC(4,2),
    average_hrv NUMERIC(6,2),
    average_soreness NUMERIC(3,1),
    average_energy NUMERIC(3,1),
    
    -- Progress indicators
    prs_hit INTEGER DEFAULT 0,
    exercises_progressed INTEGER DEFAULT 0,
    exercises_regressed INTEGER DEFAULT 0,
    
    -- Body metrics (if measured)
    body_weight_start_kg NUMERIC(5,2),
    body_weight_end_kg NUMERIC(5,2),
    
    -- Overall rating
    week_rating INTEGER CHECK (week_rating >= 1 AND week_rating <= 5),
    
    notes TEXT,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(user_id, week_start)
);

CREATE INDEX IF NOT EXISTS idx_weekly_summaries_user ON public.weekly_summaries(user_id, week_start DESC);

-- =============================================================================
-- 11. EXERCISE SUBSTITUTION HISTORY
-- =============================================================================

-- Track what substitutions users make and why (learns preferences)
CREATE TABLE IF NOT EXISTS public.exercise_substitutions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    session_id UUID REFERENCES public.workout_sessions(id) ON DELETE SET NULL,
    
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- What was planned
    original_exercise_id TEXT NOT NULL,
    original_exercise_name TEXT NOT NULL,
    
    -- What was done instead
    substituted_exercise_id TEXT NOT NULL,
    substituted_exercise_name TEXT NOT NULL,
    
    -- Why
    reason TEXT CHECK (reason IN (
        'equipment_unavailable',
        'discomfort_pain',
        'preference',
        'time_constraint',
        'fatigue',
        'variety',
        'progression',
        'other'
    )),
    reason_details TEXT,
    
    -- Was this a good swap?
    satisfaction_with_swap INTEGER CHECK (satisfaction_with_swap >= 1 AND satisfaction_with_swap <= 5),
    
    -- Should we remember this preference?
    make_permanent BOOLEAN DEFAULT false,
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_substitutions_user ON public.exercise_substitutions(user_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_substitutions_original ON public.exercise_substitutions(original_exercise_id);

-- =============================================================================
-- 12. REST PERIOD TRACKING
-- =============================================================================

-- Actual rest periods taken (vs prescribed)
CREATE TABLE IF NOT EXISTS public.rest_periods (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_exercise_id UUID NOT NULL REFERENCES public.session_exercises(id) ON DELETE CASCADE,
    
    -- After which set
    after_set_number INTEGER NOT NULL,
    
    -- Timing
    rest_started_at TIMESTAMPTZ,
    rest_ended_at TIMESTAMPTZ,
    actual_rest_seconds INTEGER,
    
    -- What was prescribed
    prescribed_rest_seconds INTEGER,
    
    -- Did they skip/cut short?
    was_skipped BOOLEAN DEFAULT false,
    was_extended BOOLEAN DEFAULT false,
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_rest_periods_exercise ON public.rest_periods(session_exercise_id);

-- =============================================================================
-- 13. IN-SESSION ADJUSTMENTS
-- =============================================================================

-- Track real-time adjustments made during workout
CREATE TABLE IF NOT EXISTS public.session_adjustments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id UUID NOT NULL REFERENCES public.workout_sessions(id) ON DELETE CASCADE,
    
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    adjustment_type TEXT NOT NULL CHECK (adjustment_type IN (
        'weight_reduced',
        'weight_increased',
        'sets_reduced',
        'sets_added',
        'reps_reduced',
        'reps_increased',
        'exercise_skipped',
        'exercise_added',
        'exercise_reordered',
        'rest_extended',
        'workout_ended_early',
        'deload_triggered'
    )),
    
    -- Context
    exercise_id TEXT,
    exercise_name TEXT,
    set_number INTEGER,
    
    -- What changed
    original_value TEXT,
    new_value TEXT,
    
    -- Why
    reason TEXT,
    
    -- Was it a good call?
    was_good_decision BOOLEAN,
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_adjustments_session ON public.session_adjustments(session_id);

-- =============================================================================
-- 14. GOAL TRACKING
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.user_goals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    
    -- Goal definition
    goal_type TEXT NOT NULL CHECK (goal_type IN (
        'strength',      -- Hit a specific lift number
        'body_weight',   -- Reach a weight
        'body_comp',     -- Body fat percentage
        'consistency',   -- Workout X times per week
        'volume',        -- Hit weekly volume targets
        'habit',         -- Build a habit
        'event',         -- Prepare for an event
        'measurement',   -- Arm size, waist size, etc.
        'custom'
    )),
    
    title TEXT NOT NULL,
    description TEXT,
    
    -- Target
    target_value NUMERIC(10,2),
    target_unit TEXT,  -- "kg", "lbs", "%", "sessions", "cm"
    target_exercise_id TEXT,  -- For strength goals
    
    -- Baseline
    starting_value NUMERIC(10,2),
    starting_date DATE NOT NULL DEFAULT CURRENT_DATE,
    
    -- Timeline
    target_date DATE,
    
    -- Progress
    current_value NUMERIC(10,2),
    last_updated_at TIMESTAMPTZ,
    
    -- Status
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'achieved', 'abandoned', 'paused')),
    achieved_at TIMESTAMPTZ,
    
    -- Milestones
    milestones JSONB DEFAULT '[]'::jsonb,
    -- e.g., [{"value": 100, "achieved_at": "2024-01-15"}, {"value": 110, "achieved_at": null}]
    
    notes TEXT,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_goals ON public.user_goals(user_id, status);

-- =============================================================================
-- 15. FEATURE FLAGS FOR ML EXPERIMENTS
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.user_experiments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    
    experiment_name TEXT NOT NULL,
    variant TEXT NOT NULL,  -- e.g., "control", "treatment_a", "treatment_b"
    
    enrolled_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Outcome tracking
    conversion_event TEXT,
    converted_at TIMESTAMPTZ,
    
    -- Feedback
    user_feedback TEXT,
    
    UNIQUE(user_id, experiment_name)
);

-- =============================================================================
-- RLS POLICIES FOR NEW TABLES
-- =============================================================================

ALTER TABLE public.muscle_recovery ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pre_workout_check_ins ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.post_workout_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.missed_workouts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exercise_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.body_measurements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_nutrition ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.training_blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.weekly_summaries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exercise_substitutions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rest_periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.session_adjustments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_experiments ENABLE ROW LEVEL SECURITY;

-- Standard user-only access policies
CREATE POLICY muscle_recovery_policy ON public.muscle_recovery FOR ALL USING (auth.uid() = user_id);
CREATE POLICY pre_workout_policy ON public.pre_workout_check_ins FOR ALL USING (auth.uid() = user_id);
CREATE POLICY post_workout_policy ON public.post_workout_feedback FOR ALL USING (auth.uid() = user_id);
CREATE POLICY missed_workouts_policy ON public.missed_workouts FOR ALL USING (auth.uid() = user_id);
CREATE POLICY exercise_prefs_policy ON public.exercise_preferences FOR ALL USING (auth.uid() = user_id);
CREATE POLICY body_measurements_policy ON public.body_measurements FOR ALL USING (auth.uid() = user_id);
CREATE POLICY nutrition_policy ON public.daily_nutrition FOR ALL USING (auth.uid() = user_id);
CREATE POLICY training_blocks_policy ON public.training_blocks FOR ALL USING (auth.uid() = user_id);
CREATE POLICY weekly_summaries_policy ON public.weekly_summaries FOR ALL USING (auth.uid() = user_id);
CREATE POLICY substitutions_policy ON public.exercise_substitutions FOR ALL USING (auth.uid() = user_id);
CREATE POLICY user_goals_policy ON public.user_goals FOR ALL USING (auth.uid() = user_id);
CREATE POLICY experiments_policy ON public.user_experiments FOR ALL USING (auth.uid() = user_id);

-- Rest periods and session adjustments inherit from session
CREATE POLICY rest_periods_policy ON public.rest_periods FOR ALL 
    USING (EXISTS (
        SELECT 1 FROM public.session_exercises se 
        JOIN public.workout_sessions s ON s.id = se.session_id 
        WHERE se.id = session_exercise_id AND auth.uid() = s.user_id
    ));

CREATE POLICY adjustments_policy ON public.session_adjustments FOR ALL 
    USING (EXISTS (
        SELECT 1 FROM public.workout_sessions s 
        WHERE s.id = session_id AND auth.uid() = s.user_id
    ));

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

-- Function to compute weekly summary (can be called via cron or after each session)
CREATE OR REPLACE FUNCTION public.compute_weekly_summary(
    p_user_id UUID,
    p_week_start DATE
) RETURNS UUID AS $$
DECLARE
    v_summary_id UUID;
    v_week_end DATE := p_week_start + INTERVAL '6 days';
BEGIN
    INSERT INTO public.weekly_summaries (
        user_id,
        week_start,
        completed_sessions,
        total_sets,
        total_reps,
        total_volume_kg,
        total_workout_minutes
    )
    SELECT 
        p_user_id,
        p_week_start,
        COUNT(DISTINCT ws.id),
        COALESCE(SUM(ws.total_sets), 0),
        COALESCE(SUM(ws.total_reps), 0),
        COALESCE(SUM(ws.total_volume_kg), 0),
        COALESCE(SUM(ws.duration_seconds) / 60, 0)
    FROM public.workout_sessions ws
    WHERE ws.user_id = p_user_id
      AND ws.started_at::date >= p_week_start
      AND ws.started_at::date <= v_week_end
      AND ws.ended_at IS NOT NULL
    ON CONFLICT (user_id, week_start) 
    DO UPDATE SET
        completed_sessions = EXCLUDED.completed_sessions,
        total_sets = EXCLUDED.total_sets,
        total_reps = EXCLUDED.total_reps,
        total_volume_kg = EXCLUDED.total_volume_kg,
        total_workout_minutes = EXCLUDED.total_workout_minutes,
        updated_at = NOW()
    RETURNING id INTO v_summary_id;
    
    RETURN v_summary_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- Done! Run this after the main schema
-- =============================================================================
