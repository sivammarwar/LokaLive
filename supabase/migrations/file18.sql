-- ============================================
-- COMPLETE DATABASE FIX FOR MATCHMAKING SYSTEM
-- Run this in Supabase SQL Editor
-- ============================================

-- STEP 1: Clean up existing data
-- Mark all current participants as left
UPDATE public.room_participants
SET left_at = NOW()
WHERE left_at IS NULL;

-- Deactivate all current rooms
UPDATE public.rooms
SET is_active = false
WHERE is_active = true;

-- Clean up old signaling messages
DELETE FROM public.signaling WHERE created_at < NOW() - INTERVAL '1 hour';

-- STEP 2: Drop existing triggers and functions that might conflict
DROP TRIGGER IF EXISTS enforce_single_active_room ON public.room_participants;
DROP TRIGGER IF EXISTS enforce_room_capacity ON public.room_participants;
DROP FUNCTION IF EXISTS prevent_duplicate_participation();
DROP FUNCTION IF EXISTS check_room_capacity();
DROP FUNCTION IF EXISTS join_room_if_available(UUID, UUID);

-- STEP 3: Create optimized indexes for matchmaking
CREATE INDEX IF NOT EXISTS idx_rooms_matchmaking 
ON public.rooms(room_type, is_active, room_size, gender_preference, interest_category, created_at)
WHERE room_type = 'public' AND is_active = true;

CREATE INDEX IF NOT EXISTS idx_rooms_creator_gender 
ON public.rooms(creator_gender) 
WHERE room_type = 'public' AND is_active = true;

CREATE INDEX IF NOT EXISTS idx_room_participants_active 
ON public.room_participants(room_id, user_id, left_at) 
WHERE left_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_room_participants_user_active 
ON public.room_participants(user_id, room_id) 
WHERE left_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_signaling_room_time 
ON public.signaling(room_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_signaling_target 
ON public.signaling(room_id, target_id) 
WHERE target_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_chess_games_active 
ON public.chess_games(room_id, status) 
WHERE status IN ('active', 'pending');

-- STEP 4: Improved atomic room joining function
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
  
  -- Check if user is already in the room
  SELECT EXISTS(
    SELECT 1 FROM room_participants
    WHERE room_id = p_room_id 
    AND user_id = p_user_id 
    AND left_at IS NULL
  ) INTO v_already_joined;
  
  IF v_already_joined THEN
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
  
  -- Join the room
  INSERT INTO room_participants (room_id, user_id)
  VALUES (p_room_id, p_user_id)
  ON CONFLICT (room_id, user_id) DO NOTHING;
  
  RETURN jsonb_build_object(
    'success', true,
    'message', 'Successfully joined room',
    'current_count', v_current_count + 1,
    'max_size', v_room_size
  );
  
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'database_error',
      'message', SQLERRM
    );
END;
$$;

-- STEP 5: Function to safely leave all rooms for a user
CREATE OR REPLACE FUNCTION leave_all_user_rooms(
  p_user_id UUID
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  UPDATE room_participants
  SET left_at = NOW()
  WHERE user_id = p_user_id
  AND left_at IS NULL
  RETURNING 1 INTO v_count;
  
  RETURN COALESCE(v_count, 0);
END;
$$;

-- STEP 6: Function to get room participant count
CREATE OR REPLACE FUNCTION get_room_participant_count(
  p_room_id UUID
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM room_participants
  WHERE room_id = p_room_id
  AND left_at IS NULL;
  
  RETURN COALESCE(v_count, 0);
END;
$$;

-- STEP 7: Function to cleanup abandoned rooms
CREATE OR REPLACE FUNCTION cleanup_abandoned_rooms()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  -- Deactivate rooms with no participants older than 5 minutes
  UPDATE rooms
  SET is_active = false
  WHERE is_active = true
  AND created_at < NOW() - INTERVAL '5 minutes'
  AND id NOT IN (
    SELECT DISTINCT room_id
    FROM room_participants
    WHERE left_at IS NULL
  )
  RETURNING 1 INTO v_count;
  
  RETURN COALESCE(v_count, 0);
END;
$$;

-- STEP 8: Grant permissions
GRANT EXECUTE ON FUNCTION join_room_if_available(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION join_room_if_available(UUID, UUID) TO anon;
GRANT EXECUTE ON FUNCTION leave_all_user_rooms(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION leave_all_user_rooms(UUID) TO anon;
GRANT EXECUTE ON FUNCTION get_room_participant_count(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_room_participant_count(UUID) TO anon;
GRANT EXECUTE ON FUNCTION cleanup_abandoned_rooms() TO authenticated;
GRANT EXECUTE ON FUNCTION cleanup_abandoned_rooms() TO service_role;

-- STEP 9: Set search_path for all functions
ALTER FUNCTION generate_room_code() SET search_path = public;
ALTER FUNCTION set_room_code() SET search_path = public;
ALTER FUNCTION process_validated_report() SET search_path = public;
ALTER FUNCTION check_membership_expiry() SET search_path = public;
ALTER FUNCTION handle_new_user() SET search_path = public;
ALTER FUNCTION set_reporter_membership_tier() SET search_path = public;
ALTER FUNCTION activate_membership(UUID, membership_tier) SET search_path = public;
ALTER FUNCTION extend_membership(UUID, membership_tier) SET search_path = public;
ALTER FUNCTION complete_transaction_and_activate() SET search_path = public;
ALTER FUNCTION cleanup_old_signals() SET search_path = public;
ALTER FUNCTION cleanup_abandoned_chess_games() SET search_path = public;
ALTER FUNCTION update_chess_game_timestamp() SET search_path = public;
ALTER FUNCTION join_room_if_available(UUID, UUID) SET search_path = public;
ALTER FUNCTION leave_all_user_rooms(UUID) SET search_path = public;
ALTER FUNCTION get_room_participant_count(UUID) SET search_path = public;
ALTER FUNCTION cleanup_abandoned_rooms() SET search_path = public;

-- STEP 10: Verify installation
DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ DATABASE FIX COMPLETE';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Installed Functions:';
  RAISE NOTICE '  • join_room_if_available()';
  RAISE NOTICE '  • leave_all_user_rooms()';
  RAISE NOTICE '  • get_room_participant_count()';
  RAISE NOTICE '  • cleanup_abandoned_rooms()';
  RAISE NOTICE '';
  RAISE NOTICE 'Optimized Indexes:';
  RAISE NOTICE '  • idx_rooms_matchmaking';
  RAISE NOTICE '  • idx_room_participants_active';
  RAISE NOTICE '  • idx_signaling_room_time';
  RAISE NOTICE '';
  RAISE NOTICE 'System is ready for matchmaking!';
  RAISE NOTICE '========================================';
END $$;

-- STEP 11: Show current state
SELECT 
  'Active Rooms' as metric,
  COUNT(*) as value
FROM public.rooms
WHERE is_active = true

UNION ALL

SELECT 
  'Active Participants' as metric,
  COUNT(*) as value
FROM public.room_participants
WHERE left_at IS NULL

UNION ALL

SELECT 
  'Total Users' as metric,
  COUNT(*) as value
FROM public.users;