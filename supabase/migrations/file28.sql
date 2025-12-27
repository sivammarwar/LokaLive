-- ============================================
-- CORRECTED join_room_if_available - Fixed FOR UPDATE Issue
-- ============================================

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
  v_participant_id UUID;
  v_left_at TIMESTAMPTZ;
BEGIN
  -- ✅ CRITICAL: Lock the room row FIRST to prevent race conditions
  SELECT room_size, is_active 
  INTO v_room_size, v_room_active
  FROM rooms 
  WHERE id = p_room_id 
  FOR UPDATE;  -- Lock room to prevent concurrent modifications
  
  -- Check room exists and is active
  IF NOT FOUND OR NOT v_room_active THEN
    RETURN json_build_object(
      'success', false,
      'error', 'room_not_found',
      'message', 'Room not found or inactive'
    );
  END IF;
  
  -- ✅ Check for existing participation record (with lock)
  SELECT id, left_at 
  INTO v_participant_id, v_left_at
  FROM room_participants
  WHERE room_id = p_room_id 
    AND user_id = p_user_id
  FOR UPDATE;  -- Lock this specific record
  
  -- User already in room and hasn't left
  IF FOUND AND v_left_at IS NULL THEN
    RETURN json_build_object(
      'success', true,
      'already_joined', true,
      'message', 'Already in room'
    );
  END IF;
  
  -- ✅ FIXED: Count without FOR UPDATE (we already have room lock)
  -- Count current active participants (excluding this user if rejoining)
  SELECT COUNT(*) INTO v_current_count
  FROM room_participants
  WHERE room_id = p_room_id 
    AND left_at IS NULL
    AND user_id != p_user_id;  -- Don't count user if they're rejoining
  
  -- Check capacity BEFORE insert/update
  IF v_current_count >= v_room_size THEN
    RETURN json_build_object(
      'success', false,
      'error', 'room_full',
      'message', 'Room is full',
      'current_count', v_current_count,
      'max_size', v_room_size
    );
  END IF;
  
  -- ✅ UPSERT: Handle both new join and rejoin in single atomic operation
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
    'rejoined', (v_participant_id IS NOT NULL),
    'current_count', v_current_count + 1,
    'max_size', v_room_size
  );
  
EXCEPTION 
  WHEN unique_violation THEN
    -- Should never happen with UPSERT, but handle just in case
    RETURN json_build_object(
      'success', true,
      'already_joined', true,
      'message', 'Already in room (race condition handled)'
    );
  WHEN OTHERS THEN
    RETURN json_build_object(
      'success', false,
      'error', 'database_error',
      'message', SQLERRM
    );
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION join_room_if_available(UUID, UUID) TO authenticated, anon;

-- ============================================
-- VERIFICATION QUERY
-- ============================================
DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ CORRECTED join_room_if_available installed';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Fixed:';
  RAISE NOTICE '  • Removed FOR UPDATE from COUNT query';
  RAISE NOTICE '  • Room lock is sufficient for consistency';
  RAISE NOTICE '  • Excludes current user from count (for rejoin)';
  RAISE NOTICE '';
  RAISE NOTICE 'Key features:';
  RAISE NOTICE '  • Locks room row FIRST';
  RAISE NOTICE '  • Atomic count check without aggregate lock';
  RAISE NOTICE '  • UPSERT prevents duplicate inserts';
  RAISE NOTICE '  • No race conditions possible';
  RAISE NOTICE '========================================';
END $$;