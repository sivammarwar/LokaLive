-- ============================================
-- COMPLETE DATABASE STATE VERIFICATION
-- Run this in Supabase SQL Editor to see what's wrong
-- ============================================

-- 1. Check if find_compatible_room function exists
SELECT 
    '1. Function Exists' as check_name,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM pg_proc 
            WHERE proname = 'find_compatible_room'
        ) THEN '✅ Yes'
        ELSE '❌ No - You need to run the SQL migration!'
    END as result;

-- 2. Check function signature
SELECT 
    '2. Function Signature' as check_name,
    pg_get_function_arguments(oid) as signature
FROM pg_proc 
WHERE proname = 'find_compatible_room';

-- 3. Check if there are any syntax errors in the function
SELECT 
    '3. Function Validity' as check_name,
    CASE 
        WHEN prorettype IS NOT NULL THEN '✅ Function is valid'
        ELSE '❌ Function has errors'
    END as result
FROM pg_proc 
WHERE proname = 'find_compatible_room';

-- 4. Check users table structure
SELECT 
    '4. Users Table - Gender Column' as check_name,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_name = 'users' 
            AND column_name = 'gender'
            AND data_type = 'USER-DEFINED' -- Means it's using gender_preference enum
        ) THEN '✅ Correct type (enum)'
        ELSE '❌ Wrong type or missing'
    END as result;

-- 5. Check rooms table structure
SELECT 
    '5. Rooms Table - Interest Column' as check_name,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_name = 'rooms' 
            AND column_name = 'interest_category'
            AND data_type = 'USER-DEFINED'
        ) THEN '✅ Correct (interest_category enum)'
        ELSE '❌ Wrong type or missing'
    END as result;

-- 6. Check active public rooms
SELECT 
    '6. Active Public Rooms' as check_name,
    COUNT(*)::text || ' rooms' as result
FROM rooms
WHERE room_type = 'public' AND is_active = true;

-- 7. Check users with valid gender
SELECT 
    '7. Users with Valid Gender' as check_name,
    COUNT(*)::text || ' users (male/female)' as result
FROM users
WHERE gender IN ('male', 'female');

-- 8. Check users with 'other' gender (problematic)
SELECT 
    '8. Users with "other" Gender' as check_name,
    COUNT(*)::text || ' users (⚠️ cannot match)' as result
FROM users
WHERE gender = 'other';

-- 9. Test the function with dummy data (CRITICAL TEST)
SELECT 
    '9. Function Test' as check_name,
    'See result below' as result;

-- Actually try to call the function
-- This will show the exact error if it fails
DO $$
DECLARE
    test_result RECORD;
BEGIN
    -- Try to call find_compatible_room
    BEGIN
        SELECT * INTO test_result
        FROM find_compatible_room(
            '00000000-0000-0000-0000-000000000000'::UUID,
            'male'::gender_preference,
            'female'::gender_preference,
            'random'::interest_category,
            2
        );
        
        RAISE NOTICE '✅ Function call succeeded!';
        RAISE NOTICE 'Result: room_id=%, is_new_room=%', test_result.room_id, test_result.is_new_room;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '❌ Function call failed!';
        RAISE NOTICE 'Error: %', SQLERRM;
        RAISE NOTICE 'Detail: %', SQLSTATE;
    END;
END $$;

-- 10. Show all function definitions that might be conflicting
SELECT 
    '10. All find_compatible Functions' as check_name,
    string_agg(proname || '(' || pg_get_function_arguments(oid) || ')', ', ') as result
FROM pg_proc 
WHERE proname LIKE '%find_compatible%';

-- ============================================
-- DETAILED ROOM ANALYSIS
-- ============================================

SELECT 
    '══════════════════════════════════════' as separator,
    'DETAILED ROOM ANALYSIS' as title,
    '══════════════════════════════════════' as separator2;

SELECT 
    r.id,
    r.room_type,
    r.is_active,
    r.creator_gender,
    r.gender_preference,
    r.interest_category,
    r.room_size,
    COUNT(rp.user_id) FILTER (WHERE rp.left_at IS NULL) as current_participants,
    r.created_at
FROM rooms r
LEFT JOIN room_participants rp ON rp.room_id = r.id
WHERE r.room_type = 'public'
GROUP BY r.id
ORDER BY r.created_at DESC
LIMIT 5;

-- ============================================
-- CRITICAL ISSUES SUMMARY
-- ============================================

SELECT 
    '══════════════════════════════════════' as separator,
    'CRITICAL ISSUES' as title,
    '══════════════════════════════════════' as separator2;

SELECT 
    CASE 
        WHEN NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'find_compatible_room')
        THEN '🔴 CRITICAL: find_compatible_room function does not exist!'
        
        WHEN EXISTS (
            SELECT 1 FROM users WHERE gender = 'other'
        )
        THEN '⚠️ WARNING: Some users have gender="other" (cannot match in public rooms)'
        
        WHEN NOT EXISTS (
            SELECT 1 FROM rooms WHERE room_type = 'public' AND is_active = true
        )
        THEN 'ℹ️ INFO: No active public rooms (this is OK if no one is matching)'
        
        ELSE '✅ All checks passed! The database structure looks good.'
    END as status;

-- ============================================
-- NEXT STEPS
-- ============================================

DO $$
BEGIN
    RAISE NOTICE '══════════════════════════════════════';
    RAISE NOTICE 'NEXT STEPS:';
    RAISE NOTICE '══════════════════════════════════════';
    RAISE NOTICE '1. Review the results above';
    RAISE NOTICE '2. If function does not exist, run the fix_matchmaking_function.sql';
    RAISE NOTICE '3. If users have gender="other", they need to update their profile';
    RAISE NOTICE '4. Copy the exact error from the "9. Function Test" section';
    RAISE NOTICE '5. Share that error for further diagnosis';
    RAISE NOTICE '══════════════════════════════════════';
END $$;