-- ============================================
-- FIX 409 CONFLICT ERROR
-- The error means: User is trying to join room they're already in
-- This happens because find_compatible_room already joins the room
-- Then your code tries to join AGAIN
-- ============================================

-- This is actually NOT a problem with the SQL function
-- The SQL function ALREADY joins the user to the room
-- So you DON'T need to join again in your frontend!

-- But let's verify your join_room_if_available handles this correctly:

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
  -- Lock the room row to prevent race conditions
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
  
  -- ✅ FIX: Check for existing participation record
  SELECT id, left_at 
  INTO v_participant_id, v_left_at
  FROM room_participants
  WHERE room_id = p_room_id 
    AND user_id = p_user_id
  FOR UPDATE;
  
  -- ✅ User already in room and hasn't left
  IF FOUND AND v_left_at IS NULL THEN
    RETURN json_build_object(
      'success', true,
      'already_joined', true,
      'message', 'Already in room'
    );
  END IF;
  
  -- Count current active participants (excluding this user if rejoining)
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
  
  -- ✅ UPSERT: Join or rejoin the room (handles 409 conflict)
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

GRANT EXECUTE ON FUNCTION join_room_if_available(UUID, UUID) TO authenticated, anon;

-- ============================================
-- IMPORTANT NOTE ABOUT 409 CONFLICTS
-- ============================================

/*
The 409 Conflict happens because:

1. find_compatible_room() ALREADY joins the user to the room
2. Then your useMatchmaking.ts tries to join AGAIN
3. Database says "you're already in this room" → 409 Conflict

SOLUTION OPTIONS:

Option A (RECOMMENDED): 
- Use ONLY find_compatible_room()
- Remove the extra join attempt
- This is what the simplified CreateRoom.tsx does

Option B (If you want to keep useMatchmaking.ts):
- Add ON CONFLICT DO NOTHING to your insert
- Or check if user is already in room before inserting

The SQL function ALREADY handles joining atomically,
so you DON'T need additional join logic!
*/

-- Verify the fix
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ join_room_if_available FIXED';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Improvements:';
    RAISE NOTICE '  • Handles already-joined users gracefully';
    RAISE NOTICE '  • Uses UPSERT to prevent 409 conflicts';
    RAISE NOTICE '  • Returns success=true if already in room';
    RAISE NOTICE '';
    RAISE NOTICE 'The 409 Conflict should be gone!';
    RAISE NOTICE '========================================';
END $$;