-- =============================================================================
-- PILOT USER CREATION SQL
-- Run these commands in Supabase SQL Editor or Dashboard
-- =============================================================================

-- =============================================================================
-- OPTION 1: Create users via Supabase Dashboard (RECOMMENDED)
-- =============================================================================
-- 
-- 1. Go to your Supabase project → Authentication → Users
-- 2. Click "Add user" → "Create new user"
-- 3. Enter email and password
-- 4. Check "Auto Confirm User" so they can login immediately
-- 5. Copy the user's UUID from the list
-- 6. Then run the SQL below to enroll them in the pilot

-- =============================================================================
-- OPTION 2: Create users via SQL (if you have admin access)
-- =============================================================================

-- NOTE: Creating auth users via SQL requires the service_role key or admin access.
-- The Supabase Dashboard method (Option 1) is easier and safer.

-- If you DO have admin access, you can use this function:
-- (Run this once to create the helper function)

CREATE OR REPLACE FUNCTION create_pilot_user(
    user_email TEXT,
    user_password TEXT,
    user_display_name TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, public
AS $$
DECLARE
    new_user_id UUID;
BEGIN
    -- Insert into auth.users (this requires elevated privileges)
    INSERT INTO auth.users (
        instance_id,
        id,
        aud,
        role,
        email,
        encrypted_password,
        email_confirmed_at,
        raw_app_meta_data,
        raw_user_meta_data,
        created_at,
        updated_at,
        confirmation_token,
        recovery_token
    )
    VALUES (
        '00000000-0000-0000-0000-000000000000',
        gen_random_uuid(),
        'authenticated',
        'authenticated',
        user_email,
        crypt(user_password, gen_salt('bf')),
        NOW(), -- Auto-confirm
        '{"provider":"email","providers":["email"]}',
        jsonb_build_object('display_name', COALESCE(user_display_name, split_part(user_email, '@', 1))),
        NOW(),
        NOW(),
        '',
        ''
    )
    RETURNING id INTO new_user_id;
    
    RETURN new_user_id;
END;
$$;

-- =============================================================================
-- STEP 2: Enroll user in pilot program
-- =============================================================================

-- After creating the user (via Dashboard or SQL), enroll them in the pilot:

-- Replace 'USER_UUID_HERE' with the actual user ID from Supabase Dashboard
-- Then uncomment and run the INSERT statement below

/*
INSERT INTO public.pilot_participants (
    user_id,
    enrolled_at,
    enrolled_by,
    status,
    conservative_mode,
    max_weekly_increase_percent,
    allow_increase_after_grinder,
    allow_increase_low_readiness,
    consent_given_at,
    consent_version,
    label_prompt_frequency
)
VALUES (
    'USER_UUID_HERE'::uuid,  -- ← Replace with actual user UUID
    NOW(),
    'rahul',                  -- Who recruited them
    'active',
    true,                     -- Conservative mode ON
    5.0,                      -- Max 5% weekly increase
    false,                    -- No increase after grinder
    false,                    -- No increase if low readiness
    NOW(),
    'v1',
    'triggers_only'           -- Only prompt at key moments
);
*/

-- =============================================================================
-- BATCH ENROLLMENT EXAMPLE
-- =============================================================================

-- If you've created multiple users via Dashboard, enroll them all at once:

/*
INSERT INTO public.pilot_participants (user_id, enrolled_at, enrolled_by, status, conservative_mode)
VALUES 
    ('uuid-for-friend-1'::uuid, NOW(), 'rahul', 'active', true),
    ('uuid-for-friend-2'::uuid, NOW(), 'rahul', 'active', true),
    ('uuid-for-friend-3'::uuid, NOW(), 'rahul', 'active', true);
*/

-- =============================================================================
-- QUICK REFERENCE: Create user + enroll in one go (if using SQL function)
-- =============================================================================

/*
DO $$
DECLARE
    new_id UUID;
BEGIN
    -- Create the user
    new_id := create_pilot_user(
        'friend@example.com',
        'SecurePassword123!',
        'Alex'
    );
    
    -- Enroll in pilot
    INSERT INTO public.pilot_participants (user_id, enrolled_by, status, conservative_mode)
    VALUES (new_id, 'rahul', 'active', true);
    
    RAISE NOTICE 'Created pilot user with ID: %', new_id;
END $$;
*/

-- =============================================================================
-- VERIFY PILOT USERS
-- =============================================================================

-- Check who's enrolled in the pilot:
SELECT 
    pp.user_id,
    up.email,
    up.display_name,
    pp.status,
    pp.conservative_mode,
    pp.enrolled_at,
    pp.enrolled_by
FROM public.pilot_participants pp
LEFT JOIN public.user_profiles up ON up.id = pp.user_id
ORDER BY pp.enrolled_at DESC;

-- =============================================================================
-- UPDATE PILOT SETTINGS FOR A USER
-- =============================================================================

-- Make a user's settings more/less conservative:
/*
UPDATE public.pilot_participants
SET 
    conservative_mode = true,
    max_weekly_increase_percent = 3.0,  -- Even more conservative
    allow_increase_after_grinder = false,
    allow_increase_low_readiness = false
WHERE user_id = 'USER_UUID_HERE'::uuid;
*/

-- =============================================================================
-- PAUSE/RESUME A PILOT USER
-- =============================================================================

-- Pause a user (they can still use the app, but won't be prompted for labels):
/*
UPDATE public.pilot_participants
SET status = 'paused', status_changed_at = NOW()
WHERE user_id = 'USER_UUID_HERE'::uuid;
*/

-- Resume:
/*
UPDATE public.pilot_participants
SET status = 'active', status_changed_at = NOW()
WHERE user_id = 'USER_UUID_HERE'::uuid;
*/

-- =============================================================================
-- WITHDRAW A USER FROM PILOT
-- =============================================================================

/*
UPDATE public.pilot_participants
SET status = 'withdrawn', status_changed_at = NOW()
WHERE user_id = 'USER_UUID_HERE'::uuid;
*/
