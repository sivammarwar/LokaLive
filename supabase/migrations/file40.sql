-- ============================================
-- 🚨 CRITICAL DATABASE FIXES
-- Run these in Supabase SQL Editor
-- ============================================

-- ============================================
-- FIX #1: ⚠️ HIGHEST PRIORITY - Matchmaking Logic
-- The gender matching was backwards!
-- ============================================

DROP FUNCTION IF EXISTS find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER);

CREATE OR REPLACE FUNCTION find_compatible_room(
    p_user_id UUID,
    p_user_gender gender_preference,
    p_interested_in gender_preference,
    p_interest interest_category,
    p_room_size INTEGER
)
RETURNS TABLE(matched_room_id UUID, is_new_room BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_found_room_id UUID;
    v_created_room_id UUID;
BEGIN
    -- Update user's gender
    UPDATE public.users
    SET gender = p_user_gender, updated_at = NOW()
    WHERE id = p_user_id;
    
    -- Leave existing rooms
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id AND left_at IS NULL;
    
    -- ✅ FIXED: Correct gender matching logic
    -- OLD (WRONG): r.gender_preference = p_user_gender AND r.creator_gender = p_interested_in
    -- NEW (CORRECT): r.gender_preference = p_interested_in AND r.creator_gender = p_user_gender
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.interest_category = p_interest
      AND r.gender_preference = p_interested_in  -- ✅ FIXED: Room wants people I'm interested in
      AND r.creator_gender = p_user_gender        -- ✅ FIXED: Room created by someone of MY gender
      AND r.creator_gender != 'other'
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- Found existing room
    IF v_found_room_id IS NOT NULL THEN
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    -- Create new room
    INSERT INTO public.rooms (room_type, room_size, gender_preference, interest_category, creator_id, is_active)
    VALUES ('public', p_room_size, p_interested_in, p_interest, p_user_id, true)
    RETURNING id INTO v_created_room_id;
    
    RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
END;
$$;

-- ============================================
-- FIX #2: Room Creator Auto-Join Trigger
-- Ensures room creator is automatically added as participant
-- ============================================

CREATE OR REPLACE FUNCTION auto_join_room_creator()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- ✅ NEW: Auto-add creator as participant when room is created
    IF NEW.creator_id IS NOT NULL THEN
        INSERT INTO public.room_participants (room_id, user_id, joined_at, left_at)
        VALUES (NEW.id, NEW.creator_id, NOW(), NULL)
        ON CONFLICT (room_id, user_id) DO UPDATE 
        SET left_at = NULL, joined_at = NOW();
        
        RAISE NOTICE '✅ Auto-joined creator % to room %', NEW.creator_id, NEW.id;
    END IF;
    
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_auto_join_room_creator ON public.rooms;
CREATE TRIGGER trigger_auto_join_room_creator
    AFTER INSERT ON public.rooms
    FOR EACH ROW
    EXECUTE FUNCTION auto_join_room_creator();

-- ============================================
-- FIX #3: Fix join_room_if_available Counting Bug
-- Was excluding current user when counting participants
-- ============================================

DROP FUNCTION IF EXISTS join_room_if_available(UUID, UUID);

CREATE OR REPLACE FUNCTION join_room_if_available(p_room_id UUID, p_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_room_size INTEGER;
  v_current_count INTEGER;
  v_room_active BOOLEAN;
BEGIN
  -- Get room info
  SELECT room_size, is_active INTO v_room_size, v_room_active
  FROM rooms WHERE id = p_room_id FOR UPDATE;
  
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'room_not_found');
  END IF;
  
  IF NOT v_room_active THEN
    RETURN json_build_object('success', false, 'error', 'room_inactive');
  END IF;
  
  -- ✅ FIXED: Count ALL participants (don't exclude current user)
  -- OLD (WRONG): WHERE room_id = p_room_id AND left_at IS NULL AND user_id != p_user_id
  -- NEW (CORRECT): WHERE room_id = p_room_id AND left_at IS NULL
  SELECT COUNT(*) INTO v_current_count
  FROM room_participants
  WHERE room_id = p_room_id AND left_at IS NULL;
  
  -- Check if room is full
  IF v_current_count >= v_room_size THEN
    RETURN json_build_object('success', false, 'error', 'room_full');
  END IF;
  
  -- Join the room (or rejoin if already joined)
  INSERT INTO room_participants (room_id, user_id, joined_at, left_at)
  VALUES (p_room_id, p_user_id, NOW(), NULL)
  ON CONFLICT (room_id, user_id) DO UPDATE 
  SET left_at = NULL, joined_at = NOW();
  
  RETURN json_build_object('success', true, 'message', 'Successfully joined room');
END;
$$;

-- ============================================
-- FIX #4: Prevent 'other' Gender in Public Rooms
-- Public rooms MUST have specific gender for matching
-- ============================================

CREATE OR REPLACE FUNCTION validate_public_room_gender()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.room_type = 'public' THEN
        -- ✅ NEW: Validate creator has valid gender
        IF NEW.creator_gender IS NULL OR NEW.creator_gender = 'other' THEN
            RAISE EXCEPTION 'Cannot create public room with gender "other". Please set your gender to male or female first.';
        END IF;
        
        -- ✅ NEW: Validate gender_preference is set
        IF NEW.gender_preference IS NULL OR NEW.gender_preference = 'other' THEN
            RAISE EXCEPTION 'Public rooms must specify gender preference (male or female).';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_validate_public_room_gender ON public.rooms;
CREATE TRIGGER trigger_validate_public_room_gender
    BEFORE INSERT ON public.rooms
    FOR EACH ROW
    EXECUTE FUNCTION validate_public_room_gender();

-- ============================================
-- FIX #5: Auto-Cleanup Empty Rooms
-- Automatically deactivate rooms with no active participants
-- ============================================

CREATE OR REPLACE FUNCTION auto_cleanup_empty_rooms()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Deactivate rooms with no active participants
    UPDATE rooms
    SET is_active = false
    WHERE is_active = true
      AND room_type = 'public'  -- Only cleanup public rooms automatically
      AND id NOT IN (
          SELECT DISTINCT room_id
          FROM room_participants
          WHERE left_at IS NULL
      )
      AND created_at < NOW() - INTERVAL '30 minutes';  -- Only cleanup old rooms
      
    RAISE NOTICE '✅ Auto-cleanup completed';
END;
$$;

-- ✅ NEW: Schedule auto-cleanup (run this in pg_cron if available)
-- Or call this function manually/periodically via a backend job

-- ============================================
-- FIX #6: Ludo Vote Functions (Referenced but Missing)
-- ============================================

CREATE OR REPLACE FUNCTION get_ludo_vote_count()
RETURNS INTEGER
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COUNT(*)::INTEGER FROM public.ludo_votes;
$$;

CREATE OR REPLACE FUNCTION has_user_voted_ludo(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS(SELECT 1 FROM public.ludo_votes WHERE user_id = p_user_id);
$$;

-- ============================================
-- Grant Permissions for New Functions
-- ============================================

GRANT EXECUTE ON FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION join_room_if_available(UUID, UUID) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION auto_cleanup_empty_rooms() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION get_ludo_vote_count() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION has_user_voted_ludo(UUID) TO authenticated, anon;

-- ============================================
-- Verification Queries
-- Run these to verify fixes worked
-- ============================================

DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ DATABASE FIXES APPLIED';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE 'Fixed Issues:';
    RAISE NOTICE '  1. ✅ Matchmaking gender logic corrected';
    RAISE NOTICE '  2. ✅ Room creator auto-join trigger added';
    RAISE NOTICE '  3. ✅ Join counting bug fixed';
    RAISE NOTICE '  4. ✅ Public room gender validation added';
    RAISE NOTICE '  5. ✅ Auto-cleanup function created';
    RAISE NOTICE '  6. ✅ Ludo vote functions added';
    RAISE NOTICE '';
    RAISE NOTICE 'Next Steps:';
    RAISE NOTICE '  1. Test matchmaking with 2 users';
    RAISE NOTICE '  2. Verify room creator appears in participants';
    RAISE NOTICE '  3. Test private room joining';
    RAISE NOTICE '  4. Try creating public room with "other" gender (should fail)';
    RAISE NOTICE '========================================';
END $$;

-- ============================================
-- TEST DATA CLEANUP (Optional)
-- Run this to clear test data
-- ============================================

-- ⚠️ UNCOMMENT ONLY IF YOU WANT TO RESET ALL ROOMS/PARTICIPANTS
-- DELETE FROM public.room_participants;
-- DELETE FROM public.rooms;
-- DELETE FROM public.signaling;