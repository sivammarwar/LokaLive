-- ============================================
-- 🚨 CRITICAL MATCHMAKING FIX (Production Safe)
-- Run this in Supabase SQL Editor
-- ============================================

-- STEP 1: Remove problematic constraint
DO $$ 
BEGIN
    IF EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'users_id_fkey' 
        AND table_name = 'users'
    ) THEN
        ALTER TABLE users DROP CONSTRAINT users_id_fkey;
        RAISE NOTICE '✅ Removed users_id_fkey constraint';
    ELSE
        RAISE NOTICE '⚠️ Constraint does not exist (safe to continue)';
    END IF;
END $$;

-- STEP 2: Drop and recreate find_compatible_room with CORRECT logic
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
    -- Log input parameters
    RAISE NOTICE '🔍 MATCHMAKING - User: %, Gender: %, Looking for: %, Interest: %, Size: %', 
        p_user_id, p_user_gender, p_interested_in, p_interest, p_room_size;
    
    -- Update user's gender
    UPDATE public.users
    SET gender = p_user_gender, updated_at = NOW()
    WHERE id = p_user_id;
    
    -- Leave existing rooms
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id AND left_at IS NULL;
    
    -- ✅ CORRECT MATCHING LOGIC:
    -- Find rooms created by users with MY gender that want people I'm interested in
    RAISE NOTICE '🔍 SEARCHING FOR: creator_gender=% AND gender_preference=%', 
        p_user_gender, p_interested_in;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.interest_category = p_interest
      -- ✅ CRITICAL: Correct matching logic
      AND r.creator_gender = p_user_gender        -- Room creator has MY gender
      AND r.gender_preference = p_interested_in   -- Room wants people I'm interested in
      AND r.creator_id != p_user_id               -- Don't match my own room
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- Found existing room
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ FOUND ROOM: %', v_found_room_id;
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    -- No room found, create new one
    RAISE NOTICE '🏗️ CREATING NEW ROOM';
    
    INSERT INTO public.rooms (
        room_type, 
        room_size, 
        gender_preference,  -- ✅ This room wants people I'm interested in
        interest_category, 
        creator_id,
        creator_gender,     -- ✅ Store MY gender
        is_active
    )
    VALUES (
        'public', 
        p_room_size, 
        p_interested_in,    -- ✅ Room preference = who I want to meet
        p_interest, 
        p_user_id,
        p_user_gender,      -- ✅ Store MY gender
        true
    )
    RETURNING id INTO v_created_room_id;
    
    RAISE NOTICE '✅ CREATED ROOM: % (wants: %, created by: %)', 
        v_created_room_id, p_interested_in, p_user_gender;
    
    RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
END;
$$;

-- STEP 3: Grant permissions
GRANT EXECUTE ON FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) TO authenticated, anon;

-- STEP 4: Verify the function exists
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_proc 
        WHERE proname = 'find_compatible_room'
    ) THEN
        RAISE NOTICE '✅ Function find_compatible_room created successfully';
    ELSE
        RAISE NOTICE '❌ Function creation failed';
    END IF;
END $$;

-- ============================================
-- VERIFICATION: Check your schema
-- ============================================

-- Show rooms table structure
DO $$
DECLARE
    col_record RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '📊 ROOMS TABLE COLUMNS';
    RAISE NOTICE '========================================';
    
    FOR col_record IN 
        SELECT column_name, data_type 
        FROM information_schema.columns 
        WHERE table_name = 'rooms' 
        ORDER BY ordinal_position
    LOOP
        RAISE NOTICE '  • %: %', col_record.column_name, col_record.data_type;
    END LOOP;
    
    RAISE NOTICE '========================================';
END $$;

-- Show active rooms count
DO $$
DECLARE
    room_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO room_count FROM rooms WHERE is_active = true;
    RAISE NOTICE '';
    RAISE NOTICE '📊 Active Rooms: %', room_count;
END $$;

-- ============================================
-- SUCCESS MESSAGE
-- ============================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ MATCHMAKING FIX COMPLETE';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Changes applied:';
    RAISE NOTICE '  1. Removed problematic constraint';
    RAISE NOTICE '  2. Fixed matching logic';
    RAISE NOTICE '  3. Granted permissions';
    RAISE NOTICE '';
    RAISE NOTICE 'Next steps:';
    RAISE NOTICE '  1. Test with your React app';
    RAISE NOTICE '  2. Check browser console for logs';
    RAISE NOTICE '  3. Monitor Supabase logs for NOTICE messages';
    RAISE NOTICE '========================================';
END $$;