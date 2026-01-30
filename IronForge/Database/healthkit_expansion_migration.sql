-- ============================================================================
-- HEALTHKIT EXPANSION MIGRATION
-- Adds all new HealthKit data fields to daily_biometrics
-- Run this in Supabase SQL Editor
-- ============================================================================

-- ============================================================================
-- SECTION 0: ENSURE BASE COLUMNS EXIST
-- These may already exist from the original table, but we add them just in case
-- ============================================================================
ALTER TABLE daily_biometrics
ADD COLUMN IF NOT EXISTS sleep_minutes DECIMAL(8,2),
ADD COLUMN IF NOT EXISTS hrv_sdnn DECIMAL(6,2),
ADD COLUMN IF NOT EXISTS resting_hr DECIMAL(5,2),
ADD COLUMN IF NOT EXISTS active_energy DECIMAL(10,2),
ADD COLUMN IF NOT EXISTS steps DECIMAL(10,0),
ADD COLUMN IF NOT EXISTS body_weight_kg DECIMAL(6,2),
ADD COLUMN IF NOT EXISTS body_fat_percentage DECIMAL(5,2),
ADD COLUMN IF NOT EXISTS lean_body_mass_kg DECIMAL(6,2),
ADD COLUMN IF NOT EXISTS body_weight_from_healthkit BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS nutrition_bucket TEXT,
ADD COLUMN IF NOT EXISTS protein_bucket TEXT,
ADD COLUMN IF NOT EXISTS protein_grams INT,
ADD COLUMN IF NOT EXISTS total_calories INT,
ADD COLUMN IF NOT EXISTS hydration_level INT,
ADD COLUMN IF NOT EXISTS alcohol_level INT,
ADD COLUMN IF NOT EXISTS cycle_phase TEXT,
ADD COLUMN IF NOT EXISTS cycle_day_number INT,
ADD COLUMN IF NOT EXISTS on_hormonal_birth_control BOOLEAN,
ADD COLUMN IF NOT EXISTS sleep_quality INT,
ADD COLUMN IF NOT EXISTS sleep_disruptions INT,
ADD COLUMN IF NOT EXISTS energy_level INT,
ADD COLUMN IF NOT EXISTS stress_level INT,
ADD COLUMN IF NOT EXISTS mood_score INT,
ADD COLUMN IF NOT EXISTS overall_soreness INT,
ADD COLUMN IF NOT EXISTS readiness_score INT,
ADD COLUMN IF NOT EXISTS has_illness BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS has_travel BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS has_work_stress BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS had_poor_sleep BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS has_other_stress BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS stress_notes TEXT,
ADD COLUMN IF NOT EXISTS from_healthkit BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS from_manual_entry BOOLEAN DEFAULT FALSE;

-- ============================================================================
-- SECTION 1: CORE RECOVERY METRICS
-- ============================================================================
ALTER TABLE daily_biometrics
ADD COLUMN IF NOT EXISTS vo2_max DECIMAL(6,2),
ADD COLUMN IF NOT EXISTS respiratory_rate DECIMAL(5,2),
ADD COLUMN IF NOT EXISTS oxygen_saturation DECIMAL(5,2);

COMMENT ON COLUMN daily_biometrics.vo2_max IS 'VO2 Max in mL/(kg·min) - best single predictor of recovery capacity';
COMMENT ON COLUMN daily_biometrics.respiratory_rate IS 'Respiratory rate in breaths/min during sleep';
COMMENT ON COLUMN daily_biometrics.oxygen_saturation IS 'Blood oxygen saturation percentage (0-100)';

-- ============================================================================
-- SECTION 2: ACTIVITY METRICS
-- ============================================================================
ALTER TABLE daily_biometrics
ADD COLUMN IF NOT EXISTS exercise_time_minutes DECIMAL(8,2),
ADD COLUMN IF NOT EXISTS stand_hours INT;

COMMENT ON COLUMN daily_biometrics.exercise_time_minutes IS 'Total exercise time in minutes';
COMMENT ON COLUMN daily_biometrics.stand_hours IS 'Count of hours with standing activity';

-- ============================================================================
-- SECTION 3: WALKING METRICS (Injury Detection)
-- ============================================================================
ALTER TABLE daily_biometrics
ADD COLUMN IF NOT EXISTS walking_heart_rate_avg DECIMAL(5,2),
ADD COLUMN IF NOT EXISTS walking_asymmetry DECIMAL(5,2),
ADD COLUMN IF NOT EXISTS walking_speed DECIMAL(5,3),
ADD COLUMN IF NOT EXISTS walking_step_length DECIMAL(5,3),
ADD COLUMN IF NOT EXISTS walking_double_support DECIMAL(5,2),
ADD COLUMN IF NOT EXISTS stair_ascent_speed DECIMAL(5,3),
ADD COLUMN IF NOT EXISTS stair_descent_speed DECIMAL(5,3),
ADD COLUMN IF NOT EXISTS six_minute_walk_distance DECIMAL(8,2);

COMMENT ON COLUMN daily_biometrics.walking_heart_rate_avg IS 'Walking heart rate average in BPM';
COMMENT ON COLUMN daily_biometrics.walking_asymmetry IS 'Walking asymmetry percentage - early injury indicator';
COMMENT ON COLUMN daily_biometrics.walking_speed IS 'Walking speed in m/s';
COMMENT ON COLUMN daily_biometrics.walking_step_length IS 'Step length in meters';
COMMENT ON COLUMN daily_biometrics.walking_double_support IS 'Double support percentage';
COMMENT ON COLUMN daily_biometrics.stair_ascent_speed IS 'Stair climb speed in m/s - leg power indicator';
COMMENT ON COLUMN daily_biometrics.stair_descent_speed IS 'Stair descent speed in m/s';
COMMENT ON COLUMN daily_biometrics.six_minute_walk_distance IS 'Six minute walk test distance in meters';

-- ============================================================================
-- SECTION 4: SLEEP DETAILS (iOS 16+)
-- ============================================================================
ALTER TABLE daily_biometrics
ADD COLUMN IF NOT EXISTS time_in_bed_minutes DECIMAL(8,2),
ADD COLUMN IF NOT EXISTS sleep_awake_minutes DECIMAL(8,2),
ADD COLUMN IF NOT EXISTS sleep_core_minutes DECIMAL(8,2),
ADD COLUMN IF NOT EXISTS sleep_deep_minutes DECIMAL(8,2),
ADD COLUMN IF NOT EXISTS sleep_rem_minutes DECIMAL(8,2),
ADD COLUMN IF NOT EXISTS time_in_daylight_minutes DECIMAL(8,2),
ADD COLUMN IF NOT EXISTS wrist_temperature_celsius DECIMAL(5,2);

COMMENT ON COLUMN daily_biometrics.time_in_bed_minutes IS 'Total time in bed in minutes';
COMMENT ON COLUMN daily_biometrics.sleep_awake_minutes IS 'Time awake during sleep in minutes';
COMMENT ON COLUMN daily_biometrics.sleep_core_minutes IS 'Light/core sleep in minutes';
COMMENT ON COLUMN daily_biometrics.sleep_deep_minutes IS 'Deep sleep in minutes - correlates with anabolic hormones';
COMMENT ON COLUMN daily_biometrics.sleep_rem_minutes IS 'REM sleep in minutes';
COMMENT ON COLUMN daily_biometrics.time_in_daylight_minutes IS 'Time in daylight - affects circadian rhythm (iOS 17+)';
COMMENT ON COLUMN daily_biometrics.wrist_temperature_celsius IS 'Wrist temperature deviation in Celsius (Watch S8+)';

-- ============================================================================
-- SECTION 5: NUTRITION FROM HEALTHKIT
-- ============================================================================
ALTER TABLE daily_biometrics
ADD COLUMN IF NOT EXISTS dietary_energy_kcal DECIMAL(8,2),
ADD COLUMN IF NOT EXISTS dietary_protein_grams DECIMAL(8,2),
ADD COLUMN IF NOT EXISTS dietary_carbs_grams DECIMAL(8,2),
ADD COLUMN IF NOT EXISTS dietary_fat_grams DECIMAL(8,2),
ADD COLUMN IF NOT EXISTS water_intake_liters DECIMAL(6,3),
ADD COLUMN IF NOT EXISTS caffeine_mg DECIMAL(8,2);

COMMENT ON COLUMN daily_biometrics.dietary_energy_kcal IS 'Dietary energy from HealthKit in kcal';
COMMENT ON COLUMN daily_biometrics.dietary_protein_grams IS 'Dietary protein from HealthKit in grams';
COMMENT ON COLUMN daily_biometrics.dietary_carbs_grams IS 'Dietary carbohydrates from HealthKit in grams';
COMMENT ON COLUMN daily_biometrics.dietary_fat_grams IS 'Dietary fat from HealthKit in grams';
COMMENT ON COLUMN daily_biometrics.water_intake_liters IS 'Water intake from HealthKit in liters';
COMMENT ON COLUMN daily_biometrics.caffeine_mg IS 'Caffeine intake from HealthKit in mg';

-- ============================================================================
-- SECTION 6: FEMALE HEALTH (Opt-in)
-- ============================================================================
ALTER TABLE daily_biometrics
ADD COLUMN IF NOT EXISTS menstrual_flow_raw INT,
ADD COLUMN IF NOT EXISTS cervical_mucus_quality_raw INT,
ADD COLUMN IF NOT EXISTS basal_body_temperature_celsius DECIMAL(5,2);

COMMENT ON COLUMN daily_biometrics.menstrual_flow_raw IS 'Menstrual flow (raw HealthKit value)';
COMMENT ON COLUMN daily_biometrics.cervical_mucus_quality_raw IS 'Cervical mucus quality (raw HealthKit value)';
COMMENT ON COLUMN daily_biometrics.basal_body_temperature_celsius IS 'Basal body temperature in Celsius';

-- ============================================================================
-- SECTION 7: MINDFULNESS
-- ============================================================================
ALTER TABLE daily_biometrics
ADD COLUMN IF NOT EXISTS mindful_minutes DECIMAL(8,2);

COMMENT ON COLUMN daily_biometrics.mindful_minutes IS 'Mindful session minutes from HealthKit';

-- ============================================================================
-- SECTION 8: INDEXES FOR ML QUERIES
-- ============================================================================

-- Recovery metrics (commonly used for readiness calculations)
CREATE INDEX IF NOT EXISTS idx_daily_biometrics_vo2max ON daily_biometrics(vo2_max) WHERE vo2_max IS NOT NULL;

-- Walking asymmetry (injury detection)
CREATE INDEX IF NOT EXISTS idx_daily_biometrics_asymmetry ON daily_biometrics(walking_asymmetry) WHERE walking_asymmetry IS NOT NULL;

-- Sleep quality (deep sleep percentage)
CREATE INDEX IF NOT EXISTS idx_daily_biometrics_deep_sleep ON daily_biometrics(sleep_deep_minutes) WHERE sleep_deep_minutes IS NOT NULL;

-- ============================================================================
-- SECTION 9: ML TRAINING VIEW (Expanded Biometrics)
-- ============================================================================
DROP VIEW IF EXISTS ml_daily_biometrics CASCADE;

CREATE VIEW ml_daily_biometrics AS
SELECT 
    id,
    user_id,
    date,
    
    -- Core Recovery (High ML Value)
    sleep_minutes,
    hrv_sdnn,
    resting_hr,
    vo2_max,
    respiratory_rate,
    oxygen_saturation,
    
    -- Sleep Quality Derived
    time_in_bed_minutes,
    sleep_deep_minutes,
    sleep_rem_minutes,
    CASE WHEN time_in_bed_minutes > 0 
         THEN sleep_minutes / time_in_bed_minutes 
         ELSE NULL 
    END as sleep_efficiency,
    CASE WHEN sleep_minutes > 0 
         THEN sleep_deep_minutes / sleep_minutes * 100 
         ELSE NULL 
    END as deep_sleep_percentage,
    CASE WHEN sleep_minutes > 0 
         THEN sleep_rem_minutes / sleep_minutes * 100 
         ELSE NULL 
    END as rem_sleep_percentage,
    time_in_daylight_minutes,
    wrist_temperature_celsius,
    
    -- Activity
    active_energy,
    steps,
    exercise_time_minutes,
    stand_hours,
    
    -- Walking (Injury Signals)
    walking_heart_rate_avg,
    walking_asymmetry,
    walking_speed,
    stair_ascent_speed,
    six_minute_walk_distance,
    
    -- Body Composition
    body_weight_kg,
    body_fat_percentage,
    lean_body_mass_kg,
    
    -- Nutrition (if tracked)
    dietary_energy_kcal,
    dietary_protein_grams,
    CASE WHEN dietary_energy_kcal > 0 AND dietary_protein_grams > 0
         THEN dietary_protein_grams * 4 / dietary_energy_kcal * 100
         ELSE NULL
    END as protein_percentage,
    caffeine_mg,
    water_intake_liters,
    
    -- Female Health (opt-in)
    cycle_phase,
    cycle_day_number,
    menstrual_flow_raw,
    basal_body_temperature_celsius,
    
    -- Mindfulness
    mindful_minutes,
    
    -- Subjective
    energy_level,
    stress_level,
    mood_score,
    overall_soreness,
    readiness_score,
    
    -- Stress Flags
    has_illness,
    has_travel,
    has_work_stress,
    had_poor_sleep,
    has_other_stress,
    
    -- Metadata
    from_healthkit,
    from_manual_entry,
    updated_at
    
FROM daily_biometrics
WHERE 
    -- At least one meaningful metric present
    sleep_minutes IS NOT NULL 
    OR hrv_sdnn IS NOT NULL 
    OR vo2_max IS NOT NULL
    OR steps IS NOT NULL
    OR active_energy IS NOT NULL;

COMMENT ON VIEW ml_daily_biometrics IS 'Flattened daily biometrics with derived metrics for ML training';

-- ============================================================================
-- DONE
-- ============================================================================
SELECT 'HealthKit expansion migration complete. Added: VO2 Max, respiratory rate, SpO2, walking metrics, sleep stages, nutrition, female health, mindfulness.' as status;
