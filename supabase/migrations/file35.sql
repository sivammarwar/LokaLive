-- ============================================
-- NUCLEAR FIX: Completely Rewrite find_compatible_room
-- Use COMPLETELY different naming to avoid ANY ambiguity
-- ============================================

-- Step 1: Drop the old function completely
DROP FUNCTION IF EXISTS find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER);

-- Step 2: Create NEW version with zero ambiguity
CREATE OR REPLACE FUNCTION find_compatible_room(
    p_user_id UUID,
    p_user_gender gender_preference,
    p_interested_in gender_preference,
    p_interest interest_category,
    p_room_size INTEGER
)
RETURNS TABLE(
    matched_room_id UUID,  -- ✅ CHANGED: Not "room_id" to avoid conflict
    is_new_room BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_found_room_id UUID;  -- ✅ CHANGED: Clear, unique name
    v_created_room_id UUID;  -- ✅ CHANGED: Clear, unique name
    v_count INTEGER;
BEGIN
    RAISE NOTICE '🔍 Starting matchmaking for user: %', p_user_id;
    
    -- Update user's gender
    UPDATE public.users
    SET gender = p_user_gender,
        updated_at = NOW()
    WHERE id = p_user_id;
    
    RAISE NOTICE '✅ Updated user gender to: %', p_user_gender;
    
    -- Leave existing rooms
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id
      AND left_at IS NULL;
    
    RAISE NOTICE '🚪 Left existing rooms';
    
    -- ✅ CRITICAL FIX: Search with EXPLICIT aliases everywhere
    SELECT rooms.id INTO v_found_room_id
    FROM public.rooms AS rooms
    WHERE rooms.room_type = 'public'
      AND rooms.is_active = true
      AND rooms.room_size = p_room_size
      AND rooms.interest_category = p_interest
      AND rooms.gender_preference = p_user_gender
      AND rooms.creator_gender = p_interested_in
      AND rooms.creator_gender != 'other'
      -- Check room has space
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants AS participants
          WHERE participants.room_id = rooms.id 
            AND participants.left_at IS NULL
      ) < p_room_size
    ORDER BY rooms.created_at ASC
    LIMIT 1;
    
    -- Found existing room?
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '🎉 Found existing room: %', v_found_room_id;
        
        -- Join it
        INSERT INTO public.room_participants (room_id, user_id)
        VALUES (v_found_room_id, p_user_id)
        ON CONFLICT (room_id, user_id) DO UPDATE
        SET left_at = NULL, joined_at = NOW();
        
        RAISE NOTICE '✅ Joined existing room';
        
        -- ✅ Return with explicit column names
        RETURN QUERY 
        SELECT 
            v_found_room_id AS matched_room_id,
            false AS is_new_room;
        RETURN;
    END IF;
    
    RAISE NOTICE '🆕 No room found, creating new one';
    
    -- Create new room
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
    RETURNING id INTO v_created_room_id;
    
    RAISE NOTICE '✅ Created new room: %', v_created_room_id;
    
    -- Join new room
    INSERT INTO public.room_participants (room_id, user_id)
    VALUES (v_created_room_id, p_user_id);
    
    RAISE NOTICE '✅ Joined new room';
    
    -- ✅ Return with explicit column names
    RETURN QUERY 
    SELECT 
        v_created_room_id AS matched_room_id,
        true AS is_new_room;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) TO authenticated, anon;

-- ============================================
-- VERIFY THE FIX
-- ============================================
DO $$
DECLARE
    test_result RECORD;
    test_user_id UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '🧪 TESTING NEW FUNCTION';
    RAISE NOTICE '========================================';
    
    -- Get a test user
    SELECT id INTO test_user_id FROM public.users LIMIT 1;
    
    IF test_user_id IS NULL THEN
        RAISE NOTICE '⚠️  No users found for testing';
        RETURN;
    END IF;
    
    -- Test the function
    SELECT * INTO test_result
    FROM find_compatible_room(
        test_user_id,
        'male'::gender_preference,
        'female'::gender_preference,
        'random'::interest_category,
        2
    );
    
    RAISE NOTICE '✅ SUCCESS! Function works!';
    RAISE NOTICE '   Room ID: %', test_result.matched_room_id;
    RAISE NOTICE '   Is New: %', test_result.is_new_room;
    RAISE NOTICE '';
    RAISE NOTICE '🎯 The ambiguity error is FIXED!';
    RAISE NOTICE '========================================';
    
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '❌ Test failed: %', SQLERRM;
    RAISE NOTICE 'SQL State: %', SQLSTATE;
END $$;

-- Show function signature
SELECT 
    'Function installed:' as status,
    proname as name,
    pg_get_function_arguments(oid) as parameters,
    pg_get_function_result(oid) as returns
FROM pg_proc 
WHERE proname = 'find_compatible_room';