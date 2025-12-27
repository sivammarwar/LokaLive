-- ============================================
-- 🔧 COMPLETE NEXT ROOM FIX
-- Run this in Supabase SQL Editor
-- ============================================

-- Drop old functions
DROP FUNCTION IF EXISTS find_compatible_room_simple(UUID, gender_preference, INTEGER);

-- ============================================
-- NEW: Unified matchmaking function for Next Room
-- ============================================
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
    -- Validation
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
    RAISE NOTICE '🔍 NEXT ROOM SEARCH';
    RAISE NOTICE 'User: % (Gender: %)', p_user_id, p_user_gender;
    RAISE NOTICE 'Room Size: %', p_room_size;
    RAISE NOTICE '========================================';
    
    -- Update user's gender
    UPDATE public.users
    SET gender = p_user_gender, updated_at = NOW()
    WHERE id = p_user_id;
    
    -- ✅ CRITICAL: Leave ALL existing rooms first
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id AND left_at IS NULL;
    
    RAISE NOTICE '✅ Left all existing rooms';
    
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
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) > 0  -- ✅ NEW: Must have at least 1 person waiting
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCHED opposite gender room: %', v_found_room_id;
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
      AND r.gender_preference = v_opposite_gender -- Room wants opposite
      AND r.creator_id != p_user_id               -- Not my own room
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) > 0  -- ✅ NEW: Must have at least 1 person waiting
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCHED same gender room (fallback): %', v_found_room_id;
        RAISE NOTICE '========================================';
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    RAISE NOTICE '⚠️ No same gender match found';
    
    -- ============================================
    -- STEP 3: Try ANY room with space (for 4-person)
    -- ============================================
    IF p_room_size = 4 THEN
        RAISE NOTICE '🔍 STEP 3: Looking for ANY 4-person room with space';
        
        SELECT r.id INTO v_found_room_id
        FROM public.rooms r
        WHERE r.room_type = 'public'
          AND r.is_active = true
          AND r.room_size = 4
          AND r.creator_id != p_user_id
          AND (
              SELECT COUNT(*) 
              FROM public.room_participants rp
              WHERE rp.room_id = r.id AND rp.left_at IS NULL
          ) BETWEEN 1 AND 3  -- ✅ Has 1-3 people (not empty, not full)
        ORDER BY r.created_at ASC
        LIMIT 1;
        
        IF v_found_room_id IS NOT NULL THEN
            RAISE NOTICE '✅ MATCHED 4-person room: %', v_found_room_id;
            RAISE NOTICE '========================================';
            RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
            RETURN;
        END IF;
    END IF;
    
    RAISE NOTICE '⚠️ No available room found';
    
    -- ============================================
    -- STEP 4: Create new room
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
    RAISE NOTICE '  Prefers: %', v_opposite_gender;
    RAISE NOTICE '========================================';
    
    RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
END;
$$;

GRANT EXECUTE ON FUNCTION find_compatible_room_simple(UUID, gender_preference, INTEGER) TO authenticated, anon;

-- ============================================
-- TEST THE FIX
-- ============================================
DO $$
DECLARE
    test_male UUID := gen_random_uuid();
    test_female UUID := gen_random_uuid();
    result1 RECORD;
    result2 RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🧪 TESTING NEXT ROOM FUNCTION';
    RAISE NOTICE '========================================';
    
    -- Create test users
    INSERT INTO users (id, email, display_name, gender) VALUES
        (test_male, 'test_next_male@test.com', 'Test Male', 'male'),
        (test_female, 'test_next_female@test.com', 'Test Female', 'female');
    
    -- Test 1: Male creates room
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 1: Male creates 2-person room';
    SELECT * INTO result1 FROM find_compatible_room_simple(test_male, 'male'::gender_preference, 2);
    RAISE NOTICE '  Room: %', result1.matched_room_id;
    RAISE NOTICE '  Is New: % (Expected: true)', result1.is_new_room;
    
    -- Test 2: Female should match
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 2: Female tries next room';
    SELECT * INTO result2 FROM find_compatible_room_simple(test_female, 'female'::gender_preference, 2);
    RAISE NOTICE '  Room: %', result2.matched_room_id;
    RAISE NOTICE '  Is New: % (Expected: false)', result2.is_new_room;
    
    IF result1.matched_room_id = result2.matched_room_id THEN
        RAISE NOTICE '  ✅ SUCCESS: Both matched same room!';
    ELSE
        RAISE NOTICE '  ❌ FAILED: Different rooms';
    END IF;
    
    -- Cleanup
    DELETE FROM users WHERE email LIKE 'test_next_%@test.com';
    
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ NEXT ROOM FUNCTION READY';
    RAISE NOTICE '========================================';
END $$;