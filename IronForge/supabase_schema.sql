-- =============================================================================
-- IronForge / Atlas Supabase Schema
-- Comprehensive data model for workout tracking, progression, and analytics
-- =============================================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================================================
-- 1. USERS & PROFILES
-- =============================================================================

-- User profiles (extends Supabase auth.users)
CREATE TABLE IF NOT EXISTS public.user_profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Demographics
    display_name TEXT,
    email TEXT,
    age INTEGER CHECK (age >= 13 AND age <= 120),
    sex TEXT CHECK (sex IN ('male', 'female', 'other')),
    height_cm NUMERIC(5,2),
    
    -- Body composition (tracked over time, but latest stored here for convenience)
    body_weight_kg NUMERIC(5,2),
    body_fat_percentage NUMERIC(4,1),
    
    -- Training background
    workout_experience TEXT CHECK (workout_experience IN ('newbie', 'beginner', 'intermediate', 'advanced', 'expert')),
    training_age_months INTEGER DEFAULT 0,
    
    -- Goals (stored as JSONB array for flexibility)
    fitness_goals JSONB DEFAULT '[]'::jsonb,
    -- e.g. ["buildMuscle", "gainStrength", "loseFat", "improveEndurance"]
    
    -- Schedule preferences
    weekly_frequency INTEGER DEFAULT 3 CHECK (weekly_frequency >= 1 AND weekly_frequency <= 7),
    preferred_workout_duration_minutes INTEGER DEFAULT 60,
    preferred_workout_days JSONB DEFAULT '[]'::jsonb, -- e.g. ["monday", "wednesday", "friday"]
    
    -- Gym / Equipment
    gym_type TEXT CHECK (gym_type IN ('commercial', 'homeGym', 'crossfit', 'university', 'outdoor', 'minimalist')),
    available_equipment JSONB DEFAULT '[]'::jsonb, -- e.g. ["barbell", "dumbbell", "cable"]
    
    -- Units preference
    preferred_weight_unit TEXT DEFAULT 'pounds' CHECK (preferred_weight_unit IN ('pounds', 'kilograms')),
    preferred_distance_unit TEXT DEFAULT 'miles' CHECK (preferred_distance_unit IN ('miles', 'kilometers')),
    
    -- App settings
    notifications_enabled BOOLEAN DEFAULT true,
    rest_timer_enabled BOOLEAN DEFAULT true,
    default_rest_seconds INTEGER DEFAULT 120,
    
    -- Onboarding status
    onboarding_completed BOOLEAN DEFAULT false,
    onboarding_completed_at TIMESTAMPTZ,
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- User known maxes (1RM estimates for key lifts)
CREATE TABLE IF NOT EXISTS public.user_maxes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    
    exercise_id TEXT NOT NULL, -- Reference to exercise
    exercise_name TEXT NOT NULL,
    
    -- The estimated or tested 1RM
    estimated_1rm_kg NUMERIC(6,2) NOT NULL,
    
    -- How was this determined?
    source TEXT CHECK (source IN ('tested', 'estimated', 'calculated', 'imported')),
    
    -- Date of the max
    achieved_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Additional context
    reps_performed INTEGER, -- If calculated from a rep max
    weight_used_kg NUMERIC(6,2), -- The actual weight lifted
    notes TEXT,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(user_id, exercise_id)
);

-- =============================================================================
-- 2. EXERCISES (Reference data)
-- =============================================================================

-- Exercise library (can be seeded from exercises.json)
CREATE TABLE IF NOT EXISTS public.exercises (
    id TEXT PRIMARY KEY, -- e.g. "barbell_bench_press"
    
    name TEXT NOT NULL,
    body_part TEXT,
    equipment TEXT,
    target_muscle TEXT,
    secondary_muscles JSONB DEFAULT '[]'::jsonb,
    
    -- Movement classification
    movement_pattern TEXT, -- e.g. "horizontalPush", "hipHinge"
    is_compound BOOLEAN DEFAULT false,
    is_unilateral BOOLEAN DEFAULT false,
    
    -- Media
    gif_url TEXT,
    video_url TEXT,
    instructions JSONB DEFAULT '[]'::jsonb,
    
    -- Metadata
    difficulty_level INTEGER DEFAULT 1 CHECK (difficulty_level >= 1 AND difficulty_level <= 5),
    popularity_score INTEGER DEFAULT 0,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================================================
-- 3. WORKOUT TEMPLATES
-- =============================================================================

-- Workout templates (user-created or system-provided)
CREATE TABLE IF NOT EXISTS public.workout_templates (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES public.user_profiles(id) ON DELETE CASCADE, -- NULL for system templates
    
    name TEXT NOT NULL,
    description TEXT,
    
    -- Classification
    template_type TEXT DEFAULT 'custom' CHECK (template_type IN ('system', 'custom', 'shared')),
    split_type TEXT, -- e.g. "push", "pull", "legs", "upper", "lower", "fullBody"
    
    -- Estimated duration
    estimated_duration_minutes INTEGER,
    
    -- Target muscles (denormalized for quick filtering)
    target_muscle_groups JSONB DEFAULT '[]'::jsonb,
    
    -- Ordering for rotation schedules
    sort_order INTEGER DEFAULT 0,
    
    -- Active/archived status
    is_active BOOLEAN DEFAULT true,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Exercises within a template
CREATE TABLE IF NOT EXISTS public.workout_template_exercises (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    template_id UUID NOT NULL REFERENCES public.workout_templates(id) ON DELETE CASCADE,
    
    -- Exercise reference
    exercise_id TEXT NOT NULL,
    exercise_name TEXT NOT NULL,
    exercise_equipment TEXT,
    exercise_target TEXT,
    
    -- Prescription
    sets_target INTEGER NOT NULL DEFAULT 3 CHECK (sets_target >= 1 AND sets_target <= 20),
    rep_range_min INTEGER NOT NULL DEFAULT 6 CHECK (rep_range_min >= 1),
    rep_range_max INTEGER NOT NULL DEFAULT 12 CHECK (rep_range_max >= rep_range_min),
    
    -- Progression settings
    increment_kg NUMERIC(4,2) DEFAULT 2.5,
    deload_factor NUMERIC(3,2) DEFAULT 0.9 CHECK (deload_factor > 0 AND deload_factor <= 1),
    failure_threshold INTEGER DEFAULT 2 CHECK (failure_threshold >= 1),
    
    -- Rest period
    rest_seconds INTEGER DEFAULT 120,
    
    -- RIR/RPE target
    target_rir INTEGER DEFAULT 2 CHECK (target_rir >= 0 AND target_rir <= 5),
    
    -- Superset grouping (exercises with same group_id are supersetted)
    superset_group_id UUID,
    
    -- Order within template
    sort_order INTEGER NOT NULL DEFAULT 0,
    
    -- Notes
    notes TEXT,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================================================
-- 4. WORKOUT SESSIONS (Completed workouts)
-- =============================================================================

-- Individual workout sessions
CREATE TABLE IF NOT EXISTS public.workout_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    
    -- Template reference (nullable for ad-hoc workouts)
    template_id UUID REFERENCES public.workout_templates(id) ON DELETE SET NULL,
    template_name TEXT, -- Denormalized for history
    
    -- Session metadata
    name TEXT NOT NULL,
    
    -- Timing
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    duration_seconds INTEGER,
    
    -- Context
    readiness_score INTEGER CHECK (readiness_score >= 0 AND readiness_score <= 100),
    was_deload BOOLEAN DEFAULT false,
    deload_reason TEXT,
    
    -- Location (optional)
    gym_name TEXT,
    latitude NUMERIC(10,7),
    longitude NUMERIC(10,7),
    
    -- User feedback
    perceived_difficulty INTEGER CHECK (perceived_difficulty >= 1 AND perceived_difficulty <= 10),
    overall_feeling TEXT CHECK (overall_feeling IN ('great', 'good', 'okay', 'tough', 'terrible')),
    notes TEXT,
    
    -- Computed stats (denormalized for quick access)
    total_sets INTEGER DEFAULT 0,
    total_reps INTEGER DEFAULT 0,
    total_volume_kg NUMERIC(10,2) DEFAULT 0,
    exercise_count INTEGER DEFAULT 0,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Exercise performances within a session
CREATE TABLE IF NOT EXISTS public.session_exercises (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id UUID NOT NULL REFERENCES public.workout_sessions(id) ON DELETE CASCADE,
    
    -- Exercise reference
    exercise_id TEXT NOT NULL,
    exercise_name TEXT NOT NULL,
    exercise_equipment TEXT,
    exercise_target TEXT,
    
    -- Original prescription (snapshot from template)
    sets_target INTEGER NOT NULL,
    rep_range_min INTEGER NOT NULL,
    rep_range_max INTEGER NOT NULL,
    increment_kg NUMERIC(4,2),
    deload_factor NUMERIC(3,2),
    failure_threshold INTEGER,
    
    -- Order in session
    sort_order INTEGER NOT NULL DEFAULT 0,
    
    -- Completion status
    is_completed BOOLEAN DEFAULT false,
    completed_at TIMESTAMPTZ,
    
    -- Computed (denormalized)
    total_sets_completed INTEGER DEFAULT 0,
    total_reps_completed INTEGER DEFAULT 0,
    total_volume_kg NUMERIC(10,2) DEFAULT 0,
    
    -- Notes
    notes TEXT,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Individual sets within an exercise performance
CREATE TABLE IF NOT EXISTS public.session_sets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_exercise_id UUID NOT NULL REFERENCES public.session_exercises(id) ON DELETE CASCADE,
    
    -- Set number (1, 2, 3, etc.)
    set_number INTEGER NOT NULL CHECK (set_number >= 1),
    
    -- What was performed
    reps INTEGER NOT NULL CHECK (reps >= 0),
    weight_kg NUMERIC(6,2) NOT NULL CHECK (weight_kg >= 0),
    
    -- Optional: time under tension, distance, etc.
    duration_seconds INTEGER,
    distance_meters NUMERIC(10,2),
    
    -- RIR/RPE observed
    rir_observed INTEGER CHECK (rir_observed >= 0 AND rir_observed <= 10),
    rpe_observed NUMERIC(3,1) CHECK (rpe_observed >= 1 AND rpe_observed <= 10),
    
    -- Set type
    is_warmup BOOLEAN DEFAULT false,
    is_dropset BOOLEAN DEFAULT false,
    is_failure BOOLEAN DEFAULT false,
    
    -- Completion
    is_completed BOOLEAN DEFAULT true,
    completed_at TIMESTAMPTZ,
    
    -- Notes (e.g., "felt easy", "form broke down")
    notes TEXT,
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================================================
-- 5. LIFT STATES (Progression tracking)
-- =============================================================================

-- Current state for each exercise per user (for progression decisions)
CREATE TABLE IF NOT EXISTS public.lift_states (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    
    exercise_id TEXT NOT NULL,
    exercise_name TEXT NOT NULL,
    
    -- Current working weight
    last_working_weight_kg NUMERIC(6,2) NOT NULL DEFAULT 0,
    
    -- Estimated 1RM tracking
    rolling_e1rm_kg NUMERIC(6,2),
    e1rm_trend TEXT CHECK (e1rm_trend IN ('improving', 'stable', 'declining', 'insufficient')),
    
    -- E1RM history (last N values)
    e1rm_history JSONB DEFAULT '[]'::jsonb,
    
    -- Failure tracking for deload decisions
    consecutive_failures INTEGER DEFAULT 0,
    last_deload_at TIMESTAMPTZ,
    
    -- Session tracking
    last_session_at TIMESTAMPTZ,
    successful_sessions_count INTEGER DEFAULT 0,
    total_sessions_count INTEGER DEFAULT 0,
    
    -- Volume tracking
    last_session_volume_kg NUMERIC(10,2),
    average_session_volume_kg NUMERIC(10,2),
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(user_id, exercise_id)
);

-- Lift state history (for analytics and debugging)
CREATE TABLE IF NOT EXISTS public.lift_state_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    lift_state_id UUID NOT NULL REFERENCES public.lift_states(id) ON DELETE CASCADE,
    
    -- Snapshot of state at this point
    working_weight_kg NUMERIC(6,2) NOT NULL,
    e1rm_kg NUMERIC(6,2),
    consecutive_failures INTEGER,
    
    -- What triggered this snapshot
    trigger_type TEXT CHECK (trigger_type IN ('session_completed', 'deload', 'manual_update', 'import')),
    session_id UUID REFERENCES public.workout_sessions(id) ON DELETE SET NULL,
    
    recorded_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================================================
-- 6. BIOMETRICS & HEALTH DATA
-- =============================================================================

-- Daily biometrics (from HealthKit or manual entry)
CREATE TABLE IF NOT EXISTS public.daily_biometrics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    
    -- Date (one record per day)
    date DATE NOT NULL,
    
    -- Sleep
    sleep_hours NUMERIC(4,2),
    sleep_quality INTEGER CHECK (sleep_quality >= 1 AND sleep_quality <= 5),
    time_in_bed_hours NUMERIC(4,2),
    sleep_start_time TIME,
    sleep_end_time TIME,
    
    -- Recovery / HRV
    hrv_ms NUMERIC(6,2),
    resting_heart_rate INTEGER,
    
    -- Activity
    steps INTEGER,
    active_calories INTEGER,
    total_calories INTEGER,
    exercise_minutes INTEGER,
    stand_hours INTEGER,
    
    -- Body metrics
    body_weight_kg NUMERIC(5,2),
    body_fat_percentage NUMERIC(4,1),
    
    -- Subjective
    energy_level INTEGER CHECK (energy_level >= 1 AND energy_level <= 5),
    stress_level INTEGER CHECK (stress_level >= 1 AND stress_level <= 5),
    soreness_level INTEGER CHECK (soreness_level >= 1 AND soreness_level <= 5),
    mood INTEGER CHECK (mood >= 1 AND mood <= 5),
    
    -- Computed readiness
    readiness_score INTEGER CHECK (readiness_score >= 0 AND readiness_score <= 100),
    
    -- Data source flags
    from_healthkit BOOLEAN DEFAULT false,
    from_manual_entry BOOLEAN DEFAULT false,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(user_id, date)
);

-- HealthKit workout imports (cardio, etc.)
CREATE TABLE IF NOT EXISTS public.healthkit_workouts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    
    -- HealthKit identifiers
    hk_uuid TEXT NOT NULL,
    
    -- Workout details
    workout_type TEXT NOT NULL, -- e.g., "running", "cycling", "swimming"
    started_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ NOT NULL,
    duration_seconds INTEGER,
    
    -- Metrics
    total_distance_meters NUMERIC(10,2),
    total_energy_burned_kcal NUMERIC(8,2),
    average_heart_rate INTEGER,
    max_heart_rate INTEGER,
    
    -- Source
    source_name TEXT, -- e.g., "Apple Watch"
    source_bundle_id TEXT,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(user_id, hk_uuid)
);

-- =============================================================================
-- 7. ANALYTICS & EVENTS
-- =============================================================================

-- App events for analytics
CREATE TABLE IF NOT EXISTS public.app_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    
    -- Event details
    event_name TEXT NOT NULL,
    event_category TEXT, -- e.g., "workout", "navigation", "settings"
    
    -- Event properties
    properties JSONB DEFAULT '{}'::jsonb,
    
    -- Context
    app_version TEXT,
    os_version TEXT,
    device_model TEXT,
    screen_name TEXT,
    
    -- Session tracking
    session_id TEXT, -- App session ID
    
    occurred_at TIMESTAMPTZ DEFAULT NOW()
);

-- Personal records (PRs)
CREATE TABLE IF NOT EXISTS public.personal_records (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    
    exercise_id TEXT NOT NULL,
    exercise_name TEXT NOT NULL,
    
    -- PR type
    record_type TEXT NOT NULL CHECK (record_type IN ('1rm', 'rep_max', 'volume', 'streak')),
    
    -- Values
    weight_kg NUMERIC(6,2),
    reps INTEGER,
    volume_kg NUMERIC(10,2),
    streak_days INTEGER,
    
    -- When achieved
    achieved_at TIMESTAMPTZ NOT NULL,
    session_id UUID REFERENCES public.workout_sessions(id) ON DELETE SET NULL,
    
    -- Previous record (for comparison)
    previous_value NUMERIC(10,2),
    improvement_percentage NUMERIC(5,2),
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================================================
-- 8. INDEXES FOR PERFORMANCE
-- =============================================================================

-- User profiles
CREATE INDEX IF NOT EXISTS idx_user_profiles_email ON public.user_profiles(email);

-- Workout templates
CREATE INDEX IF NOT EXISTS idx_workout_templates_user ON public.workout_templates(user_id);
CREATE INDEX IF NOT EXISTS idx_workout_template_exercises_template ON public.workout_template_exercises(template_id);

-- Sessions
CREATE INDEX IF NOT EXISTS idx_workout_sessions_user ON public.workout_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_workout_sessions_started_at ON public.workout_sessions(started_at DESC);
CREATE INDEX IF NOT EXISTS idx_workout_sessions_user_started ON public.workout_sessions(user_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_session_exercises_session ON public.session_exercises(session_id);
CREATE INDEX IF NOT EXISTS idx_session_sets_exercise ON public.session_sets(session_exercise_id);

-- Lift states
CREATE INDEX IF NOT EXISTS idx_lift_states_user ON public.lift_states(user_id);
CREATE INDEX IF NOT EXISTS idx_lift_states_user_exercise ON public.lift_states(user_id, exercise_id);

-- Biometrics
CREATE INDEX IF NOT EXISTS idx_daily_biometrics_user_date ON public.daily_biometrics(user_id, date DESC);

-- Events
CREATE INDEX IF NOT EXISTS idx_app_events_user ON public.app_events(user_id);
CREATE INDEX IF NOT EXISTS idx_app_events_occurred ON public.app_events(occurred_at DESC);

-- =============================================================================
-- 9. ROW LEVEL SECURITY (RLS)
-- =============================================================================

-- Enable RLS on all user-data tables
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_maxes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workout_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workout_template_exercises ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workout_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.session_exercises ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.session_sets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lift_states ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lift_state_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_biometrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.healthkit_workouts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.personal_records ENABLE ROW LEVEL SECURITY;

-- Exercises are public (read-only for all)
ALTER TABLE public.exercises ENABLE ROW LEVEL SECURITY;

-- RLS Policies

-- User profiles: users can only access their own
CREATE POLICY user_profiles_select ON public.user_profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY user_profiles_insert ON public.user_profiles FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY user_profiles_update ON public.user_profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY user_profiles_delete ON public.user_profiles FOR DELETE USING (auth.uid() = id);

-- User maxes
CREATE POLICY user_maxes_select ON public.user_maxes FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY user_maxes_insert ON public.user_maxes FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY user_maxes_update ON public.user_maxes FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY user_maxes_delete ON public.user_maxes FOR DELETE USING (auth.uid() = user_id);

-- Workout templates: own templates + system templates
CREATE POLICY workout_templates_select ON public.workout_templates FOR SELECT 
    USING (auth.uid() = user_id OR user_id IS NULL);
CREATE POLICY workout_templates_insert ON public.workout_templates FOR INSERT 
    WITH CHECK (auth.uid() = user_id);
CREATE POLICY workout_templates_update ON public.workout_templates FOR UPDATE 
    USING (auth.uid() = user_id);
CREATE POLICY workout_templates_delete ON public.workout_templates FOR DELETE 
    USING (auth.uid() = user_id);

-- Template exercises (follows template access)
CREATE POLICY template_exercises_select ON public.workout_template_exercises FOR SELECT 
    USING (EXISTS (SELECT 1 FROM public.workout_templates t WHERE t.id = template_id AND (auth.uid() = t.user_id OR t.user_id IS NULL)));
CREATE POLICY template_exercises_insert ON public.workout_template_exercises FOR INSERT 
    WITH CHECK (EXISTS (SELECT 1 FROM public.workout_templates t WHERE t.id = template_id AND auth.uid() = t.user_id));
CREATE POLICY template_exercises_update ON public.workout_template_exercises FOR UPDATE 
    USING (EXISTS (SELECT 1 FROM public.workout_templates t WHERE t.id = template_id AND auth.uid() = t.user_id));
CREATE POLICY template_exercises_delete ON public.workout_template_exercises FOR DELETE 
    USING (EXISTS (SELECT 1 FROM public.workout_templates t WHERE t.id = template_id AND auth.uid() = t.user_id));

-- Sessions
CREATE POLICY sessions_select ON public.workout_sessions FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY sessions_insert ON public.workout_sessions FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY sessions_update ON public.workout_sessions FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY sessions_delete ON public.workout_sessions FOR DELETE USING (auth.uid() = user_id);

-- Session exercises
CREATE POLICY session_exercises_select ON public.session_exercises FOR SELECT 
    USING (EXISTS (SELECT 1 FROM public.workout_sessions s WHERE s.id = session_id AND auth.uid() = s.user_id));
CREATE POLICY session_exercises_insert ON public.session_exercises FOR INSERT 
    WITH CHECK (EXISTS (SELECT 1 FROM public.workout_sessions s WHERE s.id = session_id AND auth.uid() = s.user_id));
CREATE POLICY session_exercises_update ON public.session_exercises FOR UPDATE 
    USING (EXISTS (SELECT 1 FROM public.workout_sessions s WHERE s.id = session_id AND auth.uid() = s.user_id));
CREATE POLICY session_exercises_delete ON public.session_exercises FOR DELETE 
    USING (EXISTS (SELECT 1 FROM public.workout_sessions s WHERE s.id = session_id AND auth.uid() = s.user_id));

-- Session sets
CREATE POLICY session_sets_select ON public.session_sets FOR SELECT 
    USING (EXISTS (
        SELECT 1 FROM public.session_exercises se 
        JOIN public.workout_sessions s ON s.id = se.session_id 
        WHERE se.id = session_exercise_id AND auth.uid() = s.user_id
    ));
CREATE POLICY session_sets_insert ON public.session_sets FOR INSERT 
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.session_exercises se 
        JOIN public.workout_sessions s ON s.id = se.session_id 
        WHERE se.id = session_exercise_id AND auth.uid() = s.user_id
    ));
CREATE POLICY session_sets_update ON public.session_sets FOR UPDATE 
    USING (EXISTS (
        SELECT 1 FROM public.session_exercises se 
        JOIN public.workout_sessions s ON s.id = se.session_id 
        WHERE se.id = session_exercise_id AND auth.uid() = s.user_id
    ));
CREATE POLICY session_sets_delete ON public.session_sets FOR DELETE 
    USING (EXISTS (
        SELECT 1 FROM public.session_exercises se 
        JOIN public.workout_sessions s ON s.id = se.session_id 
        WHERE se.id = session_exercise_id AND auth.uid() = s.user_id
    ));

-- Lift states
CREATE POLICY lift_states_select ON public.lift_states FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY lift_states_insert ON public.lift_states FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY lift_states_update ON public.lift_states FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY lift_states_delete ON public.lift_states FOR DELETE USING (auth.uid() = user_id);

-- Lift state history
CREATE POLICY lift_history_select ON public.lift_state_history FOR SELECT 
    USING (EXISTS (SELECT 1 FROM public.lift_states ls WHERE ls.id = lift_state_id AND auth.uid() = ls.user_id));
CREATE POLICY lift_history_insert ON public.lift_state_history FOR INSERT 
    WITH CHECK (EXISTS (SELECT 1 FROM public.lift_states ls WHERE ls.id = lift_state_id AND auth.uid() = ls.user_id));

-- Biometrics
CREATE POLICY biometrics_select ON public.daily_biometrics FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY biometrics_insert ON public.daily_biometrics FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY biometrics_update ON public.daily_biometrics FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY biometrics_delete ON public.daily_biometrics FOR DELETE USING (auth.uid() = user_id);

-- HealthKit workouts
CREATE POLICY hk_workouts_select ON public.healthkit_workouts FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY hk_workouts_insert ON public.healthkit_workouts FOR INSERT WITH CHECK (auth.uid() = user_id);

-- App events
CREATE POLICY events_select ON public.app_events FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY events_insert ON public.app_events FOR INSERT WITH CHECK (auth.uid() = user_id OR user_id IS NULL);

-- Personal records
CREATE POLICY records_select ON public.personal_records FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY records_insert ON public.personal_records FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Exercises are public read-only
CREATE POLICY exercises_select ON public.exercises FOR SELECT USING (true);

-- =============================================================================
-- 10. FUNCTIONS & TRIGGERS
-- =============================================================================

-- Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to relevant tables
CREATE TRIGGER update_user_profiles_updated_at BEFORE UPDATE ON public.user_profiles
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
    
CREATE TRIGGER update_user_maxes_updated_at BEFORE UPDATE ON public.user_maxes
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
    
CREATE TRIGGER update_workout_templates_updated_at BEFORE UPDATE ON public.workout_templates
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
    
CREATE TRIGGER update_template_exercises_updated_at BEFORE UPDATE ON public.workout_template_exercises
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
    
CREATE TRIGGER update_workout_sessions_updated_at BEFORE UPDATE ON public.workout_sessions
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
    
CREATE TRIGGER update_session_exercises_updated_at BEFORE UPDATE ON public.session_exercises
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
    
CREATE TRIGGER update_lift_states_updated_at BEFORE UPDATE ON public.lift_states
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
    
CREATE TRIGGER update_daily_biometrics_updated_at BEFORE UPDATE ON public.daily_biometrics
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
    
CREATE TRIGGER update_exercises_updated_at BEFORE UPDATE ON public.exercises
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- Function to create user profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.user_profiles (id, email, created_at)
    VALUES (NEW.id, NEW.email, NOW())
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for new user signup
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- =============================================================================
-- 11. VIEWS FOR COMMON QUERIES
-- =============================================================================

-- User workout summary view
CREATE OR REPLACE VIEW public.user_workout_summary AS
SELECT 
    u.id as user_id,
    COUNT(DISTINCT ws.id) as total_sessions,
    SUM(ws.total_volume_kg) as total_volume_kg,
    SUM(ws.total_sets) as total_sets,
    SUM(ws.total_reps) as total_reps,
    AVG(ws.duration_seconds) as avg_session_duration,
    MAX(ws.started_at) as last_workout_at,
    COUNT(DISTINCT DATE(ws.started_at)) as unique_workout_days
FROM public.user_profiles u
LEFT JOIN public.workout_sessions ws ON ws.user_id = u.id AND ws.ended_at IS NOT NULL
GROUP BY u.id;

-- Recent workouts view
CREATE OR REPLACE VIEW public.recent_workouts AS
SELECT 
    ws.*,
    COUNT(se.id) as exercise_count_actual
FROM public.workout_sessions ws
LEFT JOIN public.session_exercises se ON se.session_id = ws.id
WHERE ws.ended_at IS NOT NULL
GROUP BY ws.id
ORDER BY ws.started_at DESC;

-- =============================================================================
-- Done! Run this entire script in Supabase SQL Editor
-- =============================================================================
