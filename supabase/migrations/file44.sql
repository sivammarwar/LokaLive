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
    v_room_count INTEGER;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '🔍 MATCHMAKING START';
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
    
    -- Count available rooms
    SELECT COUNT(*) INTO v_room_count
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.interest_category = p_interest;
    
    RAISE NOTICE '📊 Total public rooms matching size/interest: %', v_room_count;
    
    -- Show all candidate rooms
    FOR v_found_room_id IN
        SELECT r.id
        FROM public.rooms r
        WHERE r.room_type = 'public'
          AND r.is_active = true
          AND r.room_size = p_room_size
          AND r.interest_category = p_interest
        LIMIT 5
    LOOP
        DECLARE
            room_info RECORD;
            participant_count INTEGER;
        BEGIN
            SELECT * INTO room_info FROM rooms WHERE id = v_found_room_id;
            SELECT COUNT(*) INTO participant_count 
            FROM room_participants 
            WHERE room_id = v_found_room_id AND left_at IS NULL;
            
            RAISE NOTICE '  Room %:', v_found_room_id;
            RAISE NOTICE '    Creator Gender: %', room_info.creator_gender;
            RAISE NOTICE '    Wants: %', room_info.gender_preference;
            RAISE NOTICE '    Creator ID: %', room_info.creator_id;
            RAISE NOTICE '    Participants: %/%', participant_count, room_info.room_size;
            RAISE NOTICE '    Match Criteria:';
            RAISE NOTICE '      creator_gender = my_gender? % = % → %', 
                room_info.creator_gender, p_user_gender, 
                room_info.creator_gender = p_user_gender;
            RAISE NOTICE '      gender_preference = interested_in? % = % → %', 
                room_info.gender_preference, p_interested_in,
                room_info.gender_preference = p_interested_in;
            RAISE NOTICE '      Not my room? %', room_info.creator_id != p_user_id;
            RAISE NOTICE '      Has space? %', participant_count < room_info.room_size;
        END;
    END LOOP;
    
    -- Find compatible room with explicit logging
    RAISE NOTICE '🔍 SEARCHING FOR MATCH...';
    RAISE NOTICE '  Looking for: creator_gender=% AND gender_preference=%', 
        p_user_gender, p_interested_in;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.interest_category = p_interest
      AND r.creator_gender = p_user_gender
      AND r.gender_preference = p_interested_in
      AND r.creator_id != p_user_id
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCH FOUND: %', v_found_room_id;
        RAISE NOTICE '========================================';
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    -- Create new room
    RAISE NOTICE '❌ NO MATCH FOUND - Creating new room';
    
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
        p_room_size, 
        p_interested_in,
        p_interest, 
        p_user_id,
        p_user_gender,
        true
    )
    RETURNING id INTO v_created_room_id;
    
    RAISE NOTICE '✅ NEW ROOM CREATED: %', v_created_room_id;
    RAISE NOTICE '  Creator Gender: %', p_user_gender;
    RAISE NOTICE '  Wants: %', p_interested_in;
    RAISE NOTICE '========================================';
    
    RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
END;
$$;

GRANT EXECUTE ON FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) TO authenticated, anon;
