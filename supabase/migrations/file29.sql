-- ============================================
-- ROOT CAUSE FIX: Proper Gender-Based Matchmaking
-- This fixes the fundamental issue where creator_gender
-- and matching logic are not properly enforced
-- ============================================

-- STEP 1: Clean up existing broken data
-- Mark all participants as left and deactivate all rooms
UPDATE public.room_participants SET left_at = NOW() WHERE left_at IS NULL;
UPDATE public.rooms SET is_active = false WHERE is_active = true;

-- STEP 2: Add trigger to auto-set creator_gender when room is created
-- This ensures creator_gender is ALWAYS set correctly from users table
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
    
    -- Set creator_gender to match user's gender
    -- This ensures the room has correct creator gender for matching
    NEW.creator_gender := COALESCE(user_gender, 'other');
    
    RETURN NEW;
END;
$$;

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS trigger_set_creator_gender ON public.rooms;

-- Create trigger to run BEFORE INSERT on rooms
CREATE TRIGGER trigger_set_creator_gender
    BEFORE INSERT ON public.rooms
    FOR EACH ROW
    EXECUTE FUNCTION set_creator_gender();

-- STEP 3: Create improved matchmaking function with proper gender validation
DROP FUNCTION IF EXISTS find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER);

CREATE OR REPLACE FUNCTION find_compatible_room(
    p_user_id UUID,
    p_user_gender gender_preference,
    p_interested_in gender_preference,
    p_interest interest_category,
    p_room_size INTEGER
)
RETURNS TABLE(room_id UUID, is_new_room BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_existing_room UUID;
    v_new_room UUID;
    v_participant_count INTEGER;
BEGIN
    -- CRITICAL: First update user's gender in database
    -- This ensures all subsequent operations use correct gender
    UPDATE public.users
    SET gender = p_user_gender,
        updated_at = NOW()
    WHERE id = p_user_id;
    
    -- Leave any existing rooms first
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id
      AND left_at IS NULL;
    
    -- Search for compatible existing room with STRICT matching
    SELECT r.id, COUNT(rp.user_id)
    INTO v_existing_room, v_participant_count
    FROM public.rooms r
    LEFT JOIN public.room_participants rp 
        ON rp.room_id = r.id AND rp.left_at IS NULL
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.interest_category = p_interest_category
      -- CRITICAL MATCHING LOGIC:
      -- Room creator wants someone of p_user_gender
      AND r.gender_preference = p_user_gender
      -- Room creator's gender matches what user wants
      AND r.creator_gender = p_interested_in
      -- Ensure creator_gender is not 'other' (prevents broken matches)
      AND r.creator_gender != 'other'
      -- Room must have space
      AND r.id NOT IN (
          SELECT room_id 
          FROM public.room_participants 
          WHERE left_at IS NULL 
          GROUP BY room_id 
          HAVING COUNT(*) >= p_room_size
      )
    GROUP BY r.id
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- If found compatible room, join it
    IF v_existing_room IS NOT NULL THEN
        INSERT INTO public.room_participants (room_id, user_id)
        VALUES (v_existing_room, p_user_id)
        ON CONFLICT (room_id, user_id) DO UPDATE
        SET left_at = NULL, joined_at = NOW();
        
        RETURN QUERY SELECT v_existing_room, false;
        RETURN;
    END IF;
    
    -- No compatible room found, create new one
    -- The trigger will automatically set creator_gender from users table
    INSERT INTO public.rooms (
        room_type,
        room_size,
        gender_preference,
        interest_category,
        creator_id,
        is_active
    ) VALUES (
        'public',
        p_room_size,
        p_interested_in,  -- This room wants someone of p_interested_in gender
        p_interest,
        p_user_id,
        true
    )
    RETURNING id INTO v_new_room;
    
    -- Join the newly created room
    INSERT INTO public.room_participants (room_id, user_id)
    VALUES (v_new_room, p_user_id);
    
    RETURN QUERY SELECT v_new_room, true;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) TO authenticated, anon;

-- STEP 4: Add validation to prevent 'other' gender from creating public rooms
-- This prevents the root cause of matching failures
CREATE OR REPLACE FUNCTION validate_public_room_gender()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- For public rooms, creator must have valid gender (not 'other')
    IF NEW.room_type = 'public' AND NEW.creator_gender = 'other' THEN
        RAISE EXCEPTION 'Public rooms require gender to be "male" or "female", not "other". Please set your gender preference first.';
    END IF;
    
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_validate_public_room_gender ON public.rooms;

CREATE TRIGGER trigger_validate_public_room_gender
    BEFORE INSERT ON public.rooms
    FOR EACH ROW
    WHEN (NEW.room_type = 'public')
    EXECUTE FUNCTION validate_public_room_gender();

-- STEP 5: Create helper function to check if user can create public room
CREATE OR REPLACE FUNCTION can_user_create_public_room(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    user_gender gender_preference;
BEGIN
    SELECT gender INTO user_gender
    FROM public.users
    WHERE id = p_user_id;
    
    -- User can create public room if gender is 'male' or 'female'
    RETURN (user_gender IS NOT NULL AND user_gender != 'other');
END;
$$;

GRANT EXECUTE ON FUNCTION can_user_create_public_room(UUID) TO authenticated, anon;

-- STEP 6: Fix search_path for all functions
ALTER FUNCTION set_creator_gender() SET search_path = public;
ALTER FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) SET search_path = public;
ALTER FUNCTION validate_public_room_gender() SET search_path = public;
ALTER FUNCTION can_user_create_public_room(UUID) SET search_path = public;

-- STEP 7: Add helpful comments
COMMENT ON FUNCTION set_creator_gender() IS 'Automatically sets creator_gender from users table when room is created';
COMMENT ON FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) IS 'Finds compatible room based on STRICT gender matching or creates new room';
COMMENT ON FUNCTION validate_public_room_gender() IS 'Prevents creating public rooms with "other" gender to ensure proper matching';
COMMENT ON FUNCTION can_user_create_public_room(UUID) IS 'Checks if user has valid gender (male/female) to create public room';

-- STEP 8: Create view to debug matching issues
CREATE OR REPLACE VIEW public.matchmaking_debug AS
SELECT 
    r.id as room_id,
    r.creator_id,
    u.display_name as creator_name,
    r.creator_gender,
    r.gender_preference as wants_gender,
    r.interest_category,
    r.room_size,
    r.is_active,
    COUNT(rp.user_id) FILTER (WHERE rp.left_at IS NULL) as current_participants,
    r.created_at
FROM public.rooms r
LEFT JOIN public.users u ON u.id = r.creator_id
LEFT JOIN public.room_participants rp ON rp.room_id = r.id
WHERE r.room_type = 'public'
GROUP BY r.id, u.display_name
ORDER BY r.created_at DESC;

GRANT SELECT ON public.matchmaking_debug TO authenticated, anon;

-- STEP 9: Verification and summary
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ ROOT CAUSE FIX APPLIED';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE 'What was fixed:';
    RAISE NOTICE '  1. Auto-set creator_gender from users table';
    RAISE NOTICE '  2. Strict gender matching in find_compatible_room';
    RAISE NOTICE '  3. Prevent "other" gender from creating public rooms';
    RAISE NOTICE '  4. Added validation triggers';
    RAISE NOTICE '  5. Created debug view';
    RAISE NOTICE '';
    RAISE NOTICE 'Matching Rules:';
    RAISE NOTICE '  • User gender must be male/female (not other)';
    RAISE NOTICE '  • Room creator_gender auto-set from user';
    RAISE NOTICE '  • Match only if: room.gender_preference = user.gender';
    RAISE NOTICE '  • Match only if: room.creator_gender = user.interested_in';
    RAISE NOTICE '';
    RAISE NOTICE 'Next Steps:';
    RAISE NOTICE '  1. Update frontend to use find_compatible_room()';
    RAISE NOTICE '  2. Show error if user tries to match with "other"';
    RAISE NOTICE '  3. Test with 2 users: male→female and female→male';
    RAISE NOTICE '========================================';
END $$;

-- STEP 10: Show current state
SELECT 
    'Total Users' as metric,
    COUNT(*) as value
FROM public.users
UNION ALL
SELECT 
    'Users with valid gender (male/female)' as metric,
    COUNT(*) as value
FROM public.users
WHERE gender IN ('male', 'female')
UNION ALL
SELECT 
    'Users with "other" gender' as metric,
    COUNT(*) as value
FROM public.users
WHERE gender = 'other'
UNION ALL
SELECT 
    'Active Public Rooms' as metric,
    COUNT(*) as value
FROM public.rooms
WHERE room_type = 'public' AND is_active = true;