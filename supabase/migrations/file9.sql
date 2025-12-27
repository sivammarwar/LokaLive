-- Add this to your Supabase SQL Editor
-- This function ensures atomic room joining (prevents race conditions)

CREATE OR REPLACE FUNCTION join_room_if_available(
  p_room_id UUID,
  p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_room_size INTEGER;
  v_current_count INTEGER;
  v_already_joined BOOLEAN;
BEGIN
  -- Lock the room row to prevent race conditions
  SELECT room_size INTO v_room_size
  FROM rooms
  WHERE id = p_room_id
  FOR UPDATE;
  
  -- Check if user is already in the room
  SELECT EXISTS(
    SELECT 1 FROM room_participants
    WHERE room_id = p_room_id 
    AND user_id = p_user_id 
    AND left_at IS NULL
  ) INTO v_already_joined;
  
  IF v_already_joined THEN
    RAISE NOTICE 'User already in room';
    RETURN true;
  END IF;
  
  -- Count current active participants
  SELECT COUNT(*) INTO v_current_count
  FROM room_participants
  WHERE room_id = p_room_id 
  AND left_at IS NULL;
  
  -- Check if room has space
  IF v_current_count >= v_room_size THEN
    RAISE NOTICE 'Room is full: % / %', v_current_count, v_room_size;
    RETURN false;
  END IF;
  
  -- Join the room
  INSERT INTO room_participants (room_id, user_id)
  VALUES (p_room_id, p_user_id);
  
  RAISE NOTICE 'Successfully joined room: % / %', v_current_count + 1, v_room_size;
  RETURN true;
  
EXCEPTION
  WHEN unique_violation THEN
    -- User already in room (race condition)
    RETURN true;
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Error joining room: %', SQLERRM;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION join_room_if_available(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION join_room_if_available(UUID, UUID) TO anon;