CREATE OR REPLACE FUNCTION leave_all_user_rooms(p_user_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
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
$$;