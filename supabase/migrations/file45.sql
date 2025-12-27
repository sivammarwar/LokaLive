-- Clean slate first
UPDATE room_participants SET left_at = NOW() WHERE left_at IS NULL;
UPDATE rooms SET is_active = false WHERE is_active = true;

-- Test 1: Male looking for Female
DO $$
DECLARE
    result RECORD;
BEGIN
    RAISE NOTICE '=== TEST 1: MALE LOOKING FOR FEMALE ===';
    
    SELECT * INTO result FROM find_compatible_room(
        gen_random_uuid(),
        'male'::gender_preference,
        'female'::gender_preference,
        'random'::interest_category,
        2
    );
    
    RAISE NOTICE 'Room ID: %', result.matched_room_id;
    RAISE NOTICE 'Is New: %', result.is_new_room;
END $$;

-- Test 2: Female looking for Male (should match above room)
DO $$
DECLARE
    result RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=== TEST 2: FEMALE LOOKING FOR MALE ===';
    
    SELECT * INTO result FROM find_compatible_room(
        gen_random_uuid(),
        'female'::gender_preference,
        'male'::gender_preference,
        'random'::interest_category,
        2
    );
    
    RAISE NOTICE 'Room ID: %', result.matched_room_id;
    RAISE NOTICE 'Is New: %', result.is_new_room;
    
    IF result.is_new_room THEN
        RAISE NOTICE '❌ FAILED: Should have matched existing room!';
    ELSE
        RAISE NOTICE '✅ SUCCESS: Matched existing room!';
    END IF;
END $$;