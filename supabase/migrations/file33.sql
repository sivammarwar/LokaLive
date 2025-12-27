-- ============================================
-- DIRECT FUNCTION TEST
-- This will show if the function works at all
-- ============================================

-- First, let's see the exact function signature
SELECT 
    'Function Name' as detail,
    proname as value
FROM pg_proc 
WHERE proname = 'find_compatible_room'

UNION ALL

SELECT 
    'Parameters' as detail,
    pg_get_function_arguments(oid) as value
FROM pg_proc 
WHERE proname = 'find_compatible_room'

UNION ALL

SELECT 
    'Return Type' as detail,
    pg_get_function_result(oid) as value
FROM pg_proc 
WHERE proname = 'find_compatible_room';

-- Now test calling it with a real user ID
-- Replace 'YOUR_USER_ID_HERE' with your actual user ID from the users table
DO $$
DECLARE
    test_user_id UUID;
    result RECORD;
BEGIN
    -- Get the first user ID from your users table
    SELECT id INTO test_user_id FROM users LIMIT 1;
    
    IF test_user_id IS NULL THEN
        RAISE NOTICE '❌ No users found in database!';
        RETURN;
    END IF;
    
    RAISE NOTICE '🧪 Testing with user ID: %', test_user_id;
    
    -- Try calling the function
    BEGIN
        SELECT * INTO result
        FROM find_compatible_room(
            test_user_id,
            'male'::gender_preference,
            'female'::gender_preference,
            'random'::interest_category,
            2
        );
        
        RAISE NOTICE '✅ SUCCESS! Function returned:';
        RAISE NOTICE '   room_id: %', result.room_id;
        RAISE NOTICE '   is_new_room: %', result.is_new_room;
        
    EXCEPTION 
        WHEN undefined_function THEN
            RAISE NOTICE '❌ ERROR: Function does not exist!';
            RAISE NOTICE 'You need to run the SQL migration to create it.';
            
        WHEN undefined_column THEN
            RAISE NOTICE '❌ ERROR: Column does not exist!';
            RAISE NOTICE 'Hint: %', SQLERRM;
            RAISE NOTICE 'There is a typo in the function definition.';
            
        WHEN OTHERS THEN
            RAISE NOTICE '❌ ERROR: %', SQLERRM;
            RAISE NOTICE 'SQL State: %', SQLSTATE;
    END;
END $$;

-- Check if the function actually created a room
SELECT 
    'Rooms created in last 5 minutes' as check,
    COUNT(*) as count
FROM rooms 
WHERE created_at > NOW() - INTERVAL '5 minutes';

-- Show the most recent room
SELECT 
    'Most recent room' as info,
    id,
    room_type,
    is_active,
    creator_gender,
    gender_preference,
    interest_category,
    created_at
FROM rooms 
ORDER BY created_at DESC 
LIMIT 1;