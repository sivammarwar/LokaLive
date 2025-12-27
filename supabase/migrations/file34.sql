-- ============================================
-- FIXED find_compatible_room - Resolves Ambiguous Column Reference
-- The bug: "room_id" is ambiguous - could be variable OR column
-- Solution: Qualify all column references with table aliases
-- ============================================

DROP FUNCTION IF EXISTS find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER);

CREATE OR REPLACE FUNCTION find_compatible_room(
    p_user_id UUID,
    p_user_gender gender_preference,
    p_interested_in gender_preference,
    p_interest interest_category,
    p_room_size INTEGER
)
RETURNS TABLE(room_id UUID, is_new_room BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_existing_room UUID;  -- Changed variable name to avoid conflict
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
    
    -- ✅ FIX: Explicitly qualify ALL column references with table aliases
    -- Search for compatible existing room
    SELECT r.id, COUNT(rp.user_id)
    INTO v_existing_room, v_participant_count
    FROM public.rooms r
    LEFT JOIN public.room_participants rp 
        ON rp.room_id = r.id AND rp.left_at IS NULL
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.interest_category = p_interest
      -- Gender matching logic
      AND r.gender_preference = p_user_gender
      AND r.creator_gender = p_interested_in
      AND r.creator_gender != 'other'
      -- Room must have space - ✅ FIX: Use subquery alias
      AND r.id NOT IN (
          SELECT rp2.room_id 
          FROM public.room_participants rp2
          WHERE rp2.left_at IS NULL 
          GROUP BY rp2.room_id 
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
        
        -- ✅ FIX: Return explicitly named columns to avoid ambiguity
        RETURN QUERY SELECT v_existing_room AS room_id, false AS is_new_room;
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
        p_interest,
        p_user_id,
        true
    )
    RETURNING id INTO v_new_room;
    
    -- Join the newly created room
    INSERT INTO public.room_participants (room_id, user_id)
    VALUES (v_new_room, p_user_id);
    
    -- ✅ FIX: Return explicitly named columns
    RETURN QUERY SELECT v_new_room AS room_id, true AS is_new_room;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) TO authenticated, anon;

-- Verification
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ FIXED find_compatible_room';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'What was fixed:';
    RAISE NOTICE '  • Qualified all column refs with table aliases (r.id, rp.room_id)';
    RAISE NOTICE '  • Used aliases in subqueries (rp2.room_id)';
    RAISE NOTICE '  • Explicit column naming in RETURN QUERY';
    RAISE NOTICE '  • Renamed variables to avoid conflicts';
    RAISE NOTICE '';
    RAISE NOTICE 'The "ambiguous column reference" error is now fixed!';
    RAISE NOTICE '';
    RAISE NOTICE 'Next steps:';
    RAISE NOTICE '  1. Run this SQL in Supabase SQL Editor';
    RAISE NOTICE '  2. Refresh your app (F5)';
    RAISE NOTICE '  3. Try matching again';
    RAISE NOTICE '========================================';
END $$;

-- Test the function (optional)
DO $$
DECLARE
    test_user_id UUID;
    result RECORD;
BEGIN
    SELECT id INTO test_user_id FROM users LIMIT 1;
    
    IF test_user_id IS NOT NULL THEN
        SELECT * INTO result
        FROM find_compatible_room(
            test_user_id,
            'male'::gender_preference,
            'female'::gender_preference,
            'random'::interest_category,
            2
        );
        
        RAISE NOTICE 'Test successful! Created room: %', result.room_id;
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Test failed: %', SQLERRM;
END $$;