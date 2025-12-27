-- ============================================
-- 🔧 ENHANCED MATCHMAKING: Opposite Gender First, Same Gender Fallback
-- Run this in Supabase SQL Editor
-- ============================================

DROP FUNCTION IF EXISTS find_compatible_room_simple(UUID, gender_preference, INTEGER);

CREATE OR REPLACE FUNCTION find_compatible_room_simple(
    p_user_id UUID,
    p_user_gender gender_preference,
    p_room_size INTEGER
)
RETURNS TABLE(matched_room_id UUID, is_new_room BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_found_room_id UUID;
    v_created_room_id UUID;
    v_opposite_gender gender_preference;
BEGIN
    -- Validation: Only male or female allowed
    IF p_user_gender NOT IN ('male', 'female') THEN
        RAISE EXCEPTION 'Only "male" or "female" gender allowed for public matching';
    END IF;
    
    -- Determine opposite gender
    IF p_user_gender = 'male' THEN
        v_opposite_gender := 'female';
    ELSE
        v_opposite_gender := 'male';
    END IF;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '🔍 SIMPLE MATCHMAKING WITH FALLBACK';
    RAISE NOTICE 'User: % (Gender: %)', p_user_id, p_user_gender;
    RAISE NOTICE 'Preferred: % | Fallback: %', v_opposite_gender, p_user_gender;
    RAISE NOTICE 'Room Size: %', p_room_size;
    RAISE NOTICE '========================================';
    
    -- Update user's gender
    UPDATE public.users
    SET gender = p_user_gender, updated_at = NOW()
    WHERE id = p_user_id;
    
    -- Leave existing rooms
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id AND left_at IS NULL;
    
    -- ============================================
    -- STEP 1: Try OPPOSITE gender first
    -- ============================================
    RAISE NOTICE '🔍 STEP 1: Looking for opposite gender (%)', v_opposite_gender;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.creator_gender = v_opposite_gender    -- Creator is opposite gender
      AND r.gender_preference = p_user_gender     -- Room wants my gender
      AND r.creator_id != p_user_id               -- Not my own room
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- Found opposite gender match
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCHED with opposite gender room: %', v_found_room_id;
        RAISE NOTICE '========================================';
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    RAISE NOTICE '⚠️ No opposite gender match found';
    
    -- ============================================
    -- STEP 2: Fallback to SAME gender
    -- ============================================
    RAISE NOTICE '🔍 STEP 2: Looking for same gender (%)', p_user_gender;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.creator_gender = p_user_gender        -- Creator is same gender
      AND r.gender_preference = v_opposite_gender -- Room wants opposite (but we'll join anyway)
      AND r.creator_id != p_user_id               -- Not my own room
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- Found same gender match
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCHED with same gender room (fallback): %', v_found_room_id;
        RAISE NOTICE '========================================';
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    RAISE NOTICE '⚠️ No same gender match found';
    
    -- ============================================
    -- STEP 3: Create new room
    -- ============================================
    RAISE NOTICE '🏗️ CREATING NEW ROOM';
    
    INSERT INTO public.rooms (
        room_type,
        room_size,
        gender_preference,    -- Want opposite gender
        interest_category,    -- Default to 'random'
        creator_id,
        creator_gender,       -- My gender
        is_active
    )
    VALUES (
        'public',
        p_room_size,
        v_opposite_gender,    -- Prefer opposite gender
        'random',             -- Default interest
        p_user_id,
        p_user_gender,        -- I am this gender
        true
    )
    RETURNING id INTO v_created_room_id;
    
    RAISE NOTICE '✅ CREATED new room: %', v_created_room_id;
    RAISE NOTICE '  Creator: % (gender: %)', p_user_id, p_user_gender;
    RAISE NOTICE '  Prefers: % | Will accept: %', v_opposite_gender, p_user_gender;
    RAISE NOTICE '========================================';
    
    RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
END;
$$;

GRANT EXECUTE ON FUNCTION find_compatible_room_simple(UUID, gender_preference, INTEGER) TO authenticated, anon;

-- ============================================
-- 🧹 CLEANUP OLD ROOMS (Optional - for testing)
-- ============================================

-- Uncomment these lines if you want to start fresh:
-- UPDATE room_participants SET left_at = NOW() WHERE left_at IS NULL;
-- UPDATE rooms SET is_active = false WHERE is_active = true;

-- ============================================
-- 🧪 COMPREHENSIVE TEST
-- ============================================

DO $$
DECLARE
    male1 UUID := gen_random_uuid();
    male2 UUID := gen_random_uuid();
    female1 UUID := gen_random_uuid();
    result1 RECORD;
    result2 RECORD;
    result3 RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🧪 TESTING SIMPLE MATCHMAKING WITH FALLBACK';
    RAISE NOTICE '========================================';
    
    -- Create test users
    INSERT INTO users (id, email, display_name, gender) VALUES
        (male1, 'testmale1@test.com', 'Male 1', 'male'),
        (male2, 'testmale2@test.com', 'Male 2', 'male'),
        (female1, 'testfemale1@test.com', 'Female 1', 'female');
    
    -- Test 1: First male
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 1: Male 1 creating room';
    SELECT * INTO result1 FROM find_compatible_room_simple(male1, 'male'::gender_preference, 2);
    RAISE NOTICE '  ✓ Room: %', result1.matched_room_id;
    RAISE NOTICE '  ✓ Is New: % (Expected: true)', result1.is_new_room;
    
    -- Test 2: Second male (should match first male via fallback)
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 2: Male 2 looking for match';
    SELECT * INTO result2 FROM find_compatible_room_simple(male2, 'male'::gender_preference, 2);
    RAISE NOTICE '  ✓ Room: %', result2.matched_room_id;
    RAISE NOTICE '  ✓ Is New: % (Expected: false)', result2.is_new_room;
    
    -- Test 3: Female
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 3: Female creating room';
    SELECT * INTO result3 FROM find_compatible_room_simple(female1, 'female'::gender_preference, 2);
    RAISE NOTICE '  ✓ Room: %', result3.matched_room_id;
    RAISE NOTICE '  ✓ Is New: % (Expected: true)', result3.is_new_room;
    
    -- Verify results
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '📊 TEST RESULTS';
    RAISE NOTICE '========================================';
    
    IF result1.is_new_room = true THEN
        RAISE NOTICE '✅ Test 1 PASSED: Male 1 created new room';
    ELSE
        RAISE NOTICE '❌ Test 1 FAILED';
    END IF;
    
    IF result2.is_new_room = false AND result2.matched_room_id = result1.matched_room_id THEN
        RAISE NOTICE '✅ Test 2 PASSED: Male 2 matched with Male 1 (same gender fallback)';
    ELSE
        RAISE NOTICE '❌ Test 2 FAILED';
    END IF;
    
    IF result3.is_new_room = true THEN
        RAISE NOTICE '✅ Test 3 PASSED: Female created new room';
    ELSE
        RAISE NOTICE '❌ Test 3 FAILED';
    END IF;
    
    -- Cleanup
    DELETE FROM users WHERE email LIKE 'test%@test.com';
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
END $$;

-- ============================================
-- ✅ SUCCESS MESSAGE
-- ============================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ SIMPLE MATCHMAKING INSTALLED';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE 'Function: find_compatible_room_simple()';
    RAISE NOTICE 'Parameters: (user_id, gender, room_size)';
    RAISE NOTICE '';
    RAISE NOTICE 'Matching Priority:';
    RAISE NOTICE '  1️⃣ Try opposite gender';
    RAISE NOTICE '  2️⃣ Fallback to same gender';
    RAISE NOTICE '  3️⃣ Create new room';
    RAISE NOTICE '';
    RAISE NOTICE 'Your React app should now work!';
    RAISE NOTICE '========================================';
END $$;