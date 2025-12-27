-- ============================================
-- 🔧 CRITICAL FIX: Matchmaking Logic
-- Run this in Supabase SQL Editor
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
-- 🧹 CLEANUP OLD ROOMS
-- ============================================

UPDATE room_participants SET left_at = NOW() WHERE left_at IS NULL;
UPDATE rooms SET is_active = false WHERE is_active = true;

-- ============================================
-- 🧪 TEST THE FIX
-- ============================================

DO $$
DECLARE
    user1 UUID := gen_random_uuid();
    user2 UUID := gen_random_uuid();
    result1 RECORD;
    result2 RECORD;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '🧪 TESTING MATCHMAKING';
    RAISE NOTICE '========================================';
    
    -- Create test users
    INSERT INTO users (id, email, display_name, gender) VALUES
        (user1, 'testmale@test.com', 'Test Male', 'male'),
        (user2, 'testfemale@test.com', 'Test Female', 'female');
    
    -- Test 1: Male looking for Female
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 1: Male looking for Female';
    SELECT * INTO result1 FROM find_compatible_room(
        user1, 'male'::gender_preference, 'female'::gender_preference, 
        'random'::interest_category, 2
    );
    RAISE NOTICE '  Room: %', result1.matched_room_id;
    RAISE NOTICE '  Is New: %', result1.is_new_room;
    
    -- Test 2: Female looking for Male (should match Test 1's room)
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 2: Female looking for Male';
    SELECT * INTO result2 FROM find_compatible_room(
        user2, 'female'::gender_preference, 'male'::gender_preference, 
        'random'::interest_category, 2
    );
    RAISE NOTICE '  Room: %', result2.matched_room_id;
    RAISE NOTICE '  Is New: %', result2.is_new_room;
    
    -- Verify match
    RAISE NOTICE '';
    IF result1.matched_room_id = result2.matched_room_id THEN
        RAISE NOTICE '✅ SUCCESS: Both users matched to SAME room!';
    ELSE
        RAISE NOTICE '❌ FAILED: Users got different rooms';
        RAISE NOTICE '  Room 1: %', result1.matched_room_id;
        RAISE NOTICE '  Room 2: %', result2.matched_room_id;
    END IF;
    
    -- Cleanup
    DELETE FROM users WHERE email LIKE 'test%@test.com';
    
    RAISE NOTICE '========================================';
END $$;