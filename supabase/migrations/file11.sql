-- Run this to clean up empty rooms and fix your database

-- 1. Deactivate ALL empty rooms
UPDATE public.rooms
SET is_active = false
WHERE id IN (
  SELECT r.id
  FROM public.rooms r
  LEFT JOIN public.room_participants rp 
    ON rp.room_id = r.id AND rp.left_at IS NULL
  WHERE r.is_active = true
  GROUP BY r.id
  HAVING COUNT(rp.id) = 0
);

-- 2. Also deactivate rooms older than 30 minutes with no participants
UPDATE public.rooms
SET is_active = false
WHERE is_active = true
AND created_at < NOW() - INTERVAL '30 minutes'
AND id NOT IN (
  SELECT DISTINCT room_id
  FROM public.room_participants
  WHERE left_at IS NULL
);

-- 3. Verify the cleanup
SELECT 
  'Active Rooms with Participants' as status,
  COUNT(DISTINCT r.id) as count
FROM public.rooms r
INNER JOIN public.room_participants rp 
  ON rp.room_id = r.id AND rp.left_at IS NULL
WHERE r.is_active = true

UNION ALL

SELECT 
  'Empty Active Rooms' as status,
  COUNT(*) as count
FROM public.rooms r
LEFT JOIN public.room_participants rp 
  ON rp.room_id = r.id AND rp.left_at IS NULL
WHERE r.is_active = true
AND rp.id IS NULL

UNION ALL

SELECT 
  'Total Active Participants' as status,
  COUNT(*) as count
FROM public.room_participants
WHERE left_at IS NULL;