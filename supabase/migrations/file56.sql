-- ============================================
-- 🔧 ENHANCED MATCHMAKING: Handle 2 and 4 room sizes
-- Run this in Supabase SQL Editor
-- ============================================

DROP FUNCTION IF EXISTS find_compatible_room_enhanced(UUID, gender_preference, INTEGER);

CREATE OR REPLACE FUNCTION find_compatible_room_enhanced(
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
    v_target_gender gender_preference;
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
    RAISE NOTICE '🔍 ENHANCED MATCHMAKING';
    RAISE NOTICE 'User: % (Gender: %)', p_user_id, p_user_gender;
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
      AND r.gender_preference = v_opposite_gender -- Room wants opposite
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
    
    -- ============================================
    -- STEP 3: Try ANY gender (any room with space)
    -- ============================================
    RAISE NOTICE '🔍 STEP 3: Looking for ANY room with space (%)', p_room_size;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.creator_id != p_user_id               -- Not my own room
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- Found any gender match
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCHED with any gender room: %', v_found_room_id;
        RAISE NOTICE '========================================';
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    RAISE NOTICE '⚠️ No room with space found';
    
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

GRANT EXECUTE ON FUNCTION find_compatible_room_enhanced(UUID, gender_preference, INTEGER) TO authenticated, anon;

-- ============================================
-- 🧪 TEST THE ENHANCED FUNCTION
-- ============================================

DO $$
DECLARE
    test_user UUID := gen_random_uuid();
    result RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🧪 TESTING ENHANCED MATCHMAKING';
    RAISE NOTICE '========================================';
    
    -- Create test user
    INSERT INTO users (id, email, display_name, gender) VALUES
        (test_user, 'test@enhanced.com', 'Test User', 'male');
    
    -- Test with room size 2
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 1: Room Size 2';
    SELECT * INTO result FROM find_compatible_room_enhanced(test_user, 'male'::gender_preference, 2);
    RAISE NOTICE '  Room: %', result.matched_room_id;
    RAISE NOTICE '  Is New: %', result.is_new_room;
    
    -- Test with room size 4
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 2: Room Size 4';
    SELECT * INTO result FROM find_compatible_room_enhanced(test_user, 'male'::gender_preference, 4);
    RAISE NOTICE '  Room: %', result.matched_room_id;
    RAISE NOTICE '  Is New: %', result.is_new_room;
    
    -- Cleanup
    DELETE FROM users WHERE email = 'test@enhanced.com';
    
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ ENHANCED MATCHMAKING INSTALLED';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Priority order:';
    RAISE NOTICE '  1️⃣ Opposite gender match';
    RAISE NOTICE '  2️⃣ Same gender fallback';
    RAISE NOTICE '  3️⃣ Any room with space';
    RAISE NOTICE '  4️⃣ Create new room';
    RAISE NOTICE '========================================';
END $$;