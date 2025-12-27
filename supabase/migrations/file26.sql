-- Drop and recreate with proper rejoin handling
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
  v_existing_record RECORD;
BEGIN
  -- Lock the room row
  SELECT room_size, is_active INTO v_room_size, v_room_active
  FROM rooms WHERE id = p_room_id FOR UPDATE;
  
  IF NOT FOUND OR NOT v_room_active THEN
    RETURN json_build_object('success', false, 'error', 'room_not_found', 'message', 'Room not found or inactive');
  END IF;
  
  -- Check for existing participation record (active OR inactive)
  SELECT * INTO v_existing_record 
  FROM room_participants 
  WHERE room_id = p_room_id AND user_id = p_user_id;
  
  IF FOUND THEN
    -- Record exists
    IF v_existing_record.left_at IS NULL THEN
      -- Already actively in room
      RETURN json_build_object('success', true, 'already_joined', true, 'message', 'Already in room');
    ELSE
      -- Previously left, check if can rejoin
      SELECT COUNT(*) INTO v_current_count 
      FROM room_participants 
      WHERE room_id = p_room_id AND left_at IS NULL;
      
      IF v_current_count >= v_room_size THEN
        RETURN json_build_object('success', false, 'error', 'room_full', 'message', 'Room is full');
      END IF;
      
      -- Rejoin by clearing left_at
      UPDATE room_participants 
      SET left_at = NULL, joined_at = NOW()
      WHERE room_id = p_room_id AND user_id = p_user_id;
      
      RETURN json_build_object('success', true, 'rejoined', true, 'message', 'Rejoined room');
    END IF;
  END IF;
  
  -- No existing record, check capacity and insert
  SELECT COUNT(*) INTO v_current_count 
  FROM room_participants 
  WHERE room_id = p_room_id AND left_at IS NULL;
  
  IF v_current_count >= v_room_size THEN
    RETURN json_build_object('success', false, 'error', 'room_full', 'message', 'Room is full');
  END IF;
  
  INSERT INTO room_participants (room_id, user_id) VALUES (p_room_id, p_user_id);
  
  RETURN json_build_object('success', true, 'message', 'Joined room');
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', 'database_error', 'message', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION join_room_if_available(UUID, UUID) TO authenticated, anon;
