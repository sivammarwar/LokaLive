-- Check existing policies
SELECT * FROM pg_policies WHERE tablename IN ('rooms', 'room_participants', 'signaling');

-- If needed, add permissive policies:
ALTER TABLE rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE room_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE signaling ENABLE ROW LEVEL SECURITY;

-- Allow authenticated users to read/write
CREATE POLICY "Allow authenticated users" ON rooms
  FOR ALL USING (auth.role() = 'authenticated');

CREATE POLICY "Allow authenticated users" ON room_participants
  FOR ALL USING (auth.role() = 'authenticated');

CREATE POLICY "Allow authenticated users" ON signaling
  FOR ALL USING (auth.role() = 'authenticated');




------- FILE - 22






-- Clean up any potential duplicate active participations
WITH duplicates AS (
  SELECT 
    id,
    ROW_NUMBER() OVER (PARTITION BY user_id, room_id ORDER BY joined_at DESC) as rn
  FROM room_participants
  WHERE left_at IS NULL
)
UPDATE room_participants rp
SET left_at = NOW()
FROM duplicates d
WHERE rp.id = d.id 
  AND d.rn > 1;

-- Ensure all users are only in one active room at a time
WITH user_multiple_rooms AS (
  SELECT 
    user_id,
    COUNT(DISTINCT room_id) as room_count
  FROM room_participants
  WHERE left_at IS NULL
  GROUP BY user_id
  HAVING COUNT(DISTINCT room_id) > 1
),
latest_room AS (
  SELECT DISTINCT ON (user_id) 
    user_id,
    room_id,
    joined_at
  FROM room_participants
  WHERE left_at IS NULL
    AND user_id IN (SELECT user_id FROM user_multiple_rooms)
  ORDER BY user_id, joined_at DESC
)
UPDATE room_participants rp
SET left_at = NOW()
FROM latest_room lr
WHERE rp.user_id = lr.user_id 
  AND rp.room_id != lr.room_id
  AND rp.left_at IS NULL;






--------- FILE - 23




-- Step 1: Drop the problematic function
DROP FUNCTION IF EXISTS join_room_if_available(UUID, UUID);

-- Step 2: Create a FIXED version that handles all edge cases
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
  v_already_joined BOOLEAN;
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
  
  -- Count current active participants (excluding the user we're checking)
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
  
  -- If user has an existing record but has left (left_at NOT NULL), update it
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
    -- If it's a unique constraint violation, user is already in room somehow
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

-- Step 3: Update your leave_all_user_rooms to be more thorough
CREATE OR REPLACE FUNCTION leave_all_user_rooms(p_user_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  affected_count INTEGER;
BEGIN
  -- Mark ALL user's room_participants as left, even if already left
  UPDATE room_participants
  SET left_at = NOW()
  WHERE user_id = p_user_id
    AND left_at IS NULL
  RETURNING COUNT(*) INTO affected_count;
  
  RETURN COALESCE(affected_count, 0);
END;
$$;

-- Step 4: Grant permissions
GRANT EXECUTE ON FUNCTION join_room_if_available(UUID, UUID) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION leave_all_user_rooms(UUID) TO authenticated, anon;