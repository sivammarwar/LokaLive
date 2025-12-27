-- ============================================
-- 🔧 ENHANCED MATCHMAKING: Opposite Gender First, Same Gender Fallback
-- Run this in Supabase SQL Editor
-- ============================================

DROP FUNCTION IF EXISTS find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER);

CREATE OR REPLACE FUNCTION find_compatible_room(
    p_user_id UUID,
    p_user_gender gender_preference,
    p_interested_in gender_preference,
    p_interest interest_category,
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
BEGIN
    -- Validation
    IF p_user_gender = 'other' OR p_interested_in = 'other' THEN
        RAISE EXCEPTION 'Cannot use "other" gender for public matching';
    END IF;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '🔍 MATCHMAKING REQUEST';
    RAISE NOTICE 'User: % (Gender: %)', p_user_id, p_user_gender;
    RAISE NOTICE 'Preferred Match: %', p_interested_in;
    RAISE NOTICE 'Interest: %', p_interest;
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
    -- STEP 1: Try to match with OPPOSITE gender first
    -- ============================================
    RAISE NOTICE '🔍 STEP 1: Looking for opposite gender (%)', p_interested_in;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.interest_category = p_interest
      AND r.creator_gender = p_interested_in    -- Creator has the gender I want
      AND r.gender_preference = p_user_gender   -- Room wants MY gender
      AND r.creator_id != p_user_id
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
    -- STEP 2: Fallback to SAME gender matching
    -- ============================================
    RAISE NOTICE '🔍 STEP 2: Looking for same gender (%)', p_user_gender;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.interest_category = p_interest
      AND r.creator_gender = p_user_gender      -- Creator has MY gender
      AND r.gender_preference = p_user_gender   -- Room wants MY gender (same gender matching)
      AND r.creator_id != p_user_id
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- Found same gender match
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCHED with same gender room: %', v_found_room_id;
        RAISE NOTICE '========================================';
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    RAISE NOTICE '⚠️ No same gender match found';
    
    -- ============================================
    -- STEP 3: Create new room (will match opposite gender first)
    -- ============================================
    RAISE NOTICE '🏗️ CREATING NEW ROOM';
    RAISE NOTICE '  Creator Gender: %', p_user_gender;
    RAISE NOTICE '  Preferred Match: %', p_interested_in;
    
    INSERT INTO public.rooms (
        room_type,
        room_size,
        gender_preference,    -- Prefer opposite gender
        interest_category,
        creator_id,
        creator_gender,       -- My gender
        is_active
    )
    VALUES (
        'public',
        p_room_size,
        p_interested_in,      -- Room prefers opposite gender
        p_interest,
        p_user_id,
        p_user_gender,
        true
    )
    RETURNING id INTO v_created_room_id;
    
    RAISE NOTICE '✅ NEW ROOM CREATED: %', v_created_room_id;
    RAISE NOTICE '  Will match with % first, then % if needed', p_interested_in, p_user_gender;
    RAISE NOTICE '========================================';
    
    RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
END;
$$;

GRANT EXECUTE ON FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) TO authenticated, anon;

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
    RAISE NOTICE '🧪 TESTING ENHANCED MATCHMAKING';
    RAISE NOTICE '========================================';
    
    -- Create test users
    INSERT INTO users (id, email, display_name, gender) VALUES
        (male1, 'testmale1@test.com', 'Male 1', 'male'),
        (male2, 'testmale2@test.com', 'Male 2', 'male'),
        (female1, 'testfemale1@test.com', 'Female 1', 'female');
    
    -- Test 1: First male looking for female
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 1: Male 1 looking for Female';
    SELECT * INTO result1 FROM find_compatible_room(
        male1, 'male'::gender_preference, 'female'::gender_preference, 
        'random'::interest_category, 2
    );
    RAISE NOTICE '  ✓ Room: %', result1.matched_room_id;
    RAISE NOTICE '  ✓ Is New: % (Expected: true)', result1.is_new_room;
    
    -- Test 2: Second male looking for female (should match same gender as fallback)
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 2: Male 2 looking for Female (no females available yet)';
    SELECT * INTO result2 FROM find_compatible_room(
        male2, 'male'::gender_preference, 'female'::gender_preference, 
        'random'::interest_category, 2
    );
    RAISE NOTICE '  ✓ Room: %', result2.matched_room_id;
    RAISE NOTICE '  ✓ Is New: % (Expected: false - should match Male 1)', result2.is_new_room;
    
    -- Test 3: Female looking for male (should match the male room)
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 3: Female looking for Male';
    SELECT * INTO result3 FROM find_compatible_room(
        female1, 'female'::gender_preference, 'male'::gender_preference, 
        'random'::interest_category, 2
    );
    RAISE NOTICE '  ✓ Room: %', result3.matched_room_id;
    RAISE NOTICE '  ✓ Is New: % (Expected: true - creates new female room)', result3.is_new_room;
    
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
    RAISE NOTICE '✅ ENHANCED MATCHMAKING INSTALLED';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE 'Matching Priority:';
    RAISE NOTICE '  1️⃣ Try opposite gender match';
    RAISE NOTICE '  2️⃣ Fallback to same gender';
    RAISE NOTICE '  3️⃣ Create new room if nothing found';
    RAISE NOTICE '';
    RAISE NOTICE 'Example Flow (Male looking for Female):';
    RAISE NOTICE '  • First searches for female-created rooms';
    RAISE NOTICE '  • If none found, matches with other males';
    RAISE NOTICE '  • Creates new room as last resort';
    RAISE NOTICE '';
    RAISE NOTICE 'Ready to use in your React app!';
    RAISE NOTICE '========================================';
END $$;