-- ============================================
-- 🧪 TEST MATCHMAKING
-- This simulates two users matching
-- ============================================

-- Test 1: Male creates room looking for Female
DO $$
DECLARE
    test_user_1 UUID := gen_random_uuid();
    result_1 RECORD;
BEGIN
    -- Create test user
    INSERT INTO users (id, email, display_name, gender)
    VALUES (test_user_1, 'test1@example.com', 'Test Male', 'male');
    
    -- Try to find/create room
    SELECT * INTO result_1 FROM find_compatible_room(
        test_user_1,
        'male'::gender_preference,
        'female'::gender_preference,
        'random'::interest_category,
        2
    );
    
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 1 RESULT:';
    RAISE NOTICE 'Room ID: %', result_1.matched_room_id;
    RAISE NOTICE 'Is New: %', result_1.is_new_room;
    RAISE NOTICE 'Expected: Should CREATE new room (is_new_room = true)';
END $$;

-- Test 2: Female tries to match with that room
DO $$
DECLARE
    test_user_2 UUID := gen_random_uuid();
    result_2 RECORD;
BEGIN
    -- Create test user
    INSERT INTO users (id, email, display_name, gender)
    VALUES (test_user_2, 'test2@example.com', 'Test Female', 'female');
    
    -- Try to find/create room
    SELECT * INTO result_2 FROM find_compatible_room(
        test_user_2,
        'female'::gender_preference,
        'male'::gender_preference,
        'random'::interest_category,
        2
    );
    
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 2 RESULT:';
    RAISE NOTICE 'Room ID: %', result_2.matched_room_id;
    RAISE NOTICE 'Is New: %', result_2.is_new_room;
    RAISE NOTICE 'Expected: Should MATCH existing room (is_new_room = false)';
END $$;

-- Clean up test users
DELETE FROM users WHERE email LIKE 'test%@example.com';