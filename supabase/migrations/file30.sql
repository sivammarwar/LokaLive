-- ============================================
-- COMPLETE DATABASE CLEANUP & RESET
-- This fixes the corrupted state where rooms are inactive
-- but users think they're in them
-- ============================================

-- STEP 1: NUCLEAR RESET - Clean ALL matchmaking data
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '🧹 STARTING COMPLETE CLEANUP';
    RAISE NOTICE '========================================';
END $$;

-- Mark ALL participants as left (no exceptions)
UPDATE public.room_participants 
SET left_at = NOW() 
WHERE left_at IS NULL;

-- Deactivate ALL rooms (no exceptions)
UPDATE public.rooms 
SET is_active = false 
WHERE is_active = true;

-- Delete ALL signaling messages
DELETE FROM public.signaling;

-- Delete ALL chess games that aren't bet matches
DELETE FROM public.chess_games 
WHERE is_bet_match = false OR is_bet_match IS NULL;

DO $$
BEGIN
    RAISE NOTICE '✅ Cleaned all existing data';
    RAISE NOTICE '';
END $$;

-- STEP 2: Fix ALL users with 'other' gender
-- This is CRITICAL - 'other' breaks matching completely
UPDATE public.users 
SET gender = 'male',
    updated_at = NOW()
WHERE gender = 'other' OR gender IS NULL;

DO $$
DECLARE
    updated_count INTEGER;
BEGIN
    GET DIAGNOSTICS updated_count = ROW_COUNT;
    RAISE NOTICE '✅ Fixed % users with "other" gender → set to "male"', updated_count;
    RAISE NOTICE '   (Users can change this in the UI)';
    RAISE NOTICE '';
END $$;

-- STEP 3: Drop and recreate the trigger to auto-set creator_gender
DROP TRIGGER IF EXISTS trigger_set_creator_gender ON public.rooms;
DROP FUNCTION IF EXISTS set_creator_gender();

CREATE OR REPLACE FUNCTION set_creator_gender()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    user_gender gender_preference;
BEGIN
    -- Get the creator's current gender from users table
    SELECT gender INTO user_gender
    FROM public.users
    WHERE id = NEW.creator_id;
    
    -- CRITICAL: Set creator_gender to match user's gender
    -- Never allow 'other' for public rooms
    IF NEW.room_type = 'public' THEN
        IF user_gender IS NULL OR user_gender = 'other' THEN
            RAISE EXCEPTION 'Cannot create public room with gender "other". Please set your gender to male or female first.';
        END IF;
        NEW.creator_gender := user_gender;
    ELSE
        -- Private rooms can have any gender
        NEW.creator_gender := COALESCE(user_gender, 'other');
    END IF;
    
    RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_set_creator_gender
    BEFORE INSERT ON public.rooms
    FOR EACH ROW
    EXECUTE FUNCTION set_creator_gender();

DO $$
BEGIN
    RAISE NOTICE '✅ Recreated trigger: set_creator_gender';
    RAISE NOTICE '';
END $$;

-- STEP 4: Create improved join_room_if_available that NEVER fails silently
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
    RAISE NOTICE 'Room not found: %', p_room_id;
    RETURN json_build_object(
      'success', false,
      'error', 'room_not_found',
      'message', 'Room does not exist'
    );
  END IF;
  
  -- Check room is active
  IF NOT v_room_active THEN
    RAISE NOTICE 'Room % is inactive', p_room_id;
    RETURN json_build_object(
      'success', false,
      'error', 'room_inactive',
      'message', 'Room is no longer active'
    );
  END IF;
  
  -- Check for existing participation record
  SELECT id, left_at 
  INTO v_participant_id, v_left_at
  FROM room_participants
  WHERE room_id = p_room_id 
    AND user_id = p_user_id
  FOR UPDATE;
  
  -- User already in room and hasn't left
  IF FOUND AND v_left_at IS NULL THEN
    RAISE NOTICE 'User % already in room %', p_user_id, p_room_id;
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
    RAISE NOTICE 'Room % is full: % / %', p_room_id, v_current_count, v_room_size;
    RETURN json_build_object(
      'success', false,
      'error', 'room_full',
      'message', 'Room is full',
      'current_count', v_current_count,
      'max_size', v_room_size
    );
  END IF;
  
  -- UPSERT: Join or rejoin the room
  INSERT INTO room_participants (room_id, user_id, joined_at, left_at)
  VALUES (p_room_id, p_user_id, NOW(), NULL)
  ON CONFLICT (room_id, user_id) 
  DO UPDATE SET 
    left_at = NULL,
    joined_at = NOW()
  WHERE room_participants.room_id = p_room_id 
    AND room_participants.user_id = p_user_id;
  
  RAISE NOTICE 'User % successfully joined room %', p_user_id, p_room_id;
  
  RETURN json_build_object(
    'success', true,
    'message', 'Successfully joined room',
    'rejoined', (v_participant_id IS NOT NULL),
    'current_count', v_current_count + 1,
    'max_size', v_room_size
  );
  
EXCEPTION 
  WHEN unique_violation THEN
    RAISE NOTICE 'Unique violation handled for user % in room %', p_user_id, p_room_id;
    RETURN json_build_object(
      'success', true,
      'already_joined', true,
      'message', 'Already in room (race condition handled)'
    );
  WHEN OTHERS THEN
    RAISE WARNING 'Error in join_room_if_available: %', SQLERRM;
    RETURN json_build_object(
      'success', false,
      'error', 'database_error',
      'message', SQLERRM
    );
END;
$$;

GRANT EXECUTE ON FUNCTION join_room_if_available(UUID, UUID) TO authenticated, anon;

DO $$
BEGIN
    RAISE NOTICE '✅ Recreated function: join_room_if_available';
    RAISE NOTICE '';
END $$;

-- STEP 5: Create function to force-leave a room (for stuck users)
DROP FUNCTION IF EXISTS force_leave_room(UUID);

CREATE OR REPLACE FUNCTION force_leave_room(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Mark all participations as left
    UPDATE room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id
      AND left_at IS NULL;
    
    -- Clean up signaling
    DELETE FROM signaling
    WHERE sender_id = p_user_id OR target_id = p_user_id;
    
    RAISE NOTICE 'Force-left user % from all rooms', p_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION force_leave_room(UUID) TO authenticated, anon;

DO $$
BEGIN
    RAISE NOTICE '✅ Created function: force_leave_room';
    RAISE NOTICE '';
END $$;

-- STEP 6: Create automatic room cleanup function
DROP FUNCTION IF EXISTS cleanup_inactive_rooms();

CREATE OR REPLACE FUNCTION cleanup_inactive_rooms()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    cleaned_count INTEGER;
BEGIN
    -- Deactivate rooms with no active participants
    UPDATE rooms
    SET is_active = false
    WHERE is_active = true
      AND id NOT IN (
          SELECT DISTINCT room_id
          FROM room_participants
          WHERE left_at IS NULL
      );
    
    GET DIAGNOSTICS cleaned_count = ROW_COUNT;
    
    RETURN cleaned_count;
END;
$$;

GRANT EXECUTE ON FUNCTION cleanup_inactive_rooms() TO authenticated, service_role;

DO $$
BEGIN
    RAISE NOTICE '✅ Created function: cleanup_inactive_rooms';
    RAISE NOTICE '';
END $$;

-- STEP 7: Set search_path for all functions
ALTER FUNCTION set_creator_gender() SET search_path = public;
ALTER FUNCTION join_room_if_available(UUID, UUID) SET search_path = public;
ALTER FUNCTION force_leave_room(UUID) SET search_path = public;
ALTER FUNCTION cleanup_inactive_rooms() SET search_path = public;
ALTER FUNCTION leave_all_user_rooms(UUID) SET search_path = public;

-- STEP 8: Create a view to monitor system health
CREATE OR REPLACE VIEW public.system_health AS
SELECT 
    (SELECT COUNT(*) FROM users) as total_users,
    (SELECT COUNT(*) FROM users WHERE gender = 'other') as users_with_other_gender,
    (SELECT COUNT(*) FROM rooms WHERE is_active = true AND room_type = 'public') as active_public_rooms,
    (SELECT COUNT(*) FROM room_participants WHERE left_at IS NULL) as active_participants,
    (SELECT COUNT(DISTINCT room_id) FROM room_participants WHERE left_at IS NULL) as rooms_with_participants,
    (SELECT COUNT(*) FROM rooms WHERE is_active = true AND id NOT IN (
        SELECT DISTINCT room_id FROM room_participants WHERE left_at IS NULL
    )) as empty_active_rooms,
    (SELECT COUNT(*) FROM signaling) as pending_signals;

GRANT SELECT ON public.system_health TO authenticated, anon;

DO $$
BEGIN
    RAISE NOTICE '✅ Created view: system_health';
    RAISE NOTICE '';
END $$;

-- STEP 9: Final verification
DO $$
DECLARE
    health_record RECORD;
BEGIN
    SELECT * INTO health_record FROM system_health;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ DATABASE CLEANUP COMPLETE';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE 'System Health:';
    RAISE NOTICE '  • Total Users: %', health_record.total_users;
    RAISE NOTICE '  • Users with "other" gender: %', health_record.users_with_other_gender;
    RAISE NOTICE '  • Active Public Rooms: %', health_record.active_public_rooms;
    RAISE NOTICE '  • Active Participants: %', health_record.active_participants;
    RAISE NOTICE '  • Empty Active Rooms: %', health_record.empty_active_rooms;
    RAISE NOTICE '  • Pending Signals: %', health_record.pending_signals;
    RAISE NOTICE '';
    
    IF health_record.users_with_other_gender > 0 THEN
        RAISE NOTICE '⚠️  WARNING: % users still have gender="other"', health_record.users_with_other_gender;
        RAISE NOTICE '   They will not be able to use public matching!';
        RAISE NOTICE '';
    END IF;
    
    IF health_record.empty_active_rooms > 0 THEN
        RAISE NOTICE '⚠️  WARNING: % active rooms have no participants', health_record.empty_active_rooms;
        RAISE NOTICE '   Run: SELECT cleanup_inactive_rooms();';
        RAISE NOTICE '';
    END IF;
    
    RAISE NOTICE 'Next Steps:';
    RAISE NOTICE '  1. Both users should refresh their browsers (F5)';
    RAISE NOTICE '  2. Both users select gender (NOT "other")';
    RAISE NOTICE '  3. Click "Start Matching"';
    RAISE NOTICE '  4. They should match immediately!';
    RAISE NOTICE '';
    RAISE NOTICE 'If still stuck, run:';
    RAISE NOTICE '  SELECT force_leave_room(''USER_ID_HERE'');';
    RAISE NOTICE '========================================';
END $$;

-- STEP 10: Show current rooms (for debugging)
SELECT 
    r.id,
    r.room_type,
    r.is_active,
    r.creator_gender,
    r.gender_preference,
    r.interest_category,
    r.room_size,
    COUNT(rp.user_id) FILTER (WHERE rp.left_at IS NULL) as participant_count,
    r.created_at
FROM rooms r
LEFT JOIN room_participants rp ON rp.room_id = r.id
WHERE r.created_at > NOW() - INTERVAL '1 hour'
GROUP BY r.id
ORDER BY r.created_at DESC
LIMIT 10;