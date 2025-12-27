-- ============================================
-- CORRECTED DATABASE FUNCTIONS
-- Run this in Supabase SQL Editor
-- ============================================

-- Fix 1: Corrected leave_all_user_rooms function
-- The previous version had incorrect RETURNING syntax
DROP FUNCTION IF EXISTS leave_all_user_rooms(UUID);

CREATE OR REPLACE FUNCTION leave_all_user_rooms(p_user_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  affected_count INTEGER;
BEGIN
  UPDATE room_participants
  SET left_at = NOW()
  WHERE user_id = p_user_id
    AND left_at IS NULL;
  
  -- Correct way to get affected row count
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  
  RETURN COALESCE(affected_count, 0);
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION leave_all_user_rooms(UUID) TO authenticated, anon;

-- Fix 2: Ensure join_room_if_available handles all edge cases properly
DROP FUNCTION IF EXISTS join_room_if_available(UUID, UUID);

CREATE OR REPLACE FUNCTION join_room_if_available(
  p_room_id UUID,
  p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_room_size INTEGER;
  v_current_count INTEGER;
  v_room_active BOOLEAN;
  v_existing_record_id UUID;
  v_existing_left_at TIMESTAMPTZ;
BEGIN
  -- Lock the room row to prevent race conditions
  SELECT room_size, is_active 
  INTO v_room_size, v_room_active
  FROM rooms
  WHERE id = p_room_id
  FOR UPDATE;
  
  -- Check if room exists and is active
  IF NOT FOUND OR NOT v_room_active THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'room_not_found',
      'message', 'Room does not exist or is inactive'
    );
  END IF;
  
  -- Check if user already has a record in this room (any state)
  SELECT id, left_at 
  INTO v_existing_record_id, v_existing_left_at
  FROM room_participants
  WHERE room_id = p_room_id 
    AND user_id = p_user_id;
  
  -- If user exists but hasn't left (left_at IS NULL), they're already joined
  IF FOUND AND v_existing_left_at IS NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'message', 'User already in room',
      'already_joined', true
    );
  END IF;
  
  -- Count current active participants
  SELECT COUNT(*) INTO v_current_count
  FROM room_participants
  WHERE room_id = p_room_id 
    AND left_at IS NULL;
  
  -- Check if room has space
  IF v_current_count >= v_room_size THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'room_full',
      'message', 'Room is full',
      'current_count', v_current_count,
      'max_size', v_room_size
    );
  END IF;
  
  -- If user has an existing record but has left, update it
  IF FOUND AND v_existing_left_at IS NOT NULL THEN
    UPDATE room_participants
    SET left_at = NULL,
        joined_at = NOW()
    WHERE id = v_existing_record_id;
    
    RETURN jsonb_build_object(
      'success', true,
      'message', 'Rejoined room successfully',
      'rejoined', true,
      'current_count', v_current_count + 1,
      'max_size', v_room_size
    );
  END IF;
  
  -- User has no record at all, insert new
  INSERT INTO room_participants (room_id, user_id, joined_at, left_at)
  VALUES (p_room_id, p_user_id, NOW(), NULL)
  ON CONFLICT (room_id, user_id) 
  DO UPDATE SET 
    left_at = NULL,
    joined_at = NOW();
  
  RETURN jsonb_build_object(
    'success', true,
    'message', 'Successfully joined room',
    'current_count', v_current_count + 1,
    'max_size', v_room_size
  );
  
EXCEPTION
  WHEN OTHERS THEN
    IF SQLSTATE = '23505' THEN
      RETURN jsonb_build_object(
        'success', true,
        'message', 'User already in room (race condition handled)',
        'already_joined', true
      );
    END IF;
    
    RETURN jsonb_build_object(
      'success', false,
      'error', 'database_error',
      'message', SQLERRM
    );
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION join_room_if_available(UUID, UUID) TO authenticated, anon;
