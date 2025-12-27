-- ============================================
-- 🔧 CRITICAL FIX: Matchmaking Function
-- This fixes the room matching logic
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
    v_participant_count INTEGER;
    v_room_record RECORD;
BEGIN
    -- ✅ Validation
    IF p_user_gender = 'other' THEN
        RAISE EXCEPTION 'Cannot use "other" gender for public matching';
    END IF;
    
    IF p_interested_in = 'other' THEN
        RAISE EXCEPTION 'Cannot match with "other" gender';
    END IF;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '🔍 MATCHMAKING REQUEST';
    RAISE NOTICE 'User: %', p_user_id;
    RAISE NOTICE 'My Gender: %', p_user_gender;
    RAISE NOTICE 'Looking For: %', p_interested_in;
    RAISE NOTICE 'Interest: %', p_interest;
    RAISE NOTICE 'Size: %', p_room_size;
    RAISE NOTICE '========================================';
    
    -- Update user's gender
    UPDATE public.users
    SET gender = p_user_gender, updated_at = NOW()
    WHERE id = p_user_id;
    
    -- Leave existing rooms
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id AND left_at IS NULL;
    
    -- ✅ CRITICAL FIX: Correct matching logic
    -- Find rooms where:
    --   1. Room creator has MY gender
    --   2. Room wants people I'm interested in
    --   3. Has space available
    
    RAISE NOTICE '🔍 SEARCHING FOR COMPATIBLE ROOMS...';
    
    FOR v_room_record IN
        SELECT 
            r.id,
            r.creator_gender,
            r.gender_preference,
            r.creator_id,
            COUNT(rp.id) as participant_count
        FROM public.rooms r
        LEFT JOIN public.room_participants rp ON rp.room_id = r.id AND rp.left_at IS NULL
        WHERE r.room_type = 'public'
          AND r.is_active = true
          AND r.room_size = p_room_size
          AND r.interest_category = p_interest
          AND r.creator_gender = p_user_gender      -- ✅ Creator has MY gender
          AND r.gender_preference = p_interested_in -- ✅ Room wants who I want
          AND r.creator_id != p_user_id             -- ✅ Not my own room
        GROUP BY r.id, r.creator_gender, r.gender_preference, r.creator_id, r.created_at
        ORDER BY r.created_at ASC
        LIMIT 5
    LOOP
        RAISE NOTICE '  📊 Checking room %:', v_room_record.id;
        RAISE NOTICE '    • Creator gender: %', v_room_record.creator_gender;
        RAISE NOTICE '    • Wants: %', v_room_record.gender_preference;
        RAISE NOTICE '    • Participants: %/%', v_room_record.participant_count, p_room_size;
        RAISE NOTICE '    • Match?: creator_gender=% AND preference=%', 
            (v_room_record.creator_gender = p_user_gender),
            (v_room_record.gender_preference = p_interested_in);
        
        -- Check if room has space
        IF v_room_record.participant_count < p_room_size THEN
            RAISE NOTICE '✅ MATCH FOUND! Room: %', v_room_record.id;
            RAISE NOTICE '========================================';
            RETURN QUERY SELECT v_room_record.id AS matched_room_id, false AS is_new_room;
            RETURN;
        ELSE
            RAISE NOTICE '  ⚠️ Room full, skipping';
        END IF;
    END LOOP;
    
    -- No compatible room found, create new one
    RAISE NOTICE '❌ NO MATCH FOUND - Creating new room';
    RAISE NOTICE '  Will create room with:';
    RAISE NOTICE '    • creator_gender: %', p_user_gender;
    RAISE NOTICE '    • gender_preference: %', p_interested_in;
    
    INSERT INTO public.rooms (
        room_type,
        room_size,
        gender_preference,    -- Who I want to match with
        interest_category,
        creator_id,
        creator_gender,       -- My gender
        is_active
    )
    VALUES (
        'public',
        p_room_size,
        p_interested_in,      -- ✅ This room wants people I'm interested in
        p_interest,
        p_user_id,
        p_user_gender,        -- ✅ My gender
        true
    )
    RETURNING id INTO v_created_room_id;
    
    RAISE NOTICE '✅ CREATED NEW ROOM: %', v_created_room_id;
    RAISE NOTICE '========================================';
    
    RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
END;
$$;

GRANT EXECUTE ON FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) TO authenticated, anon;

-- ✅ Verify it was created
SELECT 
    proname as function_name,
    pg_get_function_identity_arguments(oid) as arguments
FROM pg_proc 
WHERE proname = 'find_compatible_room';