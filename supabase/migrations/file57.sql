-- ============================================
-- 🔄 REVERT ENHANCED MATCHMAKING FUNCTION
-- This removes the enhanced function and keeps the original setup
-- ============================================

-- Step 1: Drop the enhanced function if it exists
DROP FUNCTION IF EXISTS find_compatible_room_enhanced(UUID, gender_preference, INTEGER);

-- Step 2: Recreate the original simple matchmaking function from FILE-53
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

-- Step 3: Recreate the main find_compatible_room function from FILE-51
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
    
    RAISE NOTICE '🔍 MATCHMAKING: User % (gender: %) looking for %', 
        p_user_id, p_user_gender, p_interested_in;
    
    -- Update user's gender
    UPDATE public.users
    SET gender = p_user_gender, updated_at = NOW()
    WHERE id = p_user_id;
    
    -- Leave existing rooms
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id AND left_at IS NULL;
    
    -- ✅ CORRECT LOGIC: Find rooms created by people I'm interested in, who want my gender
    -- If I'm Male looking for Female:
    --   Find rooms where creator_gender='female' AND gender_preference='male'
    -- If I'm Female looking for Male:
    --   Find rooms where creator_gender='male' AND gender_preference='female'
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.interest_category = p_interest
      AND r.creator_gender = p_interested_in    -- ✅ Creator has the gender I want
      AND r.gender_preference = p_user_gender   -- ✅ Room wants MY gender
      AND r.creator_id != p_user_id
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- Found existing room
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCHED existing room: %', v_found_room_id;
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    -- Create new room
    -- This room will be found by users with opposite matching criteria
    INSERT INTO public.rooms (
        room_type,
        room_size,
        gender_preference,    -- What gender I want to meet
        interest_category,
        creator_id,
        creator_gender,       -- My gender
        is_active
    )
    VALUES (
        'public',
        p_room_size,
        p_interested_in,      -- I want to meet this gender
        p_interest,
        p_user_id,
        p_user_gender,        -- I am this gender
        true
    )
    RETURNING id INTO v_created_room_id;
    
    RAISE NOTICE '🏗️ CREATED new room: %', v_created_room_id;
    
    RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
END;
$$;

GRANT EXECUTE ON FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) TO authenticated, anon;

-- ============================================
-- ✅ VERIFICATION
-- ============================================

DO $$
DECLARE
    test_user UUID := gen_random_uuid();
    result RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ REVERT COMPLETE';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    
    -- Test that the simple function exists
    SELECT proname INTO result 
    FROM pg_proc 
    WHERE proname = 'find_compatible_room_simple';
    
    IF FOUND THEN
        RAISE NOTICE '✅ find_compatible_room_simple function restored';
    ELSE
        RAISE NOTICE '❌ Function not found';
    END IF;
    
    -- Test that the main function exists
    SELECT proname INTO result 
    FROM pg_proc 
    WHERE proname = 'find_compatible_room';
    
    IF FOUND THEN
        RAISE NOTICE '✅ find_compatible_room function restored';
    ELSE
        RAISE NOTICE '❌ Function not found';
    END IF;
    
    -- Verify enhanced function is gone
    SELECT proname INTO result 
    FROM pg_proc 
    WHERE proname = 'find_compatible_room_enhanced';
    
    IF NOT FOUND THEN
        RAISE NOTICE '✅ find_compatible_room_enhanced function removed';
    ELSE
        RAISE NOTICE '❌ Enhanced function still exists';
    END IF;
    
    RAISE NOTICE '';
    RAISE NOTICE '🎯 Original setup restored:';
    RAISE NOTICE '   • find_compatible_room_simple() - for CreateRoom.tsx';
    RAISE NOTICE '   • find_compatible_room() - for Room.tsx';
    RAISE NOTICE '';
    RAISE NOTICE '📱 Frontend should use:';
    RAISE NOTICE '   • CreateRoom.tsx → find_compatible_room_simple()';
    RAISE NOTICE '   • Room.tsx handleNextRoom() → find_compatible_room()';
    RAISE NOTICE '========================================';
END $$;