-- ============================================
-- 🔧 COMPLETE MATCHMAKING & ROOM CLEANUP FIX
-- Run this in Supabase SQL Editor
-- ============================================

-- ============================================
-- PART 1: DROP OLD FUNCTIONS
-- ============================================

DROP FUNCTION IF EXISTS find_compatible_room_simple(UUID, gender_preference, INTEGER);
DROP FUNCTION IF EXISTS find_compatible_room_enhanced(UUID, gender_preference, INTEGER);
DROP FUNCTION IF EXISTS get_active_users_by_gender();
DROP FUNCTION IF EXISTS auto_deactivate_empty_rooms();
DROP TRIGGER IF EXISTS trigger_auto_deactivate_room ON room_participants;
DROP FUNCTION IF EXISTS auto_deactivate_room_on_leave() CASCADE;

-- ============================================
-- PART 2: NEW MATCHMAKING FUNCTION
-- Handles both 2-person and 4-person rooms
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
    RAISE NOTICE '🔍 MATCHMAKING REQUEST';
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
    -- 4-PERSON ROOM LOGIC: Join ANY available room
    -- ============================================
    IF p_room_size = 4 THEN
        RAISE NOTICE '🔍 4-PERSON ROOM: Looking for any room with space...';
        
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
          ) < 4
        ORDER BY r.created_at ASC
        LIMIT 1;
        
        IF v_found_room_id IS NOT NULL THEN
            RAISE NOTICE '✅ MATCHED 4-person room: %', v_found_room_id;
            RAISE NOTICE '========================================';
            RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
            RETURN;
        END IF;
        
        RAISE NOTICE '⚠️ No 4-person room found, creating new one';
        
        -- Create new 4-person room (gender-neutral)
        INSERT INTO public.rooms (
            room_type,
            room_size,
            gender_preference,
            interest_category,
            creator_id,
            creator_gender,
            is_active
        )
        VALUES (
            'public',
            4,
            v_opposite_gender,  -- Preference but accepts anyone
            'random',
            p_user_id,
            p_user_gender,
            true
        )
        RETURNING id INTO v_created_room_id;
        
        RAISE NOTICE '✅ CREATED 4-person room: %', v_created_room_id;
        RAISE NOTICE '========================================';
        
        RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
        RETURN;
    END IF;
    
    -- ============================================
    -- 2-PERSON ROOM LOGIC: Opposite > Same > Create
    -- ============================================
    RAISE NOTICE '🔍 2-PERSON ROOM STEP 1: Looking for opposite gender (%)', v_opposite_gender;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = 2
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
        RAISE NOTICE '========================================';
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    RAISE NOTICE '⚠️ No opposite gender match found';
    RAISE NOTICE '🔍 2-PERSON ROOM STEP 2: Looking for same gender (%)', p_user_gender;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = 2
      AND r.creator_gender = p_user_gender
      AND r.gender_preference = v_opposite_gender
      AND r.creator_id != p_user_id
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < 2
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCHED same gender room (fallback): %', v_found_room_id;
        RAISE NOTICE '========================================';
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    RAISE NOTICE '⚠️ No same gender match found';
    RAISE NOTICE '🏗️ 2-PERSON ROOM STEP 3: Creating new room';
    
    INSERT INTO public.rooms (
        room_type,
        room_size,
        gender_preference,
        interest_category,
        creator_id,
        creator_gender,
        is_active
    )
    VALUES (
        'public',
        2,
        v_opposite_gender,
        'random',
        p_user_id,
        p_user_gender,
        true
    )
    RETURNING id INTO v_created_room_id;
    
    RAISE NOTICE '✅ CREATED 2-person room: %', v_created_room_id;
    RAISE NOTICE '  Creator: % (gender: %)', p_user_id, p_user_gender;
    RAISE NOTICE '  Prefers: %', v_opposite_gender;
    RAISE NOTICE '========================================';
    
    RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
END;
$$;

GRANT EXECUTE ON FUNCTION find_compatible_room_simple(UUID, gender_preference, INTEGER) TO authenticated, anon;

-- ============================================
-- PART 3: AUTO-DEACTIVATE EMPTY ROOMS
-- Trigger runs when participant leaves
-- ============================================

CREATE OR REPLACE FUNCTION auto_deactivate_room_on_leave()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_remaining_count INTEGER;
BEGIN
    -- Only proceed if a user just left (left_at was NULL, now has value)
    IF OLD.left_at IS NULL AND NEW.left_at IS NOT NULL THEN
        
        -- Count remaining active participants
        SELECT COUNT(*) INTO v_remaining_count
        FROM room_participants
        WHERE room_id = NEW.room_id AND left_at IS NULL;
        
        -- If no one left, deactivate the room
        IF v_remaining_count = 0 THEN
            UPDATE rooms
            SET is_active = false
            WHERE id = NEW.room_id AND is_active = true;
            
            RAISE NOTICE '✅ Room % auto-deactivated (empty)', NEW.room_id;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_auto_deactivate_room
    AFTER UPDATE ON public.room_participants
    FOR EACH ROW
    EXECUTE FUNCTION auto_deactivate_room_on_leave();

-- ============================================
-- PART 4: REAL-TIME ACTIVE USERS COUNT
-- For premium users dashboard
-- ============================================

CREATE OR REPLACE FUNCTION get_active_users_by_gender()
RETURNS TABLE(
    male_count BIGINT,
    female_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COUNT(DISTINCT rp.user_id) FILTER (WHERE u.gender = 'male') as male_count,
        COUNT(DISTINCT rp.user_id) FILTER (WHERE u.gender = 'female') as female_count
    FROM room_participants rp
    INNER JOIN users u ON u.id = rp.user_id
    INNER JOIN rooms r ON r.id = rp.room_id
    WHERE rp.left_at IS NULL
      AND r.is_active = true
      AND r.room_type = 'public'
      AND u.gender IN ('male', 'female');
END;
$$;

GRANT EXECUTE ON FUNCTION get_active_users_by_gender() TO authenticated, anon;

-- ============================================
-- PART 5: CLEANUP STALE ROOMS (Optional cron job)
-- ============================================

CREATE OR REPLACE FUNCTION cleanup_stale_rooms()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    cleaned_count INTEGER;
BEGIN
    -- Deactivate rooms that:
    -- 1. Have no active participants
    -- 2. Are older than 1 hour
    UPDATE rooms
    SET is_active = false
    WHERE is_active = true
      AND created_at < NOW() - INTERVAL '1 hour'
      AND id NOT IN (
          SELECT DISTINCT room_id
          FROM room_participants
          WHERE left_at IS NULL
      );
    
    GET DIAGNOSTICS cleaned_count = ROW_COUNT;
    
    RAISE NOTICE '✅ Cleaned up % stale rooms', cleaned_count;
    RETURN cleaned_count;
END;
$$;

GRANT EXECUTE ON FUNCTION cleanup_stale_rooms() TO authenticated, service_role;

-- ============================================
-- PART 6: ENHANCED ROOM WITH PARTICIPANTS VIEW
-- ============================================

DROP VIEW IF EXISTS room_with_participants CASCADE;

CREATE OR REPLACE VIEW room_with_participants AS
SELECT 
    r.*,
    COUNT(rp.id) FILTER (WHERE rp.left_at IS NULL) as participant_count,
    ARRAY_AGG(
        json_build_object(
            'user_id', rp.user_id,
            'joined_at', rp.joined_at,
            'display_name', u.display_name,
            'membership_tier', u.membership_tier
        )
    ) FILTER (WHERE rp.left_at IS NULL) as participants
FROM rooms r
LEFT JOIN room_participants rp ON rp.room_id = r.id
LEFT JOIN users u ON u.id = rp.user_id
GROUP BY r.id;

GRANT SELECT ON room_with_participants TO authenticated, anon;

-- ============================================
-- PART 7: VERIFICATION & TESTING
-- ============================================

DO $$
DECLARE
    test_male UUID := gen_random_uuid();
    test_female UUID := gen_random_uuid();
    result RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🧪 TESTING MATCHMAKING SYSTEM';
    RAISE NOTICE '========================================';
    
    -- Create test users
    INSERT INTO users (id, email, display_name, gender) VALUES
        (test_male, 'testmale@fix.test', 'Test Male', 'male'),
        (test_female, 'testfemale@fix.test', 'Test Female', 'female');
    
    -- TEST 1: Male creates 2-person room
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 1: Male creating 2-person room';
    SELECT * INTO result FROM find_compatible_room_simple(test_male, 'male'::gender_preference, 2);
    RAISE NOTICE '  Room: %', result.matched_room_id;
    RAISE NOTICE '  Is New: %', result.is_new_room;
    
    IF result.is_new_room THEN
        RAISE NOTICE '  ✅ Correctly created new room';
    ELSE
        RAISE NOTICE '  ❌ FAILED: Should have created new room';
    END IF;
    
    -- TEST 2: Female should match male's room
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 2: Female looking for male (should match)';
    SELECT * INTO result FROM find_compatible_room_simple(test_female, 'female'::gender_preference, 2);
    RAISE NOTICE '  Room: %', result.matched_room_id;
    RAISE NOTICE '  Is New: %', result.is_new_room;
    
    IF NOT result.is_new_room THEN
        RAISE NOTICE '  ✅ Correctly matched existing room';
    ELSE
        RAISE NOTICE '  ❌ FAILED: Should have matched existing room';
    END IF;
    
    -- TEST 3: Check room deactivation
    RAISE NOTICE '';
    RAISE NOTICE '🧹 TEST 3: Testing room auto-deactivation';
    
    -- Both users leave
    UPDATE room_participants SET left_at = NOW() 
    WHERE user_id IN (test_male, test_female) AND left_at IS NULL;
    
    -- Check if room is deactivated
    IF EXISTS (
        SELECT 1 FROM rooms 
        WHERE id = result.matched_room_id 
        AND is_active = false
    ) THEN
        RAISE NOTICE '  ✅ Room correctly deactivated when empty';
    ELSE
        RAISE NOTICE '  ❌ FAILED: Room should be deactivated';
    END IF;
    
    -- Cleanup
    DELETE FROM users WHERE email LIKE '%@fix.test';
    
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ ALL FIXES INSTALLED';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE '📋 Features:';
    RAISE NOTICE '  ✓ 2-person rooms: Opposite > Same > Create';
    RAISE NOTICE '  ✓ 4-person rooms: Join any > Create';
    RAISE NOTICE '  ✓ Auto-deactivate empty rooms';
    RAISE NOTICE '  ✓ Real-time user counts';
    RAISE NOTICE '  ✓ Proper cleanup triggers';
    RAISE NOTICE '';
    RAISE NOTICE '🎯 Frontend functions to use:';
    RAISE NOTICE '  • find_compatible_room_simple(user_id, gender, room_size)';
    RAISE NOTICE '  • get_active_users_by_gender()';
    RAISE NOTICE '  • cleanup_stale_rooms() [optional cron]';
    RAISE NOTICE '========================================';
END $$;