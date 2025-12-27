-- ============================================
-- FIXED find_compatible_room Function
-- Fixes the parameter name mismatch
-- ============================================

DROP FUNCTION IF EXISTS find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER);

CREATE OR REPLACE FUNCTION find_compatible_room(
    p_user_id UUID,
    p_user_gender gender_preference,
    p_interested_in gender_preference,
    p_interest interest_category,  -- ✅ This is the correct parameter name
    p_room_size INTEGER
)
RETURNS TABLE(room_id UUID, is_new_room BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_existing_room UUID;
    v_new_room UUID;
    v_participant_count INTEGER;
BEGIN
    -- Update user's gender in database
    UPDATE public.users
    SET gender = p_user_gender,
        updated_at = NOW()
    WHERE id = p_user_id;
    
    -- Leave any existing rooms first
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id
      AND left_at IS NULL;
    
    -- Search for compatible existing room
    SELECT r.id, COUNT(rp.user_id)
    INTO v_existing_room, v_participant_count
    FROM public.rooms r
    LEFT JOIN public.room_participants rp 
        ON rp.room_id = r.id AND rp.left_at IS NULL
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.interest_category = p_interest  -- ✅ FIXED: Use p_interest not p_interest_category
      -- Gender matching logic
      AND r.gender_preference = p_user_gender
      AND r.creator_gender = p_interested_in
      AND r.creator_gender != 'other'
      -- Room must have space
      AND r.id NOT IN (
          SELECT room_id 
          FROM public.room_participants 
          WHERE left_at IS NULL 
          GROUP BY room_id 
          HAVING COUNT(*) >= p_room_size
      )
    GROUP BY r.id
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- If found compatible room, join it
    IF v_existing_room IS NOT NULL THEN
        INSERT INTO public.room_participants (room_id, user_id)
        VALUES (v_existing_room, p_user_id)
        ON CONFLICT (room_id, user_id) DO UPDATE
        SET left_at = NULL, joined_at = NOW();
        
        RETURN QUERY SELECT v_existing_room, false;
        RETURN;
    END IF;
    
    -- No compatible room found, create new one
    INSERT INTO public.rooms (
        room_type,
        room_size,
        gender_preference,
        interest_category,
        creator_id,
        is_active
    ) VALUES (
        'public',
        p_room_size,
        p_interested_in,
        p_interest,  -- ✅ FIXED: Use p_interest not p_interest_category
        p_user_id,
        true
    )
    RETURNING id INTO v_new_room;
    
    -- Join the newly created room
    INSERT INTO public.room_participants (room_id, user_id)
    VALUES (v_new_room, p_user_id);
    
    RETURN QUERY SELECT v_new_room, true;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) TO authenticated, anon;

-- Verify the fix
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ FIXED find_compatible_room';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Fixed parameter name mismatch:';
    RAISE NOTICE '  • Parameter: p_interest';
    RAISE NOTICE '  • Was incorrectly using: p_interest_category';
    RAISE NOTICE '  • Now correctly using: p_interest';
    RAISE NOTICE '';
    RAISE NOTICE 'Test the fix by:';
    RAISE NOTICE '  1. Refresh your browser';
    RAISE NOTICE '  2. Select gender preferences';
    RAISE NOTICE '  3. Click "Start Matching"';
    RAISE NOTICE '========================================';
END $$;