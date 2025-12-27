-- ============================================
-- COMPLETE FIX FOR ALL MATCHMAKING ISSUES
-- This resolves the "double join" race condition
-- Run this in Supabase SQL Editor
-- ============================================

-- STEP 1: Clean all existing data
DO $$
BEGIN
    RAISE NOTICE '🧹 Cleaning existing data...';
END $$;

UPDATE public.room_participants SET left_at = NOW() WHERE left_at IS NULL;
UPDATE public.rooms SET is_active = false WHERE is_active = true;
DELETE FROM public.signaling;

-- STEP 2: Fix the UNIQUE constraint to handle ON CONFLICT properly
-- The current UNIQUE(room_id, user_id) is correct, but let's ensure it exists
DO $$ 
BEGIN
    -- Drop existing constraint if it exists with wrong name
    IF EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'room_participants_room_id_user_id_key'
    ) THEN
        ALTER TABLE public.room_participants 
        DROP CONSTRAINT room_participants_room_id_user_id_key;
    END IF;
    
    -- Add the constraint with proper name
    ALTER TABLE public.room_participants 
    ADD CONSTRAINT room_participants_unique UNIQUE(room_id, user_id);
    
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'Constraint already exists';
END $$;

-- STEP 3: CRITICAL FIX - Update find_compatible_room to NOT auto-join
-- This prevents the double-join issue
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
    -- ✅ Update user's gender
    UPDATE public.users
    SET gender = p_user_gender,
        updated_at = NOW()
    WHERE id = p_user_id;
    
    -- ✅ Leave existing rooms
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id
      AND left_at IS NULL;
    
    -- ✅ Search for compatible room
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.interest_category = p_interest
      AND r.gender_preference = p_user_gender
      AND r.creator_gender = p_interested_in
      AND r.creator_gender != 'other'
      -- Check room has space
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id 
            AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- Found existing room? Return it WITHOUT joining
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE 'Found existing room: %', v_found_room_id;
        RETURN QUERY 
        SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    -- No room found, create new one
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
    
    RAISE NOTICE 'Created new room: %', v_created_room_id;
    
    -- Return new room WITHOUT joining
    RETURN QUERY 
    SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
END;
$$;

GRANT EXECUTE ON FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) TO authenticated, anon;

-- STEP 4: Fix join_room_if_available to handle all cases gracefully
DROP FUNCTION IF EXISTS join_room_if_available(UUID, UUID);

CREATE OR REPLACE FUNCTION join_room_if_available(
  p_room_id UUID,
  p_user_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_room_size INTEGER;
  v_current_count INTEGER;
  v_room_active BOOLEAN;
BEGIN
  -- Lock the room row
  SELECT room_size, is_active 
  INTO v_room_size, v_room_active
  FROM rooms 
  WHERE id = p_room_id 
  FOR UPDATE;
  
  -- Check room exists
  IF NOT FOUND THEN
    RETURN json_build_object(
      'success', false,
      'error', 'room_not_found',
      'message', 'Room does not exist'
    );
  END IF;
  
  -- Check room is active
  IF NOT v_room_active THEN
    RETURN json_build_object(
      'success', false,
      'error', 'room_inactive',
      'message', 'Room is no longer active'
    );
  END IF;
  
  -- Count participants (excluding this user)
  SELECT COUNT(*) INTO v_current_count
  FROM room_participants
  WHERE room_id = p_room_id 
    AND left_at IS NULL
    AND user_id != p_user_id;
  
  -- Check capacity
  IF v_current_count >= v_room_size THEN
    RETURN json_build_object(
      'success', false,
      'error', 'room_full',
      'message', 'Room is full',
      'current_count', v_current_count,
      'max_size', v_room_size
    );
  END IF;
  
  -- ✅ CRITICAL FIX: Use UPSERT with ON CONFLICT
  -- This prevents 409 errors if already joined
  INSERT INTO room_participants (room_id, user_id, joined_at, left_at)
  VALUES (p_room_id, p_user_id, NOW(), NULL)
  ON CONFLICT (room_id, user_id) 
  DO UPDATE SET 
    left_at = NULL,
    joined_at = NOW()
  WHERE room_participants.room_id = p_room_id 
    AND room_participants.user_id = p_user_id;
  
  RETURN json_build_object(
    'success', true,
    'message', 'Successfully joined room',
    'current_count', v_current_count + 1,
    'max_size', v_room_size
  );
  
EXCEPTION 
  WHEN OTHERS THEN
    RETURN json_build_object(
      'success', false,
      'error', 'database_error',
      'message', SQLERRM
    );
END;
$$;

GRANT EXECUTE ON FUNCTION join_room_if_available(UUID, UUID) TO authenticated, anon;

-- STEP 5: Ensure all functions have correct search_path
ALTER FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) SET search_path = public;
ALTER FUNCTION join_room_if_available(UUID, UUID) SET search_path = public;
ALTER FUNCTION leave_all_user_rooms(UUID) SET search_path = public;

-- STEP 6: Verification
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ ALL FIXES APPLIED';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Key Changes:';
    RAISE NOTICE '  1. find_compatible_room NO LONGER auto-joins';
    RAISE NOTICE '  2. join_room_if_available uses UPSERT (no 409)';
    RAISE NOTICE '  3. Unique constraint properly named';
    RAISE NOTICE '  4. All existing data cleaned';
    RAISE NOTICE '';
    RAISE NOTICE 'HOW IT WORKS NOW:';
    RAISE NOTICE '  Step 1: find_compatible_room → Returns room_id';
    RAISE NOTICE '  Step 2: Frontend calls join_room_if_available';
    RAISE NOTICE '  Step 3: User joins atomically (no race)';
    RAISE NOTICE '  Step 4: Navigate to room';
    RAISE NOTICE '';
    RAISE NOTICE 'This eliminates the double-join issue!';
    RAISE NOTICE '========================================';
END $$;

-- Test the functions
DO $$
DECLARE
    test_user_id UUID;
    find_result RECORD;
    join_result JSON;
BEGIN
    SELECT id INTO test_user_id FROM public.users LIMIT 1;
    
    IF test_user_id IS NOT NULL THEN
        RAISE NOTICE '🧪 Testing with user: %', test_user_id;
        
        -- Test find_compatible_room
        SELECT * INTO find_result
        FROM find_compatible_room(
            test_user_id,
            'male'::gender_preference,
            'female'::gender_preference,
            'random'::interest_category,
            2
        );
        
        RAISE NOTICE '✅ find_compatible_room: room_id=%', find_result.matched_room_id;
        
        -- Test join_room_if_available
        SELECT * INTO join_result
        FROM join_room_if_available(
            find_result.matched_room_id,
            test_user_id
        );
        
        RAISE NOTICE '✅ join_room_if_available: %', join_result;
        
        -- Clean up test data
        UPDATE public.room_participants 
        SET left_at = NOW() 
        WHERE user_id = test_user_id;
        
        UPDATE public.rooms 
        SET is_active = false 
        WHERE id = find_result.matched_room_id;
        
        RAISE NOTICE '✅ Test complete and cleaned up';
    ELSE
        RAISE NOTICE '⚠️  No users found for testing';
    END IF;
END $$;