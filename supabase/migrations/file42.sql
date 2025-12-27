-- Just run this part to update the function:
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
    -- Update user's gender
    UPDATE public.users
    SET gender = p_user_gender, updated_at = NOW()
    WHERE id = p_user_id;
    
    -- Leave existing rooms
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id AND left_at IS NULL;
    
    -- Find compatible room
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
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    -- Create new room
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
    
    RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
END;
$$;

GRANT EXECUTE ON FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) TO authenticated, anon;