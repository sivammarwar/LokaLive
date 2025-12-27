-- ============================================
-- 🔧 FIX: Ghost User Prevention
-- Prevents matching with stale participants
-- ============================================

-- STEP 1: Cleanup function for stale participants
DROP FUNCTION IF EXISTS cleanup_stale_participants(INTEGER);

CREATE OR REPLACE FUNCTION cleanup_stale_participants(
    p_minutes_threshold INTEGER DEFAULT 5
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_cleaned_count INTEGER;
BEGIN
    -- Mark participants as left if they've been inactive for X minutes
    -- "Inactive" = joined but no recent activity (approximated by joined_at)
    UPDATE room_participants
    SET left_at = NOW()
    WHERE left_at IS NULL
      AND joined_at < NOW() - (p_minutes_threshold || ' minutes')::INTERVAL;
    
    GET DIAGNOSTICS v_cleaned_count = ROW_COUNT;
    
    RAISE NOTICE '✅ Cleaned up % stale participants', v_cleaned_count;
    RETURN v_cleaned_count;
END;
$$;

GRANT EXECUTE ON FUNCTION cleanup_stale_participants(INTEGER) TO authenticated, service_role;

-- ============================================
-- STEP 2: Enhanced find_compatible_room_simple
-- Validates that rooms have REAL active participants
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
    v_active_participants INTEGER;
BEGIN
    -- Validation
    IF p_user_gender NOT IN ('male', 'female') THEN
        RAISE EXCEPTION 'Gender must be "male" or "female" for public rooms';
    END IF;
    
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
    
    -- ✅ FIX #1: Cleanup stale participants FIRST
    PERFORM cleanup_stale_participants(5);
    
    -- Get last room to avoid re-matching
    SELECT room_id INTO v_last_room_id
    FROM room_participants
    WHERE user_id = p_user_id
    ORDER BY left_at DESC NULLS FIRST
    LIMIT 1;
    
    -- Update user's gender
    UPDATE public.users
    SET gender = p_user_gender, updated_at = NOW()
    WHERE id = p_user_id;
    
    -- ✅ FIX #2: Properly leave ALL active rooms for this user
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id AND left_at IS NULL;
    
    -- Small delay for cleanup to propagate
    PERFORM pg_sleep(0.15);
    
    -- ============================================
    -- 4-PERSON ROOM MATCHING
    -- ============================================
    IF p_room_size = 4 THEN
        RAISE NOTICE '🔍 Looking for 4-person room...';
        
        -- ✅ FIX #3: Only match rooms with REAL active participants
        SELECT r.id INTO v_found_room_id
        FROM public.rooms r
        WHERE r.room_type = 'public'
          AND r.is_active = true
          AND r.room_size = 4
          AND r.id != COALESCE(v_last_room_id, '00000000-0000-0000-0000-000000000000')
          AND r.creator_id != p_user_id
          -- ✅ CRITICAL: Verify participants are recent (within 2 minutes)
          AND EXISTS (
              SELECT 1 FROM room_participants rp
              WHERE rp.room_id = r.id 
                AND rp.left_at IS NULL
                AND rp.joined_at > NOW() - INTERVAL '2 minutes'
          )
          AND (
              SELECT COUNT(*) 
              FROM public.room_participants rp
              WHERE rp.room_id = r.id 
                AND rp.left_at IS NULL
                AND rp.joined_at > NOW() - INTERVAL '2 minutes'
          ) < 4
        ORDER BY 
          -- Prioritize rooms closest to full
          (SELECT COUNT(*) FROM room_participants WHERE room_id = r.id AND left_at IS NULL) DESC,
          r.created_at ASC
        LIMIT 1;
        
        IF v_found_room_id IS NOT NULL THEN
            -- ✅ FIX #4: Double-check room is still valid
            SELECT COUNT(*) INTO v_active_participants
            FROM room_participants
            WHERE room_id = v_found_room_id 
              AND left_at IS NULL
              AND joined_at > NOW() - INTERVAL '2 minutes';
            
            IF v_active_participants > 0 AND v_active_participants < 4 THEN
                RAISE NOTICE '✅ MATCHED 4-person room: % (% active)', v_found_room_id, v_active_participants;
                RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
                RETURN;
            ELSE
                RAISE NOTICE '⚠️ Room % became invalid, creating new', v_found_room_id;
            END IF;
        END IF;
        
        -- Create new 4-person room
        INSERT INTO public.rooms (room_type, room_size, gender_preference, interest_category, creator_id, creator_gender, is_active)
        VALUES ('public', 4, v_opposite_gender, 'random', p_user_id, p_user_gender, true)
        RETURNING id INTO v_created_room_id;
        
        RAISE NOTICE '✅ CREATED 4-person room: %', v_created_room_id;
        RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
        RETURN;
    END IF;
    
    -- ============================================
    -- 2-PERSON ROOM MATCHING
    -- ============================================
    
    -- STEP 1: Try opposite gender
    RAISE NOTICE '🔍 Looking for opposite gender (%)...', v_opposite_gender;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = 2
      AND r.id != COALESCE(v_last_room_id, '00000000-0000-0000-0000-000000000000')
      AND r.creator_gender = v_opposite_gender
      AND r.gender_preference = p_user_gender
      AND r.creator_id != p_user_id
      -- ✅ CRITICAL: Verify real active participants
      AND EXISTS (
          SELECT 1 FROM room_participants rp
          WHERE rp.room_id = r.id 
            AND rp.left_at IS NULL
            AND rp.joined_at > NOW() - INTERVAL '2 minutes'
      )
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id 
            AND rp.left_at IS NULL
            AND rp.joined_at > NOW() - INTERVAL '2 minutes'
      ) < 2
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    IF v_found_room_id IS NOT NULL THEN
        -- Double-check validity
        SELECT COUNT(*) INTO v_active_participants
        FROM room_participants
        WHERE room_id = v_found_room_id 
          AND left_at IS NULL
          AND joined_at > NOW() - INTERVAL '2 minutes';
        
        IF v_active_participants > 0 AND v_active_participants < 2 THEN
            RAISE NOTICE '✅ MATCHED opposite gender room: % (% active)', v_found_room_id, v_active_participants;
            RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
            RETURN;
        END IF;
    END IF;
    
    -- STEP 2: Try same gender
    RAISE NOTICE '🔍 Fallback: Looking for same gender (%)...', p_user_gender;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = 2
      AND r.id != COALESCE(v_last_room_id, '00000000-0000-0000-0000-000000000000')
      AND r.creator_gender = p_user_gender
      AND r.creator_id != p_user_id
      -- ✅ CRITICAL: Verify real active participants
      AND EXISTS (
          SELECT 1 FROM room_participants rp
          WHERE rp.room_id = r.id 
            AND rp.left_at IS NULL
            AND rp.joined_at > NOW() - INTERVAL '2 minutes'
      )
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id 
            AND rp.left_at IS NULL
            AND rp.joined_at > NOW() - INTERVAL '2 minutes'
      ) < 2
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    IF v_found_room_id IS NOT NULL THEN
        SELECT COUNT(*) INTO v_active_participants
        FROM room_participants
        WHERE room_id = v_found_room_id 
          AND left_at IS NULL
          AND joined_at > NOW() - INTERVAL '2 minutes';
        
        IF v_active_participants > 0 AND v_active_participants < 2 THEN
            RAISE NOTICE '✅ MATCHED same gender room: % (% active)', v_found_room_id, v_active_participants;
            RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
            RETURN;
        END IF;
    END IF;
    
    -- STEP 3: Create new room
    RAISE NOTICE '🏗️ Creating new room';
    
    INSERT INTO public.rooms (room_type, room_size, gender_preference, interest_category, creator_id, creator_gender, is_active)
    VALUES ('public', 2, v_opposite_gender, 'random', p_user_id, p_user_gender, true)
    RETURNING id INTO v_created_room_id;
    
    RAISE NOTICE '✅ CREATED 2-person room: %', v_created_room_id;
    RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
END;
$$;

GRANT EXECUTE ON FUNCTION find_compatible_room_simple(UUID, gender_preference, INTEGER) TO authenticated, anon;

-- ============================================
-- STEP 3: Auto-cleanup trigger
-- Runs every time someone leaves
-- ============================================

DROP TRIGGER IF EXISTS trigger_cleanup_on_leave ON room_participants;
DROP FUNCTION IF EXISTS trigger_cleanup_stale_on_leave() CASCADE;

CREATE OR REPLACE FUNCTION trigger_cleanup_stale_on_leave()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- When someone leaves, cleanup other stale participants in that room
    IF NEW.left_at IS NOT NULL AND OLD.left_at IS NULL THEN
        -- Cleanup stale participants in this room only
        UPDATE room_participants
        SET left_at = NOW()
        WHERE room_id = NEW.room_id
          AND left_at IS NULL
          AND user_id != NEW.user_id
          AND joined_at < NOW() - INTERVAL '3 minutes';
    END IF;
    
    RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_cleanup_on_leave
    AFTER UPDATE ON room_participants
    FOR EACH ROW
    EXECUTE FUNCTION trigger_cleanup_stale_on_leave();

-- ============================================
-- VERIFICATION
-- ============================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ GHOST USER FIX INSTALLED';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Fixes:';
    RAISE NOTICE '  ✓ Cleanup stale participants before matching';
    RAISE NOTICE '  ✓ Only match rooms with recent joins (<2 min)';
    RAISE NOTICE '  ✓ Double-check room validity before joining';
    RAISE NOTICE '  ✓ Auto-cleanup on user leave';
    RAISE NOTICE '  ✓ Prioritize fuller rooms';
    RAISE NOTICE '';
    RAISE NOTICE 'New Functions:';
    RAISE NOTICE '  • cleanup_stale_participants() - Manual cleanup';
    RAISE NOTICE '  • trigger_cleanup_on_leave() - Auto cleanup';
    RAISE NOTICE '========================================';
END $$;