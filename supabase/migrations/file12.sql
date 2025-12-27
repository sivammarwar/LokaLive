-- COMPLETE RESET - Run this before testing

-- 1. Mark ALL participants as left
UPDATE public.room_participants
SET left_at = NOW()
WHERE left_at IS NULL;

-- 2. Deactivate ALL rooms
UPDATE public.rooms
SET is_active = false
WHERE is_active = true;

-- 3. Verify clean state
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
  'Total Users' as type,
  COUNT(*) as count
FROM public.users;

-- Result should be:
-- Active Rooms: 0
-- Active Participants: 0
-- Total Users: (your user count)