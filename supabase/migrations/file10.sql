-- Run this in Supabase SQL Editor to clean up existing issues

-- 1. Find and remove duplicate active participations (keep only the most recent)
WITH duplicates AS (
  SELECT 
    user_id,
    room_id,
    id,
    joined_at,
    ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY joined_at DESC) as rn
  FROM public.room_participants
  WHERE left_at IS NULL
)
UPDATE public.room_participants
SET left_at = NOW()
WHERE id IN (
  SELECT id FROM duplicates WHERE rn > 1
);

-- 2. Deactivate rooms with no active participants
UPDATE public.rooms
SET is_active = false
WHERE id IN (
  SELECT r.id
  FROM public.rooms r
  LEFT JOIN public.room_participants rp ON rp.room_id = r.id AND rp.left_at IS NULL
  WHERE r.is_active = true
  GROUP BY r.id
  HAVING COUNT(rp.id) = 0
);

-- 3. Create a function to prevent duplicate participations
CREATE OR REPLACE FUNCTION prevent_duplicate_participation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  existing_count INTEGER;
BEGIN
  -- Check if user is already in another active room
  SELECT COUNT(*) INTO existing_count
  FROM room_participants
  WHERE user_id = NEW.user_id
  AND left_at IS NULL
  AND room_id != NEW.room_id;
  
  IF existing_count > 0 THEN
    RAISE EXCEPTION 'User is already in another active room';
  END IF;
  
  RETURN NEW;
END;
$$;

-- 4. Add trigger to enforce single active room per user
DROP TRIGGER IF EXISTS enforce_single_active_room ON public.room_participants;
CREATE TRIGGER enforce_single_active_room
  BEFORE INSERT ON public.room_participants
  FOR EACH ROW
  EXECUTE FUNCTION prevent_duplicate_participation();

-- 5. Add index to speed up duplicate checks
CREATE INDEX IF NOT EXISTS idx_room_participants_user_active 
ON public.room_participants(user_id) 
WHERE left_at IS NULL;

-- Check results
SELECT 
  'Active Rooms' as type,
  COUNT(*) as count
FROM public.rooms
WHERE is_active = true

UNION ALL

SELECT 
  'Active Participants' as type,
  COUNT(*) as count
FROM public.room_participants
WHERE left_at IS NULL

UNION ALL

SELECT 
  'Users in Multiple Rooms' as type,
  COUNT(*) as count
FROM (
  SELECT user_id
  FROM public.room_participants
  WHERE left_at IS NULL
  GROUP BY user_id
  HAVING COUNT(*) > 1
) multi_room_users;