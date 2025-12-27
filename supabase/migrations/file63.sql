-- ============================================
-- 🔧 PRODUCTION-READY NEXT ROOM FIX
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
    v_last_room_id UUID;
BEGIN
    -- ✅ FIX #1: Validate gender (block 'other')
    IF p_user_gender NOT IN ('male', 'female') THEN
        RAISE EXCEPTION 'Gender must be "male" or "female" for public rooms. Please update your profile.';
    END IF;
    
    -- Determine opposite gender
    IF p_user_gender = 'male' THEN
        v_opposite_gender := 'female';
    ELSE
        v_opposite_gender := 'male';
    END IF;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '🔍 NEXT ROOM REQUEST';
    RAISE NOTICE 'User: % (Gender: %)', p_user_id, p_user_gender;
    RAISE NOTICE 'Room Size: %', p_room_size;
    RAISE NOTICE '========================================';
    
    -- ✅ FIX #2: Get last room to avoid re-matching
    SELECT room_id INTO v_last_room_id
    FROM room_participants
    WHERE user_id = p_user_id
    ORDER BY left_at DESC NULLS FIRST
    LIMIT 1;
    
    -- Update user's gender
    UPDATE public.users
    SET gender = p_user_gender, updated_at = NOW()
    WHERE id = p_user_id;
    
    -- ✅ FIX #3: Properly leave existing rooms
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id AND left_at IS NULL;
    
    -- Wait a moment for cleanup
    PERFORM pg_sleep(0.1);
    
    -- ============================================
    -- MATCHING LOGIC
    -- ============================================
    
    IF p_room_size = 4 THEN
        -- 4-PERSON ROOM: Join any available
        RAISE NOTICE '🔍 Looking for 4-person room...';
        
        SELECT r.id INTO v_found_room_id
        FROM public.rooms r
        WHERE r.room_type = 'public'
          AND r.is_active = true
          AND r.room_size = 4
          AND r.id != COALESCE(v_last_room_id, '00000000-0000-0000-0000-000000000000') -- ✅ Avoid last room
          AND r.creator_id != p_user_id
          AND (
              SELECT COUNT(*) 
              FROM public.room_participants rp
              WHERE rp.room_id = r.id AND rp.left_at IS NULL
          ) < 4
        ORDER BY r.created_at ASC
        LIMIT 1;
        
        IF v_found_room_id IS NOT NULL THEN
            RAISE NOTICE '✅ MATCHED 4-person room: %', v_found_room_id;
            RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
            RETURN;
        END IF;
        
        -- Create new 4-person room
        INSERT INTO public.rooms (room_type, room_size, gender_preference, interest_category, creator_id, creator_gender, is_active)
        VALUES ('public', 4, v_opposite_gender, 'random', p_user_id, p_user_gender, true)
        RETURNING id INTO v_created_room_id;
        
        RAISE NOTICE '✅ CREATED 4-person room: %', v_created_room_id;
        RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
        RETURN;
    END IF;
    
    -- 2-PERSON ROOM: Opposite > Same > Create
    RAISE NOTICE '🔍 Looking for opposite gender (%)...', v_opposite_gender;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = 2
      AND r.id != COALESCE(v_last_room_id, '00000000-0000-0000-0000-000000000000') -- ✅ Avoid last room
      AND r.creator_gender = v_opposite_gender
      AND r.gender_preference = p_user_gender
      AND r.creator_id != p_user_id
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < 2
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCHED opposite gender room: %', v_found_room_id;
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    -- Fallback: Same gender
    RAISE NOTICE '🔍 Fallback: Looking for same gender (%)...', p_user_gender;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = 2
      AND r.id != COALESCE(v_last_room_id, '00000000-0000-0000-0000-000000000000')
      AND r.creator_gender = p_user_gender
      AND r.creator_id != p_user_id
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < 2
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCHED same gender room: %', v_found_room_id;
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    -- Create new room
    INSERT INTO public.rooms (room_type, room_size, gender_preference, interest_category, creator_id, creator_gender, is_active)
    VALUES ('public', 2, v_opposite_gender, 'random', p_user_id, p_user_gender, true)
    RETURNING id INTO v_created_room_id;
    
    RAISE NOTICE '✅ CREATED 2-person room: %', v_created_room_id;
    RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
END;
$$;

GRANT EXECUTE ON FUNCTION find_compatible_room_simple(UUID, gender_preference, INTEGER) TO authenticated, anon;

-- ============================================
-- ✅ VERIFICATION
-- ============================================
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ NEXT ROOM FIX INSTALLED';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Improvements:';
    RAISE NOTICE '  ✓ Blocks "other" gender';
    RAISE NOTICE '  ✓ Avoids re-matching last room';
    RAISE NOTICE '  ✓ Proper cleanup timing';
    RAISE NOTICE '  ✓ 4-person room support';
    RAISE NOTICE '========================================';
END $$;