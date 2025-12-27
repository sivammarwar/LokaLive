-- Step 1: Drop the old function
DROP FUNCTION IF EXISTS join_room_if_available(UUID, UUID);

-- Step 2: Create the new function with different delimiter
CREATE OR REPLACE FUNCTION join_room_if_available(
  p_room_id UUID,
  p_user_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
AS $function$
DECLARE
  v_room_size INTEGER;
  v_current_count INTEGER;
  v_result JSON;
BEGIN
  -- Lock the room row
  SELECT room_size INTO v_room_size
  FROM rooms
  WHERE id = p_room_id
  FOR UPDATE;

  -- Count current active participants
  SELECT COUNT(*) INTO v_current_count
  FROM room_participants
  WHERE room_id = p_room_id
    AND left_at IS NULL;

  -- Check if room is full
  IF v_current_count >= v_room_size THEN
    RETURN json_build_object(
      'success', false,
      'error', 'room_full',
      'message', 'Room is full'
    );
  END IF;

  -- Check if user already in room
  IF EXISTS (
    SELECT 1 FROM room_participants
    WHERE room_id = p_room_id
      AND user_id = p_user_id
      AND left_at IS NULL
  ) THEN
    RETURN json_build_object(
      'success', false,
      'error', 'already_joined',
      'message', 'User already in room'
    );
  END IF;

  -- Insert participant
  INSERT INTO room_participants (room_id, user_id)
  VALUES (p_room_id, p_user_id);

  RETURN json_build_object(
    'success', true,
    'message', 'Successfully joined room'
  );
EXCEPTION
  WHEN OTHERS THEN
    RETURN json_build_object(
      'success', false,
      'error', 'database_error',
      'message', SQLERRM
    );
END;
$function$;

-- Step 3: Create/recreate the leave function
CREATE OR REPLACE FUNCTION leave_all_user_rooms(p_user_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
AS $function$
DECLARE
  affected_count INTEGER;
BEGIN
  UPDATE room_participants
  SET left_at = NOW()
  WHERE user_id = p_user_id
    AND left_at IS NULL;
  
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  RETURN affected_count;
END;
$function$;